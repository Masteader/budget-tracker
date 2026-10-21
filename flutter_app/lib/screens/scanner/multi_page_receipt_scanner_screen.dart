import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/nafaqah.dart';
import '../../providers/household_role_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_themes.dart';
import '../../services/offline_sync_service.dart';
import '../../services/sync_worker.dart' show SyncWorker;
import 'package:uuid/uuid.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import '../../widgets/zatca_qr_camera_scanner.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/nafaqah/nafaqah_review_section.dart';
import '../../l10n/app_localizations.dart';

class MultiPageReceiptScannerScreen extends StatefulWidget {
  final String householdId;

  const MultiPageReceiptScannerScreen({super.key, required this.householdId});

  @override
  State<MultiPageReceiptScannerScreen> createState() => _MultiPageReceiptScannerScreenState();
}

class _MultiPageReceiptScannerScreenState extends State<MultiPageReceiptScannerScreen> {
  final ImagePicker _picker = ImagePicker();
  final List<File> _capturedShots = [];
  bool _isProcessing = false;
  String? _errorMessage;

  // Family (Islamic Nafaqah): this screen saves without a preview, so the
  // caller's role comes from the Nafaqah summary. Unknown (offline) = the
  // server applies the same default as chat.
  NafaqahPreview _nafaqah = const NafaqahPreview();
  String? _nafaqahClass;
  String? _nafaqahWifeId;
  bool _showWifeRequired = false;

  @override
  void initState() {
    super.initState();
    _loadNafaqahContext();
  }

  Future<void> _loadNafaqahContext() async {
    try {
      final summary = await ApiService.instance.getNafaqahSummary(widget.householdId);
      _safeSetState(() {
        _nafaqah = NafaqahPreview.fromSummary(summary).withAdmin(viewerIsAdminOf(context, widget.householdId));
        _nafaqahClass = _nafaqah.suggestedClass;
        _nafaqahWifeId = _nafaqah.defaultSpouseId;
      });
    } catch (e) {
      debugPrint('[MultiPageScanner] Nafaqah context unavailable: $e');
    }
  }

  Map<String, String> get _nafaqahFields => _nafaqah.requestFields(_nafaqahClass, chosenWifeId: _nafaqahWifeId);

  // Translation keys for the per-shot capture guidance.
  static const List<String> _guideSteps = [
    'mp_guide_shot1',
    'mp_guide_shot2',
    'mp_guide_shot3',
    'mp_guide_shot4',
  ];

  String? get _currentUserId {
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  /// setState that is a no-op once the widget is unmounted (async callbacks).
  void _safeSetState(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  Future<void> _captureShot() async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 88,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (picked != null) {
        _safeSetState(() {
          _capturedShots.add(File(picked.path));
          _errorMessage = null;
        });
      }
    } catch (e) {
      _safeSetState(() => _errorMessage = context.trArgs('mp_camera_error', {'error': e}));
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final picked = await _picker.pickMultiImage(
        imageQuality: 88,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (picked.isNotEmpty) {
        _safeSetState(() {
          _capturedShots.addAll(picked.map((x) => File(x.path)));
          _errorMessage = null;
        });
      }
    } catch (e) {
      _safeSetState(() => _errorMessage = context.trArgs('mp_gallery_error', {'error': e}));
    }
  }

  void _removeShot(int index) {
    setState(() => _capturedShots.removeAt(index));
  }

  Future<void> _processAllShots() async {
    if (_capturedShots.isEmpty) return;
    if (!NafaqahReviewSection.hasRequiredWife(_nafaqah, _nafaqahClass, _nafaqahWifeId)) {
      setState(() => _showWifeRequired = true);
      return;
    }
    final nafaqah = _nafaqahFields;
    // One key for the online attempt and its offline replay: a request that
    // timed out after the server stored the receipt is not booked twice when
    // the queue replays it (FR-A-04).
    final idempotencyKey = const Uuid().v4();
    final occurredAt = DateTime.now();

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      final List<String> base64List = [];
      for (final f in _capturedShots) {
        final bytes = await f.readAsBytes();
        base64List.add(base64Encode(bytes));
      }

      final res = await ApiService.instance.scanReceipt(
        imagesBase64: base64List,
        householdId: widget.householdId,
        allowDuplicate: false,
        paidBy: nafaqah['paid_by'],
        beneficiary: nafaqah['beneficiary'],
        nafaqahClass: nafaqah['nafaqah_class'],
        nafaqahSpouseId: nafaqah['nafaqah_spouse_id'],
        idempotencyKey: idempotencyKey,
        occurredAt: occurredAt,
      );

      _safeSetState(() => _isProcessing = false);

      if (mounted) {
        if (res['status'] == 'success') {
          AppSnackBar.showSuccess(
            context,
            res['message'] ?? context.tr('mp_saved_msg'),
            title: context.tr('mp_saved_title'),
          );
          Navigator.pop(context, true);
        } else if (SyncWorker.shouldQueueAfterOnlineFailure(res)) {
          // Offline or a transient server failure; a refusal is shown below.
          await _queueOffline(base64List, messageKey: 'mp_queued_offline_msg', idempotencyKey: idempotencyKey);
        } else {
          _safeSetState(() {
            _errorMessage = res['message'] ?? context.tr('mp_parse_failed');
          });
        }
      }
    } catch (e) {
      // Offline fallback
      _safeSetState(() => _isProcessing = false);
      try {
        final List<String> base64List = [];
        for (final f in _capturedShots) {
          final bytes = await f.readAsBytes();
          base64List.add(base64Encode(bytes));
        }
        await _queueOffline(base64List, messageKey: 'mp_queued_offline_short', idempotencyKey: idempotencyKey);
      } catch (_) {
        _safeSetState(() => _errorMessage = context.trArgs('mp_process_failed', {'error': e}));
      }
    }
  }

