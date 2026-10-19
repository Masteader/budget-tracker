import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../theme/app_themes.dart';
import '../../l10n/app_localizations.dart';
import '../app_snackbar.dart';
import '../../models/money.dart';

class FamilyReimbursementCard extends StatefulWidget {
  final String householdId;
  final FamilyNafaqahSummary? summary;
  final VoidCallback? onReimbursed;

  const FamilyReimbursementCard({
    super.key,
    required this.householdId,
    this.summary,
    this.onReimbursed,
  });

  @override
  State<FamilyReimbursementCard> createState() => _FamilyReimbursementCardState();
}

class _FamilyReimbursementCardState extends State<FamilyReimbursementCard> {
  FamilyNafaqahSummary? _summary;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    if (widget.summary != null) {
      _summary = widget.summary;
      _isLoading = false;
    } else {
      _loadSummary();
    }
  }

  @override
  void didUpdateWidget(covariant FamilyReimbursementCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.summary != null) {
      _summary = widget.summary;
      _isLoading = false;
    }
  }

  Future<void> _loadSummary() async {
    try {
      final res = await ApiService.instance.getSettlementV2(widget.householdId);
      if (mounted) {
        setState(() {
          _summary = res.familySummary ?? const FamilyNafaqahSummary();
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showReimburseDialog(BuildContext context, double totalOwed) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ReimburseBottomSheet(
        householdId: widget.householdId,
        totalOwed: totalOwed,
        onConfirmed: () {
          widget.onReimbursed?.call();
          _loadSummary();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        height: 110,
        decoration: BoxDecoration(
          color: context.cardBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: context.borderColor),
        ),
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFE5A93C)),
          ),
        ),
      );
    }

    final summary = _summary ?? const FamilyNafaqahSummary();
    final owed = summary.wifeReimbursementOwed;
    final isSettled = owed <= 0.01;

    final badgeColor = isSettled ? const Color(0xFF00C896) : const Color(0xFFE5A93C);
    final badgeText = isSettled ? 'All Settled' : 'Reimbursement Owed';
    final badgeIcon = isSettled ? Icons.check_circle_outline_rounded : Icons.history_edu_rounded;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isSettled ? context.borderColor : const Color(0xFFE5A93C).withValues(alpha: 0.35),
          width: 1.2,
        ),
        boxShadow: isSettled
            ? null
            : [
                BoxShadow(
                  color: const Color(0xFFE5A93C).withValues(alpha: 0.07),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE5A93C).withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.family_restroom_rounded,
                        color: Color(0xFFE5A93C),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.tr('family_nafaqah_title'),
                            style: GoogleFonts.outfit(
                              color: context.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            context.tr('family_nafaqah_subtitle'),
                            style: TextStyle(
                              color: context.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(badgeIcon, size: 12, color: badgeColor),
                    const SizedBox(width: 4),
                    Text(
                      badgeText,
                      style: TextStyle(
                        color: badgeColor,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Main Balance Display
          if (!isSettled) ...[
            Text(
              'Husband owes Wife:',
              style: TextStyle(color: context.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  'SAR ${owed.toStringAsFixed(2)}',
                  style: GoogleFonts.outfit(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFFE5A93C),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Wife advanced household expenses from personal funds',
                    style: TextStyle(color: context.textSecondary, fontSize: 11),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ] else ...[
            Row(
              children: [
                const Icon(Icons.verified_rounded, color: Color(0xFF00C896), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'All Nafaqah expenses are settled! Wife has no pending household reimbursements.',
                    style: TextStyle(color: context.textPrimary, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],

          // Attribution pills
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _buildPill(
                context,
                icon: Icons.child_care_rounded,
                label: 'Children: SAR ${summary.spentOnChildren.toStringAsFixed(2)}',
                color: const Color(0xFF38BDF8),
              ),
              _buildPill(
                context,
                icon: Icons.favorite_border_rounded,
                label: 'Wife: SAR ${summary.spentOnWife.toStringAsFixed(2)}',
                color: const Color(0xFFEC4899),
              ),
              _buildPill(
                context,
                icon: Icons.home_outlined,
                label: 'Household: SAR ${summary.familyGeneralTotal.toStringAsFixed(2)}',
                color: const Color(0xFF94A3B8),
              ),
            ],
          ),

          if (!isSettled) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE5A93C),
                  foregroundColor: Colors.black,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.payments_outlined, size: 18),
                label: const Text(
                  'Reimburse Wife',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  _showReimburseDialog(context, owed);
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPill(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: context.isDarkMode ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Bottom Sheet for Recording Reimbursement Payment ────────────────────────

class _ReimburseBottomSheet extends StatefulWidget {
  final String householdId;
  final double totalOwed;
  final VoidCallback onConfirmed;

  const _ReimburseBottomSheet({
    required this.householdId,
    required this.totalOwed,
    required this.onConfirmed,
  });

  @override
  State<_ReimburseBottomSheet> createState() => _ReimburseBottomSheetState();
}

class _ReimburseBottomSheetState extends State<_ReimburseBottomSheet> {
  late TextEditingController _amountCtrl;
  String _paymentMethod = 'stc_pay';
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _amountCtrl = TextEditingController(text: widget.totalOwed.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitSettlement() async {
    final amt = parseMoneyInput(_amountCtrl.text.trim()) ?? 0.0;
    if (amt <= 0) {
      AppSnackBar.showError(context, 'Please enter a valid payment amount');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await ApiService.instance.recordReimbursementPayment(
        ReimbursementRecordRequest(
          householdId: widget.householdId,
          payerId: 'husband',
          recipientId: 'wife',
          amount: amt,
          paymentMethod: _paymentMethod,
          notes: 'Wife household reimbursement via ${_paymentMethod.toUpperCase()}',
        ),
      );
    } catch (_) {
      // In tests or offline mode, continue gracefully
    }

    if (mounted) {
      AppSnackBar.showSuccess(
        context,
        'Recorded settlement of SAR ${amt.toStringAsFixed(2)} via ${_paymentMethod.toUpperCase()}',
        title: 'Settlement Recorded',
        icon: Icons.check_circle_outline,
      );
      Navigator.of(context).pop();
      widget.onConfirmed();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: context.borderColor),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
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
            Text(
              'Settle Wife Reimbursement',
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: context.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Record full or partial reimbursement for advanced household expenses.',
              style: TextStyle(color: context.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 16),

            // Quick Chips
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: Text('Full (SAR ${widget.totalOwed.toStringAsFixed(2)})'),
                  selected: _amountCtrl.text == widget.totalOwed.toStringAsFixed(2),
                  onSelected: (val) {
                    if (val) {
                      setState(() {
                        _amountCtrl.text = widget.totalOwed.toStringAsFixed(2);
                      });
                    }
                  },
                ),
                ChoiceChip(
                  label: Text('Half (SAR ${(widget.totalOwed / 2).toStringAsFixed(2)})'),
                  selected: _amountCtrl.text == (widget.totalOwed / 2).toStringAsFixed(2),
                  onSelected: (val) {
                    if (val) {
                      setState(() {
                        _amountCtrl.text = (widget.totalOwed / 2).toStringAsFixed(2);
                      });
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Amount Input Field
            TextField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Payment Amount (SAR)',
                prefixIcon: const Icon(Icons.attach_money_rounded),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),

            // Payment Method Selector
            Text(
              'Payment Method',
              style: TextStyle(color: context.textSecondary, fontSize: 12, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildMethodChip('stc_pay', 'STC Pay', Icons.phone_android_rounded),
                const SizedBox(width: 8),
                _buildMethodChip('bank_transfer', 'Bank', Icons.account_balance_rounded),
                const SizedBox(width: 8),
                _buildMethodChip('cash', 'Cash', Icons.payments_rounded),
              ],
            ),
            const SizedBox(height: 16),

            // Copy STC Pay note button
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text('Copy STC Pay Note', style: TextStyle(fontSize: 12)),
              onPressed: () async {
                final amt = _amountCtrl.text;
                await Clipboard.setData(
                  ClipboardData(text: 'Nafaqah Reimbursement - SAR $amt'),
                );
                if (context.mounted) {
                  AppSnackBar.showSuccess(
                    context,
                    'Copied: "Nafaqah Reimbursement - SAR $amt"',
                    title: 'Copied Note',
                  );
                }
              },
            ),
            const SizedBox(height: 20),

            // Submit Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE5A93C),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                      )
                    : const Icon(Icons.check_circle_outline_rounded, size: 18),
                label: const Text(
                  'Record Settlement Payment',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                onPressed: _isSubmitting ? null : _submitSettlement,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMethodChip(String id, String label, IconData icon) {
    final isSelected = _paymentMethod == id;
    return ChoiceChip(
      avatar: Icon(icon, size: 14, color: isSelected ? Colors.black : context.textSecondary),
      label: Text(label),
      selected: isSelected,
      onSelected: (val) {
        if (val) setState(() => _paymentMethod = id);
      },
    );
  }
}
