import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../l10n/app_localizations.dart';
import '../../models/nafaqah.dart';
import '../../models/transaction_attribution.dart';
import '../../providers/budget_provider.dart';
import '../../providers/household_role_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../services/api/base_api_client.dart' show BaseApiClient;
import '../../services/api_service.dart';
import '../../services/offline_queue_manager.dart';
import '../../services/nafaqah_write_errors.dart';
import '../../theme/app_themes.dart';
import '../receipt_photo_viewer_dialog.dart';
import '../app_snackbar.dart';
import '../nafaqah/nafaqah_review_section.dart';
import '../../models/money.dart';
import '../../models/category_catalog.dart';

/// Sequential review modal for processing a batch of captured receipts step by step.
class BatchItemReviewSheet extends StatefulWidget {
  final List<File> receiptImages;
  final String householdId;
  /// Reads a receipt photo (defaults to the receipt API's preview).
  final Future<Map<String, dynamic>> Function(File file)? previewReceipt;

  /// Stores one reviewed receipt (defaults to a direct insert, or the
  /// offline queue when that fails).
  final Future<void> Function(Map<String, dynamic> receipt)? saveReceipt;
  final void Function(int savedCount, double totalAmount)? onComplete;

  const BatchItemReviewSheet({
    super.key,
    required this.receiptImages,
    required this.householdId,
    this.previewReceipt,
    this.saveReceipt,
    this.onComplete,
  });

  @override
  State<BatchItemReviewSheet> createState() => _BatchItemReviewSheetState();
}

class _BatchItemReviewSheetState extends State<BatchItemReviewSheet> {
  int _currentIndex = 0;
  int _savedCount = 0;
  double _totalBatchAmount = 0.0;
  bool _isAnalyzing = false;
  bool _isSaving = false;
  bool _batchFinished = false;

  late final TextEditingController _merchantCtrl;
  late final TextEditingController _amountCtrl;
  late final TextEditingController _vatCtrl;

  String _selectedCategory = 'OPEX-GROCERY';
  final String _selectedSpentBy = 'both';
  bool _isOfflineDraft = false;

  // Family (Islamic Nafaqah), per receipt: the server's suggestion from the
  // preview and the user's choice (a wife's shared advance the husband owes,
  // or her personal purchase from her allowance; never split).
  NafaqahPreview _nafaqah = const NafaqahPreview();
  String? _nafaqahClass;
  String? _nafaqahWifeId;
  bool _showWifeRequired = false;

  void _applyNafaqahPreview(Map<String, dynamic>? res) {
    // Only the wife, the provider (husband) or an admin classifies.
    _nafaqah = NafaqahPreview.fromPreview(res).withAdmin(viewerIsAdminOf(context, widget.householdId));
    _nafaqahClass = _nafaqah.suggestedClass;
    _nafaqahWifeId = _nafaqah.defaultSpouseId;
    _showWifeRequired = false;
  }

  Map<String, String> get _nafaqahRequestFields =>
      _nafaqah.requestFields(_nafaqahClass, chosenWifeId: _nafaqahWifeId);

  static const List<String> _categories = CategoryCatalog.pickerCodes;

  @override
  void initState() {
    super.initState();
    _merchantCtrl = TextEditingController();
    _amountCtrl = TextEditingController();
    _vatCtrl = TextEditingController();

    _loadReceiptAtIndex(0);
  }

  @override
  void dispose() {
    _merchantCtrl.dispose();
    _amountCtrl.dispose();
    _vatCtrl.dispose();
    super.dispose();
  }