  /// Stores the shots in the offline queue and reports "queued" only when the
  /// write succeeded (MOB-28). On failure the shots stay on screen with an
  /// error so the user can retry; nothing was stored.
  Future<void> _queueOffline(List<String> base64List, {required String messageKey, String? idempotencyKey}) async {
    try {
      await OfflineSyncService.instance.enqueue(
        endpoint: 'receipt',
        payload: {
          'images_base64': base64List,
          // Owner of the queued receipt, so another account never replays it (FR-A-09).
          if (_currentUserId != null) 'user_id': _currentUserId,
          ..._nafaqahFields,
        },
        householdId: widget.householdId,
        idempotencyKey: idempotencyKey,
      );
    } catch (err) {
      debugPrint('[MultiPageScanner] Offline queue write failed: $err');
      _safeSetState(() {
        _isProcessing = false;
        _errorMessage = context.tr('offline_queue_failed');
      });
      return;
    }
    if (mounted) {
      AppSnackBar.showWarning(
        context,
        context.tr(messageKey),
        title: context.tr('mp_queued_offline'),
        icon: Icons.cloud_off_rounded,
      );
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentGuide = _capturedShots.length < _guideSteps.length
        ? context.tr(_guideSteps[_capturedShots.length])
        : context.tr('mp_ready');

    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: AppBar(
        backgroundColor: context.cardBg,
        elevation: 0,
        title: Text(
          context.tr('mp_title'),
          style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.bold, color: context.textPrimary),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner, color: AppThemes.success),
            tooltip: context.tr('mp_scan_zatca'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ZatcaQrCameraScanner()),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Guided Instruction Banner
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: context.cardBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppThemes.success.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppThemes.success.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.auto_awesome, color: AppThemes.success, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr('mp_overlap_hint'),
                          style: GoogleFonts.outfit(color: context.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          currentGuide,
                          style: TextStyle(color: context.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            if (_errorMessage != null)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                    ),
                  ],
                ),
              ),

            // Main Preview Area / Empty state
            Expanded(
              child: _capturedShots.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: context.cardBg,
                              shape: BoxShape.circle,
                              border: Border.all(color: context.borderColor),
                            ),
                            child: const Icon(Icons.receipt_long_rounded, size: 54, color: AppThemes.success),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            context.tr('capture_continuous_receipts'),
                            style: GoogleFonts.outfit(color: context.textPrimary, fontSize: 17, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 6),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 36),
                            child: Text(
                              context.tr('multi_page_guide_desc'),
                              textAlign: TextAlign.center,
                              style: TextStyle(color: context.textSecondary, fontSize: 13, height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    )
                  : Stack(
                      children: [
                        Center(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.file(
                              _capturedShots.last,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                        PositionedDirectional(
                          top: 12,
                          start: 16,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.75),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              context.trArgs('mp_latest_shot', {'n': _capturedShots.length}),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),

            // Bottom Filmstrip
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              color: context.cardBg,
              child: Column(
                children: [
                  if (_capturedShots.isNotEmpty)
                    SizedBox(
                      height: 85,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _capturedShots.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                        itemBuilder: (ctx, i) {
                          return Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.file(
                                  _capturedShots[i],
                                  width: 65,
                                  height: 85,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              PositionedDirectional(
                                top: 2,
                                start: 2,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.8),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '#${i + 1}',
                                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                              PositionedDirectional(
                                top: 2,
                                end: 2,
                                child: GestureDetector(
                                  onTap: () => _removeShot(i),
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.redAccent,
                                    ),
                                    child: Icon(Icons.close, size: 12, color: Colors.white, semanticLabel: context.tr('a11y_remove_photo')),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  if (_capturedShots.isNotEmpty && _nafaqah.canClassify)
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 0),
                      child: NafaqahReviewSection(
                        key: const ValueKey('multipage_nafaqah_review'),
                        preview: _nafaqah,
                        value: _nafaqahClass,
                        wifeId: _nafaqahWifeId,
                        showWifeRequired: _showWifeRequired,
                        onChanged: (cls) => setState(() => _nafaqahClass = cls),
                        onWifeChanged: (id) => setState(() => _nafaqahWifeId = id),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: context.chipBg,
                              foregroundColor: context.textPrimary,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.add_a_photo_outlined, size: 20),
                            label: Text(
                              context.trArgs('take_shot_n', {'n': _capturedShots.length + 1}),
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            onPressed: _isProcessing ? null : _captureShot,
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          style: IconButton.styleFrom(
                            backgroundColor: context.chipBg,
                            padding: const EdgeInsets.all(14),
                          ),
                          icon: Icon(Icons.photo_library_outlined, color: context.textPrimary),
                          tooltip: context.tr('pick_from_gallery'),
                          onPressed: _isProcessing ? null : _pickFromGallery,
                        ),
                        if (_capturedShots.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppThemes.success,
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              icon: _isProcessing
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                                    )
                                  : const Icon(Icons.check_circle_outline, size: 20),
                              label: Text(
                                _isProcessing ? context.tr('stitching') : '${context.tr('process')} (${_capturedShots.length})',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              onPressed: _isProcessing ? null : _processAllShots,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
