/// Main dashboard — budget progress bars, burn rate, expense status.
/// Uses Supabase Realtime streams to update instantly when new data arrives.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../main.dart';
import '../../models/household_dues.dart';
import '../../models/household_setup.dart';
import '../../models/models.dart';
import '../../models/nafaqah.dart';
import '../../providers/budget_provider.dart';
import '../../providers/installment_provider.dart';
import '../../providers/recurring_bills_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../services/api_service.dart';
import '../../services/offline_sync_service.dart';
import '../../widgets/dashboard/budget_hero_card.dart';
import '../../widgets/dashboard/category_budget_card.dart';
import '../../widgets/dashboard/over_budget_alerts.dart';
import '../../widgets/dashboard/household_setup_card.dart';
import '../../widgets/dashboard/recurring_bills_card.dart';
import '../../widgets/dashboard/installment_plans_card.dart';
import '../../widgets/dashboard/salary_cycle_selector_bar.dart';
import '../../widgets/dashboard/household_balances_section.dart';
import '../../widgets/card_error_state.dart';
import '../../widgets/dashboard/accounts_summary_card.dart';
import '../../widgets/dashboard/payday_checkin_banner.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/app_shimmer.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/dashboard/app_speed_dial_fab.dart';
import '../../widgets/dashboard/app_bottom_nav_bar.dart';
import '../../widgets/reminder_sync.dart';
import '../../widgets/lazy_indexed_stack.dart';
import '../settings/settings_screen.dart';
import '../settings/help_support_screen.dart';
import '../../widgets/settings/household_switch_sheet.dart';
import '../../widgets/onboarding/user_guide_walkthrough_dialog.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_themes.dart';
import '../../core/widgets/widgets.dart';
import '../chat/chat_entry_screen.dart';
import '../tools/tools_screen.dart';
import 'budget_management_screen.dart';
import 'transaction_feed_screen.dart';
import '../accounts/accounts_overview_screen.dart';
import '../../services/account_service.dart';
import '../../services/salary_cycle_service.dart';
import '../../models/account.dart';

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
    // Built on first visit and kept alive (UX-26): chat, budgets and
    // settings no longer build and fetch at launch.
    Widget screen(BuildContext context, int index) {
      switch (index) {
        case 0:
          return const _BudgetDashboard();
        case 1:
          return const TransactionFeedScreen();
        case 2:
          return const ChatEntryScreen();
        case 3:
          return const BudgetManagementScreen();
        default:
          return const SettingsScreen();
      }
    }

    // Local reminders follow this household's payday, bills and plans.
    return ReminderSync(
      child: Scaffold(
        extendBody: true,
        body: LazyIndexedStack(
          index: _selectedIndex,
          itemCount: 5,
          itemBuilder: screen,
        ),
        floatingActionButton: (_selectedIndex == 0 || _selectedIndex == 1)
            ? AppSpeedDialFab(householdId: _householdId)
            : null,
        bottomNavigationBar: AppBottomNavBar(
          selectedIndex: _selectedIndex,
          onSelected: (i) => setState(() => _selectedIndex = i),
        ),
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

  /// Bumped by "Try again" to subscribe to the budgets stream afresh.
  int _budgetStreamGeneration = 0;

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
    _fetchSetup(hid);
    _fetchAccountsCount(hid);
    return hid;
  }

  Future<void> _fetchAccountsCount(String hid) async {
    try {
      final accounts = await AccountService.instance.getAccounts(hid);
      if (mounted) {
        final cash = accounts
            .where((a) => !a.isArchived && a.accountType.isOperatingPool)
            .fold<double>(0.0, (s, a) => s + (a.balance > 0 ? a.balance : 0.0));
        setState(() {
          _accountsCount = accounts.length;
          _operatingCash = cash > 0 ? cash : null;
        });
      }
    } catch (_) {}
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

  /// The selected cycle's active budgets from the budgets stream.
  List<Budget> _cycleBudgets(List<Map<String, dynamic>> rows) =>
      rows.map(Budget.fromMap).where((b) => b.isActive && _matchesSelectedCycle(b)).toList();

  final GlobalKey _categoriesKey = GlobalKey();
  final GlobalKey _balancesKey = GlobalKey();
  final GlobalKey _commitmentsKey = GlobalKey();
  int? _accountsCount;
  double? _operatingCash;

  /// First-run checklist data (UX-02): payday, income, members. The income is
  /// also the hero's base (UX-07); null until loaded.
  HouseholdSetupData? _setup;

  bool get _isCurrentCycle => _selectedCycle == null || _selectedCycle!.isCurrent;

  /// The family Nafaqah summary the balances card loaded (hero dues line).
  NafaqahSummary? _nafaqah;

  /// The settlement summary the balances section loaded (roommate dues).
  SettlementV2Summary? _settlement;

  /// The hero's dues: the viewer's roommate balances (UX-16), else what is
  /// owed to the wife (UX-07).
  List<DueLine> _dueLines() {
    final settlement = _settlement;
    if (settlement != null && settlement.isRoommateMode) {
      return roommateDueLines(settlement, supabase.auth.currentUser?.id);
    }
    return _nafaqah == null ? const [] : nafaqahDueLines(_nafaqah!);
  }

  void _scrollToBalances() {
    final ctx = _balancesKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
    }
  }

  void _scrollToCommitments() {
    final ctx = _commitmentsKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
    }
  }

  Future<void> _fetchSetup(String hid) async {
    final data = await HouseholdSetupPrefs.load(hid);
    if (mounted) setState(() => _setup = data);
  }

  /// The top of the dashboard: the guided setup for a household without
  /// budgets (UX-02), otherwise the "until payday" hero and the overspent
  /// categories, plus the checklist while setup steps remain.
  List<Widget> _buildTop(String hid, List<Budget> budgets) {
    final setup = _setup;
    final hasBudgets = budgets.isNotEmpty;
    if (!hasBudgets && _isCurrentCycle) {
      if (setup == null) return [AppShimmer.heroCard()];
      if (setup.roster == null) {
        return [
          CardErrorState(
            title: context.tr('setup_load_error_title'),
            message: context.tr('load_error_generic'),
            onRetry: () => _fetchSetup(hid),
          ),
        ];
      }
      return [HouseholdSetupCard(householdId: hid, data: setup, hasBudgets: false, onChanged: () => _fetchSetup(hid))];
    }
    final showChecklist = _isCurrentCycle &&
        setup != null &&
        setup.isAdmin &&
        !setup.hidden &&
        !setup.isComplete(hasBudgets: hasBudgets);
    return [
      BudgetHeroCard(
        budgets: budgets,
        cycle: _selectedCycle,
        monthlyIncome: setup?.monthlyIncome,
        operatingCash: _operatingCash,
        dueLines: _dueLines(),
        onDueTap: _scrollToBalances,
      ),
      // UX-08: overspent categories right under the hero.
      OverBudgetAlerts(budgets: budgets, onShowAll: _scrollToCategories),
      const SizedBox(height: 12),
      QuickAccessStrip(
        accountsCount: _accountsCount,
        wifeAllowance: _nafaqah?.primaryWife?.allowance.allocated,
        billsCount: context.watch<RecurringBillsProvider>().summary?.bills.length,
        onAccountsTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => AccountsOverviewScreen(householdId: hid)),
        ),
        onNafaqahTap: _scrollToBalances,
        onBillsTap: _scrollToCommitments,
        onSmartBasketTap: () => ToolsScreen.open(context, householdId: hid),
        onViewAllTap: () => ToolsScreen.open(context, householdId: hid),
      ),
      if (showChecklist) ...[
        const SizedBox(height: 12),
        HouseholdSetupCard(
          householdId: hid,
          data: setup,
          hasBudgets: true,
          onChanged: () => _fetchSetup(hid),
          onHide: () async {
            await HouseholdSetupPrefs.setHidden(hid);
            if (mounted) setState(() => _setup = setup.copyWith(hidden: true));
          },
        ),
      ],
    ];
  }

  void _scrollToCategories() {
    final ctx = _categoriesKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
    }
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
              key: ValueKey('budgets-$hid-$_budgetStreamGeneration'),
              stream: supabase
                  .from('budgets')
                  .stream(primaryKey: ['id'])
                  .eq('household_id', hid)
                  .order('category_code'),
              builder: (ctx, budgetSnap) {
                return RefreshIndicator(
                  color: context.accentText,
                  backgroundColor: context.cardBg,
                  onRefresh: () async {
                    try {
                      await Future.wait([
                        context.read<InstallmentProvider>().fetchPlans(),
                        context.read<TransactionProvider>().fetchTransactions(),
                        context.read<BudgetProvider>().refresh(),
                        context.read<RecurringBillsProvider>().fetchBills(),
                        _fetchSetup(hid),
                        _fetchAccountsCount(hid),
                      ]);
                    } catch (_) {}
                  },
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                    _buildAppBar(hid),
                    if (budgetSnap.hasError && !budgetSnap.hasData)
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        sliver: SliverToBoxAdapter(
                          // UX-01: a failed budget stream is an error, not an endless skeleton.
                          child: CardErrorState(
                            title: context.tr('hero_left_until_payday'),
                            message: context.tr('load_error_budgets'),
                            onRetry: () => setState(() => _budgetStreamGeneration++),
                          ),
                        ),
                      )
                    else if (!budgetSnap.hasData)
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
                              ..._buildTop(hid, _cycleBudgets(budgetSnap.data!)),
                              const SizedBox(height: 12),
                              // Balances only once there are 2+ accounts; the
                              // Tools screen always has them.
                              AccountsSummaryCard(householdId: hid, minAccounts: 2),
                              const SizedBox(height: 12),
                              HouseholdBalancesSection(
                                key: _balancesKey,
                                householdId: hid,
                                onNafaqahLoaded: (summary) {
                                  if (mounted) setState(() => _nafaqah = summary);
                                },
                                onSettlementLoaded: (summary) {
                                  if (mounted) setState(() => _settlement = summary);
                                },
                              ),
                              const SizedBox(height: 16),
                              // Commitments: recurring bills and installments together.
                              Padding(
                                key: _commitmentsKey,
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
                        padding: const EdgeInsetsDirectional.fromSTEB(24, 4, 20, 8),
                        sliver: SliverToBoxAdapter(
                          child: Text(
                            context.tr('category_budgets_heading'),
                            key: _categoriesKey,
                            style: GoogleFonts.outfit(
                              color: context.textSecondary,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        sliver: Builder(
                          builder: (context) {
                            // Most at risk first: overspent, then by share used (UX-08).
                            final cycleBudgets = Budget.sortByRisk(_cycleBudgets(budgetSnap.data!));
                            if (cycleBudgets.isEmpty) {
                              // The running cycle's empty state is the setup
                              // card at the top (UX-02); it no longer points
                              // "below" at nothing.
                              if (_isCurrentCycle) return const SliverToBoxAdapter(child: SizedBox.shrink());
                              return SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 20),
                                  child: AppEmptyState(
                                    icon: Icons.calendar_today_outlined,
                                    title: context.trArgs('no_allocations_for_cycle', {'cycle': _cycleLabel(context)}),
                                    message: context.tr('dashboard_past_cycle_no_budgets'),
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
    return SliverToBoxAdapter(
      child: VelvetWaveHeader(
        height: 120,
        leading: ThreeDIconPuck(
          key: const Key('tools_appbar_button'),
          size: 38,
          isWhiteSurface: true,
          icon: Icons.grid_view_rounded,
          iconSize: 20,
          onTap: () => ToolsScreen.open(context, householdId: hid),
        ),
        titleWidget: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [VelvetBurgundyColors.roseGold, VelvetBurgundyColors.accentRose],
                ),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(Icons.shield_rounded, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 8),
            Text(
              context.tr('app_title'),
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ).copyWith(fontFamilyFallback: VelvetBurgundyTheme.arabicFallback),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
              decoration: BoxDecoration(
                color: VelvetBurgundyColors.roseGold.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: VelvetBurgundyColors.roseGold.withValues(alpha: 0.4),
                ),
              ),
              child: Text(
                context.isArabic ? 'ذكي' : 'Smart',
                style: GoogleFonts.outfit(
                  color: VelvetBurgundyColors.roseGold,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                ).copyWith(fontFamilyFallback: VelvetBurgundyTheme.arabicFallback),
              ),
            ),
          ],
        ),
        actions: [
          ThreeDIconPuck(
            key: const Key('switch_household_appbar_button'),
            size: 38,
            isWhiteSurface: true,
            icon: Icons.swap_horiz_rounded,
            iconSize: 20,
            onTap: () {
              HouseholdSwitchSheet.show(
                context,
                currentHouseholdId: hid,
                onSwitched: () {
                  setState(() {
                    _setup = null;
                    _nafaqah = null;
                    _settlement = null;
                    _householdId = _fetchHouseholdId();
                  });
                },
              );
            },
          ),
          const SizedBox(width: 8),
          ThreeDIconPuck(
            size: 38,
            isWhiteSurface: true,
            icon: Icons.notifications_rounded,
            iconSize: 20,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => HelpSupportScreen(householdId: hid),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class QuickAccessStrip extends StatelessWidget {
  final int? accountsCount;
  final double? wifeAllowance;
  final int? billsCount;
  final VoidCallback onAccountsTap;
  final VoidCallback onNafaqahTap;
  final VoidCallback onBillsTap;
  final VoidCallback onSmartBasketTap;
  final VoidCallback onViewAllTap;

  const QuickAccessStrip({
    super.key,
    this.accountsCount,
    this.wifeAllowance,
    this.billsCount,
    required this.onAccountsTap,
    required this.onNafaqahTap,
    required this.onBillsTap,
    required this.onSmartBasketTap,
    required this.onViewAllTap,
  });

  String _accountsLabel(BuildContext context) {
    if (accountsCount != null && accountsCount! > 0) {
      return '${context.tr('quick_accounts')} ($accountsCount)';
    }
    return context.tr('quick_accounts');
  }

  String _wifeAllowanceLabel(BuildContext context) {
    if (wifeAllowance != null && wifeAllowance! > 0) {
      return '${context.tr('quick_wife_allowance')} (${context.sar(wifeAllowance!)})';
    }
    return context.tr('quick_wife_allowance');
  }

  String _billsLabel(BuildContext context) {
    if (billsCount != null && billsCount! > 0) {
      return '${context.tr('quick_bills')} ($billsCount)';
    }
    return context.tr('quick_bills');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                context.tr('quick_access'),
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: context.textPrimary,
                ).copyWith(fontFamilyFallback: VelvetBurgundyTheme.arabicFallback),
              ),
              InkWell(
                onTap: onViewAllTap,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    context.tr('show_all'),
                    style: GoogleFonts.outfit(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: isDark ? VelvetBurgundyColors.roseGoldGlow : VelvetBurgundyColors.accentRose,
                    ).copyWith(fontFamilyFallback: VelvetBurgundyTheme.arabicFallback),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: [
              _buildMiniPill(context, '💳', _accountsLabel(context), onAccountsTap),
              const SizedBox(width: 8),
              _buildMiniPill(context, '⚖️', _wifeAllowanceLabel(context), onNafaqahTap),
              const SizedBox(width: 8),
              _buildMiniPill(context, '📅', _billsLabel(context), onBillsTap),
              const SizedBox(width: 8),
              _buildMiniPill(context, '🛒', context.tr('quick_smart_basket'), onSmartBasketTap),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMiniPill(
    BuildContext context,
    String iconEmoji,
    String title,
    VoidCallback onTap,
  ) {
    final isDark = context.isDark;

    return ThreeDSurfaceCard(
      borderRadius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(iconEmoji, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 6),
          Text(
            title,
            style: GoogleFonts.outfit(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : VelvetBurgundyColors.primaryLight,
            ).copyWith(fontFamilyFallback: VelvetBurgundyTheme.arabicFallback),
          ),
        ],
      ),
    );
  }
}

