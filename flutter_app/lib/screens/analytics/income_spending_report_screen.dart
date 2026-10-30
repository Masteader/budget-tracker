import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/widgets/three_d_surface_card.dart';
import '../../core/widgets/velvet_wave_header.dart';
import '../../l10n/app_localizations.dart';
import '../../main.dart';
import '../../models/account.dart';
import '../../models/category_catalog.dart';
import '../../models/models.dart';
import '../../services/account_service.dart';
import '../../services/salary_cycle_service.dart';
import '../../theme/app_themes.dart';
import '../../widgets/accounts/record_income_sheet.dart';
import '../../widgets/dashboard/salary_cycle_selector_bar.dart';

/// In-depth Cash Flow and Income vs. Spending Analysis Screen.
///
/// Provides complete cycle clarity across all itemized income sources (Salary, OT,
/// Bonus, Freelance, Opening Balances), category expenditures, net cash margin,
/// and household savings rate.
class IncomeSpendingReportScreen extends StatefulWidget {
  final String householdId;

  const IncomeSpendingReportScreen({super.key, required this.householdId});

  @override
  State<IncomeSpendingReportScreen> createState() => _IncomeSpendingReportScreenState();
}

class _IncomeSpendingReportScreenState extends State<IncomeSpendingReportScreen> {
  List<SalaryCycleInfo> _cycles = [];
  int _currentCycleIndex = 0;
  bool _isLoading = true;

  List<IncomeRecord> _incomeRecords = [];
  List<Account> _accounts = [];
  Map<String, double> _categorySpend = {};
  double _totalSpend = 0.0;

  @override
  void initState() {
    super.initState();
    _cycles = SalaryCycleService.getAvailableCycles();
    final idx = _cycles.indexWhere((c) => c.isCurrentCycle || c.isCurrent);
    _currentCycleIndex = idx != -1 ? idx : 0;
    _loadReportData();
  }

  SalaryCycleInfo get _selectedCycle {
    if (_cycles.isEmpty) {
      final cur = SalaryCycleService.currentCycle();
      return SalaryCycleInfo(
        cycleKey: cur.key,
        cycleStart: cur.startIso,
        cycleEnd: cur.endIso,
        label: cur.key,
        monthName: cur.key,
        isCurrent: true,
      );
    }
    final clamped = _currentCycleIndex.clamp(0, _cycles.length - 1);
    return _cycles[clamped];
  }

  String get _currentCycleKey => _selectedCycle.cycleKey;

