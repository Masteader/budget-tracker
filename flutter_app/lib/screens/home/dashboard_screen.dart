/// Main dashboard — budget progress bars, burn rate, SMS service status.
/// Uses Supabase Realtime streams to update instantly when new data arrives.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../main.dart';
import '../../models/models.dart';
import '../../services/sms_service.dart';
import '../../services/offline_sync_service.dart';
import '../../widgets/salary_cycle_widget.dart';
import '../../widgets/partner_settlement_card.dart';
import '../chat/chat_entry_screen.dart';
import '../scanner/multi_page_receipt_scanner_screen.dart';
import '../scanner/receipt_scanner_sheet.dart';
import '../analytics/grocery_price_intelligence_screen.dart';
import '../settings/ingestion_settings_screen.dart';
import '../../services/api_service.dart';
import '../../widgets/sub_budget_breakdown_sheet.dart';
import 'transaction_feed_screen.dart';
import 'budget_management_screen.dart';


class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;
  String? _householdId;

  @override
  void initState() {
    super.initState();
    // Drain any SMS that arrived while the app was closed
    SmsService.instance.drainOfflineQueue();
    // Drain any offline SQLite transaction queue
    OfflineSyncService.instance.flushQueue();
    OfflineSyncService.instance.updatePendingCount();

    OfflineSyncService.instance.onItemsFlushed.listen((count) {
      if (mounted && count > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Synced $count queued offline transaction(s) with cloud!'),
            backgroundColor: const Color(0xFF00C896),
          ),
        );
      }
    });

    _fetchHouseholdId();
  }

  Future<void> _fetchHouseholdId() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final data = await supabase
          .from('users')
          .select('household_id')
          .eq('id', uid)
          .single();
      if (mounted) {
        setState(() => _householdId = data['household_id'] as String?);
      }
    } catch (_) {}
  }

  void _showAddExpenseModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF161B22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF30363D),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Add Transaction',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              Material(
                color: Colors.transparent,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00C896).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.auto_awesome, color: Color(0xFF00C896), size: 22),
                  ),
                  title: const Text('AI Conversational Chat & Simulator', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
                  subtitle: const Text('Say what you spent or ask "Can I afford this?"', style: TextStyle(color: Color(0xFF8B949E), fontSize: 12)),
                  trailing: const Icon(Icons.chevron_right, color: Color(0xFF8B949E)),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ChatEntryScreen()),
                    );
                  },
                ),
              ),
              const SizedBox(height: 6),
              Material(
                color: Colors.transparent,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1F6FEB).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.document_scanner_outlined, color: Color(0xFF58A6FF), size: 22),
                  ),
                  title: const Text('Scan VAT Invoice / Receipt (ZATCA & Multi-Page)', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
                  subtitle: const Text('ZATCA QR camera, manual code input, or multi-page photos', style: TextStyle(color: Color(0xFF8B949E), fontSize: 12)),
                  trailing: const Icon(Icons.chevron_right, color: Color(0xFF8B949E)),
                  onTap: () {
                    Navigator.pop(ctx);
                    if (_householdId != null) {
                      ReceiptScannerSheet.show(context, _householdId!);
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      const _BudgetDashboard(),
      const TransactionFeedScreen(),
      const BudgetManagementScreen(),
      const IngestionSettingsScreen(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: screens,
      ),
      floatingActionButton: (_selectedIndex == 2 || _selectedIndex == 3)
          ? null
          : FloatingActionButton.extended(
              backgroundColor: const Color(0xFF00C896),
              foregroundColor: Colors.black,
              icon: const Icon(Icons.add_rounded, size: 22),
              label: const Text('Add Expense', style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: () => _showAddExpenseModal(context),
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        backgroundColor: const Color(0xFF161B22),
        indicatorColor: const Color(0xFF00C896).withValues(alpha: 0.2),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard, color: Color(0xFF00C896)),
              label: 'Dashboard'),
          NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long, color: Color(0xFF00C896)),
              label: 'Transactions'),
          NavigationDestination(
              icon: Icon(Icons.tune_outlined),
              selectedIcon: Icon(Icons.tune, color: Color(0xFF00C896)),
              label: 'Budgets'),
          NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings, color: Color(0xFF00C896)),
              label: 'Settings'),
        ],
      ),
    );
  }
}

