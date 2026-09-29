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
import '../analytics/grocery_price_intelligence_screen.dart';
import '../settings/ingestion_settings_screen.dart';
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
      backgroundColor: const Color(0xFF161B22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
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
              'Add Transaction & Financial Tools',
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
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
                title: const Text('AI Chat & Pre-Purchase Simulator', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
                subtitle: const Text('Log expenses or ask "Can I buy a 1200 SAR iPad?"', style: TextStyle(color: Color(0xFF8B949E), fontSize: 12)),
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
                title: const Text('Continuous Multi-Page Receipt Stitcher', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
                subtitle: const Text('Snap sequential shots of long 60+ item grocery receipts', style: TextStyle(color: Color(0xFF8B949E), fontSize: 12)),
                trailing: const Icon(Icons.chevron_right, color: Color(0xFF8B949E)),
                onTap: () {
                  Navigator.pop(ctx);
                  if (_householdId != null) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MultiPageReceiptScannerScreen(householdId: _householdId!),
                      ),
                    );
                  }
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
                    color: Colors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.analytics_outlined, color: Colors.amber, size: 22),
                ),
                title: const Text('Grocery Price Intelligence & Inflation', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
                subtitle: const Text('Compare prices across Panda, Danube, and Tamimi', style: TextStyle(color: Color(0xFF8B949E), fontSize: 12)),
                trailing: const Icon(Icons.chevron_right, color: Color(0xFF8B949E)),
                onTap: () {
                  Navigator.pop(ctx);
                  if (_householdId != null) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => GroceryPriceIntelligenceScreen(householdId: _householdId!),
                      ),
                    );
                  }
                },
              ),
            ),
          ],
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
      floatingActionButton: _selectedIndex == 3
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
    return data['household_id'] as String;
  }

  String get _currentMonth =>
      DateFormat('yyyy-MM-01').format(DateTime.now());

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
                              _SummaryCard(budgets: budgetSnap.data!
                                  .map(Budget.fromMap)
                                  .where((b) => b.month == _currentMonth)
                                  .toList()),
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
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (ctx, i) {
                              final budget = Budget.fromMap(budgetSnap.data![i]);
                              if (budget.month != _currentMonth) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _BudgetCard(budget: budget),
                              );
                            },
                            childCount: budgetSnap.data!.length,
                          ),
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
      expandedHeight: 120,
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              DateFormat('MMMM yyyy').format(DateTime.now()),
              style: GoogleFonts.outfit(
                  fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
            ),
            _SmsStatusIndicator(),
          ],
        ),
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0D1117), Color(0xFF0A1628)],
            ),
          ),
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.tune_rounded, color: Color(0xFF8B949E)),
          tooltip: 'Ingestion & Channels',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const IngestionSettingsScreen()),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.logout),
          onPressed: () => supabase.auth.signOut(),
        ),
      ],
    );
  }
}

// ─── SMS Status Indicator ──────────────────────────────────────────────────

class _SmsStatusIndicator extends StatefulWidget {
  @override
  State<_SmsStatusIndicator> createState() => _SmsStatusIndicatorState();
}

class _SmsStatusIndicatorState extends State<_SmsStatusIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
        vsync: this, duration: const Duration(seconds: 1))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: SmsService.instance.listeningNotifier,
      builder: (ctx, active, _) {
        return GestureDetector(
          onTap: () async {
            if (active) {
              await SmsService.instance.stopService();
            } else {
              await SmsService.instance.startService();
            }
          },
          child: AnimatedBuilder(
            animation: _pulse,
            builder: (ctx, _) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: (active ? const Color(0xFF00C896) : Colors.redAccent)
                    .withValues(alpha: 0.15 + _pulse.value * 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: active ? const Color(0xFF00C896) : Colors.redAccent,
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: active ? const Color(0xFF00C896) : Colors.redAccent,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    active ? 'SMS ON' : 'SMS OFF',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: active ? const Color(0xFF00C896) : Colors.redAccent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─── Summary Card ─────────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final List<Budget> budgets;
  const _SummaryCard({required this.budgets});

  @override
  Widget build(BuildContext context) {
    final totalAllocated = budgets.fold(0.0, (s, b) => s + b.allocatedAmount);
    final totalSpent     = budgets.fold(0.0, (s, b) => s + b.spentAmount);
    final daysInMonth    = DateUtils.getDaysInMonth(
        DateTime.now().year, DateTime.now().month);
    final daysElapsed    = DateTime.now().day;
    final dailyBurn      = daysElapsed > 0 ? totalSpent / daysElapsed : 0.0;
    final projectedSpend = dailyBurn * daysInMonth;
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
  const _BudgetCard({required this.budget});

  Color get _barColor {
    if (budget.usagePercent >= 1.0) return Colors.redAccent;
    if (budget.usagePercent >= 0.8) return Colors.orange;
    return const Color(0xFF00C896);
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00', 'en_US');
    return Container(
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
              Text(
                budget.categoryCode.replaceFirst(RegExp(r'^[A-Z]+-'), ''),
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              Text(
                '${(budget.usagePercent * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                    color: _barColor, fontWeight: FontWeight.w700, fontSize: 14),
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
        ],
      ),
    );
  }
}
