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
  late Future<_BudgetPageData> _dataFuture;

  @override
  void initState() {
    super.initState();
    _dataFuture = _loadData();
  }

  Future<_BudgetPageData> _loadData() async {
    final user = supabase.auth.currentUser!;
    final profile = await supabase
        .from('users')
        .select('household_id, role')
        .eq('id', user.id)
        .single();

    final hid = profile['household_id'] as String;
    final role = profile['role'] as String? ?? 'member';
    final month = DateFormat('yyyy-MM-01').format(DateTime.now());

    final budgetsRaw = await supabase
        .from('budgets')
        .select()
        .eq('household_id', hid)
        .eq('month', month);

    final codesRaw = await supabase
        .from('cost_control_codes')
        .select('code, category')
        .order('code');

    return _BudgetPageData(
      householdId: hid,
      isAdmin: role == 'admin',
      month: month,
      budgets: (budgetsRaw as List).map((r) => Budget.fromMap(r)).toList(),
      allCodes: (codesRaw as List)
          .map<Map<String, String>>((r) => {
                'code': r['code'] as String,
                'category': r['category'] as String,
              })
          .toList(),
    );
  }

  Future<void> _editBudget(
    _BudgetPageData data,
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
        'month': data.month,
        'category_code': categoryCode,
        'allocated_amount': amount,
        'spent_amount': 0,
      });
    }
    setState(() => _dataFuture = _loadData());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Budget Allocations')),
      body: FutureBuilder<_BudgetPageData>(
        future: _dataFuture,
        builder: (ctx, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snap.data!;
          final fmt  = NumberFormat('#,##0.00', 'en_US');

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: data.allCodes.length,
            itemBuilder: (ctx, i) {
              final code     = data.allCodes[i]['code'] as String;
              final category = data.allCodes[i]['category'] as String;
              final existing = data.budgets.where((b) => b.categoryCode == code).firstOrNull;

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
                    if (data.isAdmin)
                      IconButton(
                        icon: const Icon(Icons.edit_outlined,
                            color: Color(0xFF8B949E)),
                        onPressed: () => _editBudget(data, existing, code),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _BudgetPageData {
  final String householdId;
  final bool isAdmin;
  final String month;
  final List<Budget> budgets;
  final List<Map<String, String>> allCodes;

  _BudgetPageData({
    required this.householdId,
    required this.isAdmin,
    required this.month,
    required this.budgets,
    required this.allCodes,
  });
}
