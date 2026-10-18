/// Budget management screen — edit monthly allocations per category.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../main.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../widgets/sub_budget_allocation_dialog.dart';
import '../../widgets/sub_budget_breakdown_sheet.dart';
import '../../widgets/categories/category_library_sheet.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/app_shimmer.dart';
import '../../l10n/app_localizations.dart';
import '../../models/account.dart';
import '../../services/account_service.dart';
import '../../widgets/budgets/link_account_sheet.dart';
import '../../widgets/accounts/account_transfer_sheet.dart';
import '../accounts/accounts_overview_screen.dart';
import '../../theme/app_themes.dart';

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

    final catData = await ApiService.instance.fetchHouseholdCategories(hid);
    final activeFromApi = catData['active'] ?? [];
    final activeCodes = <Map<String, String>>[];

    if (activeFromApi.isNotEmpty) {
      for (final cat in activeFromApi) {
        if (!cat.name.toLowerCase().contains('test') && !cat.code.toLowerCase().contains('test')) {
          activeCodes.add({
            'code': cat.code,
            'category': cat.name,
          });
        }
      }
    } else {
      final codesRaw = await supabase
          .from('cost_control_codes')
          .select('code, category')
          .order('code');

      final activeBudgets = await supabase
          .from('budgets')
          .select('category_code')
          .eq('household_id', hid)
          .eq('is_active', true);
      final activeBudgetCodes = (activeBudgets as List)
          .map((r) => r['category_code'] as String)
          .toSet();

      final inactiveBudgets = await supabase
          .from('budgets')
          .select('category_code')
          .eq('household_id', hid)
          .eq('is_active', false);
      final inactiveCodes = (inactiveBudgets as List)
          .map((r) => r['category_code'] as String)
          .toSet();
      inactiveCodes.removeAll(activeBudgetCodes);

      for (final r in (codesRaw as List)) {
        final code = r['code'] as String;
        final name = r['category'] as String;
        if (!inactiveCodes.contains(code) &&
            !code.toLowerCase().contains('test') &&
            !name.toLowerCase().contains('test')) {
          activeCodes.add({
            'code': code,
            'category': name,
          });
        }
      }
    }

    double income = 0.0;
    try {
      final hh = await supabase
          .from('households')
          .select('monthly_income')
          .eq('id', hid)
          .maybeSingle();
      if (hh != null && hh['monthly_income'] != null) {
        income = (hh['monthly_income'] as num).toDouble();
      }
    } catch (_) {}
    if (income <= 0) {
      try {
        income = await ApiService.instance.getHouseholdIncome(hid);
      } catch (_) {}
    }

    List<Account> accounts = [];
    try {
      accounts = await AccountService.instance.getAccounts(hid);
    } catch (_) {}

    return _BudgetStaticData(
      householdId: hid,
      isAdmin: role == 'admin',
      allCodes: activeCodes,
      monthlyIncome: income,
      accounts: accounts,
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
          .select('category_code, allocated_amount, account_id, remaining_amount, spent_amount, sub_allocations')
          .eq('household_id', householdId)
          .eq('month', prevMonthStr);

      if (prevBudgets.isEmpty) {
        if (mounted) {
          AppSnackBar.showInfo(
            context,
            'No allocations found in ${DateFormat('MMMM yyyy').format(prevDate)} to copy.',
            title: 'No Prior Allocations',
          );
        }
        return;
      }

      double totalUnspent = 0.0;
      for (final b in (prevBudgets as List)) {
        final alloc = (b['allocated_amount'] as num?)?.toDouble() ?? 0.0;
        final spent = (b['spent_amount'] as num?)?.toDouble() ?? 0.0;
        final rem = alloc - spent;
        if (rem > 0) totalUnspent += rem;
      }

      bool rolloverToCushion = true;
      if (totalUnspent > 0 && mounted) {
        final choice = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: context.cardBg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                const Icon(Icons.savings_outlined, color: Color(0xFF00E5BF), size: 22),
                const SizedBox(width: 8),
                Text('Unspent Funds: SAR ${totalUnspent.toStringAsFixed(2)}', style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            content: Text(
              'You have SAR ${totalUnspent.toStringAsFixed(2)} leftover from the previous cycle.\n\n'
              '• Option A: Roll over unspent funds into this cycle\'s category cushions.\n'
              '• Option C: Sweep leftover funds into savings and start with clean target budgets.',
              style: TextStyle(color: context.textSecondary, fontSize: 13),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Option C: Sweep to Savings'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E5BF), foregroundColor: Colors.black),
                child: const Text('Option A: Roll Over Cushion', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
        rolloverToCushion = choice ?? true;
      }

      final newEntries = (prevBudgets as List).map((b) {
        final alloc = (b['allocated_amount'] as num?)?.toDouble() ?? 0.0;
        final spent = (b['spent_amount'] as num?)?.toDouble() ?? 0.0;
        final rem = alloc - spent;
        final delta = (rolloverToCushion && rem > 0) ? rem : 0.0;

        return {
          'household_id': householdId,
          'month': _currentMonthStr,
          'cycle_key': _currentCycleKey,
          'category_code': b['category_code'],
          'allocated_amount': b['allocated_amount'],
          'account_id': b['account_id'],
          'sub_allocations': b['sub_allocations'] ?? {},
          'previous_cycle_delta': delta,
          'spent_amount': 0.0,
          'is_active': true,
        };
      }).toList();

      await supabase.from('budgets').insert(newEntries);

      if (mounted) {
        AppSnackBar.showSuccess(
          context,
          'Copied ${newEntries.length} allocations with mapped accounts from ${DateFormat('MMMM yyyy').format(prevDate)}!',
          title: 'Budget Copied',
        );
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.showError(
          context,
          'Error copying allocations: $e',
          title: 'Copy Failed',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCopying = false);
      }
    }
  }

  Future<void> _showAddCategoryDialog(_BudgetStaticData staticData) async {
    int activeTab = 0; // 0: Category, 1: Sub-Category
    final catNameCtrl = TextEditingController();
    final catAmountCtrl = TextEditingController(text: '500');
    bool isFlexible = true;

    String selectedParentCode = staticData.allCodes.isNotEmpty ? staticData.allCodes.first['code']! : '';
    final subNameCtrl = TextEditingController();
    final subAmountCtrl = TextEditingController(text: '150');
    bool isSubmitting = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: context.cardBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          contentPadding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                activeTab == 0 ? context.tr('add_category') : context.tr('add_sub_category'),
                style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 12),
              // Clean Segmented toggle
              Container(
                decoration: BoxDecoration(
                  color: context.inputBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: context.borderColor),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setDialogState(() => activeTab = 0),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: activeTab == 0 ? const Color(0xFF00C896) : Colors.transparent,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Center(
                            child: Text(
                              context.tr('main_category'),
                              style: TextStyle(
                                color: activeTab == 0 ? Colors.black : context.textSecondary,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setDialogState(() => activeTab = 1),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: activeTab == 1 ? const Color(0xFF00C896) : Colors.transparent,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Center(
                            child: Text(
                              context.tr('sub_category'),
                              style: TextStyle(
                                color: activeTab == 1 ? Colors.black : context.textSecondary,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: activeTab == 0
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: catNameCtrl,
                        style: TextStyle(color: context.textPrimary),
                        decoration: InputDecoration(
                          labelText: context.tr('category_name'),
                          hintText: 'e.g. Pet Care, Fitness & Gym',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: catAmountCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: TextStyle(color: context.textPrimary),
                        decoration: InputDecoration(
                          labelText: context.tr('monthly_allocation'),
                          prefixText: 'SAR ',
                          hintText: '500.00',
                        ),
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(context.tr('flexible_pool'), style: TextStyle(color: context.textPrimary, fontSize: 13)),
                        subtitle: Text(context.tr('flexible_pool_desc'), style: TextStyle(color: context.textSecondary, fontSize: 11)),
                        value: isFlexible,
                        activeThumbColor: const Color(0xFF00C896),
                        onChanged: (v) => setDialogState(() => isFlexible = v),
                      ),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DropdownButtonFormField<String>(
                        dropdownColor: context.cardBg,
                        initialValue: selectedParentCode.isNotEmpty ? selectedParentCode : null,
                        style: TextStyle(color: context.textPrimary),
                        decoration: InputDecoration(
                          labelText: context.tr('parent_category'),
                        ),
                        items: staticData.allCodes.map((c) {
                          return DropdownMenuItem<String>(
                            value: c['code'],
                            child: Text(context.trCat(c['code']!), style: TextStyle(color: context.textPrimary)),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() => selectedParentCode = val);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: subNameCtrl,
                        style: TextStyle(color: context.textPrimary),
                        decoration: InputDecoration(
                          labelText: context.tr('sub_category_name'),
                          hintText: 'e.g. Specialty Coffee, Dog Food',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: subAmountCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: TextStyle(color: context.textPrimary),
                        decoration: InputDecoration(
                          labelText: context.tr('initial_allocation'),
                          prefixText: 'SAR ',
                          hintText: '150.00',
                        ),
                      ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(context.tr('cancel'), style: TextStyle(color: context.textSecondary)),
            ),
            ElevatedButton(
              onPressed: isSubmitting
                  ? null
                  : () async {
                      if (activeTab == 0) {
                        final name = catNameCtrl.text.trim();
                        final amount = double.tryParse(catAmountCtrl.text) ?? 0.0;
                        if (name.isEmpty) return;

                        setDialogState(() => isSubmitting = true);
                        final slug = name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();
                        final code = 'OPEX-$slug';

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
                            if (ctx.mounted) Navigator.pop(ctx);
                            setState(() {
                              _staticFuture = _loadStaticData();
                            });
                            if (mounted) {
                              AppSnackBar.showSuccess(
                                context,
                                'Added category "$name" (SAR ${amount.toStringAsFixed(2)})!',
                                title: 'Category Created',
                              );
                            }
                          } else {
                            throw Exception(res['message'] ?? 'Failed to add category');
                          }
                        } catch (e) {
                          setDialogState(() => isSubmitting = false);
                          if (mounted) {
                            AppSnackBar.showError(
                              context,
                              'Failed to add category: $e',
                              title: 'Add Failed',
                            );
                          }
                        }
                      } else {
                        final subName = subNameCtrl.text.trim();
                        final subAmount = double.tryParse(subAmountCtrl.text) ?? 0.0;
                        if (subName.isEmpty || selectedParentCode.isEmpty) return;

                        setDialogState(() => isSubmitting = true);
                        try {
                          final res = await ApiService.instance.addSubCategory(
                            householdId: staticData.householdId,
                            parentCode: selectedParentCode,
                            nameEn: subName,
                            allocatedAmount: subAmount,
                            cycleKey: _currentCycleKey,
                          );
                          if (res['status'] == 'success') {
                            if (ctx.mounted) Navigator.pop(ctx);
                            setState(() {
                              _staticFuture = _loadStaticData();
                            });
                            if (mounted) {
                              AppSnackBar.showSuccess(
                                context,
                                'Added sub-category "$subName" to budget!',
                                title: 'Sub-Category Added',
                              );
                            }
                          } else {
                            throw Exception(res['message'] ?? 'Failed to add sub-category');
                          }
                        } catch (e) {
                          setDialogState(() => isSubmitting = false);
                          if (mounted) {
                            AppSnackBar.showError(
                              context,
                              'Failed to add sub-category: $e',
                              title: 'Add Failed',
                            );
                          }
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00C896), foregroundColor: Colors.black),
              child: isSubmitting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : Text(activeTab == 0 ? 'Create Category' : 'Add Sub-Category', style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _archiveCategory(
    _BudgetStaticData staticData,
    String categoryCode,
    String categoryName,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('${context.tr('deactivate')} ${context.trCat(categoryCode)}?', style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold)),
        content: Text(
          'This will deactivate ${context.trCat(categoryCode)} and move it to your Category Library. Categories are never deleted, so your financial history remains safe and you can reactivate it at any time.',
          style: TextStyle(color: context.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('cancel'), style: TextStyle(color: context.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE3B341)),
            child: Text(context.tr('deactivate'), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
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
          staticData.allCodes.removeWhere((c) => c['code'] == categoryCode);
          _staticFuture = _loadStaticData();
        });
        if (mounted) {
          AppSnackBar.showSuccess(
            context,
            'Category "$categoryName" moved to Category Library (inactive).',
            title: 'Category Deactivated',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.showError(
          context,
          'Failed to deactivate category: $e',
          title: 'Deactivation Failed',
        );
      }
    }
  }

  Future<void> _editBudget(
    _BudgetStaticData data,
    Budget? existing,
    String categoryCode,
  ) async {
    final match = data.allCodes.firstWhere(
      (c) => c['code'] == categoryCode,
      orElse: () => {'category': categoryCode},
    );
    final catName = match['category'] ?? categoryCode;

    await SubBudgetAllocationDialog.show(
      context,
      householdId: data.householdId,
      categoryCode: categoryCode,
      categoryName: catName,
      existingBudget: existing,
      cycleKey: _currentCycleKey,
      onSaved: () {
        if (mounted) setState(() {});
      },
    );
  }

  Future<void> _openCategoryLibrary(_BudgetStaticData data) async {
    final catData = await ApiService.instance.fetchHouseholdCategories(data.householdId);
    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => CategoryLibrarySheet(
        activeCategories: catData['active'] ?? [],
        inactiveCategories: catData['inactive'] ?? [],
        onToggle: (cat, isActive) async {
          await ApiService.instance.toggleCategoryStatus(
            householdId: data.householdId,
            categoryCode: cat.code,
            isActive: isActive,
          );
          try {
            final existing = await supabase
                .from('budgets')
                .select('id')
                .eq('household_id', data.householdId)
                .eq('category_code', cat.code);
            if (existing.isEmpty && isActive) {
              await supabase.from('budgets').insert({
                'household_id': data.householdId,
                'category_code': cat.code,
                'allocated_amount': 0.0,
                'spent_amount': 0.0,
                'is_active': true,
                'month': _currentMonthStr,
                'cycle_key': _currentCycleKey.length > 7 ? _currentCycleKey.substring(0, 7) : _currentCycleKey,
              });
            } else {
              await supabase
                  .from('budgets')
                  .update({'is_active': isActive})
                  .eq('household_id', data.householdId)
                  .eq('category_code', cat.code);
            }
          } catch (_) {}
          if (mounted) {
            setState(() {
              _staticFuture = _loadStaticData();
            });
            AppSnackBar.showSuccess(
              context,
              isActive
                  ? 'Category "${cat.name}" activated.'
                  : 'Category "${cat.name}" deactivated.',
            );
          }
        },
        onAddCustom: () {
          Navigator.pop(ctx);
          _showAddCategoryDialog(data);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00', 'en_US');
    final cycle = _selectedCycle;
    final headerTitle = cycle?.monthName ?? DateFormat('MMMM yyyy').format(_selectedDate);
    final headerSub = cycle != null
        ? '${cycle.cycleStart.substring(5)} - ${cycle.cycleEnd.substring(5)}'
        : 'Active Salary Cycle';

    return FutureBuilder<_BudgetStaticData>(
      future: _staticFuture,
      builder: (ctx, staticSnap) {
        if (!staticSnap.hasData) {
          return Scaffold(
            backgroundColor: context.scaffoldBg,
            appBar: AppBar(
              title: const Text('Budget Allocations'),
            ),
            body: Padding(
              padding: const EdgeInsets.all(16.0),
              child: AppShimmer.listItems(count: 5),
            ),
          );
        }
        final staticData = staticSnap.data!;

        return Scaffold(
          appBar: AppBar(
            title: Text(context.tr('budget_allocations')),
            actions: [
              IconButton(
                icon: const Icon(Icons.account_balance_wallet_outlined, color: Color(0xFF00E5BF)),
                tooltip: 'Accounts & Balances',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AccountsOverviewScreen(householdId: staticData.householdId),
                    ),
                  ).then((_) {
                    setState(() {
                      _staticFuture = _loadStaticData();
                    });
                  });
                },
              ),
              IconButton(
                icon: const Icon(Icons.category_outlined, color: Color(0xFF00C896)),
                tooltip: context.tr('category_library'),
                onPressed: () => _openCategoryLibrary(staticData),
              ),
              if (staticData.isAdmin)
                IconButton(
                  icon: const Icon(Icons.add_circle_outline_rounded, color: Color(0xFF00C896)),
                  tooltip: 'Add Category or Sub-Category',
                  onPressed: () => _showAddCategoryDialog(staticData),
                ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(56),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: context.scaffoldBg,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: Icon(Icons.chevron_left_rounded, color: context.textPrimary.withValues(alpha: 0.7)),
                      onPressed: (_cycles.isNotEmpty && _currentCycleIndex < _cycles.length - 1)
                          ? () => setState(() => _currentCycleIndex++)
                          : null,
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          headerTitle,
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: context.textPrimary),
                        ),
                        Text(
                          headerSub,
                          style: TextStyle(color: context.textSecondary, fontSize: 11),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: Icon(Icons.chevron_right_rounded, color: context.textSecondary),
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
                  label: Text(context.tr('add_category'), style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
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
                          color: context.cardBg,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.info_outline, color: Colors.orange, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  context.tr('no_allocations_set'),
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              context.tr('budgets_auto_rollover_desc'),
                              style: TextStyle(color: context.textSecondary, fontSize: 12),
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
                                  label: Text(_isCopying ? 'Copying...' : context.tr('copy_previous')),
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

                    final income = staticData.monthlyIncome;
                    final hasIncome = income > 0;
                    final savingsReserve = hasIncome ? (income - totalAllocated) : 0.0;
                    final isOverAllocated = hasIncome && savingsReserve < 0;

                    // Calculate any account deficits
                    Account? deficitAccount;
                    double deficitAmount = 0.0;
                    if (staticData.accounts.isNotEmpty) {
                      final Map<String, double> committedByAccount = {};
                      for (final b in budgets) {
                        if (b.accountId != null && b.accountId!.isNotEmpty) {
                          committedByAccount[b.accountId!] = (committedByAccount[b.accountId!] ?? 0.0) + b.allocatedAmount;
                        }
                      }
                      for (final entry in committedByAccount.entries) {
                        final acc = staticData.accounts.where((a) => a.id == entry.key).firstOrNull;
                        if (acc != null && acc.balance < entry.value) {
                          deficitAccount = acc;
                          deficitAmount = entry.value - acc.balance;
                          break;
                        }
                      }
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (deficitAccount != null)
                          Container(
                            margin: const EdgeInsets.only(bottom: 14),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 22),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '⚠️ ${deficitAccount.name} Deficit: -${deficitAccount.currency} ${fmt.format(deficitAmount)}',
                                        style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Budgets linked to this account exceed its current balance.',
                                        style: TextStyle(color: context.textSecondary, fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ),
                                ElevatedButton(
                                  onPressed: () {
                                    AccountTransferSheet.show(
                                      context,
                                      householdId: staticData.householdId,
                                      prefilledToAccountId: deficitAccount!.id,
                                      prefilledAmount: deficitAmount,
                                      onTransferSuccess: () => setState(() {
                                        _staticFuture = _loadStaticData();
                                      }),
                                    );
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.redAccent,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    visualDensity: VisualDensity.compact,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  child: const Text('Fix', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                ),
                              ],
                            ),
                          ),
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: context.cardBg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isOverAllocated
                              ? Colors.redAccent.withValues(alpha: 0.6)
                              : context.borderColor,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${context.tr('total_allocated')} ($headerTitle)',
                                    style: TextStyle(color: context.textSecondary, fontSize: 12),
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
                                    '${setCodes.length}/${staticData.allCodes.length} ${context.tr('set')}',
                                    style: TextStyle(color: context.textSecondary, fontSize: 13),
                                  );
                                },
                              ),
                            ],
                          ),
                          if (hasIncome) ...[
                            const SizedBox(height: 12),
                            Divider(color: context.borderColor, height: 1),
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      isOverAllocated ? Icons.warning_amber_rounded : Icons.savings_rounded,
                                      size: 16,
                                      color: isOverAllocated ? Colors.redAccent : const Color(0xFF00C896),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      isOverAllocated ? context.tr('overallocated_by') : context.tr('savings_reserve_label'),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isOverAllocated ? Colors.redAccent : context.textSecondary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  isOverAllocated
                                      ? '-SAR ${fmt.format(-savingsReserve)}'
                                      : '+SAR ${fmt.format(savingsReserve)}',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: isOverAllocated ? Colors.redAccent : const Color(0xFF00C896),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isOverAllocated
                                  ? '${context.tr('allocations_exceed_salary')} ${fmt.format(income)}.'
                                  : context.tr('protected_buffer_desc'),
                              style: TextStyle(
                                fontSize: 11,
                                color: isOverAllocated
                                    ? Colors.redAccent.withValues(alpha: 0.8)
                                    : context.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                );
              }

                final code = staticData.allCodes[i - 1]['code'] as String;
                final category = staticData.allCodes[i - 1]['category'] as String;
                final existing =
                    budgets.where((b) => b.categoryCode == code).firstOrNull;
                final subCategories = kSubCategoriesByParent[code] ?? const <String>[];
                final mappedAccount = staticData.accounts
                    .where((a) => a.id == existing?.accountId)
                    .firstOrNull;

                return InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {
                    SubBudgetBreakdownSheet.show(
                      context,
                      householdId: staticData.householdId,
                      categoryCode: code,
                      cycleKey: _currentCycleKey,
                      allocatedAmount: existing?.allocatedAmount ?? 0.0,
                      spentAmount: existing?.spentAmount ?? 0.0,
                      previousCycleDelta: existing?.previousCycleDelta ?? 0.0,
                    );
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: context.cardBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: context.borderColor),
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
                                  Text(context.trCat(code),
                                      style: TextStyle(
                                          fontWeight: FontWeight.w600, fontSize: 14, color: context.textPrimary)),
                                  const SizedBox(height: 3),
                                  Row(
                                    children: [
                                      Text(
                                        existing != null
                                            ? 'SAR ${fmt.format(existing.allocatedAmount)}'
                                            : context.tr('not_set'),
                                        style: TextStyle(
                                          color: existing != null
                                              ? const Color(0xFF00C896)
                                              : context.textSecondary,
                                          fontSize: 13,
                                          fontWeight: existing != null ? FontWeight.bold : FontWeight.normal,
                                        ),
                                      ),
                                      if (existing != null && existing.spentAmount > 0) ...[
                                        const SizedBox(width: 8),
                                        Text(
                                          '• ${context.tr('spent')}: SAR ${fmt.format(existing.spentAmount)}',
                                          style: TextStyle(
                                            color: existing.spentAmount > existing.allocatedAmount && existing.allocatedAmount > 0
                                                ? Colors.redAccent
                                                : context.textSecondary,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  if (existing != null) ...[
                                    const SizedBox(height: 5),
                                    InkWell(
                                      onTap: staticData.isAdmin
                                          ? () => LinkAccountSheet.show(
                                                context,
                                                householdId: staticData.householdId,
                                                budget: existing,
                                                categoryName: context.trCat(code),
                                                onMapped: () => setState(() {}),
                                              )
                                          : null,
                                      borderRadius: BorderRadius.circular(6),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: mappedAccount != null
                                              ? const Color(0xFF00C896).withValues(alpha: 0.1)
                                              : context.chipBg,
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(
                                            color: mappedAccount != null
                                                ? const Color(0xFF00C896).withValues(alpha: 0.3)
                                                : context.borderColor,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              mappedAccount != null
                                                  ? Icons.account_balance_wallet_outlined
                                                  : Icons.link_off_outlined,
                                              size: 11,
                                              color: mappedAccount != null
                                                  ? const Color(0xFF00C896)
                                                  : context.textSecondary,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              mappedAccount != null
                                                  ? mappedAccount.name
                                                  : context.tr('link_account'),
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w500,
                                                color: mappedAccount != null
                                                    ? const Color(0xFF00C896)
                                                    : context.textSecondary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (staticData.isAdmin) ...[
                              IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                color: context.textSecondary,
                                tooltip: context.tr('edit_budget'),
                                onPressed: () => _editBudget(staticData, existing, code),
                              ),
                              IconButton(
                                icon: const Icon(Icons.archive_outlined,
                                    color: Color(0xFFE3B341), size: 20),
                                tooltip: context.tr('deactivate_category'),
                                onPressed: () => _archiveCategory(staticData, code, category),
                              ),
                            ],
                            Icon(Icons.chevron_right, size: 18, color: context.textSecondary),
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
                                color: context.chipBg,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: context.borderColor),
                              ),
                              child: Text(
                                context.trSub(sub),
                                style: TextStyle(
                                  color: context.textSecondary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
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
  final double monthlyIncome;
  final List<Account> accounts;

  _BudgetStaticData({
    required this.householdId,
    required this.isAdmin,
    required this.allCodes,
    this.monthlyIncome = 0.0,
    this.accounts = const [],
  });
}