  /// Owner of queued drafts, so another account never replays them (FR-A-09).
  String? get _currentUserId {
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  void _notifyGlobalProviders() {
    if (!mounted) return;
    try {
      context.read<TransactionProvider>().refresh();
      context.read<BudgetProvider>().refresh();
    } catch (_) {}
  }

  Future<void> _loadReceiptAtIndex(int index) async {
    if (index >= widget.receiptImages.length) {
      setState(() {
        _batchFinished = true;
      });
      widget.onComplete?.call(_savedCount, _totalBatchAmount);
      return;
    }

    final file = widget.receiptImages[index];

    setState(() {
      _currentIndex = index;
      _isAnalyzing = true;
      _merchantCtrl.text = '';
      _amountCtrl.text = '';
      _vatCtrl.text = '';
      _isOfflineDraft = false;
      _applyNafaqahPreview(null);
    });

    try {
      final preview = widget.previewReceipt;
      if (preview != null || await file.exists()) {
        final res = preview != null ? await preview(file) : await _previewViaApi(file);
        // Offline: keep the photo as a draft the server reads later (R8).
        if (res[BaseApiClient.networkErrorKey] == true) throw const SocketException('offline');

        // Photos too large for the server (413) are never parsed: say so.
        if (mounted && res['status'] == 'error' && res['status_code'] == 413) {
          AppSnackBar.showError(context, expenseApiErrorText(context, res)!);
        }
        if (mounted) {
          final merchant = res['merchant'] as String? ?? res['parsed_data']?['merchant'] as String? ?? '';
          final amount = (res['amount'] as num?)?.toDouble() ?? 0.0;
          final vat = (res['vat_amount'] as num?)?.toDouble() ?? 0.0;
          final cat = res['category_code'] as String? ?? 'OPEX-GROCERY';

          setState(() {
            _merchantCtrl.text = merchant;
            _amountCtrl.text = amount > 0 ? amount.toStringAsFixed(2) : '';
            _vatCtrl.text = vat > 0 ? vat.toStringAsFixed(2) : '0.00';
            _selectedCategory = _categories.contains(cat) ? cat : 'OPEX-GROCERY';
            _isAnalyzing = false;
            _isOfflineDraft = res['is_offline_draft'] as bool? ?? false;
            _applyNafaqahPreview(res);
          });
          return;
        }
      }
    } catch (_) {
      // Offline: the photo is saved as a pending draft and read by the
      // server when back online. Nothing is guessed; the user may type the
      // amount (R8).
      if (mounted) {
        setState(() {
          _merchantCtrl.text = '';
          _amountCtrl.text = '';
          _vatCtrl.text = '';
          _isOfflineDraft = true;
          _isAnalyzing = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _merchantCtrl.text = '';
        _amountCtrl.text = '';
        _vatCtrl.text = '';
        _isAnalyzing = false;
      });
    }
  }

  Future<Map<String, dynamic>> _previewViaApi(File file) async {
    final bytes = await file.readAsBytes();
    return ApiService.instance.scanReceipt(
      imagesBase64: [base64Encode(bytes)],
      householdId: widget.householdId,
      previewOnly: true,
    );
  }

  Future<void> _saveAndNext() async {
    if (_isSaving || _isAnalyzing) return;
    if (!NafaqahReviewSection.hasRequiredWife(_nafaqah, _nafaqahClass, _nafaqahWifeId)) {
      setState(() => _showWifeRequired = true);
      return;
    }

    final parsedAmount = parseMoneyInput(_amountCtrl.text.trim()) ?? 0.0;
    final parsedVat = parseMoneyInput(_vatCtrl.text.trim()) ?? 0.0;
    final typedMerchant = _merchantCtrl.text.trim();
    // An offline draft keeps an empty merchant (the server reads it later).
    final merchant = typedMerchant.isNotEmpty || _isOfflineDraft ? typedMerchant : context.tr('store_name');

    setState(() => _isSaving = true);

    try {
      final file = widget.receiptImages[_currentIndex];
      final save = widget.saveReceipt;

      if (save != null) {
        await save({
          'merchant': merchant,
          'amount': parsedAmount,
          'vat_amount': parsedVat,
          'category_code': _selectedCategory,
          'is_offline_draft': _isOfflineDraft,
          'image_local_path': file.path,
          ..._nafaqahRequestFields,
        });
      } else if (_isOfflineDraft) {
        await OfflineQueueManager().enqueueOrThrow(
          operationType: 'receipt_offline_draft',
          householdId: widget.householdId,
          payload: {
            if (merchant.isNotEmpty) 'merchant': merchant,
            if (parsedAmount > 0) 'amount': parsedAmount,
            'vat_amount': parsedVat,
            'category_code': _selectedCategory,
            'spent_by': _selectedSpentBy,
            'image_local_path': file.path,
            'needs_cloud_enrichment': true,
            'user_id': _currentUserId,
            ..._nafaqahRequestFields,
          },
        );
      } else {
        // Attempt saving online transaction
        try {
          final user = Supabase.instance.client.auth.currentUser;
          final nafaqahFields = _nafaqahRequestFields;
          await Supabase.instance.client.from('transactions').insert({
            'household_id': widget.householdId,
            'user_id': user?.id,
            'merchant': merchant,
            'amount': parsedAmount,
            'category_code': _selectedCategory,
            // Who paid and for whom as the receipt API stores them (FABLE2-APP-06).
            ...directInsertAttribution(
              paidBy: nafaqahFields['paid_by'],
              beneficiary: nafaqahFields['beneficiary'],
              creatorId: user?.id,
            ),
            'source': 'receipt_scan',
            // `transactions` has no `date`/`vat_amount` columns: an insert
            // naming them always failed and diverted every save offline.
            'timestamp': DateTime.now().toUtc().toIso8601String(),
            'raw_sms': 'Receipt Scan: $merchant | VAT: ${parsedVat.toStringAsFixed(2)} SAR',
            // Family Nafaqah: the wife's debt or allowance spending (both columns together).
            ..._nafaqah.transactionColumns(
              _nafaqahClass,
              chosenWifeId: _nafaqahWifeId,
              currentUserId: user?.id,
            ),
          });
        } catch (e) {
          // A Nafaqah rule refused the row (no provider yet): replaying it
          // offline could never succeed, so explain instead of queueing.
          if (nafaqahWriteRefusalOf(e) != null) rethrow;
          // If network failed during submit, queue offline
          await OfflineQueueManager().enqueueOrThrow(
            operationType: 'receipt_offline_draft',
            householdId: widget.householdId,
            payload: {
              'merchant': merchant,
              'amount': parsedAmount,
              'vat_amount': parsedVat,
              'category_code': _selectedCategory,
              'spent_by': _selectedSpentBy,
              'image_local_path': file.path,
              'needs_cloud_enrichment': true,
              'user_id': _currentUserId,
              ..._nafaqahRequestFields,
            },
          );
        }
      }

      _savedCount++;
      _totalBatchAmount += parsedAmount;
      _notifyGlobalProviders();
    } catch (e) {
      // MOB-28: neither the online insert nor the offline queue stored this
      // receipt. Do not count it as saved; stay on it so the user can retry
      // or skip.
      debugPrint('[BatchItemReview] Receipt not saved: $e');
      if (mounted) {
        setState(() => _isSaving = false);
        final nafaqahError = nafaqahWriteErrorText(context, e);
        AppSnackBar.showError(
          context,
          nafaqahError ?? context.tr('offline_queue_failed'),
          title: nafaqahError != null ? context.tr('action_failed') : context.tr('offline_queue_failed_title'),
        );
      }
      return;
    }
    if (mounted) {
      setState(() => _isSaving = false);
      _advanceQueue();
    }
  }

  void _skipReceipt() {
    _advanceQueue();
  }

  void _advanceQueue() {
    final nextIndex = _currentIndex + 1;
    if (nextIndex < widget.receiptImages.length) {
      _loadReceiptAtIndex(nextIndex);
    } else {
      setState(() {
        _batchFinished = true;
      });
      widget.onComplete?.call(_savedCount, _totalBatchAmount);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_batchFinished) {
      return _buildCompletionCard(context);
    }

    final total = widget.receiptImages.length;
    final current = _currentIndex + 1;
    final progress = total > 0 ? (current / total).clamp(0.0, 1.0) : 1.0;
    final isLast = current == total;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      // Scrolls when the family Nafaqah choice and the keyboard need the room.
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Stepper Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  context.trArgs('receipt_n_of_m', {'current': current, 'total': total}),
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: context.electricTeal,
                  ),
                ),
                if (_isOfflineDraft)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.wifi_off_rounded, size: 12, color: Colors.orange),
                        const SizedBox(width: 4),
                        Text(
                          context.tr('offline_draft_badge'),
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.orange,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (_isOfflineDraft)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  context.tr('offline_receipt_pending_notice'),
                  key: const ValueKey('batch_offline_notice'),
                  style: TextStyle(color: context.textSecondary, fontSize: 11.5),
                ),
              ),

            // Progress Bar
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.white12,
                valueColor: AlwaysStoppedAnimation<Color>(context.electricTeal),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 16),

            // Thumbnail Preview
            _buildThumbnailPreview(context),
            const SizedBox(height: 16),

            if (_isAnalyzing)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Column(
                    children: [
                      CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(context.electricTeal),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        context.tr('bir_analyzing'),
                        style: GoogleFonts.outfit(color: context.textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              // Form Fields
              TextField(
                controller: _merchantCtrl,
                decoration: InputDecoration(
                  labelText: context.tr('merchant'),
                  labelStyle: TextStyle(color: context.textSecondary),
                  prefixIcon: const Icon(Icons.storefront_rounded, size: 20),
                  filled: true,
                  fillColor: context.isDark ? AppThemes.deepGlacial : Colors.grey.shade100,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _amountCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: context.tr('bir_total_sar'),
                        labelStyle: TextStyle(color: context.textSecondary),
                        prefixIcon: const Icon(Icons.receipt_long_rounded, size: 20),
                        filled: true,
                        fillColor: context.isDark ? AppThemes.deepGlacial : Colors.grey.shade100,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 1,
                    child: TextField(
                      controller: _vatCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: context.tr('bir_vat'),
                        labelStyle: TextStyle(color: context.textSecondary),
                        filled: true,
                        fillColor: context.isDark ? AppThemes.deepGlacial : Colors.grey.shade100,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Category Dropdown
              DropdownButtonFormField<String>(
                initialValue: _selectedCategory,
                decoration: InputDecoration(
                  labelText: context.tr('category'),
                  labelStyle: TextStyle(color: context.textSecondary),
                  prefixIcon: const Icon(Icons.category_rounded, size: 20),
                  filled: true,
                  fillColor: context.isDark ? AppThemes.deepGlacial : Colors.grey.shade100,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                items: _categories.map((c) {
                  return DropdownMenuItem<String>(
                    value: c,
                    child: Text(context.trCat(c)),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedCategory = val);
                },
              ),
              if (_nafaqah.canClassify) ...[
                const SizedBox(height: 12),
                NafaqahReviewSection(
                  key: const ValueKey('batch_nafaqah_review'),
                  preview: _nafaqah,
                  value: _nafaqahClass,
                  wifeId: _nafaqahWifeId,
                  showWifeRequired: _showWifeRequired,
                  onChanged: (cls) => setState(() => _nafaqahClass = cls),
                  onWifeChanged: (id) => setState(() => _nafaqahWifeId = id),
                ),
              ],
              const SizedBox(height: 20),

              // Action Buttons
              Row(
                children: [
                  // Skip Button
                  Expanded(
                    child: OutlinedButton(
                      key: const Key('batch_skip_button'),
                      onPressed: _skipReceipt,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(color: context.textSecondary.withValues(alpha: 0.4)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        context.tr('skip_receipt'),
                        style: GoogleFonts.outfit(
                          color: context.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Save & Next Button
                  Expanded(
                    child: ElevatedButton(
                      key: const Key('batch_save_next_button'),
                      onPressed: _saveAndNext,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: context.electricTeal,
                        foregroundColor: AppThemes.brandDarkBg,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 2,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                            )
                          : Text(
                              isLast ? context.tr('save_and_finish') : context.tr('save_and_next'),
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnailPreview(BuildContext context) {
    if (_currentIndex >= widget.receiptImages.length) {
      return const SizedBox.shrink();
    }
    final file = widget.receiptImages[_currentIndex];
    final exists = file.existsSync();

    return Center(
      child: GestureDetector(
        onTap: () {
          if (exists) {
            ReceiptPhotoViewerDialog.show(
              context,
              receiptUrl: file.path,
              merchant: _merchantCtrl.text,
              amount: parseMoneyInput(_amountCtrl.text),
            );
          }
        },
        child: Container(
          width: double.infinity,
          height: 120,
          decoration: BoxDecoration(
            color: context.isDark ? AppThemes.deepGlacial : Colors.grey.shade200,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.iceCyan.withValues(alpha: 0.3)),
          ),
          child: exists
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    file,
                    fit: BoxFit.cover,
                    width: double.infinity,
                  ),
                )
              : Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.receipt_rounded, size: 40, color: context.electricTeal),
                      const SizedBox(height: 6),
                      Text(
                        file.path.split(Platform.pathSeparator).last,
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: context.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildCompletionCard(BuildContext context) {
    return Container(
      key: const Key('batch_complete_card'),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: context.electricTeal.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.check_circle_rounded, color: context.electricTeal, size: 40),
          ),
          const SizedBox(height: 16),
          Text(
            context.tr('batch_complete_title'),
            style: GoogleFonts.outfit(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: context.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            context.tr('batch_complete_desc'),
            style: GoogleFonts.outfit(
              fontSize: 13,
              color: context.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: context.isDark ? AppThemes.deepGlacial : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.electricTeal.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    Text(
                      '$_savedCount',
                      style: GoogleFonts.outfit(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: context.electricTeal,
                      ),
                    ),
                    Text(
                      context.tr('bir_saved'),
                      style: GoogleFonts.outfit(fontSize: 12, color: context.textSecondary),
                    ),
                  ],
                ),
                Container(width: 1, height: 30, color: Colors.white12),
                Column(
                  children: [
                    Text(
                      context.sar(_totalBatchAmount),
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: context.iceCyan,
                      ),
                    ),
                    Text(
                      context.tr('bir_total_logged'),
                      style: GoogleFonts.outfit(fontSize: 12, color: context.textSecondary),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: context.electricTeal,
                foregroundColor: AppThemes.brandDarkBg,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                context.tr('return_to_dashboard'),
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
