import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../theme/app_themes.dart';
import '../../l10n/app_localizations.dart';
import '../app_snackbar.dart';

class MultiRoommateSettlementCard extends StatefulWidget {
  final String householdId;
  final SettlementV2Summary? summary;
  final VoidCallback? onSettled;

  const MultiRoommateSettlementCard({
    super.key,
    required this.householdId,
    this.summary,
    this.onSettled,
  });

  @override
  State<MultiRoommateSettlementCard> createState() => _MultiRoommateSettlementCardState();
}

class _MultiRoommateSettlementCardState extends State<MultiRoommateSettlementCard> {
  SettlementV2Summary? _summary;
  bool _isLoading = true;
  bool _simplifyDebts = true;

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
  void didUpdateWidget(covariant MultiRoommateSettlementCard oldWidget) {
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
          _summary = res;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showSettleSheet(
    BuildContext context, {
    required String fromId,
    required String toId,
    required String fromName,
    required String toName,
    required double amount,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _RoommateSettleBottomSheet(
        householdId: widget.householdId,
        fromId: fromId,
        toId: toId,
        fromName: fromName,
        toName: toName,
        amount: amount,
        onConfirmed: () {
          widget.onSettled?.call();
          _loadSummary();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        height: 120,
        decoration: BoxDecoration(
          color: context.cardBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: context.borderColor),
        ),
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF38BDF8)),
          ),
        ),
      );
    }

    final summary = _summary ?? const SettlementV2Summary(mode: 'multi_roommate');
    final activeDebts = _simplifyDebts
        ? summary.simplifiedDebts.map((d) => _DebtItem(d.fromId, d.toId, d.fromName, d.toName, d.amount)).toList()
        : summary.pairwiseDebts.map((d) => _DebtItem(d.fromId, d.toId, d.fromName, d.toName, d.amount)).toList();

    final isAllSettled = activeDebts.isEmpty;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isAllSettled ? context.borderColor : const Color(0xFF38BDF8).withValues(alpha: 0.35),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.group_outlined,
                        color: Color(0xFF38BDF8),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.tr('roommate_settlements_title'),
                            style: GoogleFonts.outfit(
                              color: context.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            context.tr('roommate_settlements_subtitle'),
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
              // Simplify Debts Switch
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Simplify Debts',
                    style: TextStyle(
                      color: _simplifyDebts ? const Color(0xFF38BDF8) : context.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Transform.scale(
                    scale: 0.75,
                    child: Switch(
                      value: _simplifyDebts,
                      activeThumbColor: const Color(0xFF38BDF8),
                      onChanged: (val) {
                        setState(() => _simplifyDebts = val);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Member Net Balances
          if (summary.roommateBalances.isNotEmpty) ...[
            Text(
              'Net Balances',
              style: TextStyle(
                color: context.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: summary.roommateBalances.entries.map((entry) {
                final balance = entry.value;
                final isPositive = balance > 0.01;
                final isNegative = balance < -0.01;
                final color = isPositive
                    ? const Color(0xFF00C896)
                    : (isNegative ? const Color(0xFFFF6B6B) : context.textSecondary);

                final prefix = isPositive ? '+SAR ' : (isNegative ? '-SAR ' : 'SAR ');
                final displayAmt = '$prefix${balance.abs().toStringAsFixed(2)}';

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: context.isDarkMode ? 0.12 : 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: color.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${entry.key.toUpperCase()}: ',
                        style: TextStyle(
                          color: context.textPrimary,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        displayAmt,
                        style: TextStyle(
                          color: color,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),
          ],

          // Debts List
          if (isAllSettled) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF00C896).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF00C896).withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline_rounded, color: Color(0xFF00C896), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'All Settled',
                          style: TextStyle(
                            color: Color(0xFF00C896),
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          'No pending roommate debts. Everyone is squared away!',
                          style: TextStyle(color: context.textSecondary, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: activeDebts.length,
              separatorBuilder: (ctx, i) => const SizedBox(height: 8),
              itemBuilder: (ctx, i) {
                final debt = activeDebts[i];
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: context.chipBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: context.borderColor),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${debt.fromName} owes ${debt.toName}',
                              style: TextStyle(
                                color: context.textPrimary,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'SAR ${debt.amount.toStringAsFixed(2)}',
                              style: GoogleFonts.outfit(
                                color: const Color(0xFF38BDF8),
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF38BDF8),
                          foregroundColor: Colors.black,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text(
                          'Settle',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          _showSettleSheet(
                            context,
                            fromId: debt.fromId,
                            toId: debt.toId,
                            fromName: debt.fromName,
                            toName: debt.toName,
                            amount: debt.amount,
                          );
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _DebtItem {
  final String fromId;
  final String toId;
  final String fromName;
  final String toName;
  final double amount;

  _DebtItem(this.fromId, this.toId, this.fromName, this.toName, this.amount);
}

// ── Bottom Sheet for Recording Roommate Settlement ──────────────────────────

class _RoommateSettleBottomSheet extends StatefulWidget {
  final String householdId;
  final String fromId;
  final String toId;
  final String fromName;
  final String toName;
  final double amount;
  final VoidCallback onConfirmed;

  const _RoommateSettleBottomSheet({
    required this.householdId,
    required this.fromId,
    required this.toId,
    required this.fromName,
    required this.toName,
    required this.amount,
    required this.onConfirmed,
  });

  @override
  State<_RoommateSettleBottomSheet> createState() => _RoommateSettleBottomSheetState();
}

class _RoommateSettleBottomSheetState extends State<_RoommateSettleBottomSheet> {
  late TextEditingController _amountCtrl;
  String _paymentMethod = 'stc_pay';
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _amountCtrl = TextEditingController(text: widget.amount.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitSettlement() async {
    final amt = double.tryParse(_amountCtrl.text.trim()) ?? 0.0;
    if (amt <= 0) {
      AppSnackBar.showError(context, 'Please enter a valid amount');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await ApiService.instance.recordReimbursementPayment(
        ReimbursementRecordRequest(
          householdId: widget.householdId,
          payerId: widget.fromId,
          recipientId: widget.toId,
          amount: amt,
          paymentMethod: _paymentMethod,
          notes: '${widget.fromName} paid ${widget.toName} via ${_paymentMethod.toUpperCase()}',
        ),
      );
    } catch (_) {}

    if (mounted) {
      AppSnackBar.showSuccess(
        context,
        'Recorded settlement: ${widget.fromName} paid ${widget.toName} SAR ${amt.toStringAsFixed(2)}',
        title: 'Settlement Recorded',
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
              'Record Roommate Settlement',
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: context.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${widget.fromName} pays ${widget.toName}',
              style: TextStyle(color: context.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),

            // Quick Chips
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: Text('Full (SAR ${widget.amount.toStringAsFixed(2)})'),
                  selected: _amountCtrl.text == widget.amount.toStringAsFixed(2),
                  onSelected: (val) {
                    if (val) {
                      setState(() => _amountCtrl.text = widget.amount.toStringAsFixed(2));
                    }
                  },
                ),
                ChoiceChip(
                  label: Text('Half (SAR ${(widget.amount / 2).toStringAsFixed(2)})'),
                  selected: _amountCtrl.text == (widget.amount / 2).toStringAsFixed(2),
                  onSelected: (val) {
                    if (val) {
                      setState(() => _amountCtrl.text = (widget.amount / 2).toStringAsFixed(2));
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 14),

            TextField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Amount (SAR)',
                prefixIcon: const Icon(Icons.attach_money_rounded),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),

            // Method Selector
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

            // Copy note
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
                  ClipboardData(text: 'Roommate Settlement - SAR $amt to ${widget.toName}'),
                );
                if (context.mounted) {
                  AppSnackBar.showSuccess(
                    context,
                    'Copied: "Roommate Settlement - SAR $amt to ${widget.toName}"',
                    title: 'Copied Note',
                  );
                }
              },
            ),
            const SizedBox(height: 20),

            // Confirm Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF38BDF8),
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
