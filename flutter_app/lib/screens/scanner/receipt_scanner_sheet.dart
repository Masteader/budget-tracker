import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../main.dart';
import '../../models/nafaqah.dart';
import '../../providers/budget_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../services/api_service.dart';
import '../../services/ocr/local_ocr_service.dart';
import '../../services/offline_queue_manager.dart';
import '../../services/receipt_storage_service.dart';
import '../../services/zatca_decoder.dart';
import '../../widgets/receipt_photo_strip.dart';
import '../../widgets/scanner/duplicate_candidate_card.dart';
import '../../widgets/store_attribution_card.dart';
import '../../widgets/transaction_item_breakdown_card.dart';
import '../../widgets/zatca_qr_camera_scanner.dart';
import '../../widgets/zatca_status_badge.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/dispose_on_unmount.dart';
import '../../widgets/nafaqah/nafaqah_review_section.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_themes.dart';

class ReceiptScannerSheet extends StatefulWidget {
  final String householdId;

  const ReceiptScannerSheet({
    super.key,
    required this.householdId,
  });

  static Future<void> show(BuildContext context, String householdId) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => ReceiptScannerSheet(householdId: householdId),
    );
  }

  @override
  State<ReceiptScannerSheet> createState() => _ReceiptScannerSheetState();
}

class _ReceiptScannerSheetState extends State<ReceiptScannerSheet> {
  final ImagePicker _picker = ImagePicker();
  final List<File> _imageFiles = [];
  String? _zatcaQrRaw;
  Map<String, dynamic>? _zatcaDecoded;

  bool _isAnalyzing = false;
  Map<String, dynamic>? _scanResult;
  String? _errorMessage;

  late final TextEditingController _merchantController;
  String _selectedSpentBy = 'both';

  // Family (Islamic Nafaqah): the server's suggestion from the preview and the
  // user's choice. A wife's receipt is her shared advance (the husband owes
  // it) or a personal purchase from her allowance; never split.
  NafaqahPreview _nafaqah = const NafaqahPreview();
  String? _nafaqahClass;
  String? _nafaqahWifeId;
  bool _showWifeRequired = false;

  void _applyNafaqahPreview(Map<String, dynamic>? res) {
    _nafaqah = NafaqahPreview.fromPreview(res);
    _nafaqahClass = _nafaqah.suggestedClass;
    _nafaqahWifeId = _nafaqah.defaultSpouseId;
    _showWifeRequired = false;
  }

  /// `paid_by` / `beneficiary` / `nafaqah_class` / `nafaqah_spouse_id` for the
  /// commit, consistent with each other (empty outside family mode).
  Map<String, String> get _nafaqahFields => _nafaqah.requestFields(_nafaqahClass, chosenWifeId: _nafaqahWifeId);

  @override
  void initState() {
    super.initState();
    _merchantController = TextEditingController();
  }

