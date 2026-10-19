import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../models/account.dart';
import '../../theme/app_themes.dart';
import 'account_transfer_sheet.dart';
import 'reconcile_balance_dialog.dart';

/// Interactive card representing an individual account (Bank, E-Wallet, Crypto, Cash, Pool).
class AccountCard extends StatelessWidget {
  final Account account;
  final double committedBudgets;
  final bool hideBalance;
  final String householdId;
  final VoidCallback? onEdit;
  final VoidCallback? onRefresh;

  const AccountCard({
    super.key,
    required this.account,
    required this.committedBudgets,
    required this.householdId,
    this.hideBalance = false,
    this.onEdit,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00');
    final margin = account.calculateMargin(committedBudgets);
    final status = account.getStatus(committedBudgets);
    final isDark = context.isDark;

    Color statusColor;
    String statusLabel;
    IconData statusIcon;

    switch (status) {
      case AccountCapacityStatus.zeroBased:
        statusColor = const Color(0xFF00E5BF);
        statusLabel = context.tr('zero_based_label');
        statusIcon = Icons.check_circle_outline_rounded;
        break;
      case AccountCapacityStatus.surplus:
        statusColor = const Color(0xFF4DE6F7);
        statusLabel = '+${account.currency} ${fmt.format(margin)} ${context.tr("surplus_buffer_label")}';
        statusIcon = Icons.savings_outlined;
        break;
      case AccountCapacityStatus.deficit:
        statusColor = Colors.redAccent;
        statusLabel = '${context.tr("deficit_label")}: -${account.currency} ${fmt.format(-margin)}';
        statusIcon = Icons.warning_amber_rounded;
        break;
    }

    final displayBalance = hideBalance ? '••••••' : '${account.currency} ${fmt.format(account.balance)}';
    final displayCommitted = hideBalance ? '••••' : '${account.currency} ${fmt.format(committedBudgets)}';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: status == AccountCapacityStatus.deficit
              ? Colors.redAccent.withValues(alpha: 0.6)
              : context.borderColor,
          width: status == AccountCapacityStatus.deficit ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black.withValues(alpha: 0.25) : const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Card Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(account.accountType.defaultIcon, color: statusColor, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              account.name,
                              style: GoogleFonts.outfit(
                                color: context.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (account.isSharedPool) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF00E5BF).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                context.tr('acc_shared_pool'),
                                style: const TextStyle(color: Color(0xFF00E5BF), fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        context.tr(account.accountType.translationKey),
                        style: TextStyle(color: context.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.more_horiz_rounded, color: context.textSecondary, size: 20),
                  onPressed: onEdit,
                  tooltip: context.tr('acc_options'),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Balances & Capacity Details
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(context.tr('current_balance'), style: TextStyle(color: context.textSecondary, fontSize: 11)),
                        const SizedBox(height: 2),
                        Text(
                          displayBalance,
                          style: GoogleFonts.outfit(
                            color: context.textPrimary,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(context.tr('committed_budgets'), style: TextStyle(color: context.textSecondary, fontSize: 11)),
                        const SizedBox(height: 2),
                        Text(
                          displayCommitted,
                          style: TextStyle(
                            color: context.textSecondary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Status Pill
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 14, color: statusColor),
                      const SizedBox(width: 6),
                      Text(
                        statusLabel,
                        style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),

                // If in deficit, show immediate resolution action
                if (status == AccountCapacityStatus.deficit) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        AccountTransferSheet.show(
                          context,
                          householdId: householdId,
                          prefilledToAccountId: account.id,
                          prefilledAmount: -margin,
                          onTransferSuccess: onRefresh,
                        );
                      },
                      icon: const Icon(Icons.bolt_rounded, size: 16),
                      label: Text(
                        '⚡ ${context.tr("quick_transfer")} ${account.currency} ${fmt.format(-margin)}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Bottom Bar Actions (Reconcile & Transfer Out)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: context.subtleCardBg,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(15)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed: () {
                    ReconcileBalanceDialog.show(
                      context,
                      account: account,
                      onReconcileSuccess: onRefresh,
                    );
                  },
                  icon: const Icon(Icons.tune_rounded, size: 15),
                  label: Text(context.tr('reconcile'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  style: TextButton.styleFrom(
                    foregroundColor: context.textSecondary,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    AccountTransferSheet.show(
                      context,
                      householdId: householdId,
                      prefilledFromAccountId: account.id,
                      onTransferSuccess: onRefresh,
                    );
                  },
                  icon: const Icon(Icons.arrow_forward_rounded, size: 15),
                  label: Text(context.tr('transfer_out'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF00E5BF),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
