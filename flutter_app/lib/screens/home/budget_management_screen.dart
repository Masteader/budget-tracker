/// Budget management screen — edit monthly allocations per category.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../main.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../widgets/sub_budget_breakdown_sheet.dart';

class BudgetManagementScreen extends StatefulWidget {
  const BudgetManagementScreen({super.key});

  @override
  State<BudgetManagementScreen> createState() =>
      _BudgetManagementScreenState();
}

class _BudgetManagementScreenState extends State<BudgetManagementScreen> {
  final DateTime _selectedDate = DateTime.now();
  List<SalaryCycleInfo> _cycles = [];

  int _currentCycleIndex = 0;
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

    _fetchCycles(hid);

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
    final now = _selectedDate;
    if (now.day >= 27) {
      final next = DateTime(now.year, now.month + 1, 1);
      return DateFormat('yyyy-MM').format(next);
    }
    return DateFormat('yyyy-MM').format(now);
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
        'cycle_key': _currentCycleKey,
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

  Future<void> _showAddCategoryDialog(_BudgetStaticData staticData) async {
    final nameCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    final amountCtrl = TextEditingController(text: '500');
    bool isFlexible = true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF161B22),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Add New Budget Category', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Category Name',
                    hintText: 'e.g. Pets & Veterinary, Gym, Car Care',
                  ),
                  onChanged: (val) {
                    if (codeCtrl.text.isEmpty || codeCtrl.text.startsWith('OPEX-')) {
                      final slug = val.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();
                      codeCtrl.text = slug.isNotEmpty ? 'OPEX-$slug' : '';
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: codeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Cost Code',
                    hintText: 'e.g. OPEX-PETS',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Monthly Allocation',
                    prefixText: 'SAR ',
                    hintText: '500.00',
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Flexible Pool', style: TextStyle(color: Colors.white, fontSize: 13)),
                  subtitle: const Text('Allow automatic reallocations if another category exceeds budget', style: TextStyle(color: Color(0xFF8B949E), fontSize: 11)),
                  value: isFlexible,
                  activeThumbColor: const Color(0xFF00C896),
                  onChanged: (v) => setDialogState(() => isFlexible = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF8B949E))),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00C896), foregroundColor: Colors.black),
              child: const Text('Create Category', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;
    final name = nameCtrl.text.trim();
    var code = codeCtrl.text.trim().toUpperCase();
    if (!code.startsWith('OPEX-')) code = 'OPEX-$code';
    final amount = double.tryParse(amountCtrl.text) ?? 0.0;

    if (name.isEmpty || code.isEmpty) return;

    try {
      final res = await ApiService.instance.addBudgetCategory(
        householdId: staticData.householdId,
        code: code,
        category: name,
        allocatedAmount: amount,
        isFlexible: isFlexible,
        keywords: [name.toLowerCase(), code.toLowerCase()],
      );

      if (res['status'] == 'success') {
        setState(() {
          _staticFuture = _loadStaticData();
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Added category "$name" with SAR $amount budget!'),
              backgroundColor: const Color(0xFF00C896),
            ),
          );
        }
      } else {
        throw Exception(res['message'] ?? 'Failed to add category');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add category: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _archiveCategory(
    _BudgetStaticData staticData,
    String categoryCode,
    String categoryName,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Remove $categoryName?', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'This will remove $categoryName from your active budget list for this household. Historic transactions remain preserved.',
          style: const TextStyle(color: Color(0xFF8B949E), fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF8B949E))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Remove Category', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final res = await ApiService.instance.archiveBudgetCategory(
        staticData.householdId,
        categoryCode,
      );

      if (res['status'] == 'success') {
        setState(() {
          _staticFuture = _loadStaticData();
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Category "$categoryName" removed from active budgets.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to remove: $e'), backgroundColor: Colors.redAccent),
        );
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
          .update({
            'allocated_amount': amount,
            'is_active': true,
            'cycle_key': _currentCycleKey,
          })
          .eq('id', existing.id);
    } else {
      await supabase.from('budgets').insert({
        'household_id': data.householdId,
        'month': _currentMonthStr,
        'cycle_key': _currentCycleKey,
        'category_code': categoryCode,
        'allocated_amount': amount,
        'spent_amount': 0,
        'is_active': true,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00', 'en_US');
    final cycle = _selectedCycle;
    final headerTitle = cycle?.monthName ?? DateFormat('MMMM yyyy').format(_selectedDate);
    final headerSub = cycle != null
        ? '${cycle.cycleStart.substring(5)} - ${cycle.cycleEnd.substring(5)}'
        : 'Payday 27th Cycle';

    return FutureBuilder<_BudgetStaticData>(
      future: _staticFuture,
      builder: (ctx, staticSnap) {
        if (!staticSnap.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final staticData = staticSnap.data!;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Budget Allocations'),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(56),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: const Color(0xFF0D1117),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left_rounded, color: Colors.white70),
                      onPressed: (_cycles.isNotEmpty && _currentCycleIndex < _cycles.length - 1)
                          ? () => setState(() => _currentCycleIndex++)
                          : null,
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          headerTitle,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                        ),
                        Text(
                          headerSub,
                          style: const TextStyle(color: Color(0xFF8B949E), fontSize: 11),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right_rounded, color: Colors.white70),
                      onPressed: (_cycles.isNotEmpty && _currentCycleIndex > 0)
                          ? () => setState(() => _currentCycleIndex--)
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
          floatingActionButton: staticData.isAdmin
              ? FloatingActionButton.extended(
                  onPressed: () => _showAddCategoryDialog(staticData),
                  icon: const Icon(Icons.add_rounded, color: Colors.black),
                  label: const Text('Add Category', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                  backgroundColor: const Color(0xFF00C896),
                )
              : null,
          body: StreamBuilder<List<Map<String, dynamic>>>(
            stream: supabase
                .from('budgets')
                .stream(primaryKey: ['id'])
                .eq('household_id', staticData.householdId),
            builder: (ctx, budgetSnap) {
              final budgets = (budgetSnap.data ?? [])
                  .map(Budget.fromMap)
                  .where((b) {
                    if (!b.isActive) return false;
                    final key = _currentCycleKey;
                    if (b.cycleKey != null && b.cycleKey!.isNotEmpty) {
                      return b.cycleKey == key;
                    }
                    return b.month.startsWith(key) || b.month == _currentMonthStr;
                  })
                  .toList();

              final totalAllocated = budgets.fold<double>(0.0, (sum, b) => sum + b.allocatedAmount);

              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                itemCount: staticData.allCodes.length + 1,
                itemBuilder: (ctx, i) {
                  if (i == 0) {
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
                                  'No allocations set for this cycle',
                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Budgets automatically roll over on the 27th payday. You can copy previous month allocations or add custom categories below.',
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
                                  label: Text(_isCopying ? 'Copying...' : 'Copy Previous Cycle Allocations'),
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
                                'Total Allocated ($headerTitle)',
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
                          Builder(
                            builder: (context) {
                              final setCodes = budgets.where((b) => b.isActive).map((b) => b.categoryCode).toSet();
                              return Text(
                                '${setCodes.length}/${staticData.allCodes.length} Set',
                                style: const TextStyle(color: Color(0xFF8B949E), fontSize: 13),
                              );
                            },
                          ),
                        ],
                      ),
                  );
                }

                final code = staticData.allCodes[i - 1]['code'] as String;
                final category = staticData.allCodes[i - 1]['category'] as String;
                final existing =
                    budgets.where((b) => b.categoryCode == code).firstOrNull;
                final subCategories = kSubCategoriesByParent[code] ?? const <String>[];

                return InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {
                    SubBudgetBreakdownSheet.show(
                      context,
                      householdId: staticData.householdId,
                      categoryCode: code,
                      cycleKey: _currentCycleKey,
                      allocatedAmount: existing?.allocatedAmount ?? 0.0,
                      previousCycleDelta: existing?.previousCycleDelta ?? 0.0,
                    );
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF161B22),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF30363D)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
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
                                      fontWeight: existing != null ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (staticData.isAdmin) ...[
                              IconButton(
                                icon: const Icon(Icons.edit_outlined,
                                    color: Color(0xFF8B949E)),
                                tooltip: 'Edit Allocation',
                                onPressed: () => _editBudget(staticData, existing, code),
                              ),
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline,
                                    color: Colors.redAccent, size: 20),
                                tooltip: 'Remove Category',
                                onPressed: () => _archiveCategory(staticData, code, category),
                              ),
                            ],
                            const Icon(Icons.chevron_right, size: 18, color: Color(0xFF8B949E)),
                          ],
                        ),
                        if (subCategories.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: subCategories.map((sub) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFF21262D),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFF30363D)),
                              ),
                              child: Text(
                                sub,
                                style: const TextStyle(
                                  color: Color(0xFF8B949E),
                                  fontSize: 11,
                                ),
                              ),
                            )).toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      );
    },
  );
}
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
