import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/app_localizations.dart';
import '../../models/account.dart';
import '../../services/account_service.dart';
import '../../theme/app_themes.dart';
import '../../widgets/accounts/account_card.dart';
import '../../widgets/accounts/account_transfer_sheet.dart';
import '../../widgets/accounts/add_edit_account_dialog.dart';
import '../../widgets/accounts/record_income_sheet.dart';
import '../../core/widgets/three_d_surface_card.dart';
import '../../services/salary_cycle_service.dart';
import '../analytics/income_spending_report_screen.dart';

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
  StreamSubscription<List<Account>>? _accountsSub;
  List<Account> _cachedAccounts = [];
  bool _isLoadingAccounts = true;
  List<IncomeRecord> _cycleIncomeRecords = [];
  bool _isLoadingIncome = true;

  double get _totalCycleIncome =>
      _cycleIncomeRecords.fold<double>(0.0, (s, r) => s + r.netAmount);

  @override
  void initState() {
    super.initState();
    _initStream();
    _refreshAll();
  }

  void _initStream() {
    _accountsSub?.cancel();
    _accountsSub = AccountService.instance.streamAccounts(widget.householdId).listen(
      (data) {
        if (mounted) {
          setState(() {
            _cachedAccounts = data;
            _isLoadingAccounts = false;
          });
        }
      },
      onError: (err) {
        if (mounted && _cachedAccounts.isEmpty) {
          setState(() {
            _isLoadingAccounts = false;
          });
        }
      },
    );
  }

  @override
  void didUpdateWidget(covariant AccountsOverviewScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.householdId != widget.householdId) {
      _initStream();
      _refreshAll();
    }
  }

  @override
  void dispose() {
    _accountsSub?.cancel();
    super.dispose();
  }

  String get _currentCycleKey {
    return SalaryCycleService.cycleKeyForInstant(DateTime.now());
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

  Future<void> _loadCycleIncome() async {
    try {
      final records = await AccountService.instance.getCycleIncome(
        widget.householdId,
        _currentCycleKey,
      );
      if (mounted) {
        setState(() {
          _cycleIncomeRecords = records;
          _isLoadingIncome = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingIncome = false);
    }
  }

  Future<void> _refreshAll() async {
    try {
      await AccountService.instance.reconcileUnlinkedTransactions(widget.householdId);
    } catch (_) {}
    await Future.wait([
      _loadCommittedBudgets(),
      _fetchAccountsDirectly(),
      _loadCycleIncome(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;

    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: AppBar(
        foregroundColor: context.textPrimary,
        iconTheme: IconThemeData(color: context.textPrimary),
        title: Text(
          context.tr('accounts_balances'),
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            fontSize: 20,
            color: context.textPrimary,
          ),
        ),
        backgroundColor: context.scaffoldBg,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(
              _hideBalances ? Icons.visibility_off_rounded : Icons.visibility_rounded,
              color: context.textPrimary,
            ),
            tooltip: _hideBalances ? context.tr('show_balances') : context.tr('hide_balances'),
            onPressed: () => setState(() => _hideBalances = !_hideBalances),
          ),
          IconButton(
            icon: Icon(
              Icons.add_rounded,
              color: context.accentText,
            ),
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
      body: _buildBody(context, isDark),
    );
  }

  Widget _buildBody(BuildContext context, bool isDark) {
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
          final savings = accounts.where((a) => a.accountType == AccountType.savings && !a.isSharedPool).toList();
          final sharedPools = accounts.where((a) => a.isSharedPool || a.accountType == AccountType.sharedPool).toList();

          return RefreshIndicator(
            onRefresh: _refreshAll,
            color: context.electricTeal,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
              children: [
                // 1. Total Net Assets Card
                ThreeDSurfaceCard(
                  borderRadius: 22.0,
                  padding: const EdgeInsets.all(20),
                  customGradient: LinearGradient(
                    colors: context.icedHeroGradient.colors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
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
                              color: context.champagneGold,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.1,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: deficitCount == 0
                                  ? context.alertSuccessBg
                                  : Colors.redAccent.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: deficitCount == 0
                                    ? context.alertSuccessBorder
                                    : Colors.redAccent.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  deficitCount == 0 ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                                  size: 13,
                                  color: deficitCount == 0 ? context.successText : Colors.redAccent,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  deficitCount == 0
                                      ? context.tr('funded')
                                      : '$deficitCount ${context.tr("deficit_label")}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _hideBalances ? '••••••••' : context.sar(totalNetSAR),
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
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
                                ).then((_) => _refreshAll());
                              },
                              icon: const Icon(Icons.savings_rounded, size: 16),
                              label: Text(context.tr('record_income'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: context.champagneGold,
                                foregroundColor: context.primaryButtonBg,
                                elevation: 2,
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                                  onTransferSuccess: _refreshAll,
                                );
                              },
                              icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                              label: Text(context.tr('transfer_funds'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white.withValues(alpha: 0.15),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                side: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _buildCycleIncomeCard(context, accounts),
                const SizedBox(height: 20),

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

                // 7. Savings Vaults Section (Protected from daily budgets)
                if (savings.isNotEmpty) ...[
                  _buildSectionHeader('🔒 ${context.tr("savings_vaults_section")}', savings.length),
                  ...savings.map((a) => _buildCard(a)),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          );
  }

  Widget _buildSectionHeader(String title, int count) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 8, start: 4),
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

  Widget _buildCycleIncomeCard(BuildContext context, List<Account> accounts) {
    return ThreeDSurfaceCard(
      borderRadius: 18.0,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.savings_outlined, size: 18, color: context.electricTeal),
                  const SizedBox(width: 8),
                  Text(
                    context.tr('total_cycle_income'),
                    style: GoogleFonts.outfit(
                      color: context.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Text(
                _hideBalances ? '••••••' : context.sar(_totalCycleIncome),
                style: GoogleFonts.outfit(
                  color: context.electricTeal,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          if (_cycleIncomeRecords.isNotEmpty) ...[
            const SizedBox(height: 12),
            Divider(color: context.borderColor, height: 1),
            const SizedBox(height: 10),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _cycleIncomeRecords.length,
              separatorBuilder: (_, __) => Divider(color: context.borderColor.withValues(alpha: 0.4), height: 16),
              itemBuilder: (ctx, idx) {
                final rec = _cycleIncomeRecords[idx];
                final accountName = accounts.where((a) => a.id == rec.accountId).firstOrNull?.name ?? '';
                return _buildIncomeRow(context, rec, accountName);
              },
            ),
          ] else if (!_isLoadingIncome) ...[
            const SizedBox(height: 10),
            Text(
              context.tr('no_income_records_cycle'),
              style: TextStyle(color: context.textSecondary, fontSize: 12),
            ),
          ],
          const SizedBox(height: 12),
          InkWell(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => IncomeSpendingReportScreen(householdId: widget.householdId)),
            ),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: context.electricTeal.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: context.electricTeal.withValues(alpha: 0.25)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.analytics_outlined, size: 16, color: context.electricTeal),
                  const SizedBox(width: 6),
                  Text(
                    context.tr('view_in_depth_report'),
                    style: GoogleFonts.outfit(
                      color: context.electricTeal,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIncomeRow(BuildContext context, IncomeRecord rec, String accountName) {
    final hasBreakdown = rec.overtime > 0 || rec.bonus > 0 || rec.deductions > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: context.electricTeal.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(rec.sourceType.icon, size: 16, color: context.electricTeal),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          rec.title,
                          style: TextStyle(
                            color: context.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(
                              context.fmtDate(rec.receivedAt, 'd MMM'),
                              style: TextStyle(color: context.textSecondary, fontSize: 11),
                            ),
                            if (accountName.isNotEmpty) ...[
                              Text(' • ', style: TextStyle(color: context.textSecondary, fontSize: 11)),
                              Flexible(
                                child: Text(
                                  accountName,
                                  style: TextStyle(color: context.textSecondary, fontSize: 11),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '+${_hideBalances ? "••••" : context.sar(rec.netAmount)}',
              style: GoogleFonts.outfit(
                color: context.successText,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        if (hasBreakdown) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              if (rec.baseAmount > 0)
                _incomeBreakdownChip(context, '${context.tr("base_amount")}: ${context.sar(rec.baseAmount)}', context.textSecondary),
              if (rec.overtime > 0)
                _incomeBreakdownChip(context, '+${context.tr("overtime")}: ${context.sar(rec.overtime)}', context.electricTeal),
              if (rec.bonus > 0)
                _incomeBreakdownChip(context, '+${context.tr("bonus")}: ${context.sar(rec.bonus)}', context.champagneGold),
              if (rec.deductions > 0)
                _incomeBreakdownChip(context, '-${context.tr("deductions")}: ${context.sar(rec.deductions)}', context.dangerColor),
            ],
          ),
        ],
      ],
    );
  }

  Widget _incomeBreakdownChip(BuildContext context, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