// ─── Budget Dashboard Tab ─────────────────────────────────────────────────────

class _BudgetDashboard extends StatefulWidget {
  const _BudgetDashboard();

  @override
  State<_BudgetDashboard> createState() => _BudgetDashboardState();
}

class _BudgetDashboardState extends State<_BudgetDashboard> {
  late Future<String> _householdId;
  List<SalaryCycleInfo> _cycles = [];
  int _currentCycleIndex = 0;

  @override
  void initState() {
    super.initState();
    _householdId = _fetchHouseholdId();
  }

  Future<String> _fetchHouseholdId() async {
    final uid = supabase.auth.currentUser!.id;
    final data = await supabase
        .from('users')
        .select('household_id')
        .eq('id', uid)
        .single();
    final hid = data['household_id'] as String;
    _fetchCycles(hid);
    return hid;
  }

  Future<void> _fetchCycles(String hid) async {
    try {
      final res = await ApiService.instance.getSalaryCycles(hid);
      if (res['cycles'] != null) {
        final list = (res['cycles'] as List)
            .map((c) => SalaryCycleInfo.fromMap(Map<String, dynamic>.from(c as Map)))
            .toList();
        if (mounted && list.isNotEmpty) {
          setState(() {
            _cycles = list;
            final idx = list.indexWhere((c) => c.isCurrent);
            _currentCycleIndex = idx != -1 ? idx : 0;
          });
        }
      }
    } catch (_) {}
  }

  SalaryCycleInfo? get _selectedCycle =>
      _cycles.isNotEmpty && _currentCycleIndex < _cycles.length
          ? _cycles[_currentCycleIndex]
          : null;

  String get _currentCycleKey {
    if (_selectedCycle != null) return _selectedCycle!.cycleKey;
    final now = DateTime.now();
    if (now.day >= 27) {
      final next = DateTime(now.year, now.month + 1, 1);
      return DateFormat('yyyy-MM').format(next);
    }
    return DateFormat('yyyy-MM').format(now);
  }

