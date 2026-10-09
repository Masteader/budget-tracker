/// Main dashboard — budget progress bars, burn rate, expense status.
/// Uses Supabase Realtime streams to update instantly when new data arrives.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../main.dart';
import '../../models/models.dart';
import '../../providers/budget_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../services/api_service.dart';
import '../../services/offline_sync_service.dart';
import '../../widgets/dashboard/budget_hero_card.dart';
import '../../widgets/dashboard/category_budget_card.dart';
import '../../widgets/dashboard/dashboard_action_sheet.dart';
import '../../widgets/dashboard/recurring_bills_card.dart';
import '../../widgets/dashboard/installment_plans_card.dart';
import '../../widgets/dashboard/salary_cycle_selector_bar.dart';
import '../../widgets/partner_settlement_card.dart';
import '../../widgets/salary_cycle_widget.dart';
import '../analytics/grocery_price_intelligence_screen.dart';
import '../scanner/multi_page_receipt_scanner_screen.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/app_shimmer.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/dashboard/app_speed_dial_fab.dart';
import '../settings/ingestion_settings_screen.dart';
import 'budget_management_screen.dart';
import 'transaction_feed_screen.dart';

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
    // Drain any offline SQLite transaction queue
    OfflineSyncService.instance.flushQueue();
    OfflineSyncService.instance.updatePendingCount();

    OfflineSyncService.instance.onItemsFlushed.listen((count) {
      if (mounted && count > 0) {
        context.read<TransactionProvider>().fetchTransactions();
        context.read<BudgetProvider>().refresh();
        AppSnackBar.showSuccess(
          context,
          'Synced $count queued offline transaction(s) with cloud.',
          title: 'Sync Complete',
          icon: Icons.cloud_done_rounded,
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
          : AppSpeedDialFab(householdId: _householdId),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        backgroundColor: const Color(0xFF161B22),
        indicatorColor: const Color(0xFF00C896).withValues(alpha: 0.2),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard, color: Color(0xFF00C896)),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long, color: Color(0xFF00C896)),
            label: 'Transactions',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune, color: Color(0xFF00C896)),
            label: 'Budgets',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings, color: Color(0xFF00C896)),
            label: 'Settings',
          ),
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
      if (b.cycleKey == key) return true;
    }
    final cycleStart = _selectedCycle?.cycleStart;
    if (cycleStart != null && cycleStart.length >= 7) {
      final cycleMonth = cycleStart.substring(0, 7);
      if (b.month == cycleMonth || b.month.startsWith(cycleMonth)) return true;
    }
    final keyPrefix = key.length >= 7 ? key.substring(0, 7) : key;
    return b.month.startsWith(keyPrefix);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _householdId,
      builder: (context, snap) {
        if (!snap.hasData) {
          return Scaffold(
            backgroundColor: const Color(0xFF0D1117),
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                  children: [
                    AppShimmer.heroCard(),
                    const SizedBox(height: 16),
                    Expanded(child: AppShimmer.listItems(count: 3)),
                  ],
                ),
              ),
            ),
          );
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
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        sliver: SliverToBoxAdapter(
                          child: Column(
                            children: [
                              AppShimmer.heroCard(),
                              const SizedBox(height: 16),
                              AppShimmer.listItems(count: 3),
                            ],
                          ),
                        ),
                      )
                    else ...[
                      SliverToBoxAdapter(
                        child: SalaryCycleSelectorBar(
                          currentCycle: _selectedCycle,
                          hasPrevious: _cycles.isNotEmpty && _currentCycleIndex < _cycles.length - 1,
                          hasNext: _cycles.isNotEmpty && _currentCycleIndex > 0,
                          onPrevious: () => setState(() => _currentCycleIndex++),
                          onNext: () => setState(() => _currentCycleIndex--),
                        ),
                      ),
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
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: () => OfflineSyncService.instance.flushQueue(),
                                          child: const Text(
                                            'Sync Now',
                                            style: TextStyle(
                                              color: Color(0xFF00C896),
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                              BudgetHeroCard(
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
                              RecurringBillsCard(householdId: hid),
                              const SizedBox(height: 12),
                              InstallmentPlansCard(householdId: hid),
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
                                                style: GoogleFonts.outfit(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                ),
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
                                                style: GoogleFonts.outfit(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                ),
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
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 20),
                                  child: AppEmptyState(
                                    icon: Icons.calendar_today_outlined,
                                    title: 'No allocations for $_currentCycleKey',
                                    message: 'Budgets auto-rollover on monthly payday. You can also add categories from the Budgets tab.',
                                  ),
                                ),
                              );
                            }
                            return SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (ctx, i) {
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: CategoryBudgetCard(
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
                      const SliverToBoxAdapter(
                        child: SizedBox(height: 80),
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
}
