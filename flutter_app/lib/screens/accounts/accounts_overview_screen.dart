import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../models/account.dart';
import '../../services/account_service.dart';
import '../../theme/app_themes.dart';
import '../../widgets/accounts/account_card.dart';
import '../../widgets/accounts/account_transfer_sheet.dart';
import '../../widgets/accounts/add_edit_account_dialog.dart';
import '../../widgets/accounts/record_income_sheet.dart';

/// Screen displaying all user accounts, live balances, budget capacity statuses, and quick transfers.
class AccountsOverviewScreen extends StatefulWidget {
  final String householdId;

  const AccountsOverviewScreen({
    super.key,
    required this.householdId,
  });

  @override
  State<AccountsOverviewScreen> createState() => _AccountsOverviewScreenState();
}

class _AccountsOverviewScreenState extends State<AccountsOverviewScreen> {
  bool _hideBalances = false;
  Map<String, double> _committedBudgets = {};
  late Stream<List<Account>> _accountsStream;
  List<Account> _cachedAccounts = [];
  bool _isLoadingAccounts = true;

  @override
  void initState() {
    super.initState();
    _initStream();
    _refreshAll();
  }

  void _initStream() {
    _accountsStream = AccountService.instance.streamAccounts(widget.householdId);
  }

  @override
  void didUpdateWidget(covariant AccountsOverviewScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.householdId != widget.householdId) {
      _initStream();
      _refreshAll();
    }
  }

  String get _currentCycleKey {
    final now = DateTime.now();
    if (now.day >= 27) {
      final next = DateTime(now.year, now.month + 1, 1);
      return DateFormat('yyyy-MM').format(next);
    }
    return DateFormat('yyyy-MM').format(now);
  }

  Future<void> _loadCommittedBudgets() async {
    try {
      final map = await AccountService.instance.getCommittedBudgetsByAccount(
        widget.householdId,
        _currentCycleKey,
      );
      if (mounted) {
        setState(() {
          _committedBudgets = map;
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchAccountsDirectly() async {
    try {
      final list = await AccountService.instance.getAccounts(widget.householdId);
      if (mounted) {
        setState(() {
          _cachedAccounts = list;
          _isLoadingAccounts = false;
        });
      }
    } catch (_) {
      if (mounted && _cachedAccounts.isEmpty) {
        setState(() {
          _isLoadingAccounts = false;
        });
      }
    }
  }

  Future<void> _refreshAll() async {
    await Future.wait([
      _loadCommittedBudgets(),
      _fetchAccountsDirectly(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final fmt = NumberFormat('#,##0.00');

    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: AppBar(
        title: Text(
          context.tr('accounts_balances'),
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        backgroundColor: context.scaffoldBg,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(_hideBalances ? Icons.visibility_off_rounded : Icons.visibility_rounded),
            tooltip: _hideBalances ? 'Show' : 'Hide',
            onPressed: () => setState(() => _hideBalances = !_hideBalances),
          ),
          IconButton(
            icon: Icon(Icons.add_rounded, color: context.electricTeal),
            tooltip: context.tr('add_account'),
            onPressed: () {
              AddEditAccountDialog.show(
                context,
                householdId: widget.householdId,
                onSuccess: _refreshAll,
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<List<Account>>(
        stream: _accountsStream,
        initialData: _cachedAccounts.isNotEmpty ? _cachedAccounts : null,
        builder: (context, snapshot) {
          if (snapshot.hasData && snapshot.data != null) {
            _cachedAccounts = snapshot.data!;
            _isLoadingAccounts = false;
          }

          if (_isLoadingAccounts && _cachedAccounts.isEmpty) {
            return Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: context.electricTeal,
              ),
            );
          }

          final accounts = _cachedAccounts;

          if (accounts.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: context.electricTeal.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.account_balance_wallet_outlined, size: 48, color: context.electricTeal),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      context.tr('no_accounts_configured'),
                      style: GoogleFonts.outfit(color: context.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.tr('accounts_balances_desc'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: context.textSecondary, fontSize: 13),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: () {
                        AddEditAccountDialog.show(
                          context,
                          householdId: widget.householdId,
                          onSuccess: _refreshAll,
                        );
                      },
                      icon: const Icon(Icons.add_rounded),
                      label: Text(context.tr('add_bank_wallet_cash'), style: const TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: context.electricTeal,
                        foregroundColor: context.scaffoldBg,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          // Calculate total net assets in SAR baseline
          double totalNetSAR = 0.0;
          int deficitCount = 0;

          for (final a in accounts) {
            // Rough baseline converter (USDT/USD ~3.75 SAR)
            final rate = (a.currency == 'USD' || a.currency == 'USDT') ? 3.75 : 1.0;
            totalNetSAR += (a.balance * rate);

            final committed = _committedBudgets[a.id] ?? 0.0;
            if (a.getStatus(committed) == AccountCapacityStatus.deficit) {
              deficitCount++;
            }
          }

          // Group by account type
          final banks = accounts.where((a) => a.accountType == AccountType.bank && !a.isSharedPool).toList();
          final eWallets = accounts.where((a) => a.accountType == AccountType.eWallet && !a.isSharedPool).toList();
          final crypto = accounts.where((a) => a.accountType == AccountType.crypto && !a.isSharedPool).toList();
          final cash = accounts.where((a) => a.accountType == AccountType.cash && !a.isSharedPool).toList();
          final sharedPools = accounts.where((a) => a.isSharedPool || a.accountType == AccountType.sharedPool).toList();

          return RefreshIndicator(
            onRefresh: _refreshAll,
            color: context.electricTeal,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
              children: [
                // 1. Total Net Assets Card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: context.icedHeroGradient,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFF00E5BF).withValues(alpha: isDark ? 0.3 : 0.5),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: isDark ? Colors.black.withValues(alpha: 0.3) : const Color(0xFF00E5BF).withValues(alpha: 0.1),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            context.tr('total_net_worth'),
                            style: GoogleFonts.outfit(
                              color: isDark ? const Color(0xFF00E5BF) : const Color(0xFF008F7A),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.1,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: deficitCount == 0
                                  ? const Color(0xFF00C896).withValues(alpha: 0.15)
                                  : Colors.redAccent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  deficitCount == 0 ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                                  size: 13,
                                  color: deficitCount == 0 ? const Color(0xFF00C896) : Colors.redAccent,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  deficitCount == 0
                                      ? 'Funded'
                                      : '$deficitCount ${context.tr("deficit_label")}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: deficitCount == 0 ? const Color(0xFF00C896) : Colors.redAccent,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _hideBalances ? '••••••••' : 'SAR ${fmt.format(totalNetSAR)}',
                        style: GoogleFonts.outfit(
                          color: context.textPrimary,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Quick Action Buttons
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                RecordIncomeSheet.show(
                                  context,
                                  householdId: widget.householdId,
                                );
                              },
                              icon: const Icon(Icons.savings_rounded, size: 16),
                              label: Text(context.tr('record_income'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF00C896),
                                foregroundColor: const Color(0xFF051424),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                AccountTransferSheet.show(
                                  context,
                                  householdId: widget.householdId,
                                  onTransferSuccess: () => setState(() {}),
                                );
                              },
                              icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                              label: Text(context.tr('transfer_funds'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF00E5BF),
                                foregroundColor: const Color(0xFF051424),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // 2. Banks Section
                if (banks.isNotEmpty) ...[
                  _buildSectionHeader('🏦 ${context.tr("account_type_bank")}', banks.length),
                  ...banks.map((a) => _buildCard(a)),
                  const SizedBox(height: 12),
                ],

                // 3. E-Wallets Section
                if (eWallets.isNotEmpty) ...[
                  _buildSectionHeader('📱 ${context.tr("account_type_wallet")}', eWallets.length),
                  ...eWallets.map((a) => _buildCard(a)),
                  const SizedBox(height: 12),
                ],

                // 4. Crypto Section
                if (crypto.isNotEmpty) ...[
                  _buildSectionHeader('🪙 ${context.tr("account_type_crypto")}', crypto.length),
                  ...crypto.map((a) => _buildCard(a)),
                  const SizedBox(height: 12),
                ],

                // 5. Shared Pools Section
                if (sharedPools.isNotEmpty) ...[
                  _buildSectionHeader('👥 ${context.tr("account_type_pool")}', sharedPools.length),
                  ...sharedPools.map((a) => _buildCard(a)),
                  const SizedBox(height: 12),
                ],

                // 6. Cash Section
                if (cash.isNotEmpty) ...[
                  _buildSectionHeader('💵 ${context.tr("account_type_cash")}', cash.length),
                  ...cash.map((a) => _buildCard(a)),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(String title, int count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: GoogleFonts.outfit(
              color: context.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          Text(
            '$count',
            style: TextStyle(color: context.textSecondary, fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(Account account) {
    final committed = _committedBudgets[account.id] ?? 0.0;
    return AccountCard(
      key: ValueKey(account.id),
      account: account,
      committedBudgets: committed,
      householdId: widget.householdId,
      hideBalance: _hideBalances,
      onRefresh: _loadCommittedBudgets,
      onEdit: () {
        AddEditAccountDialog.show(
          context,
          householdId: widget.householdId,
          existingAccount: account,
          onSuccess: () => setState(() {}),
        );
      },
    );
  }
}
