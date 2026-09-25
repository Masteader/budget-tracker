/// Main dashboard — budget progress bars, burn rate, SMS service status.
/// Uses Supabase Realtime streams to update instantly when new data arrives.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../main.dart';
import '../../models/models.dart';
import '../../services/sms_service.dart';
import '../chat/chat_entry_screen.dart';
import '../scanner/receipt_scanner_sheet.dart';
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
              'Add Transaction',
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
                title: const Text('AI Conversational Chat', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
                subtitle: const Text('Say what you bought (e.g. Dunkin 19 SAR latte)', style: TextStyle(color: Color(0xFF8B949E), fontSize: 12)),
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
            const SizedBox(height: 8),
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
                title: const Text('Scan Paper Invoice / Receipt', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
                subtitle: const Text('Take a camera photo to extract itemized breakdown', style: TextStyle(color: Color(0xFF8B949E), fontSize: 12)),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      const _BudgetDashboard(),
      const TransactionFeedScreen(),
      const BudgetManagementScreen(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: screens,
      ),
      floatingActionButton: FloatingActionButton.extended(
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
        indicatorColor: const Color(0xFF00C896).withOpacity(0.2),
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
                          child: _SummaryCard(budgets: budgetSnap.data!
                              .map(Budget.fromMap)
                              .where((b) => b.month == _currentMonth)
                              .toList()),
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
  bool _active = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
        vsync: this, duration: const Duration(seconds: 1))
      ..repeat(reverse: true);
    _active = SmsService.instance.isListening;
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        if (_active) {
          await SmsService.instance.stopService();
        } else {
          await SmsService.instance.startService();
        }
        setState(() => _active = SmsService.instance.isListening);
      },
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (ctx, _) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: (_active ? const Color(0xFF00C896) : Colors.redAccent)
                .withOpacity(0.15 + _pulse.value * 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _active ? const Color(0xFF00C896) : Colors.redAccent,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6, height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _active ? const Color(0xFF00C896) : Colors.redAccent,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                _active ? 'SMS ON' : 'SMS OFF',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _active ? const Color(0xFF00C896) : Colors.redAccent,
                ),
              ),
            ],
          ),
        ),
      ),
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
                color: Colors.red.withOpacity(0.2),
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
