import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/app_localizations.dart';
import '../../main.dart';
import '../../models/models.dart';
import '../../models/payday_outlook.dart' show kFixedCostCategoryCodes;
import '../../theme/app_themes.dart';
import '../app_snackbar.dart';

/// Calculates proportional scale-down of budget allocations to match [targetTotal],
/// protecting fixed lump-sum commitments (rent, utilities) while scaling variable categories.
Map<String, double> computeProportionalRebalance({
  required List<Budget> budgets,
  required double targetTotal,
}) {
  final active = budgets.where((b) => b.isActive).toList();
  final currentTotal = active.fold<double>(0.0, (s, b) => s + b.allocatedAmount);
  final deficit = currentTotal - targetTotal;
  if (deficit <= 0.005) {
    return {for (final b in active) b.categoryCode: b.allocatedAmount};
  }

  // Separate fixed vs variable categories
  double fixedSum = 0.0;
  double variableSum = 0.0;
  for (final b in active) {
    if (kFixedCostCategoryCodes.contains(b.categoryCode)) {
      fixedSum += b.allocatedAmount;
    } else {
      variableSum += b.allocatedAmount;
    }
  }

  final Map<String, double> result = {};

  // If variable allocations are insufficient or fixed costs exceed target,
  // scale all active categories proportionally across the board.
  if (variableSum <= 0.005 || targetTotal <= fixedSum) {
    for (final b in active) {
      final ratio = currentTotal > 0 ? (b.allocatedAmount / currentTotal) : 0.0;
      result[b.categoryCode] = double.parse((ratio * targetTotal).toStringAsFixed(2));
    }
    return result;
  }

  final shrinkRequired = deficit;
  for (final b in active) {
    if (kFixedCostCategoryCodes.contains(b.categoryCode)) {
      result[b.categoryCode] = b.allocatedAmount; // Protected
    } else {
      final share = variableSum > 0 ? (b.allocatedAmount / variableSum) : 0.0;
      final deduction = shrinkRequired * share;
      final newAmt = (b.allocatedAmount - deduction).clamp(0.0, double.infinity);
      result[b.categoryCode] = double.parse(newAmt.toStringAsFixed(2));
    }
  }

  return result;
}

/// Modal sheet offering one-tap rebalancing of budget allocations to fit available operating cash.
class RebalanceBudgetSheet extends StatefulWidget {
  final String householdId;
  final String cycleKey;
  final List<Budget> budgets;
  final double targetAvailableCash;
  final VoidCallback? onRebalanced;

  const RebalanceBudgetSheet({
    super.key,
    required this.householdId,
    required this.cycleKey,
    required this.budgets,
    required this.targetAvailableCash,
    this.onRebalanced,
  });

  static Future<void> show(
    BuildContext context, {
    required String householdId,
    required String cycleKey,
    required List<Budget> budgets,
    required double targetAvailableCash,
    VoidCallback? onRebalanced,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RebalanceBudgetSheet(
        householdId: householdId,
        cycleKey: cycleKey,
        budgets: budgets,
        targetAvailableCash: targetAvailableCash,
        onRebalanced: onRebalanced,
      ),
    );
  }

  @override
  State<RebalanceBudgetSheet> createState() => _RebalanceBudgetSheetState();
}

class _RebalanceBudgetSheetState extends State<RebalanceBudgetSheet> {
  bool _isSaving = false;

  Future<void> _applyRebalance(Map<String, double> adjustments) async {
    setState(() => _isSaving = true);
    try {
      final futures = <Future>[];
      for (final entry in adjustments.entries) {
        final b = widget.budgets.where((item) => item.categoryCode == entry.key).firstOrNull;
        if (b != null) {
          futures.add(
            supabase
                .from('budgets')
                .update({
                  'allocated_amount': entry.value,
                  'remaining_amount': entry.value - b.spentAmount,
                })
                .eq('id', b.id),
          );
        }
      }
      await Future.wait(futures);
      if (mounted) {
        Navigator.pop(context);
        widget.onRebalanced?.call();
        AppSnackBar.showSuccess(
          context,
          context.tr('rebalance_success_msg'),
          title: context.tr('rebalance_success_title'),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        AppSnackBar.showError(
          context,
          context.trArgs('rebalance_failed_msg', {'error': e.toString()}),
          title: context.tr('rebalance_failed_title'),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final adjustments = computeProportionalRebalance(
      budgets: widget.budgets,
      targetTotal: widget.targetAvailableCash,
    );
    final activeBudgets = widget.budgets.where((b) => b.isActive).toList();
    final currentTotal = activeBudgets.fold<double>(0.0, (s, b) => s + b.allocatedAmount);
    final deficit = currentTotal - widget.targetAvailableCash;

    return Container(
      decoration: BoxDecoration(
        color: context.scaffoldBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: context.borderColor),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
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

          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: context.accentText.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.auto_fix_high_rounded, color: context.accentText, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('rebalance_sheet_title'),
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: context.textPrimary,
                      ),
                    ),
                    Text(
                      context.tr('rebalance_sheet_desc'),
                      style: TextStyle(fontSize: 12, color: context.textSecondary),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: context.tr('close'),
                icon: Icon(Icons.close, color: context.textSecondary),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Comparison Hero
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.borderColor),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('current_total'),
                      style: TextStyle(fontSize: 11, color: context.textSecondary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.sar(currentTotal),
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.redAccent,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.trending_down_rounded, color: Colors.redAccent, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        '-${context.sar(deficit > 0 ? deficit : 0)}',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.redAccent,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      context.tr('target_operating_cash'),
                      style: TextStyle(fontSize: 11, color: context.accentText, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.sar(widget.targetAvailableCash),
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: context.accentText,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // List of changes (Scrollable)
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: activeBudgets.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (ctx, i) {
                final b = activeBudgets[i];
                final newAmt = adjustments[b.categoryCode] ?? b.allocatedAmount;
                final isFixed = kFixedCostCategoryCodes.contains(b.categoryCode);
                final diff = newAmt - b.allocatedAmount;

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: context.subtleCardBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: context.borderColor),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  b.categoryCode,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                    color: context.textPrimary,
                                  ),
                                ),
                                if (isFixed) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: context.chipBg,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      context.tr('fixed_protected'),
                                      style: TextStyle(fontSize: 9, color: context.textSecondary),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${context.tr('allocated')}: ${context.sar(b.allocatedAmount)}',
                              style: TextStyle(fontSize: 11, color: context.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            context.sar(newAmt),
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: isFixed ? context.textPrimary : context.accentText,
                            ),
                          ),
                          if (diff.abs() > 0.005)
                            Text(
                              '-${context.sar(-diff)}',
                              style: const TextStyle(fontSize: 10, color: Colors.redAccent, fontWeight: FontWeight.bold),
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),

          // Confirm button
          ElevatedButton(
            onPressed: _isSaving ? null : () => _applyRebalance(adjustments),
            style: ElevatedButton.styleFrom(
              backgroundColor: context.accentText,
              foregroundColor: context.primaryButtonFg,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text(
                    context.tr('confirm_rebalance'),
                    style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
          ),
        ],
      ),
    );
  }
}
