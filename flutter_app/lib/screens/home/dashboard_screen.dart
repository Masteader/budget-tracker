/// Main dashboard — budget progress bars, burn rate, expense status.
/// Uses Supabase Realtime streams to update instantly when new data arrives.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../main.dart';
import '../../models/models.dart';
import '../../providers/budget_provider.dart';
import '../../providers/installment_provider.dart';
import '../../providers/recurring_bills_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../services/api_service.dart';
import '../../services/offline_sync_service.dart';
import '../../widgets/dashboard/budget_hero_card.dart';
import '../../widgets/dashboard/category_budget_card.dart';
import '../../widgets/dashboard/recurring_bills_card.dart';
import '../../widgets/dashboard/installment_plans_card.dart';
import '../../widgets/dashboard/salary_cycle_selector_bar.dart';
import '../../widgets/dashboard/family_reimbursement_card.dart';
import '../../widgets/dashboard/multi_roommate_settlement_card.dart';
import '../../widgets/dashboard/accounts_summary_card.dart';
import '../../widgets/dashboard/payday_checkin_banner.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/app_shimmer.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/dashboard/app_speed_dial_fab.dart';
import '../settings/settings_screen.dart';
import '../settings/help_support_screen.dart';
import '../../widgets/settings/household_switch_sheet.dart';
import '../../widgets/onboarding/user_guide_walkthrough_dialog.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_themes.dart';
import '../chat/chat_entry_screen.dart';
import '../tools/tools_screen.dart';
import 'budget_management_screen.dart';
import 'transaction_feed_screen.dart';
import '../../services/salary_cycle_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;
  String? _householdId;
  StreamSubscription<int>? _flushSubscription;

  @override
  void initState() {
    super.initState();
    // Drain any offline SQLite transaction queue
    OfflineSyncService.instance.flushQueue();
    OfflineSyncService.instance.updatePendingCount();

    _flushSubscription = OfflineSyncService.instance.onItemsFlushed.listen((count) {
      if (mounted && count > 0) {
        context.read<TransactionProvider>().fetchTransactions();
        context.read<BudgetProvider>().refresh();
        context.read<RecurringBillsProvider>().fetchBills();
        AppSnackBar.showSuccess(
          context,
          context.trPlural('sync_complete_msg', count),
          title: context.tr('sync_complete'),
          icon: Icons.cloud_done_rounded,
        );
      }
    });

    _fetchHouseholdId();
  }

  @override
  void dispose() {
    // The sync stream is app-lifetime; without cancelling, every dashboard
    // instance kept its listener (and a dead BuildContext) alive.
    _flushSubscription?.cancel();
    super.dispose();
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
      const ChatEntryScreen(),
      const BudgetManagementScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: _selectedIndex,
        children: screens,
      ),
      floatingActionButton: (_selectedIndex == 0 || _selectedIndex == 1)
          ? AppSpeedDialFab(householdId: _householdId)
          : null,
      bottomNavigationBar: _buildFloatingBottomNavBar(context),
    );
  }

  Widget _buildFloatingBottomNavBar(BuildContext context) {
    final isDark = context.isDark;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      height: 68,
      decoration: BoxDecoration(
        color: isDark
            ? AppThemes.deepGlacial.withValues(alpha: 0.94)
            : Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isDark
              ? AppThemes.iceCyan.withValues(alpha: 0.22)
              : AppThemes.electricTeal.withValues(alpha: 0.35),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.45)
                : AppThemes.electricTeal.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
          if (!isDark)
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildNavItem(
            index: 0,
            icon: Icons.home_outlined,
            selectedIcon: Icons.home_rounded,
            label: context.tr('nav_dashboard'),
          ),
          _buildNavItem(
            index: 1,
            icon: Icons.receipt_long_outlined,
            selectedIcon: Icons.receipt_long_rounded,
            label: context.tr('nav_transactions'),
          ),
          _buildCenterAiNavItem(),
          _buildNavItem(
            index: 3,
            icon: Icons.pie_chart_outline_rounded,
            selectedIcon: Icons.pie_chart_rounded,
            label: context.tr('nav_budgets'),
          ),
          _buildNavItem(
            index: 4,
            icon: Icons.person_outline_rounded,
            selectedIcon: Icons.person_rounded,
            label: context.tr('nav_settings'),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required IconData selectedIcon,
    required String label,
  }) {
    final isSelected = _selectedIndex == index;
    final isDark = context.isDark;
    final activeColor = isDark ? AppThemes.electricTeal : const Color(0xFF008F7A);
    final inactiveColor = isDark ? const Color(0xFF8B949E) : const Color(0xFF64748B);

    return InkWell(
      onTap: () => setState(() => _selectedIndex = index),
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding: EdgeInsets.symmetric(
                horizontal: isSelected ? 12 : 6,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: isSelected
                    ? (isDark
                        ? AppThemes.electricTeal.withValues(alpha: 0.16)
                        : AppThemes.electricTeal.withValues(alpha: 0.18))
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                isSelected ? selectedIcon : icon,
                color: isSelected ? activeColor : inactiveColor,
                size: 22,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? activeColor : inactiveColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCenterAiNavItem() {
    final isSelected = _selectedIndex == 2;
    return GestureDetector(
      onTap: () => setState(() => _selectedIndex = 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppThemes.electricTeal, AppThemes.iceCyan],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppThemes.electricTeal.withValues(alpha: isSelected ? 0.65 : 0.4),
                  blurRadius: isSelected ? 16 : 10,
                  spreadRadius: isSelected ? 2 : 0,
                ),
              ],
            ),
            child: const Icon(
              Icons.auto_awesome,
              color: AppThemes.brandDarkBg,
              size: 22,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            context.tr('nav_ai'),
            style: GoogleFonts.outfit(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              color: isSelected
                  ? (context.isDark ? AppThemes.electricTeal : const Color(0xFF008F7A))
                  : (context.isDark ? const Color(0xFF8B949E) : const Color(0xFF64748B)),
            ),
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        UserGuideWalkthroughDialog.showIfFirstTime(context);
      }
    });
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
    return SalaryCycleService.cycleKeyForInstant(DateTime.now());
  }

  /// The selected cycle by its dates ("27 Oct – 26 Nov").
  String _cycleLabel(BuildContext context) {
    final c = _selectedCycle;
    final byKey = context.cycleLabel(_currentCycleKey);
    return c == null ? byKey : context.cycleRangeIso(c.cycleStart, c.cycleEnd, fallback: byKey);
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
            backgroundColor: context.scaffoldBg,
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
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            try {
              context.read<InstallmentProvider>().init(hid);
            } catch (_) {}
          }
        });
        return Scaffold(
          body: SafeArea(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: supabase
                  .from('budgets')
                  .stream(primaryKey: ['id'])
                  .eq('household_id', hid)
                  .order('category_code'),
              builder: (ctx, budgetSnap) {
                return RefreshIndicator(
                  color: AppThemes.electricTeal,
                  backgroundColor: context.cardBg,
                  onRefresh: () async {
                    try {
                      await Future.wait([
                        context.read<InstallmentProvider>().fetchPlans(),
                        context.read<TransactionProvider>().fetchTransactions(),
                        context.read<BudgetProvider>().refresh(),
                        context.read<RecurringBillsProvider>().fetchBills(),
                      ]);
                    } catch (_) {}
                  },
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
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
                                            context.trPlural('queued_offline', pending),
                                            style: TextStyle(
                                              color: context.textPrimary,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: () => OfflineSyncService.instance.flushQueue(),
                                          child: Text(
                                            context.tr('sync_now'),
                                            style: TextStyle(
                                              color: context.accentText,
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
                              PaydayCheckinBanner(householdId: hid),
                              BudgetHeroCard(
                                budgets: budgetSnap.data!
                                    .map(Budget.fromMap)
                                    .where((b) => b.isActive && _matchesSelectedCycle(b))
                                    .toList(),
                                cycle: _selectedCycle,
                              ),
                              // Balances only once there are 2+ accounts; the
                              // Tools screen always has them.
                              AccountsSummaryCard(householdId: hid, minAccounts: 2),
                              const SizedBox(height: 12),
                              FutureBuilder<SettlementV2Summary>(
                                future: ApiService.instance.getSettlementV2(hid),
                                builder: (context, snap) {
                                  if (snap.hasData && snap.data!.isRoommateMode) {
                                    return MultiRoommateSettlementCard(
                                      householdId: hid,
                                      summary: snap.data,
                                    );
                                  }
                                  return FamilyReimbursementCard(
                                    householdId: hid,
                                  );
                                },
                              ),
                              const SizedBox(height: 16),
                              // Commitments: recurring bills and installments together.
                              Padding(
                                padding: const EdgeInsetsDirectional.only(start: 4, bottom: 8),
                                child: Text(
                                  context.tr('commitments'),
                                  style: GoogleFonts.outfit(
                                    color: context.textSecondary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ),
                              RecurringBillsCard(householdId: hid),
                              const SizedBox(height: 12),
                              InstallmentPlansCard(householdId: hid),
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
                                    title: context.trArgs('no_allocations_for_cycle', {'cycle': _cycleLabel(context)}),
                                    message: context.tr('budgets_auto_rollover_desc'),
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
                ),
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
      backgroundColor: context.scaffoldBg,
      elevation: 0,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: AppThemes.electricTeal.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppThemes.iceCyan.withValues(alpha: 0.3)),
            ),
            child: const Icon(Icons.waves_rounded, color: AppThemes.electricTeal, size: 16),
          ),
          const SizedBox(width: 8),
          Text(
            context.tr('app_title'),
            style: GoogleFonts.outfit(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: context.textPrimary,
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          key: const Key('tools_appbar_button'),
          icon: const Icon(Icons.grid_view_rounded, color: AppThemes.electricTeal),
          tooltip: context.tr('tools_title'),
          onPressed: () => ToolsScreen.open(context, householdId: hid),
        ),
        IconButton(
          key: const Key('switch_household_appbar_button'),
          icon: const Icon(Icons.swap_horiz_rounded, color: AppThemes.electricTeal),
          tooltip: context.tr('switch_household'),
          onPressed: () {
            HouseholdSwitchSheet.show(
              context,
              currentHouseholdId: hid,
              onSwitched: () {
                setState(() {
                  _householdId = _fetchHouseholdId();
                });
              },
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.help_outline_rounded, color: AppThemes.electricTeal),
          tooltip: context.tr('help_support'),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => HelpSupportScreen(householdId: hid),
              ),
            );
          },
        ),
        IconButton(
          icon: Icon(Icons.logout_rounded, color: context.textSecondary),
          tooltip: context.tr('sign_out'),
          onPressed: () => supabase.auth.signOut(),
        ),
      ],
    );
  }
}
