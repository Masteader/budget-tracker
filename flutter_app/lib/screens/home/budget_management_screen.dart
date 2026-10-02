/// Budget management screen — edit monthly allocations per category.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../main.dart';
import '../../models/models.dart';

class BudgetManagementScreen extends StatefulWidget {
  const BudgetManagementScreen({super.key});

  @override
  State<BudgetManagementScreen> createState() =>
      _BudgetManagementScreenState();
}

class _BudgetManagementScreenState extends State<BudgetManagementScreen> {
  DateTime _selectedDate = DateTime.now();
  late Future<_BudgetStaticData> _staticFuture;
  bool _isCopying = false;

  @override
  void initState() {
    super.initState();
    _staticFuture = _loadStaticData();
  }

  Future<_BudgetStaticData> _loadStaticData() async {
    final user = supabase.auth.currentUser!;
    final profile = await supabase
        .from('users')
        .select('household_id, role')
        .eq('id', user.id)
        .single();

    final hid = profile['household_id'] as String;
    final role = profile['role'] as String? ?? 'member';

    final codesRaw = await supabase
        .from('cost_control_codes')
        .select('code, category')
        .order('code');

    return _BudgetStaticData(
      householdId: hid,
      isAdmin: role == 'admin',
      allCodes: (codesRaw as List)
          .map<Map<String, String>>((r) => {
                'code': r['code'] as String,
                'category': r['category'] as String,
              })
          .toList(),
    );
  }

  String get _currentMonthStr => DateFormat('yyyy-MM-01').format(_selectedDate);

  Future<void> _copyFromPreviousMonth(String householdId) async {
    setState(() => _isCopying = true);
    try {
      final prevDate = DateTime(_selectedDate.year, _selectedDate.month - 1, 1);
      final prevMonthStr = DateFormat('yyyy-MM-01').format(prevDate);

      final prevBudgets = await supabase
          .from('budgets')
          .select('category_code, allocated_amount')
          .eq('household_id', householdId)
          .eq('month', prevMonthStr);

      if (prevBudgets.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No allocations found in ${DateFormat('MMMM yyyy').format(prevDate)} to copy.')),
          );
        }
        return;
      }

      final newEntries = (prevBudgets as List).map((b) => {
        'household_id': householdId,
        'month': _currentMonthStr,
        'category_code': b['category_code'],
        'allocated_amount': b['allocated_amount'],
        'spent_amount': 0.0,
      }).toList();

      await supabase.from('budgets').insert(newEntries);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Copied ${newEntries.length} allocations from ${DateFormat('MMMM yyyy').format(prevDate)}!'),
            backgroundColor: const Color(0xFF00C896),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error copying allocations: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCopying = false);
      }
    }
  }

  Future<void> _editBudget(
    _BudgetStaticData data,
    Budget? existing,
    String categoryCode,
  ) async {
    final ctrl = TextEditingController(
      text: existing?.allocatedAmount.toStringAsFixed(2) ?? '',
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        title: Text('Set budget: $categoryCode'),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            hintText: 'Amount (SAR)',
            prefixText: 'SAR ',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save')),
        ],
      ),
    );

    if (confirmed != true) return;
    final amount = double.tryParse(ctrl.text);
    if (amount == null || amount < 0) return;

    if (existing != null) {
      await supabase
          .from('budgets')
          .update({'allocated_amount': amount})
          .eq('id', existing.id);
    } else {
      await supabase.from('budgets').insert({
        'household_id': data.householdId,
        'month': _currentMonthStr,
        'category_code': categoryCode,
        'allocated_amount': amount,
        'spent_amount': 0,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00', 'en_US');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Budget Allocations'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: const Color(0xFF0D1117),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left_rounded, color: Colors.white70),
                  onPressed: () {
                    setState(() {
                      _selectedDate = DateTime(_selectedDate.year, _selectedDate.month - 1, 1);
                    });
                  },
                ),
                Text(
                  DateFormat('MMMM yyyy').format(_selectedDate),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right_rounded, color: Colors.white70),
                  onPressed: () {
                    setState(() {
                      _selectedDate = DateTime(_selectedDate.year, _selectedDate.month + 1, 1);
                    });
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      body: FutureBuilder<_BudgetStaticData>(
        future: _staticFuture,
        builder: (ctx, staticSnap) {
          if (!staticSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final staticData = staticSnap.data!;

          return StreamBuilder<List<Map<String, dynamic>>>(
            stream: supabase
                .from('budgets')
                .stream(primaryKey: ['id'])
                .eq('household_id', staticData.householdId),
            builder: (ctx, budgetSnap) {
              final budgets = (budgetSnap.data ?? [])
                  .map(Budget.fromMap)
                  .where((b) => b.month == _currentMonthStr)
                  .toList();

              final totalAllocated = budgets.fold<double>(0.0, (sum, b) => sum + b.allocatedAmount);

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: staticData.allCodes.length + 1,
                itemBuilder: (ctx, i) {
                  if (i == 0) {
                    // Header card
                    if (budgets.isEmpty) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF161B22),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.info_outline, color: Colors.orange, size: 20),
                                SizedBox(width: 8),
                                Text(
                                  'No allocations set for this month',
                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'You can copy the previous month’s allocation limits with 1 tap or tap edit on any category below.',
                              style: TextStyle(color: Color(0xFF8B949E), fontSize: 12),
                            ),
                            const SizedBox(height: 12),
                            if (staticData.isAdmin)
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: _isCopying ? null : () => _copyFromPreviousMonth(staticData.householdId),
                                  icon: _isCopying
                                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                                      : const Icon(Icons.copy_rounded, size: 16),
                                  label: Text(_isCopying ? 'Copying...' : 'Copy Previous Month Allocations'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF00C896),
                                    foregroundColor: Colors.black,
                                    textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    }

                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF161B22),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF30363D)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Total Allocated (${DateFormat('MMM yyyy').format(_selectedDate)})',
                                style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'SAR ${fmt.format(totalAllocated)}',
                                style: const TextStyle(
                                  color: Color(0xFF00C896),
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            '${budgets.length}/${staticData.allCodes.length} Set',
                            style: const TextStyle(color: Color(0xFF8B949E), fontSize: 13),
                          ),
                        ],
                      ),
                    );
                  }

                  final code = staticData.allCodes[i - 1]['code'] as String;
                  final category = staticData.allCodes[i - 1]['category'] as String;
                  final existing =
                      budgets.where((b) => b.categoryCode == code).firstOrNull;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF161B22),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF30363D)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(category,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600, fontSize: 14)),
                              const SizedBox(height: 3),
                              Text(
                                existing != null
                                    ? 'SAR ${fmt.format(existing.allocatedAmount)}'
                                    : 'Not set',
                                style: TextStyle(
                                  color: existing != null
                                      ? const Color(0xFF00C896)
                                      : const Color(0xFF8B949E),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (staticData.isAdmin)
                          IconButton(
                            icon: const Icon(Icons.edit_outlined,
                                color: Color(0xFF8B949E)),
                            onPressed: () => _editBudget(staticData, existing, code),
                          ),
                      ],
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

class _BudgetStaticData {
  final String householdId;
  final bool isAdmin;
  final List<Map<String, String>> allCodes;

  _BudgetStaticData({
    required this.householdId,
    required this.isAdmin,
    required this.allCodes,
  });
}