  bool _matchesSelectedCycle(Budget b) {
    final key = _currentCycleKey;
    if (b.cycleKey != null && b.cycleKey!.isNotEmpty) {
      return b.cycleKey == key;
    }
    return b.month.startsWith(key);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _householdId,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        final hid = snap.data!;
        return Scaffold(
          body: SafeArea(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: supabase
                  .from('budgets')
                  .stream(primaryKey: ['id'])
                  .eq('household_id', hid)
                  .order('category_code'),
              builder: (ctx, budgetSnap) {
                return CustomScrollView(
                  slivers: [
                    _buildAppBar(hid),
                    if (!budgetSnap.hasData)
                      const SliverFillRemaining(
                          child: Center(child: CircularProgressIndicator()))
                    else ...[
                      _buildSalaryCycleBar(),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                        sliver: SliverToBoxAdapter(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ValueListenableBuilder<int>(
                                valueListenable: OfflineSyncService.instance.pendingCountNotifier,
                                builder: (ctx, pending, _) {
                                  if (pending == 0) return const SizedBox.shrink();
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.cloud_off_rounded, color: Colors.orange, size: 18),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            '$pending transaction(s) queued offline',
                                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: () => OfflineSyncService.instance.flushQueue(),
                                          child: const Text('Sync Now', style: TextStyle(color: Color(0xFF00C896), fontWeight: FontWeight.bold, fontSize: 12)),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                              _SummaryCard(
                                budgets: budgetSnap.data!
                                    .map(Budget.fromMap)
                                    .where((b) => b.isActive && _matchesSelectedCycle(b))
                                    .toList(),
                                cycle: _selectedCycle,
                              ),
                              const SizedBox(height: 12),
                              SalaryCycleWidget(householdId: hid),
                              const SizedBox(height: 12),
                              PartnerSettlementCard(householdId: hid),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: InkWell(
                                      onTap: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => GroceryPriceIntelligenceScreen(householdId: hid),
                                        ),
                                      ),
                                      borderRadius: BorderRadius.circular(14),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF161B22),
                                          borderRadius: BorderRadius.circular(14),
                                          border: Border.all(color: const Color(0xFF30363D)),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(Icons.trending_up_rounded, color: Color(0xFF00C896), size: 18),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                'Price Tracker',
                                                style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: InkWell(
                                      onTap: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => MultiPageReceiptScannerScreen(householdId: hid),
                                        ),
                                      ),
                                      borderRadius: BorderRadius.circular(14),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF161B22),
                                          borderRadius: BorderRadius.circular(14),
                                          border: Border.all(color: const Color(0xFF30363D)),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(Icons.document_scanner_outlined, color: Color(0xFF58A6FF), size: 18),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                'Multi-Shot Scan',
                                                style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        sliver: Builder(
                          builder: (context) {
                            final cycleBudgets = budgetSnap.data!
                                .map(Budget.fromMap)
                                .where((b) => b.isActive && _matchesSelectedCycle(b))
                                .toList();
                            if (cycleBudgets.isEmpty) {
                              return SliverToBoxAdapter(
                                child: Container(
                                  padding: const EdgeInsets.all(24),
                                  margin: const EdgeInsets.only(bottom: 20),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF161B22),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: const Color(0xFF30363D)),
                                  ),
                                  child: Column(
                                    children: [
                                      const Icon(Icons.calendar_today_outlined, color: Color(0xFF8B949E), size: 36),
                                      const SizedBox(height: 12),
                                      Text(
                                        'No allocations for $_currentCycleKey',
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(height: 6),
                                      const Text(
                                        'Budgets auto-rollover on payday (27th). You can also add categories from the Budgets tab.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(color: Color(0xFF8B949E), fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }
                            return SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (ctx, i) {
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: _BudgetCard(
                                      budget: cycleBudgets[i],
                                      householdId: hid,
                                      cycleKey: _currentCycleKey,
                                    ),
                                  );
                                },
                                childCount: cycleBudgets.length,
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildAppBar(String hid) {
    return SliverAppBar(
      pinned: true,
      backgroundColor: const Color(0xFF0D1117),
      elevation: 0,
      title: Text(
        'Budget Tracker',
        style: GoogleFonts.outfit(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.logout_rounded, color: Color(0xFF8B949E)),
          tooltip: 'Sign Out',
          onPressed: () => supabase.auth.signOut(),
        ),
      ],
    );
  }

  Widget _buildSalaryCycleBar() {
    final currentCycle = _selectedCycle;
    final titleText = currentCycle?.monthName ?? DateFormat('MMMM yyyy').format(DateTime.now());
    final subText = currentCycle != null
        ? '${currentCycle.cycleStart.substring(5)} - ${currentCycle.cycleEnd.substring(5)}'
        : 'Payday 27th Cycle (27th - 26th)';
    final isCurrent = currentCycle?.isCurrent ?? true;

    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF30363D)),
        ),
        child: Row(
          children: [
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              icon: const Icon(Icons.chevron_left_rounded, color: Colors.white70, size: 24),
              onPressed: (_cycles.isNotEmpty && _currentCycleIndex < _cycles.length - 1)
                  ? () => setState(() => _currentCycleIndex++)
                  : null,
            ),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        titleText,
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      if (isCurrent) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00C896).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFF00C896).withValues(alpha: 0.6)),
                          ),
                          child: const Text(
                            'ACTIVE',
                            style: TextStyle(
                              color: Color(0xFF00C896),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subText,
                    style: const TextStyle(
                      color: Color(0xFF8B949E),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              icon: const Icon(Icons.chevron_right_rounded, color: Colors.white70, size: 24),
              onPressed: (_cycles.isNotEmpty && _currentCycleIndex > 0)
                  ? () => setState(() => _currentCycleIndex--)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

}

// ─── Summary Card ─────────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final List<Budget> budgets;
  final SalaryCycleInfo? cycle;
  const _SummaryCard({required this.budgets, this.cycle});

  @override
  Widget build(BuildContext context) {
    final totalAllocated = budgets.fold(0.0, (s, b) => s + b.allocatedAmount);
    final totalSpent     = budgets.fold(0.0, (s, b) => s + b.spentAmount);

    final daysTotal   = cycle?.daysTotal ?? 30;
    final daysElapsed = (cycle?.daysElapsed ?? 1).clamp(1, daysTotal);

    // Separate fixed lump-sum monthly commitments (rent, utilities) from variable daily expenses
    const fixedCodes = {'HOUSING-RENT', 'HOUSING', 'OPEX-UTILITIES', 'UTILITIES-BILLS'};
    double fixedSpent = 0.0;
    double variableSpent = 0.0;
    for (final b in budgets) {
      if (fixedCodes.contains(b.categoryCode)) {
        fixedSpent += b.spentAmount;
      } else {
        variableSpent += b.spentAmount;
      }
    }

    // Daily burn is computed from variable living expenses so rent doesn't distort projections
    final dailyBurn = daysElapsed > 0 ? variableSpent / daysElapsed : 0.0;
    final projectedSpend = fixedSpent + (dailyBurn * daysTotal);
    final fmt            = NumberFormat('#,##0.00', 'en_US');

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF00C896), Color(0xFF00A3FF)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Total Budget', style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 4),
          Text('SAR ${fmt.format(totalAllocated)}',
              style: GoogleFonts.outfit(
                  color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _StatItem(label: 'Spent', value: 'SAR ${fmt.format(totalSpent)}'),
              _StatItem(
                  label: 'Remaining',
                  value: 'SAR ${fmt.format(totalAllocated - totalSpent)}'),
              _StatItem(label: 'Burn/Day', value: 'SAR ${fmt.format(dailyBurn)}'),
            ],
          ),
          const SizedBox(height: 12),
          if (projectedSpend > totalAllocated)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    'Projected: SAR ${fmt.format(projectedSpend)} (over budget!)',
                    style: const TextStyle(color: Colors.orange, fontSize: 12),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  const _StatItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(
                  color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      );
}

// ─── Budget Card (per category) ───────────────────────────────────────────────

class _BudgetCard extends StatelessWidget {
  final Budget budget;
  final String householdId;
  final String? cycleKey;

  const _BudgetCard({
    required this.budget,
    required this.householdId,
    this.cycleKey,
  });

  Color get _barColor {
    if (budget.usagePercent >= 1.0) return Colors.redAccent;
    if (budget.usagePercent >= 0.8) return Colors.orange;
    return const Color(0xFF00C896);
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00', 'en_US');
    final hasRollover = budget.previousCycleDelta != 0.0;
    final subCategories = kSubCategoriesByParent[budget.categoryCode] ?? const <String>[];

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          SubBudgetBreakdownSheet.show(
            context,
            householdId: householdId,
            categoryCode: budget.categoryCode,
            cycleKey: cycleKey,
            allocatedAmount: budget.allocatedAmount,
            previousCycleDelta: budget.previousCycleDelta,
          );
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF30363D)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            budget.categoryCode.replaceFirst(RegExp(r'^[A-Z]+-'), ''),
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (hasRollover) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: budget.previousCycleDelta > 0
                                  ? const Color(0xFF00C896).withValues(alpha: 0.15)
                                  : Colors.redAccent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              budget.previousCycleDelta > 0
                                  ? '+SAR ${fmt.format(budget.previousCycleDelta)}'
                                  : '-SAR ${fmt.format(budget.previousCycleDelta.abs())}',
                              style: TextStyle(
                                color: budget.previousCycleDelta > 0
                                    ? const Color(0xFF00C896)
                                    : Colors.redAccent,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${(budget.usagePercent * 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                            color: _barColor, fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right, size: 16, color: Color(0xFF8B949E)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: budget.usagePercent,
                  backgroundColor: const Color(0xFF30363D),
                  valueColor: AlwaysStoppedAnimation(_barColor),
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('SAR ${fmt.format(budget.spentAmount)} spent',
                      style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12)),
                  Text('of SAR ${fmt.format(budget.allocatedAmount)}',
                      style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12)),
                ],
              ),
              if (subCategories.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D1117),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF21262D)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.account_tree_outlined, size: 13, color: Color(0xFF00C896)),
                          SizedBox(width: 6),
                          Text(
                            'Sub-Categories',
                            style: TextStyle(color: Color(0xFF00C896), fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                          Spacer(),
                          Text(
                            'Breakdown',
                            style: TextStyle(color: Color(0xFF8B949E), fontSize: 10),
                          ),
                          SizedBox(width: 2),
                          Icon(Icons.chevron_right, size: 14, color: Color(0xFF8B949E)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 5,
                        runSpacing: 4,
                        children: subCategories.map((s) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF161B22),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            s,
                            style: const TextStyle(color: Color(0xFF8B949E), fontSize: 10),
                          ),
                        )).toList(),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

