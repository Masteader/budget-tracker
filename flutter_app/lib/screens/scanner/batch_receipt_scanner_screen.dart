import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_themes.dart';
import '../../widgets/scanner/batch_item_review_sheet.dart';

/// Screen for batch capturing multiple paper receipts in rapid succession,
/// storing them in an in-memory queue tray, and launching sequential processing.
class BatchReceiptScannerScreen extends StatefulWidget {
  final String householdId;
  final List<File>? initialFiles;
  final Future<File?> Function()? onCapturePhoto;
  final Future<List<File>> Function()? onPickGallery;

  const BatchReceiptScannerScreen({
    super.key,
    required this.householdId,
    this.initialFiles,
    this.onCapturePhoto,
    this.onPickGallery,
  });

  @override
  State<BatchReceiptScannerScreen> createState() => _BatchReceiptScannerScreenState();
}

class _BatchReceiptScannerScreenState extends State<BatchReceiptScannerScreen> {
  late final List<File> _queuedImages;
  final ImagePicker _picker = ImagePicker();
  bool _isCapturing = false;
  String? _errorMessage;

  /// setState that is a no-op once the widget is unmounted (async callbacks).
  void _safeSetState(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  @override
  void initState() {
    super.initState();
    _queuedImages = widget.initialFiles != null ? List<File>.from(widget.initialFiles!) : [];
  }

  Future<void> _capturePhoto() async {
    if (_isCapturing) return;

    if (widget.onCapturePhoto != null) {
      final file = await widget.onCapturePhoto!();
      if (file != null && mounted) {
        setState(() {
          _queuedImages.add(file);
          _errorMessage = null;
        });
      }
      return;
    }

    // Check camera permission
    final status = await Permission.camera.status;
    if (!status.isGranted) {
      final req = await Permission.camera.request();
      if (!req.isGranted) {
        _safeSetState(() {
          _errorMessage = req.isPermanentlyDenied
              ? context.tr('scan_cam_perm_permanent')
              : context.tr('scan_cam_perm_needed');
        });
        return;
      }
    }

    setState(() => _isCapturing = true);
    try {
      HapticFeedback.mediumImpact();
      final picked = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 82,
        maxWidth: 1600,
        maxHeight: 1600,
      );

      if (picked != null && mounted) {
        setState(() {
          _queuedImages.add(File(picked.path));
          _errorMessage = null;
        });
        HapticFeedback.lightImpact();
      }
    } catch (e) {
      _safeSetState(() => _errorMessage = context.trArgs('scan_capture_error', {'error': e}));
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  Future<void> _pickFromGallery() async {
    if (widget.onPickGallery != null) {
      final files = await widget.onPickGallery!();
      if (mounted) {
        setState(() {
          _queuedImages.addAll(files);
          _errorMessage = null;
        });
      }
      return;
    }

    try {
      final pickedFiles = await _picker.pickMultiImage(
        imageQuality: 82,
        maxWidth: 1600,
        maxHeight: 1600,
      );

      if (pickedFiles.isNotEmpty && mounted) {
        setState(() {
          _queuedImages.addAll(pickedFiles.map((x) => File(x.path)));
          _errorMessage = null;
        });
        HapticFeedback.lightImpact();
      }
    } catch (e) {
      _safeSetState(() => _errorMessage = context.trArgs('mp_gallery_error', {'error': e}));
    }
  }

  void _removeAt(int index) {
    if (index >= 0 && index < _queuedImages.length) {
      setState(() {
        _queuedImages.removeAt(index);
      });
      HapticFeedback.selectionClick();
    }
  }

  void _clearAll() {
    setState(() {
      _queuedImages.clear();
    });
    HapticFeedback.lightImpact();
  }

  void _processQueue() {
    if (_queuedImages.isEmpty) return;

    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BatchItemReviewSheet(
        receiptImages: List.from(_queuedImages),
        householdId: widget.householdId,
        onComplete: (saved, total) {
          if (mounted) {
            setState(() {
              _queuedImages.clear();
            });
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF030D18),
      appBar: AppBar(
        key: const Key('batch_scanner_app_bar'),
        backgroundColor: const Color(0xFF071C33),
        elevation: 0,
        leading: IconButton(
          tooltip: context.tr('nav_back'),
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          context.tr('batch_scan_receipts'),
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: Colors.white,
          ),
        ),
        actions: [
          // Counter Pill
          Center(
            child: Container(
              key: const Key('batch_queue_counter'),
              margin: const EdgeInsets.symmetric(horizontal: 12),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: context.electricTeal.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.electricTeal.withValues(alpha: 0.6)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.collections_rounded, size: 14, color: context.electricTeal),
                  const SizedBox(width: 6),
                  Text(
                    '${_queuedImages.length}',
                    style: GoogleFonts.outfit(
                      color: context.electricTeal,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_queuedImages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded, color: Colors.white70),
              tooltip: context.tr('clear_queue'),
              onPressed: _clearAll,
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Top Description Pill
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: const Color(0xFF071C33).withValues(alpha: 0.5),
              child: Text(
                context.tr('batch_scan_desc'),
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  color: context.iceCyan.withValues(alpha: 0.8),
                ),
                textAlign: TextAlign.center,
              ),
            ),

            if (_errorMessage != null)
              Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: GoogleFonts.outfit(color: Colors.red, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),

            // Viewfinder HUD
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF071C33).withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: context.iceCyan.withValues(alpha: 0.3)),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Corner targeting brackets
                    Positioned(
                      top: 16,
                      left: 16,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(color: context.iceCyan, width: 3),
                            left: BorderSide(color: context.iceCyan, width: 3),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 16,
                      right: 16,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(color: context.iceCyan, width: 3),
                            right: BorderSide(color: context.iceCyan, width: 3),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 16,
                      left: 16,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: context.iceCyan, width: 3),
                            left: BorderSide(color: context.iceCyan, width: 3),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 16,
                      right: 16,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: context.iceCyan, width: 3),
                            right: BorderSide(color: context.iceCyan, width: 3),
                          ),
                        ),
                      ),
                    ),

                    // Central Action Controls
                    Center(
                      child: SingleChildScrollView(
                        physics: const ClampingScrollPhysics(),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.document_scanner_rounded,
                                size: 52,
                                color: context.iceCyan.withValues(alpha: 0.5),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                context.tr('brs_align'),
                                style: GoogleFonts.outfit(
                                  color: Colors.white70,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 18),

                              // Shutter Button
                              GestureDetector(
                                key: const Key('batch_shutter_button'),
                                onTap: _capturePhoto,
                                child: Container(
                                  width: 68,
                                  height: 68,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(color: context.electricTeal, width: 3.5),
                                    color: Colors.transparent,
                                  ),
                                  padding: const EdgeInsets.all(5),
                                  child: Container(
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.white,
                                    ),
                                    child: _isCapturing
                                        ? const Center(
                                            child: SizedBox(
                                              width: 22,
                                              height: 22,
                                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                                            ),
                                          )
                                        : const Icon(Icons.camera_alt_rounded, color: Color(0xFF051424), size: 26),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),

                              // Gallery Button
                              TextButton.icon(
                                onPressed: _pickFromGallery,
                                icon: Icon(Icons.photo_library_rounded, size: 16, color: context.iceCyan),
                                label: Text(
                                  context.tr('brs_add_gallery'),
                                  style: GoogleFonts.outfit(
                                    color: context.iceCyan,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Queue Tray (Bottom Horizontal Strip)
            Container(
              key: const Key('batch_queue_tray'),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFF071C33),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        context.trArgs('brs_captured', {'count': _queuedImages.length}),
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      if (_queuedImages.isNotEmpty)
                        Text(
                          context.tr('brs_ready'),
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            color: context.electricTeal,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  if (_queuedImages.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      alignment: Alignment.center,
                      child: Text(
                        context.tr('empty_queue_message'),
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: Colors.white38,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    SizedBox(
                      height: 100,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _queuedImages.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                        itemBuilder: (context, index) {
                          final file = _queuedImages[index];
                          final exists = file.existsSync();

                          return Stack(
                            key: Key('queue_item_thumbnail_$index'),
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                width: 75,
                                height: 95,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0A2544),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: context.iceCyan.withValues(alpha: 0.5),
                                    width: 1.5,
                                  ),
                                ),
                                child: exists
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.file(
                                          file,
                                          fit: BoxFit.cover,
                                          width: double.infinity,
                                          height: double.infinity,
                                        ),
                                      )
                                    : Center(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.receipt_rounded, size: 28, color: context.electricTeal),
                                            Text(
                                              '#${index + 1}',
                                              style: GoogleFonts.outfit(
                                                fontSize: 10,
                                                color: Colors.white70,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                              ),

                              // Delete Badge
                              PositionedDirectional(
                                top: -6,
                                end: -6,
                                child: GestureDetector(
                                  key: Key('delete_queue_item_$index'),
                                  onTap: () => _removeAt(index),
                                  child: Container(
                                    width: 22,
                                    height: 22,
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade600,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white, width: 1.5),
                                    ),
                                    child: Icon(
                                      Icons.close_rounded,
                                      size: 14,
                                      color: Colors.white,
                                      semanticLabel: context.tr('a11y_remove_photo'),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 12),

                  // Process Queue Button
                  ElevatedButton.icon(
                    key: const Key('process_batch_queue_button'),
                    onPressed: _queuedImages.isNotEmpty ? _processQueue : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.electricTeal,
                      foregroundColor: const Color(0xFF051424),
                      disabledBackgroundColor: Colors.white12,
                      disabledForegroundColor: Colors.white30,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: _queuedImages.isNotEmpty ? 4 : 0,
                    ),
                    icon: const Icon(Icons.playlist_play_rounded, size: 20),
                    label: Text(
                      '${context.tr('process_queue')} (${_queuedImages.length})',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
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
