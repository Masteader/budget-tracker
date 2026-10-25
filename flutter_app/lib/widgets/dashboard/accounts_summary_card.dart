import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../models/account.dart';
import '../../screens/accounts/accounts_overview_screen.dart';
import '../../services/account_service.dart';
import '../../theme/app_themes.dart';
import '../../core/widgets/three_d_surface_card.dart';
import '../../core/widgets/three_d_icon_puck.dart';

/// Dashboard summary card displaying total liquidity across all accounts
/// and horizontal account pills. Tapping navigates to AccountsOverviewScreen.
class AccountsSummaryCard extends StatefulWidget {
  final String householdId;

  /// Hidden until the household has at least this many accounts (the
  /// dashboard passes 2: with one account it repeats the budget; the Tools
  /// screen always shows it).
  final int minAccounts;

  const AccountsSummaryCard({super.key, required this.householdId, this.minAccounts = 1});

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
    final unitSpan = TextSpan(
      text: context.isRtl ? ' ${context.tr('sar')}' : '${context.tr('sar')} ',
      style: GoogleFonts.outfit(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: context.accentText,
      ),
    );
    final accounts = _cachedAccounts.where((a) => !a.isArchived).toList();
    if (accounts.isEmpty || accounts.length < widget.minAccounts) return const SizedBox.shrink();

        final totalLiquidity =
            accounts.fold<double>(0.0, (acc, item) => acc + item.balance);

        final hasDeficit = accounts.any((a) => a.balance < 0);

        return ThreeDSurfaceCard(
          borderRadius: 20.0,
          padding: EdgeInsets.zero,
          customBorder: Border.all(
            color: hasDeficit
                ? Colors.redAccent.withValues(alpha: 0.4)
                : context.borderColor,
            width: hasDeficit ? 1.5 : 1.0,
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AccountsOverviewScreen(householdId: widget.householdId),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Row: Title + Chevron
                  Row(
                    children: [
                      const ThreeDIconPuck(
                        icon: Icons.account_balance_wallet_rounded,
                        size: 38,
                        isSquircle: true,
                        isRoseGold: true,
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
                        margin: const EdgeInsetsDirectional.only(end: 6),
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
                // Wrap (not Row) so large accessibility text cannot overflow.
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.end,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          if (!context.isRtl) unitSpan,
                          TextSpan(
                            text: fmt.format(totalLiquidity),
                            style: GoogleFonts.outfit(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              color: context.textPrimary,
                            ),
                          ),
                          if (context.isRtl) unitSpan,
                        ],
                      ),
                    ),
                    Text(
                      context.trPlural('across_accounts', accounts.length),
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
                              color: isNeg ? Colors.redAccent : context.accentText,
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
                              context.sar(acc.balance),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isNeg ? Colors.redAccent : context.accentText,
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
        ),
      );
  }
}