  /// setState that is a no-op once the widget is unmounted (async callbacks).
  void _safeSetState(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  @override
  void dispose() {
    _merchantController.dispose();
    super.dispose();
  }

  void _notifyGlobalProviders() {
    if (!mounted) return;
    try {
      context.read<TransactionProvider>().refresh();
      context.read<BudgetProvider>().refresh();
    } catch (_) {}
  }

  Future<void> _addPhoto(ImageSource source) async {
    setState(() => _errorMessage = null);

    if (source == ImageSource.camera) {
      final status = await Permission.camera.status;
      if (!status.isGranted) {
        final requested = await Permission.camera.request();
        if (!requested.isGranted) {
          _safeSetState(() {
            _errorMessage = requested.isPermanentlyDenied
                ? context.tr('scan_cam_perm_permanent')
                : context.tr('scan_cam_perm_needed');
          });
          return;
        }
      }
    }

    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 78,
        maxWidth: 1280,
        maxHeight: 1280,
      );
      if (picked == null) return;

      _safeSetState(() {
        _imageFiles.add(File(picked.path));
        _errorMessage = null;
        _scanResult = null;
      });
    } on PlatformException catch (pe) {
      if (pe.code.toLowerCase().contains('camera_access_denied') ||
          (pe.message?.toLowerCase().contains('camera') ?? false)) {
        _safeSetState(() {
          _errorMessage =
              context.tr('scan_cam_denied_by_system');
        });
      } else {
        _safeSetState(() => _errorMessage = context.trArgs('scan_camera_error', {'error': pe.message ?? pe.code}));
      }
    } catch (e) {
      _safeSetState(() => _errorMessage = context.trArgs('scan_capture_error', {'error': e}));
    }
  }

  void _removePhoto(int index) {
    setState(() {
      _imageFiles.removeAt(index);
      _scanResult = null;
    });
  }

  void _showZatcaQrDialog() {
    final ctrl = TextEditingController(text: _zatcaQrRaw ?? '');
    showDialog(
      context: context,
      builder: (ctx) => DisposeOnUnmount(
        disposables: [ctrl],
        child: AlertDialog(
        backgroundColor: context.cardBg,
        title: Row(
          children: [
            const Icon(Icons.qr_code_2_rounded, color: AppThemes.success),
            const SizedBox(width: 8),
            Text(context.tr('saudi_zatca_vat_qr'), style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: context.textPrimary)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('scan_paste_qr_desc'),
              style: TextStyle(color: context.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              maxLines: 3,
              style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: context.textPrimary),
              decoration: InputDecoration(
                hintText: '${context.tr('example_prefix')} AQ5UYW1pbWkgTWFya2V0cwIPMzAwMDAwMDAwMDAwMDAz...',
                hintStyle: TextStyle(color: context.textSecondary.withValues(alpha: 0.6), fontSize: 11),
                filled: true,
                fillColor: context.inputBg,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: context.borderColor)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: context.borderColor)),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.paste, size: 14, color: Color(0xFF58A6FF)),
                  label: Text(context.tr('from_clipboard'), style: const TextStyle(fontSize: 11, color: Color(0xFF58A6FF))),
                  onPressed: () async {
                    final data = await Clipboard.getData(Clipboard.kTextPlain);
                    // The dialog (and its controller) may be gone by now.
                    if (data?.text != null && ctx.mounted) {
                      ctrl.text = data!.text!.trim();
                    }
                  },
                ),
                const Spacer(),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.receipt_long_outlined, size: 14, color: AppThemes.success),
                  label: Text(context.tr('sample_extra'), style: TextStyle(fontSize: 11, color: context.successText)),
                  onPressed: () {
                    ctrl.text = 'ARxVbml0ZWQgRWxlY3Ryb25pY3MgQ28uIGVYdHJhAg8zMDA0Njg3ODE5MTAwMDMDFDIwMjYtMTAtMDRUMjI6MTk6MzRaBAc3NDA4LjAwBQY5NjYuMjY=';
                  },
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('cancel'), style: TextStyle(color: context.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppThemes.success, foregroundColor: Colors.black),
            onPressed: () {
              final text = ctrl.text.trim();
              Navigator.pop(ctx);
              if (text.isEmpty) return;
              final decoded = ZatcaDecoder.decodeTlv(text);
              final sellerName = decoded?['seller'] as String? ?? 'Store Name';
              setState(() {
                _zatcaQrRaw = text;
                _zatcaDecoded = decoded;
                if (sellerName.isNotEmpty && sellerName != 'Store Name') {
                  _merchantController.text = sellerName;
                }
              });
              _analyzeReceipt();
            },
            child: Text(context.tr('apply_qr_code'), style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      ),
    );
  }

  Future<void> _scanZatcaQrWithCamera() async {
    final status = await Permission.camera.status;
    if (!status.isGranted) {
      final res = await Permission.camera.request();
      if (!res.isGranted) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: context.cardBg,
              title: Row(
                children: [
                  const Icon(Icons.no_photography_rounded, color: Colors.orange),
                  const SizedBox(width: 8),
                  Text(context.tr('camera_access_needed'), style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16, color: context.textPrimary)),
                ],
              ),
              content: Text(
                context.tr('scan_qr_cam_perm_required'),
                style: TextStyle(color: context.textSecondary, fontSize: 13),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(context.tr('cancel'), style: TextStyle(color: context.textSecondary)),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppThemes.success,
                    foregroundColor: Colors.black,
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    openAppSettings();
                  },
                  icon: const Icon(Icons.settings, size: 16),
                  label: Text(context.tr('open_settings'), style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
        }
        return;
      }
    }

    if (!mounted) return;
    final scannedCode = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ZatcaQrCameraScanner()),
    );
    if (scannedCode != null && scannedCode.isNotEmpty) {
      final decoded = ZatcaDecoder.decodeTlv(scannedCode);
      final sellerName = decoded?['seller'] as String? ?? 'Store Name';

      _safeSetState(() {
        _zatcaQrRaw = scannedCode;
        _zatcaDecoded = decoded;
        if (sellerName.isNotEmpty && sellerName != 'Store Name') {
          _merchantController.text = sellerName;
        }
      });
      _analyzeReceipt();
    }
  }

  Future<void> _analyzeReceipt() async {
    if (_imageFiles.isEmpty && _zatcaQrRaw == null) {
      setState(() => _errorMessage = context.tr('photo_or_qr_required'));
      return;
    }

    setState(() {
      _isAnalyzing = true;
      _errorMessage = null;
      _scanResult = null;
    });

    try {
      final List<String> base64List = [];
      for (final file in _imageFiles) {
        final bytes = await file.readAsBytes();
        base64List.add(base64Encode(bytes));
      }

      final user = supabase.auth.currentUser;
      final res = await ApiService.instance.scanReceipt(
        imagesBase64: base64List,
        qrCodeRaw: _zatcaQrRaw,
        householdId: widget.householdId,
        userId: user?.id,
        previewOnly: true,
      );

      _safeSetState(() {
        _isAnalyzing = false;
        if (res['status'] == 'error') {
          _errorMessage = res['message'] ?? context.tr('scan_analyze_failed');
        } else {
          _scanResult = res;
          _applyNafaqahPreview(res);
          final detectedMerchant = _zatcaDecoded?['seller'] as String? ??
              res['merchant'] as String? ??
              res['parsed_data']?['merchant'] as String? ??
              '';
          if (detectedMerchant.trim().isNotEmpty) {
            _merchantController.text = detectedMerchant.trim();
          }
          if (res['spent_by'] != null) {
            _selectedSpentBy = (res['spent_by'] as String).toLowerCase();
          }
        }
      });
    } catch (e) {
      if (_zatcaDecoded != null) {
        final sellerName = _zatcaDecoded!['seller'] as String? ?? 'Store Name';
        final total = (_zatcaDecoded!['total'] as num?)?.toDouble() ?? 0.0;
        final vat = (_zatcaDecoded!['vat'] as num?)?.toDouble() ?? 0.0;
        final isDup = await _checkFallbackDuplicateCandidate(sellerName, total, vat);
        if (!isDup && mounted) {
          setState(() {
            _isAnalyzing = false;
            _scanResult = {
              'status': 'preview',
              'merchant': sellerName,
              'amount': total,
              'vat_amount': vat,
              'category_code': 'OPEX-GROCERY',
              'spent_by': _selectedSpentBy,
              'items': [
                {
                  'name': context.trArgs('scan_invoice_total_item', {'vat': context.sar(vat)}),
                  'quantity': 1.0,
                  'price': total,
                }
              ],
              'zatca_verified': _zatcaDecoded,
            };
          });
        }
      } else {
        if (_imageFiles.isNotEmpty) {
          try {
            final draft = await LocalOcrService.instance.extractDraft(_imageFiles.first);
            if (mounted && draft.amount > 0) {
              setState(() {
                _isAnalyzing = false;
                _merchantController.text = draft.merchant;
                _scanResult = {
                  'status': 'preview',
                  'merchant': draft.merchant,
                  'amount': draft.amount,
                  'vat_amount': draft.vatAmount,
                  'category_code': 'OPEX-GROCERY',
                  'confidence': 'offline_fallback',
                  'items': [],
                  'is_offline_draft': true,
                };
              });
              return;
            }
          } catch (_) {}
        }
        _safeSetState(() {
          _isAnalyzing = false;
          _errorMessage = context.trArgs('scan_failed_msg', {'error': e});
        });
      }
    }
  }

  Future<void> _confirmSave({bool allowDuplicate = false, String? enrichTxId}) async {
    if (_isAnalyzing) return;
    if (enrichTxId == null && !NafaqahReviewSection.hasRequiredWife(_nafaqah, _nafaqahClass, _nafaqahWifeId)) {
      setState(() => _showWifeRequired = true);
      return;
    }
    setState(() {
      _isAnalyzing = true;
      _errorMessage = null;
    });

    String? uploadedReceiptUrl;
    try {
      if (_imageFiles.isNotEmpty) {
        try {
          uploadedReceiptUrl = await ReceiptStorageService().uploadReceipt(
            imageFile: _imageFiles.first,
            householdId: widget.householdId,
          );
        } catch (e) {
          debugPrint('[ReceiptScannerSheet] Storage upload error: $e');
        }
      }

      final List<String> base64List = [];
      for (final file in _imageFiles) {
        final bytes = await file.readAsBytes();
        base64List.add(base64Encode(bytes));
      }
      final user = supabase.auth.currentUser;
      final confirmedMerchant = _merchantController.text.trim();
      final nafaqah = _nafaqahFields;

      final res = await ApiService.instance.scanReceipt(
        imagesBase64: base64List,
        qrCodeRaw: _zatcaQrRaw,
        householdId: widget.householdId,
        userId: user?.id,
        allowDuplicate: allowDuplicate,
        enrichTxId: enrichTxId,
        merchant: confirmedMerchant.isNotEmpty ? confirmedMerchant : null,
        spentBy: _selectedSpentBy,
        previewOnly: false,
        receiptUrl: uploadedReceiptUrl,
        paidBy: nafaqah['paid_by'],
        beneficiary: nafaqah['beneficiary'],
        nafaqahClass: nafaqah['nafaqah_class'],
        nafaqahSpouseId: nafaqah['nafaqah_spouse_id'],
      );

      _safeSetState(() => _isAnalyzing = false);

      if (mounted) {
        if (res['status'] == 'success' || res['status'] == 'enriched') {
          AppSnackBar.showSuccess(
            context,
            res['message'] ?? context.tr('scan_invoice_saved_msg'),
            title: context.tr('scan_invoice_saved'),
          );
          _notifyGlobalProviders();
          Navigator.pop(context);
        } else if (res['status'] == 'duplicate_candidate') {
          setState(() {
            _scanResult = res;
          });
        } else if (res['status_code'] == 422) {
          // The server refused the request itself (e.g. the Nafaqah choice):
          // saving it directly would only bypass that check.
          setState(() => _errorMessage = res['message'] as String? ?? context.tr('scan_analyze_failed'));
        } else {
          await _fallbackSaveToSupabase(allowDuplicate: allowDuplicate, receiptUrl: uploadedReceiptUrl);
        }
      }
    } catch (_) {
      await _fallbackSaveToSupabase(allowDuplicate: allowDuplicate, receiptUrl: uploadedReceiptUrl);
    }
  }

  Future<bool> _checkFallbackDuplicateCandidate(String merchant, double total, double vat) async {
    if (total <= 0) return false;
    try {
      final recentRows = await supabase
          .from('transactions')
          .select('*')
          .eq('household_id', widget.householdId)
          .order('created_at', ascending: false)
          .limit(30);

      for (final row in (recentRows as List)) {
        final rowAmt = (row['amount'] as num?)?.toDouble() ?? 0.0;
        if ((rowAmt - total).abs() <= 0.05) {
          final rowMerchant = (row['merchant'] as String? ?? '').toLowerCase();
          final cleanMerchant = merchant.toLowerCase();
          if (rowMerchant.isEmpty || cleanMerchant.contains(rowMerchant) || rowMerchant.contains(cleanMerchant)) {
            if (mounted) {
              setState(() {
                _isAnalyzing = false;
                _scanResult = {
                  'status': 'duplicate_candidate',
                  'candidate_transaction_id': row['id'],
                  'candidate_merchant': row['merchant'],
                  'candidate_amount': rowAmt,
                  'candidate_timestamp': row['timestamp'],
                  'merchant': merchant,
                  'amount': total,
                  'items': _scanResult?['items'],
                  'message':
                      context.trArgs('scan_duplicate_found_msg', {'amount': context.sar(rowAmt), 'merchant': merchant}),
                };
              });
            }
            return true;
          }
        }
      }
    } catch (_) {}
    return false;
  }

  Future<void> _fallbackSaveToSupabase({bool allowDuplicate = false, String? receiptUrl}) async {
    try {
      if (receiptUrl == null && _imageFiles.isNotEmpty) {
        try {
          receiptUrl = await ReceiptStorageService().uploadReceipt(
            imageFile: _imageFiles.first,
            householdId: widget.householdId,
          );
        } catch (_) {}
      }
      if (!mounted) return;

      final merchant = _merchantController.text.trim().isNotEmpty
          ? _merchantController.text.trim()
          : (_zatcaDecoded?['seller'] as String? ??
              _scanResult?['merchant'] as String? ??
              context.tr('scan_vat_tax_invoice'));
      final total = (_zatcaDecoded?['total'] as num?)?.toDouble() ??
          (_scanResult?['amount'] as num?)?.toDouble() ??
          0.0;
      final vat = (_zatcaDecoded?['vat'] as num?)?.toDouble() ??
          (_scanResult?['vat_amount'] as num?)?.toDouble() ??
          (total > 0 ? (total * 0.15 / 1.15) : 0.0);

      if (!allowDuplicate && total > 0) {
        final isDup = await _checkFallbackDuplicateCandidate(merchant, total, vat);
        if (isDup || !mounted) return;
      }

      final dynamic rawItems = _scanResult?['items'];
      final List<Map<String, dynamic>> items = (rawItems is List && rawItems.isNotEmpty)
          ? rawItems.map((e) => Map<String, dynamic>.from(e as Map)).toList()
          : [
              {
                'name': context.trArgs('scan_tax_invoice_total_item', {'vat': context.sar(vat)}),
                'quantity': 1.0,
                'price': total,
              }
            ];

      final itemsSummary = items.map((e) => '${e['quantity']}x ${e['name']} (${e['price']} SAR)').join(', ');
      String auditText = 'Invoice Scan: $merchant (${items.length} items) | Items: [$itemsSummary]';
      if (_zatcaQrRaw != null && _zatcaQrRaw!.isNotEmpty) {
        auditText += ' | ZATCA QR: $_zatcaQrRaw';
      }

      final baseData = <String, dynamic>{
        'household_id': widget.householdId,
        'amount': total,
        'currency': 'SAR',
        'merchant': merchant,
        'category_code': 'OPEX-GROCERY',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'raw_sms': auditText,
        if (receiptUrl != null && receiptUrl.isNotEmpty) 'receipt_url': receiptUrl,
        if (_zatcaQrRaw != null && _zatcaQrRaw!.isNotEmpty) 'qr_code_raw': _zatcaQrRaw,
        // Never dropped by the fallbacks below: losing it would erase the
        // wife's reimbursement debt or her allowance spending.
        ..._nafaqah.transactionColumns(
          _nafaqahClass,
          chosenWifeId: _nafaqahWifeId,
          currentUserId: supabase.auth.currentUser?.id,
        ),
      };

      Map<String, dynamic> res;
      try {
        res = await supabase.from('transactions').insert({
          ...baseData,
          'source': 'receipt_scan',
          'spent_by': _selectedSpentBy,
          'items': items,
        }).select().single();
      } catch (_) {
        try {
          res = await supabase.from('transactions').insert({
            ...baseData,
            'source': 'receipt_scan',
            'spent_by': _selectedSpentBy,
          }).select().single();
        } catch (_) {
          res = await supabase.from('transactions').insert(baseData).select().single();
        }
      }

      final txId = res['id'] as String?;
      if (txId != null) {
        for (final it in items) {
          try {
            await supabase.from('transaction_items').insert({
              'transaction_id': txId,
              'name': it['name'] ?? 'Item',
              'quantity': it['quantity'] ?? 1.0,
              'price': it['price'] ?? 0.0,
            });
          } catch (_) {}
        }
      }

      _safeSetState(() => _isAnalyzing = false);

      if (mounted) {
        AppSnackBar.showSuccess(
          context,
          context.trArgs('scan_saved_amount_at', {'amount': context.sar(total), 'merchant': merchant}),
          title: context.tr('scan_invoice_recorded'),
        );
        _notifyGlobalProviders();
        Navigator.pop(context);
      }
    } catch (e) {
      try {
        final List<String> base64List = [];
        for (final file in _imageFiles) {
          final bytes = await file.readAsBytes();
          base64List.add(base64Encode(bytes));
        }
        // MOB-28: throws when the draft could not be stored, so "Offline
        // Draft" is never shown for a receipt that was lost.
        await OfflineQueueManager().enqueueOrThrow(
          operationType: 'receipt_offline_draft',
          householdId: widget.householdId,
          payload: {
            'merchant': _merchantController.text.trim().isNotEmpty
                ? _merchantController.text.trim()
                : 'Merchant',
            'amount': (_scanResult?['amount'] as num?)?.toDouble() ?? 0.0,
            'vat_amount': (_scanResult?['vat_amount'] as num?)?.toDouble() ?? 0.0,
            'category_code': _scanResult?['category_code'] ?? 'OPEX-GROCERY',
            'images_base64': base64List,
            'qr_code_raw': _zatcaQrRaw,
            'user_id': supabase.auth.currentUser?.id,
            'needs_cloud_enrichment': true,
            ..._nafaqahFields,
          },
        );
        _safeSetState(() => _isAnalyzing = false);
        if (mounted) {
          AppSnackBar.showSuccess(
            context,
            context.tr('offline_draft_notice'),
            title: context.tr('offline_draft_badge'),
          );
          _notifyGlobalProviders();
          Navigator.pop(context);
        }
        return;
      } on OfflineQueueWriteException catch (queueErr) {
        debugPrint('[ReceiptScanner] Offline draft write failed: $queueErr');
        _safeSetState(() {
          _isAnalyzing = false;
          _errorMessage = context.tr('offline_queue_failed');
        });
        return;
      } catch (_) {}

      _safeSetState(() {
        _isAnalyzing = false;
        _errorMessage = context.trArgs('scan_save_failed_msg', {'error': e});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 20,
        right: 20,
        top: 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.borderColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.document_scanner_outlined, color: AppThemes.success, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    context.tr('scan_invoice_title'),
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: context.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              context.tr('scan_invoice_desc'),
              style: GoogleFonts.outfit(fontSize: 13, color: context.textSecondary),
            ),
            const SizedBox(height: 16),

            // ── ZATCA QR Status Badge ──
            if (_zatcaDecoded != null)
              ZatcaStatusBadge(
                seller: _zatcaDecoded!['seller'] ?? context.tr('merchant_generic'),
                total: (_zatcaDecoded!['total'] as num?)?.toDouble() ?? 0.0,
                vat: (_zatcaDecoded!['vat'] as num?)?.toDouble() ?? 0.0,
                onDismiss: () => setState(() {
                  _zatcaQrRaw = null;
                  _zatcaDecoded = null;
                }),
              ),

            if (_scanResult?['is_offline_draft'] == true) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFE5A93C).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE5A93C).withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.cloud_off_rounded, color: Color(0xFFE5A93C), size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.tr('offline_draft_badge'),
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: const Color(0xFFE5A93C),
                            ),
                          ),
                          Text(
                            context.tr('offline_draft_notice'),
                            style: TextStyle(
                              fontSize: 11,
                              color: context.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // ── Photo Grid / Thumbnails ──
            ReceiptPhotoStrip(
              imageFiles: _imageFiles,
              onAddPhoto: () => _addPhoto(ImageSource.camera),
              onRemovePhoto: _removePhoto,
            ),

            // ── Capture Controls ──
            if (!_isAnalyzing && _scanResult == null) ...[
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppThemes.success,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: Text(
                        _imageFiles.isEmpty ? context.tr('snap_photo') : context.tr('snap_next_page'),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onPressed: () => _addPhoto(ImageSource.camera),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: context.textPrimary,
                        side: BorderSide(color: context.borderColor),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: Text(context.tr('gallery')),
                      onPressed: () => _addPhoto(ImageSource.gallery),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppThemes.success,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.qr_code_scanner, size: 20),
                      label: Text(context.tr('scan_qr_camera'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      onPressed: _isAnalyzing ? null : _scanZatcaQrWithCamera,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF58A6FF),
                        side: BorderSide(color: const Color(0xFF1F6FEB).withValues(alpha: 0.4)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.paste_rounded, size: 18),
                      label: Text(context.tr('paste_text'), style: const TextStyle(fontSize: 13)),
                      onPressed: _isAnalyzing ? null : _showZatcaQrDialog,
                    ),
                  ),
                ],
              ),

              // ── ZATCA QR & Photo Actions ──
              if (_zatcaDecoded != null && _scanResult == null) ...[
                const SizedBox(height: 12),
                StoreAttributionCard(
                  merchantController: _merchantController,
                  selectedSpentBy: _selectedSpentBy,
                  onSpentByChanged: (v) => setState(() => _selectedSpentBy = v),
                ),
                if (_imageFiles.isEmpty) ...[
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1F6FEB),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.camera_alt_rounded, size: 20),
                    label: Text(
                      context.tr('scan_snap_to_extract'),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    onPressed: _isAnalyzing ? null : () async {
                      await _addPhoto(ImageSource.camera);
                      if (_imageFiles.isNotEmpty && mounted) {
                        await _analyzeReceipt();
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: context.textSecondary,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    icon: const Icon(Icons.check_circle_outline, size: 16),
                    label: Text(
                      context.trArgs('scan_save_total_only', {'amount': context.sar((_zatcaDecoded!['total'] as num?) ?? 0)}),
                      style: const TextStyle(fontSize: 12),
                    ),
                    onPressed: _isAnalyzing ? null : () => _confirmSave(allowDuplicate: false),
                  ),
                ] else ...[
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppThemes.success,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.auto_awesome, size: 20),
                    label: Text(
                      context.trArgs('scan_extract_and_verify', {'amount': context.sar((_zatcaDecoded!['total'] as num?) ?? 0)}),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    onPressed: _isAnalyzing ? null : _analyzeReceipt,
                  ),
                ],
              ] else if (_imageFiles.isNotEmpty && _zatcaDecoded == null && _scanResult == null) ...[
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1F6FEB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.auto_awesome),
                  label: Text(
                    context.trArgs('scan_extract_from_photos', {'count': _imageFiles.length}),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  onPressed: _analyzeReceipt,
                ),
              ],
              const SizedBox(height: 16),
            ],

            // ── Loading state ──
            if (_isAnalyzing) ...[
              Container(
                padding: const EdgeInsets.all(24),
                alignment: Alignment.center,
                child: Column(
                  children: [
                    const CircularProgressIndicator(color: AppThemes.success),
                    const SizedBox(height: 16),
                    Text(
                      context.tr('scan_ai_scanning'),
                      style: GoogleFonts.outfit(fontWeight: FontWeight.w600, color: context.textPrimary, fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.trArgs('scan_reading_items', {'count': _imageFiles.length}),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(fontSize: 12, color: context.textSecondary),
                    ),
                  ],
                ),
              ),
            ],

            // ── Error state ──
            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(color: Colors.redAccent, fontSize: 13, height: 1.3),
                          ),
                        ),
                      ],
                    ),
                    if (_errorMessage!.toLowerCase().contains('camera') ||
                        _errorMessage!.toLowerCase().contains('permission')) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppThemes.success,
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              icon: const Icon(Icons.settings, size: 16),
                              label: Text(context.tr('open_settings'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                              onPressed: () => openAppSettings(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: BorderSide(color: context.borderColor),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              icon: const Icon(Icons.refresh, size: 16),
                              label: Text(context.tr('try_again'), style: const TextStyle(fontSize: 12)),
                              onPressed: () => _addPhoto(ImageSource.camera),
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      const SizedBox(height: 10),
                      OutlinedButton(
                        onPressed: () => setState(() {
                          _errorMessage = null;
                          _isAnalyzing = false;
                        }),
                        child: Text(context.tr('dismiss')),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ── Results content ──
            if (_scanResult != null && !_isAnalyzing) ...[
              _buildResultContent(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResultContent() {
    final status = _scanResult!['status'] as String? ?? '';
    final isCandidate = status == 'duplicate_candidate';
    final isSuccess = status == 'success' || status == 'enriched';

    final merchant = _zatcaDecoded?['seller'] as String? ??
        _scanResult!['merchant'] ??
        _scanResult!['parsed_data']?['merchant'] ??
        context.tr('merchant_generic');

    final num amountNum = (_zatcaDecoded?['total'] as num?) ??
        (_scanResult!['amount'] ??
        _scanResult!['parsed_data']?['amount'] ??
        0.0) as num;
    final amount = amountNum.toDouble();

    final categoryCode = _scanResult!['category_code'] ??
        _scanResult!['parsed_data']?['category_code'];

    final dynamic rawItems = _scanResult!['items'] ?? _scanResult!['parsed_data']?['items'];
    final List<Map<String, dynamic>> items = (rawItems is List)
        ? rawItems.map((e) => Map<String, dynamic>.from(e as Map)).toList()
        : <Map<String, dynamic>>[];

    final isZatcaVerified = _zatcaDecoded != null || _scanResult!['zatca_verified'] != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isSuccess) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppThemes.success.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppThemes.success),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: AppThemes.success, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr('scan_saved_success_title'),
                        style: GoogleFonts.outfit(color: context.textPrimary, fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${context.trArgs('scan_items_logged', {'count': items.length, 'merchant': merchant, 'amount': context.sar(amount)})}${isZatcaVerified ? ' • ${context.tr('scan_zatca_verified')}' : ''}',
                        style: TextStyle(color: context.successText, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        if (isCandidate) ...[
          DuplicateCandidateCard(
            message: _scanResult!['message'] ?? context.tr('scan_identical_recent'),
            itemCount: items.length,
            onEnrich: () {
              final cId = _scanResult!['candidate_transaction_id'];
              _confirmSave(enrichTxId: cId);
            },
            onLogSeparate: () => _confirmSave(allowDuplicate: true),
            onDiscard: () {
              Navigator.of(context).pop();
              AppSnackBar.showInfo(
                context,
                context.tr('scan_duplicate_discarded'),
                title: context.tr('scan_discarded'),
                icon: Icons.delete_sweep_outlined,
              );
            },
          ),
        ],

        if (!isSuccess && !isCandidate && isZatcaVerified) ...[
          ZatcaStatusBadge(
            seller: merchant,
            total: amount,
            vat: (_zatcaDecoded?['vat'] as num?)?.toDouble() ?? (amount * 0.15 / 1.15),
            customSubtitle: context.trArgs('scan_total_items_extracted', {'amount': context.sar(amount), 'count': items.length}),
          ),
        ],

        if (!isSuccess) ...[
          StoreAttributionCard(
            merchantController: _merchantController,
            selectedSpentBy: _selectedSpentBy,
            onSpentByChanged: (v) => setState(() => _selectedSpentBy = v),
          ),
          if (_nafaqah.canClassify) ...[
            NafaqahReviewSection(
              key: const ValueKey('receipt_nafaqah_review'),
              preview: _nafaqah,
              value: _nafaqahClass,
              wifeId: _nafaqahWifeId,
              showWifeRequired: _showWifeRequired,
              onChanged: (cls) => setState(() => _nafaqahClass = cls),
              onWifeChanged: (id) => setState(() => _nafaqahWifeId = id),
            ),
            const SizedBox(height: 12),
          ],
          if (!isCandidate && isZatcaVerified && _imageFiles.isEmpty) ...[
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1F6FEB),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.camera_alt_rounded, size: 18),
              label: Text(
                context.tr('scan_snap_to_extract_ai'),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              onPressed: () async {
                await _addPhoto(ImageSource.camera);
                if (_imageFiles.isNotEmpty && mounted) {
                  await _analyzeReceipt();
                }
              },
            ),
            const SizedBox(height: 12),
          ],
        ],

        TransactionItemBreakdownCard(
          merchant: _merchantController.text.trim().isNotEmpty
              ? _merchantController.text.trim()
              : merchant,
          amount: amount,
          categoryCode: categoryCode,
          source: 'receipt_scan',
          spentBy: _selectedSpentBy,
          items: items,
          initiallyExpanded: true,
        ),
        const SizedBox(height: 16),

        if (isSuccess) ...[
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppThemes.success,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.check_circle_outline, size: 20),
            label: Text(
              context.tr('scan_done_view_dashboard'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            onPressed: () => Navigator.pop(context, true),
          ),
          const SizedBox(height: 8),
        ] else if (!isCandidate) ...[
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppThemes.success,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.cloud_upload_outlined, size: 20),
            label: Text(
              context.trArgs('scan_confirm_save_items', {'count': items.length, 'amount': context.sar(amount)}),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            onPressed: () => _confirmSave(allowDuplicate: false),
          ),

          const SizedBox(height: 8),
        ],

        TextButton.icon(
          icon: const Icon(Icons.refresh_rounded, size: 16),
          onPressed: () => setState(() {
            _imageFiles.clear();
            _zatcaQrRaw = null;
            _zatcaDecoded = null;
            _scanResult = null;
            _applyNafaqahPreview(null);
          }),
          label: Text(context.tr('scan_another_receipt'), style: TextStyle(color: context.textSecondary)),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
