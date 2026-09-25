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
  late Future<_BudgetStaticData> _staticFuture;

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
    final month = DateFormat('yyyy-MM-01').format(DateTime.now());

    final codesRaw = await supabase
        .from('cost_control_codes')
        .select('code, category')
        .order('code');

    return _BudgetStaticData(
      householdId: hid,
      isAdmin: role == 'admin',
      month: month,
      allCodes: (codesRaw as List)
          .map<Map<String, String>>((r) => {
                'code': r['code'] as String,
                'category': r['category'] as String,
              })
          .toList(),
    );
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
        'month': data.month,
        'category_code': categoryCode,
        'allocated_amount': amount,
        'spent_amount': 0,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Budget Allocations')),
      body: FutureBuilder<_BudgetStaticData>(
        future: _staticFuture,
        builder: (ctx, staticSnap) {
          if (!staticSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final staticData = staticSnap.data!;
          final fmt = NumberFormat('#,##0.00', 'en_US');

          return StreamBuilder<List<Map<String, dynamic>>>(
            stream: supabase
                .from('budgets')
                .stream(primaryKey: ['id'])
                .eq('household_id', staticData.householdId),
            builder: (ctx, budgetSnap) {
              final budgets = (budgetSnap.data ?? [])
                  .map(Budget.fromMap)
                  .where((b) => b.month == staticData.month)
                  .toList();

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: staticData.allCodes.length,
                itemBuilder: (ctx, i) {
                  final code = staticData.allCodes[i]['code'] as String;
                  final category = staticData.allCodes[i]['category'] as String;
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
}

class _BudgetStaticData {
  final String householdId;
  final bool isAdmin;
  final String month;
  final List<Map<String, String>> allCodes;

  _BudgetStaticData({
    required this.householdId,
    required this.isAdmin,
    required this.month,
    required this.allCodes,
  });
}