  Future<void> _loadReportData() async {
    setState(() => _isLoading = true);
    final hid = widget.householdId;
    final cycleKey = _currentCycleKey;

    try {
      final results = await Future.wait([
        AccountService.instance.getCycleIncome(hid, cycleKey).catchError((_) => <IncomeRecord>[]),
        AccountService.instance.getAccounts(hid).catchError((_) => <Account>[]),
        supabase
            .from('transactions')
            .select('amount, category_code, is_settlement, nafaqah_class')
            .eq('household_id', hid)
            .eq('cycle_key', cycleKey)
            .catchError((_) => <dynamic>[]),
      ]);

      final records = results[0] as List<IncomeRecord>;
      final accounts = results[1] as List<Account>;
      final txList = results[2] as List<dynamic>;

      final Map<String, double> catMap = {};
      double spend = 0.0;
      for (final tx in txList) {
        if (tx['is_settlement'] == true) continue;
        if (tx['nafaqah_class'] == 'wife_personal') continue;
        final amt = (tx['amount'] as num?)?.toDouble() ?? 0.0;
        final cat = tx['category_code'] as String? ?? 'OPEX-MISC';
        catMap[cat] = (catMap[cat] ?? 0.0) + amt;
        spend += amt;
      }

      if (mounted) {
        setState(() {
          _incomeRecords = records;
          _accounts = accounts;
          _categorySpend = catMap;
          _totalSpend = spend;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  double get _totalInflow {
    final recorded = _incomeRecords.fold<double>(0.0, (s, r) => s + r.netAmount);
    if (recorded > 0) return recorded;

    // Fallback: operating accounts cash + current spend ensures starting income is preserved
    final liveCash = _accounts
        .where((a) => !a.isArchived && a.accountType.isOperatingPool)
        .fold<double>(0.0, (s, a) => s + (a.balance > 0 ? a.balance : 0.0));
    return liveCash + _totalSpend;
  }

  double get _netCashFlow => _totalInflow - _totalSpend;

  double get _savingsRate {
    if (_totalInflow <= 0.0) return 0.0;
    return ((_netCashFlow / _totalInflow) * 100).clamp(-100.0, 100.0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.scaffoldBg,
      body: SafeArea(
        child: Column(
          children: [
            VelvetWaveHeader(
              title: context.tr('income_spending_report'),
              subtitle: _selectedCycle.label,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              actions: [
                IconButton(
                  icon: Icon(Icons.savings_outlined, color: context.electricTeal),
                  tooltip: context.tr('record_income'),
                  onPressed: () async {
                    await RecordIncomeSheet.show(context, householdId: widget.householdId);
                    _loadReportData();
                  },
                ),
              ],
            ),
            SalaryCycleSelectorBar(
              currentCycle: _selectedCycle,
              hasPrevious: _cycles.isNotEmpty && _currentCycleIndex < _cycles.length - 1,
              hasNext: _cycles.isNotEmpty && _currentCycleIndex > 0,
              onPrevious: () {
                setState(() => _currentCycleIndex++);
                _loadReportData();
              },
              onNext: () {
                setState(() => _currentCycleIndex--);
                _loadReportData();
              },
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      color: context.accentText,
                      backgroundColor: context.cardBg,
                      onRefresh: _loadReportData,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        children: [
                          _buildCashFlowHero(context),
                          const SizedBox(height: 16),
                          _buildIncomeBreakdownSection(context),
                          const SizedBox(height: 16),
                          _buildSpendingCategorySection(context),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCashFlowHero(BuildContext context) {
    final isSurplus = _netCashFlow >= -0.005;
    final inflow = _totalInflow;
    final outflow = _totalSpend;
    final outflowRatio = inflow > 0 ? (outflow / inflow).clamp(0.0, 1.0) : 0.0;

    return ThreeDSurfaceCard(
      borderRadius: 20.0,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                context.tr('net_cash_flow'),
                style: GoogleFonts.outfit(
                  color: context.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isSurplus
                      ? context.electricTeal.withValues(alpha: 0.12)
                      : context.dangerColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSurplus
                        ? context.electricTeal.withValues(alpha: 0.3)
                        : context.dangerColor.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isSurplus ? Icons.trending_up_rounded : Icons.warning_amber_rounded,
                      size: 14,
                      color: isSurplus ? context.electricTeal : context.dangerColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${isSurplus ? context.tr('surplus') : context.tr('cash_deficit')} (${_savingsRate.toStringAsFixed(1)}%)',
                      style: GoogleFonts.outfit(
                        color: isSurplus ? context.electricTeal : context.dangerColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            context.sar(_netCashFlow),
            style: GoogleFonts.outfit(
              color: isSurplus ? context.electricTeal : context.dangerColor,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _buildMetricPill(
                  context,
                  title: context.tr('total_inflow'),
                  amount: context.sar(inflow),
                  icon: Icons.arrow_downward_rounded,
                  color: context.electricTeal,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricPill(
                  context,
                  title: context.tr('total_outflow'),
                  amount: context.sar(outflow),
                  icon: Icons.arrow_upward_rounded,
                  color: context.champagneGold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: outflowRatio,
              minHeight: 8,
              backgroundColor: context.electricTeal.withValues(alpha: 0.25),
              valueColor: AlwaysStoppedAnimation<Color>(
                outflowRatio > 0.9 ? context.dangerColor : context.champagneGold,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${context.tr('savings_rate')}: ${_savingsRate.toStringAsFixed(1)}%',
                style: TextStyle(color: context.textSecondary, fontSize: 11),
              ),
              Text(
                '${(outflowRatio * 100).toStringAsFixed(0)}% ${context.tr('spent').toLowerCase()}',
                style: TextStyle(color: context.textSecondary, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricPill(
    BuildContext context, {
    required String title,
    required String amount,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.subtleCardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(color: context.textSecondary, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            amount,
            style: GoogleFonts.outfit(
              color: context.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildIncomeBreakdownSection(BuildContext context) {
    return ThreeDSurfaceCard(
      borderRadius: 20.0,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.receipt_long_rounded, size: 18, color: context.electricTeal),
                  const SizedBox(width: 8),
                  Text(
                    context.tr('income_ledger'),
                    style: GoogleFonts.outfit(
                      color: context.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: () async {
                  await RecordIncomeSheet.show(context, householdId: widget.householdId);
                  _loadReportData();
                },
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      Icon(Icons.add_rounded, size: 16, color: context.electricTeal),
                      const SizedBox(width: 2),
                      Text(
                        context.tr('record_income'),
                        style: GoogleFonts.outfit(
                          color: context.electricTeal,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_incomeRecords.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                context.tr('no_income_this_cycle'),
                style: TextStyle(color: context.textSecondary, fontSize: 12),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _incomeRecords.length,
              separatorBuilder: (_, __) => Divider(color: context.borderColor.withValues(alpha: 0.4), height: 18),
              itemBuilder: (ctx, idx) {
                final rec = _incomeRecords[idx];
                final accName = _accounts.where((a) => a.id == rec.accountId).firstOrNull?.name ?? '';
                return _buildIncomeTile(context, rec, accName);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildIncomeTile(BuildContext context, IncomeRecord rec, String accountName) {
    final hasDetails = rec.overtime > 0 || rec.bonus > 0 || rec.deductions > 0;

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
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: context.electricTeal.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
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
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(
                              context.fmtDate(rec.receivedAt, 'd MMM yyyy'),
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
              '+${context.sar(rec.netAmount)}',
              style: GoogleFonts.outfit(
                color: context.electricTeal,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        if (hasDetails) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              if (rec.baseAmount > 0)
                _chip(context, '${context.tr("base_amount")}: ${context.sar(rec.baseAmount)}', context.textSecondary),
              if (rec.overtime > 0)
                _chip(context, '+${context.tr("overtime")}: ${context.sar(rec.overtime)}', context.electricTeal),
              if (rec.bonus > 0)
                _chip(context, '+${context.tr("bonus")}: ${context.sar(rec.bonus)}', context.champagneGold),
              if (rec.deductions > 0)
                _chip(context, '-${context.tr("deductions_gosi")}: ${context.sar(rec.deductions)}', context.dangerColor),
            ],
          ),
        ],
        if (rec.notes != null && rec.notes!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            rec.notes!,
            style: TextStyle(color: context.textSecondary, fontSize: 11, fontStyle: FontStyle.italic),
          ),
        ],
      ],
    );
  }

  Widget _chip(BuildContext context, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 0.8),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildSpendingCategorySection(BuildContext context) {
    final sortedCats = _categorySpend.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return ThreeDSurfaceCard(
      borderRadius: 20.0,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.pie_chart_outline_rounded, size: 18, color: context.champagneGold),
              const SizedBox(width: 8),
              Text(
                context.tr('category_spending'),
                style: GoogleFonts.outfit(
                  color: context.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (sortedCats.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                context.tr('no_spending_this_cycle'),
                style: TextStyle(color: context.textSecondary, fontSize: 12),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: sortedCats.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (ctx, idx) {
                final entry = sortedCats[idx];
                final catCode = entry.key;
                final amt = entry.value;
                final share = _totalSpend > 0 ? (amt / _totalSpend).clamp(0.0, 1.0) : 0.0;
                final visual = CategoryCatalog.visual(catCode);
                final name = context.trCat(catCode);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: visual.color.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(visual.icon, size: 15, color: visual.color),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              name,
                              style: TextStyle(
                                color: context.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          context.sar(amt),
                          style: GoogleFonts.outfit(
                            color: context.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: share,
                        minHeight: 5,
                        backgroundColor: context.subtleCardBg,
                        valueColor: AlwaysStoppedAnimation<Color>(visual.color),
                      ),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}
