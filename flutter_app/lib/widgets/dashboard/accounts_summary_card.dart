import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../models/account.dart';
import '../../screens/accounts/accounts_overview_screen.dart';
import '../../services/account_service.dart';
import '../../theme/app_themes.dart';

/// Dashboard summary card displaying total liquidity across all accounts
/// and horizontal account pills. Tapping navigates to AccountsOverviewScreen.
class AccountsSummaryCard extends StatefulWidget {
  final String householdId;

  const AccountsSummaryCard({super.key, required this.householdId});

  @override
  State<AccountsSummaryCard> createState() => _AccountsSummaryCardState();
}

class _AccountsSummaryCardState extends State<AccountsSummaryCard> {
  StreamSubscription<List<Account>>? _accountsSub;
  List<Account> _cachedAccounts = [];

  @override
  void initState() {
    super.initState();
    _initStream();
    _fetchDirectly();
  }

  void _initStream() {
    _accountsSub?.cancel();
    _accountsSub = AccountService.instance.streamAccounts(widget.householdId).listen(
      (data) {
        if (mounted) {
          setState(() {
            _cachedAccounts = data;
          });
        }
      },
      onError: (_) {},
    );
  }

  Future<void> _fetchDirectly() async {
    try {
      final list = await AccountService.instance.getAccounts(widget.householdId);
      if (mounted) {
        setState(() {
          _cachedAccounts = list;
        });
      }
    } catch (_) {}
  }

  @override
  void didUpdateWidget(covariant AccountsSummaryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.householdId != widget.householdId) {
      _initStream();
      _fetchDirectly();
    }
  }

  @override
  void dispose() {
    _accountsSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00', 'en_US');
    final isDark = context.isDark;

    final accounts = _cachedAccounts.where((a) => !a.isArchived).toList();
    if (accounts.isEmpty) return const SizedBox.shrink();

        final totalLiquidity =
            accounts.fold<double>(0.0, (acc, item) => acc + item.balance);

        final hasDeficit = accounts.any((a) => a.balance < 0);

        return InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AccountsOverviewScreen(householdId: widget.householdId),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: context.cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: hasDeficit
                    ? Colors.redAccent.withValues(alpha: 0.4)
                    : context.borderColor,
                width: hasDeficit ? 1.5 : 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: isDark
                      ? Colors.black.withValues(alpha: 0.2)
                      : context.electricTeal.withValues(alpha: 0.05),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Row: Title + Chevron
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: context.electricTeal.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.account_balance_wallet_rounded,
                        color: context.electricTeal,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        context.tr('accounts_balances'),
                        style: GoogleFonts.outfit(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: context.textPrimary,
                        ),
                      ),
                    ),
                    if (hasDeficit)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 12),
                            const SizedBox(width: 4),
                            Text(
                              context.tr('deficit_label'),
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 14,
                      color: context.textSecondary,
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Total Liquidity Balance
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      'SAR ',
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: context.electricTeal,
                      ),
                    ),
                    Text(
                      fmt.format(totalLiquidity),
                      style: GoogleFonts.outfit(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      context.tr('across_accounts').replaceAll('{count}', accounts.length.toString()),
                      style: TextStyle(
                        fontSize: 12,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Horizontal Account Pill Strip
                SizedBox(
                  height: 38,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: accounts.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (ctx, idx) {
                      final acc = accounts[idx];
                      final isNeg = acc.balance < 0;

                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: isNeg
                              ? Colors.redAccent.withValues(alpha: 0.1)
                              : context.chipBg,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isNeg
                                ? Colors.redAccent.withValues(alpha: 0.3)
                                : context.borderColor,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              acc.accountType.defaultIcon,
                              size: 14,
                              color: isNeg ? Colors.redAccent : context.electricTeal,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              acc.name,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: context.textPrimary,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'SAR ${fmt.format(acc.balance)}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isNeg ? Colors.redAccent : context.electricTeal,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
  }
}
