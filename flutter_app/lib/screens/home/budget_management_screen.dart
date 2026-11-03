/// Budget management screen — edit monthly allocations per category.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../main.dart';
import '../../models/models.dart';
import '../../models/budget_reconcile.dart';
import '../../services/api_service.dart';
import '../../widgets/sub_budget_allocation_dialog.dart';
import '../../widgets/sub_budget_breakdown_sheet.dart';
import '../../widgets/categories/category_library_sheet.dart';
import '../../widgets/categories/category_lifecycle_dialog.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/dispose_on_unmount.dart';
import '../../widgets/app_shimmer.dart';
import '../../l10n/app_localizations.dart';
import '../../models/account.dart';
import '../../widgets/budgets/link_account_sheet.dart';
import '../../widgets/dashboard/household_setup_card.dart';
import '../../widgets/budgets/rebalance_budget_sheet.dart';
import '../../widgets/accounts/account_transfer_sheet.dart';
import '../accounts/accounts_overview_screen.dart';
import '../../providers/household_role_provider.dart';
import '../../theme/app_themes.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/widgets/three_d_surface_card.dart';
import '../../core/widgets/three_d_icon_puck.dart';
import '../../services/salary_cycle_service.dart';
import '../../models/money.dart';
import '../../models/manual_expense_row.dart';
import '../../providers/account_provider.dart';
import '../../providers/budget_provider.dart';
import '../../providers/transaction_provider.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

double resolveDisplayOperatingCash({
  required bool isCurrentCycle,
  required bool accountsLoaded,
  required double liquidBalance,
  required double fallback,
}) {
  return (isCurrentCycle && accountsLoaded) ? liquidBalance : fallback;
}

double householdDebitedSpend(Iterable<Map<String, dynamic>> cycleExpenses) {
  double total = 0.0;
  for (final tx in cycleExpenses) {
    final nClass = tx['nafaqah_class']?.toString();
    if (nClass == 'wife_personal' || nClass == 'wife_reimbursable') continue;
    final amount = (tx['amount'] as num?)?.toDouble() ?? 0.0;
    total += amount;
  }
  return total;
}

double resolveCycleFunding({
  required double verifiedCycleIncome,
  required double liquidBalance,
  required double householdDebitedSpend,
}) {
  return verifiedCycleIncome > 0
      ? verifiedCycleIncome
      : (liquidBalance + householdDebitedSpend);
}

class BudgetManagementScreen extends StatefulWidget {
  const BudgetManagementScreen({
    super.key,
    @visibleForTesting this.initialStaticData,
    @visibleForTesting this.loadStaticDataOverride,
    @visibleForTesting this.budgetStreamOverride,
  });

  @visibleForTesting
  final BudgetStaticData? initialStaticData;
  @visibleForTesting
  final Future<BudgetStaticData> Function()? loadStaticDataOverride;
  @visibleForTesting
  final Stream<List<Map<String, dynamic>>> Function(String hid)? budgetStreamOverride;

  @visibleForTesting
  static Map<String, dynamic> buildCarryForwardRow({
    required Map<String, dynamic> b,
    required String householdId,
    required String month,
    required String cycleKey,
  }) =>
      _BudgetManagementScreenState.buildCarryForwardRow(
        b: b,
        householdId: householdId,
        month: month,
        cycleKey: cycleKey,
      );

  @visibleForTesting
  static Map<String, dynamic> buildPriorSpendRow({
    required String id,
    required String householdId,
    required String? userId,
    required double amount,
    required String merchant,
    required String categoryCode,
    required String cycleKey,
    required int paydayDay,
    DateTime? occurredAt,
  }) {
    final cycle = SalaryCycleService.cycleForKey(cycleKey, paydayDay: paydayDay);
    final targetDate = occurredAt ??
        (cycle != null
            ? DateTime.utc(cycle.start.year, cycle.start.month, cycle.start.day, 9, 0, 0)
            : DateTime.now().toUtc());

    final row = buildManualExpenseRow(
      id: id,
      householdId: householdId,
      userId: userId,
      amount: amount,
      merchant: merchant,
      categoryCode: categoryCode,
      spentBy: 'me',
      paidBy: 'me',
      beneficiaryType: 'household',
      beneficiaryId: 'household',
      accountId: null,
      occurredAt: targetDate,
    );
    // cycle_key is trigger-derived (Rule 02 §1); never sent by client
    row.remove('cycle_key');
    row['source'] = 'manual';
    return row;
  }

  @override
  State<BudgetManagementScreen> createState() =>
      _BudgetManagementScreenState();
}

class _BudgetManagementScreenState extends State<BudgetManagementScreen> {
  final DateTime _selectedDate = DateTime.now();
  List<SalaryCycleInfo> _cycles = SalaryCycleService.getAvailableCycles();

  int _currentCycleIndex = 0;
  bool _userNavigatedManually = false;
  late Future<_BudgetStaticData> _staticFuture;
  _BudgetStaticData? _lastStaticData;
  bool _isCopying = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialStaticData != null) {
      _lastStaticData = widget.initialStaticData;
    }
    int initialPayday = SalaryCycleService.defaultPaydayDay;
    try {
      initialPayday = context.read<AccountProvider>().paydayDay;
    } catch (_) {}
    final initialCycles = SalaryCycleService.getAvailableCycles(paydayDay: initialPayday);
    final idx = initialCycles.indexWhere((c) => c.isCurrentCycle || c.isCurrent);
    _cycles = initialCycles;
    _currentCycleIndex = idx != -1 ? idx : 0;
    _staticFuture = _loadStaticData();
  }

  Future<_BudgetStaticData> _loadStaticData() async {
    if (widget.loadStaticDataOverride != null) {
      final data = await widget.loadStaticDataOverride!();
      _lastStaticData = data;
      return data;
    }

    final budgetProvider = context.read<BudgetProvider>();
    final accProvider = context.read<AccountProvider>();

    String hid = '';
    String role = 'member';

    try {
      final roleProvider = context.read<HouseholdRoleProvider>();
      if (roleProvider.isLoaded &&
          roleProvider.householdId != null &&
          roleProvider.householdId!.isNotEmpty) {
        hid = roleProvider.householdId!;
        role = roleProvider.role;
      }
    } catch (_) {}

    if (hid.isEmpty) {
      final user = supabase.auth.currentUser;
      if (user != null) {
        final profile = await supabase
            .from('users')
            .select('household_id, role')
            .eq('id', user.id)
            .single();
        hid = profile['household_id'] as String;
        role = profile['role'] as String? ?? 'member';
      }
    }

    if (budgetProvider.cycles.isNotEmpty) {
      _cycles = budgetProvider.cycles;
      if (!_userNavigatedManually) {
        final curIdx = _cycles.indexWhere((c) => c.isCurrentCycle || c.isCurrent);
        _currentCycleIndex = curIdx != -1 ? curIdx : 0;
      }
    }
    unawaited(_fetchCycles(hid));

    final catData = await budgetProvider.getHouseholdCategories(hid);
    final activeFromApi = catData['active'] ?? [];
    final activeCodes = <Map<String, String>>[];

    if (activeFromApi.isNotEmpty) {
      for (final cat in activeFromApi) {
        if (!cat.name.toLowerCase().contains('test') && !cat.code.toLowerCase().contains('test')) {
          activeCodes.add({
            'code': cat.code,
            'category': cat.name,
            'is_system': cat.isSystem ? 'true' : 'false',
          });
        }
      }
    } else {
      final codesRaw = await supabase
          .from('cost_control_codes')
          .select('code, category, is_system')
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
            'is_system': (r['is_system'] == true) ? 'true' : 'false',
          });
        }
      }
    }

    double income = 0.0;
    List<Account> accounts = [];
    try {
      if (accProvider.householdId != hid) {
        final setup = await HouseholdSetupPrefs.load(hid);
        accProvider.bindHousehold(hid, paydayDay: setup.paydayDay ?? accProvider.paydayDay);
      }
      await accProvider.ensureLoaded();
      if (!mounted) {
        return _lastStaticData ??
            _BudgetStaticData(
              householdId: hid,
              isAdmin: role == 'admin',
              allCodes: activeCodes,
              monthlyIncome: 0.0,
              accounts: [],
            );
      }
      accounts = accProvider.accounts;
      income = accProvider.snapshot.cycleIncome;
    } catch (_) {}

    final data = _BudgetStaticData(
      householdId: hid,
      isAdmin: role == 'admin',
      allCodes: activeCodes,
      monthlyIncome: income,
      accounts: accounts,
    );
    _lastStaticData = data;
    return data;
  }

  Future<void> _fetchCycles(String hid) async {
    try {
      final res = await ApiService.instance.getSalaryCycles(hid);
      if (res['cycles'] != null) {
        final list = (res['cycles'] as List)
            .map((c) => SalaryCycleInfo.fromMap(Map<String, dynamic>.from(c as Map)))
            .toList();
        final merged = SalaryCycleService.getAvailableCycles(serverCycles: list);
        if (mounted && merged.isNotEmpty) {
          setState(() {
            _cycles = merged;
            if (_userNavigatedManually && _selectedCycle != null) {
              final idx = merged.indexWhere((c) => c.cycleKey == _selectedCycle!.cycleKey);
              if (idx != -1) {
                _currentCycleIndex = idx;
                return;
              }
            }
            final curIdx = merged.indexWhere((c) => c.isCurrentCycle || c.isCurrent);
            _currentCycleIndex = curIdx != -1 ? curIdx : 0;
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
    final payday = mounted ? context.read<AccountProvider>().paydayDay : SalaryCycleService.defaultPaydayDay;
    return SalaryCycleService.cycleKeyForInstant(_selectedDate, paydayDay: payday);
  }

  String get _currentMonthStr => DateFormat('yyyy-MM-01').format(_selectedDate);

  Future<void> _copyFromPreviousMonth(String householdId) async {
    setState(() => _isCopying = true);
    try {
      String prevCycleKey;
      final currentIdx = _cycles.indexWhere((c) => c.cycleKey == _currentCycleKey);
      if (currentIdx != -1 && currentIdx + 1 < _cycles.length) {
        prevCycleKey = _cycles[currentIdx + 1].cycleKey;
      } else {
        final parts = _currentCycleKey.split('-');
        if (parts.length == 2) {
          int y = int.parse(parts[0]);
          int m = int.parse(parts[1]) - 1;
          if (m < 1) {
            m = 12;
            y--;
          }
          prevCycleKey = '$y-${m.toString().padLeft(2, '0')}';
        } else {
          prevCycleKey = _currentCycleKey;
        }
      }

      final allBudgetsRes = await supabase
          .from('budgets')
          .select('category_code, allocated_amount, account_id, remaining_amount, spent_amount, sub_allocations, cycle_key, month, is_active, metadata')
          .eq('household_id', householdId);

      final prevBudgets = (allBudgetsRes as List).where((b) {
        final k = b['cycle_key'] as String?;
        final m = b['month'] as String? ?? '';
        final match = (k == prevCycleKey || (k == null && m.startsWith(prevCycleKey)));
        final active = b['is_active'] != false;
        return match && active;
      }).toList();

      if (prevBudgets.isEmpty) {
        if (mounted) {
          AppSnackBar.showInfo(
            context,
            context.trArgs('bm_no_prior_msg', {'month': prevCycleKey}),
            title: context.tr('bm_no_prior_title'),
          );
        }
        return;
      }

      final newEntries = prevBudgets.map((b) {
        return buildCarryForwardRow(
          b: Map<String, dynamic>.from(b as Map),
          householdId: householdId,
          month: _currentMonthStr,
          cycleKey: _currentCycleKey,
        );
      }).toList();

      await supabase.from('budgets').insert(newEntries);

      if (mounted) {
        AppSnackBar.showSuccess(
          context,
          context.tr('bm_copied_silent_success'),
          title: context.tr('bm_copied_title'),
        );
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.showError(
          context,
          context.trArgs('bm_copy_error_msg', {'error': e}),
          title: context.tr('bm_copy_failed'),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCopying = false);
      }
    }
  }

  @visibleForTesting
  static Map<String, dynamic> buildCarryForwardRow({
    required Map<String, dynamic> b,
    required String householdId,
    required String month,
    required String cycleKey,
  }) {
    final alloc = (b['allocated_amount'] as num?)?.toDouble() ?? 0.0;
    final spent = (b['spent_amount'] as num?)?.toDouble() ?? 0.0;
    final subAllocsRaw = b['sub_allocations'];
    final Map<String, dynamic> subAllocs = subAllocsRaw is Map
        ? Map<String, dynamic>.from(subAllocsRaw)
        : <String, dynamic>{};

    Map<String, dynamic> sinkingCfg = {};
    if (subAllocs['_sinking_fund'] is Map) {
      sinkingCfg = Map<String, dynamic>.from(subAllocs['_sinking_fund'] as Map);
    } else if (b['metadata'] is Map && (b['metadata'] as Map)['_sinking_fund'] is Map) {
      sinkingCfg = Map<String, dynamic>.from((b['metadata'] as Map)['_sinking_fund'] as Map);
    }

    final numericSubs = <String, double>{};
    for (final e in subAllocs.entries) {
      if (!e.key.startsWith('_') && e.value is num) {
        numericSubs[e.key] = (e.value as num).toDouble();
      }
    }

    double newAlloc = alloc;
    double delta = 0.0;
    final newSubAllocs = Map<String, dynamic>.from(subAllocs);

    if (sinkingCfg.isNotEmpty) {
      if (numericSubs.isNotEmpty) {
        final newSubNumeric = <String, double>{};
        for (final entry in numericSubs.entries) {
          final sc = entry.key;
          final prevSubAlloc = entry.value;
          final scCfg = sinkingCfg[sc] is Map ? (sinkingCfg[sc] as Map) : null;
          final accumulate = scCfg != null && scCfg['accumulate'] == true;
          final baseAmt = (scCfg != null && scCfg['base_amount'] is num)
              ? (scCfg['base_amount'] as num).toDouble()
              : prevSubAlloc;

          final ratio = alloc > 0 ? (prevSubAlloc / alloc) : 0.0;
          final subSpent = spent * ratio;
          final unspent = (prevSubAlloc - subSpent > 0) ? (prevSubAlloc - subSpent) : 0.0;

          if (accumulate) {
            newSubNumeric[sc] = double.parse((baseAmt + unspent).toStringAsFixed(2));
          } else {
            newSubNumeric[sc] = double.parse(baseAmt.toStringAsFixed(2));
          }
        }
        newAlloc = double.parse(
          newSubNumeric.values.fold<double>(0.0, (a, b) => a + b).toStringAsFixed(2),
        );
        newSubAllocs.addAll(newSubNumeric);

        double baseSum = 0.0;
        for (final entry in numericSubs.entries) {
          final scCfg = sinkingCfg[entry.key] is Map ? (sinkingCfg[entry.key] as Map) : null;
          baseSum += (scCfg != null && scCfg['base_amount'] is num)
              ? (scCfg['base_amount'] as num).toDouble()
              : entry.value;
        }
        final computedDelta = newAlloc - baseSum;
        delta = double.parse((computedDelta > 0 ? computedDelta : 0.0).toStringAsFixed(2));
      } else {
        final parentCfg = (sinkingCfg['_parent'] is Map
                ? sinkingCfg['_parent']
                : sinkingCfg['_self'])
            as Map?;
        final accumulate = parentCfg != null && parentCfg['accumulate'] == true;
        final baseAmt = (parentCfg != null && parentCfg['base_amount'] is num)
            ? (parentCfg['base_amount'] as num).toDouble()
            : alloc;
        final unspent = (alloc - spent > 0) ? (alloc - spent) : 0.0;

        if (accumulate) {
          newAlloc = double.parse((baseAmt + unspent).toStringAsFixed(2));
          delta = double.parse(unspent.toStringAsFixed(2));
        } else {
          newAlloc = double.parse(baseAmt.toStringAsFixed(2));
          delta = 0.0;
        }
      }
    } else {
      newAlloc = alloc;
      delta = 0.0;
    }

    return {
      'household_id': householdId,
      'month': month,
      'cycle_key': cycleKey,
      'category_code': b['category_code'],
      'allocated_amount': newAlloc,
      'account_id': b['account_id'],
      'sub_allocations': newSubAllocs,
      'metadata': b['metadata'] ?? {},
      'previous_cycle_delta': delta,
      'spent_amount': 0.0,
      'is_active': true,
    };
  }

  Future<void> _showPriorSpendingDialog({
    required String householdId,
    required double shortfall,
    required List<Budget> budgets,
    required List<Map<String, String>> allCodes,
  }) async {
    final activeBudgets = budgets.where((b) => b.isActive).toList();
    String selectedCat = activeBudgets.isNotEmpty ? activeBudgets.first.categoryCode : 'OPEX-OTHER';
    final amountCtrl = TextEditingController(text: shortfall.toStringAsFixed(2));

    String getCategoryLabel(String code) {
      final found = allCodes.where((c) => c['code'] == code).firstOrNull;
      return found?['category'] ?? code;
    }

    final merchantLabel = context.tr('prior_cycle_spending_label');
    final successMsg = context.tr('apply_prior_spend_adjustment');

    await showDialog<void>(
      context: context,
      builder: (ctx) => DisposeOnUnmount(
        disposables: [amountCtrl],
        child: StatefulBuilder(
          builder: (ctx, setDlgState) => AlertDialog(
            backgroundColor: context.cardBg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Icon(Icons.history_toggle_off_rounded, color: context.electricTeal, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    merchantLabel,
                    style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.trArgs('mid_cycle_setup_prompt', {'amount': context.sar(shortfall)}),
                    style: TextStyle(color: context.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      labelText: context.tr('amount'),
                      suffixText: context.tr('sar'),
                      filled: true,
                      fillColor: context.inputBg,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (activeBudgets.isNotEmpty)
                    DropdownButtonFormField<String>(
                      initialValue: selectedCat,
                      dropdownColor: context.cardBg,
                      style: TextStyle(color: context.textPrimary),
                      decoration: InputDecoration(
                        labelText: context.tr('category'),
                        filled: true,
                        fillColor: context.inputBg,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      items: activeBudgets.map((b) => DropdownMenuItem(
                        value: b.categoryCode,
                        child: Text('${getCategoryLabel(b.categoryCode)} (${context.sar(b.allocatedAmount)})'),
                      )).toList(),
                      onChanged: (val) {
                        if (val != null) setDlgState(() => selectedCat = val);
                      },
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(context.tr('cancel')),
              ),
              ElevatedButton(
                onPressed: () async {
                  final amt = double.tryParse(amountCtrl.text) ?? shortfall;
                  if (amt <= 0) return;
                  final paydayDay = context.read<AccountProvider>().paydayDay;
                  Navigator.pop(ctx);
                  try {
                    final currentUserId = supabase.auth.currentUser?.id;
                    if (currentUserId != null) {
                      try {
                        final memRes = await supabase
                            .from('household_memberships')
                            .select('financial_role')
                            .eq('household_id', householdId)
                            .eq('user_id', currentUserId)
                            .maybeSingle();
                        if (memRes != null && (memRes['financial_role'] as String?)?.toLowerCase() == 'spouse') {
                          if (mounted) {
                            AppSnackBar.showInfo(context, context.tr('prior_spend_spouse_blocked'));
                          }
                          return;
                        }
                      } catch (_) {}
                    }
                    final row = BudgetManagementScreen.buildPriorSpendRow(
                      id: const Uuid().v4(),
                      householdId: householdId,
                      userId: currentUserId,
                      amount: amt,
                      merchant: merchantLabel,
                      categoryCode: selectedCat,
                      cycleKey: _currentCycleKey,
                      paydayDay: paydayDay,
                    );
                    await supabase.from('transactions').insert(row);
                    if (mounted) {
                      try {
                        context.read<BudgetProvider>().refresh();
                        context.read<TransactionProvider>().refresh();
                      } catch (_) {}
                      setState(() {
                        _staticFuture = _loadStaticData();
                      });
                      AppSnackBar.showSuccess(
                        context,
                        successMsg,
                      );
                    }
                  } catch (e) {
                    debugPrint('Prior spend failed: $e');
                    if (mounted) {
                      AppSnackBar.showError(context, context.tr('bm_prior_spend_failed'));
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.primaryButtonBg,
                  foregroundColor: context.primaryButtonFg,
                ),
                child: Text(successMsg, style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
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
      builder: (ctx) => DisposeOnUnmount(
        disposables: [catNameCtrl, catAmountCtrl, subNameCtrl, subAmountCtrl],
        child: StatefulBuilder(
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
                            color: activeTab == 0
                                ? (context.primaryButtonBg)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Center(
                            child: Text(
                              context.tr('main_category'),
                              style: TextStyle(
                                color: activeTab == 0
                                    ? (context.primaryButtonFg)
                                    : context.textSecondary,
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
                            color: activeTab == 1
                                ? (context.primaryButtonBg)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Center(
                            child: Text(
                              context.tr('sub_category'),
                              style: TextStyle(
                                color: activeTab == 1
                                    ? (context.primaryButtonFg)
                                    : context.textSecondary,
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
                          hintText: context.tr('bm_category_hint'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: catAmountCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: TextStyle(color: context.textPrimary),
                        decoration: InputDecoration(
                          labelText: context.tr('monthly_allocation'),
                          prefixText: '${context.tr('sar')} ',
                          hintText: '500.00',
                        ),
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(context.tr('flexible_pool'), style: TextStyle(color: context.textPrimary, fontSize: 13)),
                        subtitle: Text(context.tr('flexible_pool_desc'), style: TextStyle(color: context.textSecondary, fontSize: 11)),
                        value: isFlexible,
                        activeThumbColor: context.accentText,
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
                          hintText: context.tr('bm_sub_hint'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: subAmountCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: TextStyle(color: context.textPrimary),
                        decoration: InputDecoration(
                          labelText: context.tr('initial_allocation'),
                          prefixText: '${context.tr('sar')} ',
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
                        final amount = parseMoneyInput(catAmountCtrl.text) ?? 0.0;
                        if (name.isEmpty) return;

                        setDialogState(() => isSubmitting = true);
                        // Arabic/Urdu names contain no ASCII letters; fall back to a
                        // unique generated code instead of the bare "OPEX-" prefix.
                        final asciiSlug = name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();
                        final slug = asciiSlug.isNotEmpty
                            ? asciiSlug
                            : 'CUSTOM${DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase()}';
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
                            if (mounted) {
                              context.read<BudgetProvider>().invalidateCategoriesCache();
                              setState(() {
                                _staticFuture = _loadStaticData();
                              });
                              AppSnackBar.showSuccess(
                                context,
                                context.trArgs('bm_category_added_msg', {'name': name, 'amount': context.sar(amount)}),
                                title: context.tr('bm_category_created'),
                              );
                            }
                          } else {
                            throw Exception(res['message'] ?? 'add_category_failed');
                          }
                        } catch (e) {
                          debugPrint('Add category failed: $e');
                          if (ctx.mounted) setDialogState(() => isSubmitting = false);
                          if (mounted) {
                            AppSnackBar.showError(
                              context,
                              context.tr('bm_add_failed'),
                            );
                          }
                        }
                      } else {
                        final subName = subNameCtrl.text.trim();
                        final subAmount = parseMoneyInput(subAmountCtrl.text) ?? 0.0;
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
                            if (mounted) {
                              context.read<BudgetProvider>().invalidateCategoriesCache();
                              setState(() {
                                _staticFuture = _loadStaticData();
                              });
                              AppSnackBar.showSuccess(
                                context,
                                context.trArgs('bm_sub_added_msg', {'name': subName}),
                                title: context.tr('bm_sub_added_title'),
                              );
                            }
                          } else {
                            throw Exception(res['message'] ?? 'add_subcategory_failed');
                          }
                        } catch (e) {
                          debugPrint('Add sub-category failed: $e');
                          if (ctx.mounted) setDialogState(() => isSubmitting = false);
                          if (mounted) {
                            AppSnackBar.showError(
                              context,
                              context.tr('bm_add_failed'),
                            );
                          }
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: context.primaryButtonBg,
                foregroundColor: context.primaryButtonFg,
              ),
              child: isSubmitting
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: context.primaryButtonFg,
                      ),
                    )
                  : Text(activeTab == 0 ? context.tr('bm_create_category') : context.tr('add_sub_category'), style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
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
        title: Text(context.trArgs('bm_deactivate_title', {'category': context.trCat(categoryCode)}), style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold)),
        content: Text(
          context.trArgs('bm_deactivate_desc', {'category': context.trCat(categoryCode)}),
          style: TextStyle(color: context.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('cancel'), style: TextStyle(color: context.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: context.isDark ? context.warnText : VelvetBurgundyColors.amberCautionBgLight,
            ),
            child: Text(
              context.tr('deactivate'),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: context.isDark ? Colors.black : VelvetBurgundyColors.amberCautionTextLight,
              ),
            ),
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

      if (res['status'] == 'success' && mounted) {
        context.read<BudgetProvider>().invalidateCategoriesCache();
        setState(() {
          staticData.allCodes.removeWhere((c) => c['code'] == categoryCode);
          _staticFuture = _loadStaticData();
        });
        if (mounted) {
          AppSnackBar.showSuccess(
            context,
            context.trArgs('bm_deactivated_msg', {'name': categoryName}),
            title: context.tr('bm_deactivated_title'),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.showError(
          context,
          context.trArgs('bm_deactivate_failed_msg', {'error': e}),
          title: context.tr('bm_deactivate_failed_title'),
        );
      }
    }
  }

  Future<void> _renameCategory(
    _BudgetStaticData staticData,
    String categoryCode,
    String currentName,
    bool isSystem,
  ) async {
    // 1. Query past expenses associated with this category in this household
    int txCount = 0;
    try {
      final countRes = await supabase
          .from('transactions')
          .select('id')
          .eq('household_id', staticData.householdId)
          .eq('category_code', categoryCode)
          .count();
      txCount = countRes.count;
    } catch (_) {
      txCount = 0;
    }

    if (!mounted) return;

    if (txCount > 0) {
      // 2. Transactions exist: Show CategoryLifecycleDialog offering Replace vs Rename
      await CategoryLifecycleDialog.show(
        context: context,
        categoryCode: categoryCode,
        currentName: currentName,
        transactionCount: txCount,
        onConfirm: (action, newName) async {
          if (newName.isEmpty || newName == currentName) return;
          try {
            final isRenameOnly = action == CategoryLifecycleAction.renameOnly;
            await ApiService.instance.replaceCategory(
              householdId: staticData.householdId,
              oldCode: categoryCode,
              newName: newName,
              updatePastTransactions: isRenameOnly,
            );
            if (mounted) {
              setState(() {
                _staticFuture = _loadStaticData();
              });
              AppSnackBar.showSuccess(
                context,
                isRenameOnly
                    ? context.trArgs('category_renamed_msg', {'name': newName})
                    : context.trArgs('category_replaced_msg', {'name': newName}),
                title: context.tr('category_renamed'),
              );
            }
          } catch (e) {
            if (mounted) {
              AppSnackBar.showError(
                context,
                context.trArgs('category_rename_failed_msg', {'error': e.toString()}),
                title: context.tr('category_rename_failed'),
              );
            }
          }
        },
      );
      return;
    }

    // 3. Zero transactions: Direct simple rename or replace if system category
    final nameCtrl = TextEditingController(text: currentName);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => DisposeOnUnmount(
        disposables: [nameCtrl],
        child: AlertDialog(
          backgroundColor: context.cardBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            context.tr('rename_category_title'),
            style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          content: TextField(
            controller: nameCtrl,
            autofocus: true,
            style: TextStyle(color: context.textPrimary),
            decoration: InputDecoration(
              labelText: context.tr('category_name'),
              hintText: context.tr('rename_category_hint'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.tr('cancel'), style: TextStyle(color: context.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: context.primaryButtonBg,
                foregroundColor: context.primaryButtonFg,
              ),
              child: Text(context.tr('save'), style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;
    final newName = nameCtrl.text.trim();
    if (newName.isEmpty || newName == currentName) return;

    try {
      await ApiService.instance.replaceCategory(
        householdId: staticData.householdId,
        oldCode: categoryCode,
        newName: newName,
        updatePastTransactions: true,
      );

      if (mounted) {
        setState(() {
          _staticFuture = _loadStaticData();
        });
        AppSnackBar.showSuccess(
          context,
          context.trArgs('category_renamed_msg', {'name': newName}),
          title: context.tr('category_renamed'),
        );
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.showError(
          context,
          context.trArgs('category_rename_failed_msg', {'error': e.toString()}),
          title: context.tr('category_rename_failed'),
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
    final catData = await context.read<BudgetProvider>().getHouseholdCategories(data.householdId);
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
          } catch (e) {
            debugPrint('Toggle category status failed: $e');
            if (mounted) {
              AppSnackBar.showError(context, context.tr('bm_toggle_failed'));
            }
            return;
          }
          if (mounted) {
            context.read<BudgetProvider>().invalidateCategoriesCache();
            setState(() {
              _staticFuture = _loadStaticData();
            });
            AppSnackBar.showSuccess(
              context,
              isActive
                  ? context.trArgs('bm_cat_activated', {'name': cat.name})
                  : context.trArgs('bm_cat_deactivated', {'name': cat.name}),
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

  IconData _categoryIconFor(String code) {
    final c = code.toLowerCase();
    if (c.contains('food') || c.contains('groc') || c.contains('مطاعم') || c.contains('بقالة')) {
      return Icons.shopping_basket_rounded;
    }
    if (c.contains('house') || c.contains('rent') || c.contains('إيجار') || c.contains('سكن')) {
      return Icons.home_rounded;
    }
    if (c.contains('util') || c.contains('bill') || c.contains('كهرباء') || c.contains('فواتير')) {
      return Icons.bolt_rounded;
    }
    if (c.contains('trans') || c.contains('car') || c.contains('سيارة') || c.contains('بنزين')) {
      return Icons.directions_car_rounded;
    }
    if (c.contains('health') || c.contains('صحة') || c.contains('علاج')) {
      return Icons.medical_services_rounded;
    }
    if (c.contains('entertain') || c.contains('ترفيه') || c.contains('قهوة') || c.contains('cafe')) {
      return Icons.local_cafe_rounded;
    }
    if (c.contains('shop') || c.contains('تسوق') || c.contains('ملابس')) {
      return Icons.local_mall_rounded;
    }
    if (c.contains('nafaqah') || c.contains('نفقة') || c.contains('family') || c.contains('عائلة')) {
      return Icons.family_restroom_rounded;
    }
    return Icons.folder_open_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final cycle = _selectedCycle;
    final headerTitle = cycle != null
        ? context.cycleRangeIso(
            cycle.cycleStart,
            cycle.cycleEnd,
            fallback: context.cycleLabel(cycle.cycleKey, fallback: cycle.monthName),
          )
        : context.cycleLabel(_currentCycleKey);
    final headerSub = cycle != null && !cycle.isCurrent ? context.tr('salary_cycle') : context.tr('active_salary_cycle');

    return FutureBuilder<_BudgetStaticData>(
      future: _staticFuture,
      builder: (ctx, staticSnap) {
        if (staticSnap.hasData) {
          _lastStaticData = staticSnap.data!;
        }

        if (!staticSnap.hasData && _lastStaticData == null) {
          return Scaffold(
            backgroundColor: context.scaffoldBg,
            appBar: AppBar(
              title: Text(context.tr('budget_allocations')),
            ),
            body: Padding(
              padding: const EdgeInsets.all(16.0),
              child: AppShimmer.listItems(count: 5),
            ),
          );
        }
        final staticData = staticSnap.data ?? _lastStaticData!;

        return Scaffold(
          appBar: AppBar(
            title: Text(context.tr('budget_allocations')),
            actions: [
              IconButton(
                icon: Icon(Icons.account_balance_wallet_outlined, color: context.primaryButtonFg),
                tooltip: context.tr('accounts_balances'),
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
              if (staticData.isAdmin)
                IconButton(
                  icon: Icon(Icons.category_outlined, color: context.primaryButtonFg),
                  tooltip: context.tr('category_library'),
                  onPressed: () => _openCategoryLibrary(staticData),
                ),
              if (staticData.isAdmin)
                IconButton(
                  icon: Icon(Icons.add_circle_outline_rounded, color: context.primaryButtonFg),
                  tooltip: context.tr('bm_add_tooltip'),
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
                      tooltip: context.tr('a11y_previous'),
                      icon: Icon(context.isRtl ? Icons.chevron_right_rounded : Icons.chevron_left_rounded, color: context.textPrimary.withValues(alpha: 0.7)),
                      onPressed: (_cycles.isNotEmpty && _currentCycleIndex < _cycles.length - 1)
                          ? () => setState(() {
                              _userNavigatedManually = true;
                              _currentCycleIndex++;
                            })
                          : null,
                    ),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            headerTitle,
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: context.textPrimary),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            headerSub,
                            style: TextStyle(color: context.textSecondary, fontSize: 11),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: context.tr('a11y_next'),
                      icon: Icon(context.isRtl ? Icons.chevron_left_rounded : Icons.chevron_right_rounded, color: context.textSecondary),
                      onPressed: (_cycles.isNotEmpty && _currentCycleIndex > 0)
                          ? () => setState(() {
                              _userNavigatedManually = true;
                              _currentCycleIndex--;
                            })
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
                  icon: const Icon(Icons.add_rounded, color: Colors.white),
                  label: Text(context.tr('add_category'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  backgroundColor: context.primaryButtonBg,
                )
              : null,
          body: StreamBuilder<List<Map<String, dynamic>>>(
            stream: widget.budgetStreamOverride != null
                ? widget.budgetStreamOverride!(staticData.householdId)
                : supabase
                    .from('budgets')
                    .stream(primaryKey: ['id'])
                    .eq('household_id', staticData.householdId),
            builder: (ctx, budgetSnap) {
              final accountProvider = ctx.watch<AccountProvider>();
              final liveAccounts = accountProvider.hasLoaded ? accountProvider.accounts : staticData.accounts;

              final rawBudgets = <Budget>[];
              for (final row in (budgetSnap.data ?? [])) {
                try {
                  final b = Budget.fromMap(row);
                  if (!b.isActive) continue;
                  final key = _currentCycleKey;
                  final matches = (b.cycleKey != null && b.cycleKey!.isNotEmpty)
                      ? b.cycleKey == key
                      : (b.month.startsWith(key) || b.month == _currentMonthStr);
                  if (matches) rawBudgets.add(b);
                } catch (e) {
                  debugPrint('[BudgetManagementScreen] Failed to parse budget row: $e');
                }
              }

              final txProvider = ctx.watch<TransactionProvider>();
              final paydayDay = context.read<AccountProvider>().paydayDay;

              final budgets = txProvider.isLoading
                  ? rawBudgets
                  : reconcileCycleBudgets(rawBudgets, txProvider, _currentCycleKey, paydayDay);

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
                                Expanded(
                                  child: Text(
                                    context.tr('no_allocations_set'),
                                    style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
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
                                      ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: context.primaryButtonFg))
                                      : const Icon(Icons.copy_rounded, size: 16),
                                  label: Text(_isCopying ? context.tr('bm_copying') : context.tr('copy_previous')),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: context.primaryButtonBg,
                                    foregroundColor: context.primaryButtonFg,
                                    textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    }

                    final isCurrentCycle = _selectedCycle?.isCurrent ?? true;

                    final totalSpent = budgets
                        .where((b) => b.isActive)
                        .fold<double>(0.0, (s, b) => s + b.spentAmount);

                    final snapshot = accountProvider.snapshot;
                    final displayOperatingCash = resolveDisplayOperatingCash(
                      isCurrentCycle: isCurrentCycle,
                      accountsLoaded: accountProvider.hasLoaded,
                      liquidBalance: snapshot.liquidBalance,
                      fallback: 0.0,
                    );
                    final verifiedCycleIncome = accountProvider.hasLoaded ? snapshot.cycleIncome : staticData.monthlyIncome;
                    final cycleFunding = resolveCycleFunding(
                      verifiedCycleIncome: verifiedCycleIncome,
                      liquidBalance: displayOperatingCash,
                      householdDebitedSpend: totalSpent,
                    );
                    final hasBenchmark = cycleFunding > 0;
                    final hasOperatingCash = isCurrentCycle && displayOperatingCash > 0;

                    // Allocation capacity margin against cycle funding
                    final fundingMargin = hasBenchmark ? (cycleFunding - totalAllocated) : 0.0;
                    final isOverAllocated = isCurrentCycle && hasBenchmark && fundingMargin < -0.005;

                    // Guardrail 2: Calculate any account deficits based on net remaining commitments vs current balance
                    Account? deficitAccount;
                    double deficitAmount = 0.0;
                    if (isCurrentCycle && liveAccounts.isNotEmpty) {
                      final Map<String, double> allocatedByAccount = {};
                      final Map<String, double> spentByAccount = {};
                      final defaultAccId = liveAccounts
                          .where((a) => !a.isArchived && a.accountType.isOperatingPool)
                          .firstOrNull
                          ?.id ?? (liveAccounts.length == 1 ? liveAccounts.first.id : null);

                      for (final b in budgets) {
                        if (b.isActive) {
                          final accId = (b.accountId != null && b.accountId!.isNotEmpty)
                              ? b.accountId!
                              : defaultAccId;
                          if (accId != null) {
                            allocatedByAccount[accId] = (allocatedByAccount[accId] ?? 0.0) + b.allocatedAmount;
                            spentByAccount[accId] = (spentByAccount[accId] ?? 0.0) + b.spentAmount;
                          }
                        }
                      }

                      for (final entry in allocatedByAccount.entries) {
                        final acc = liveAccounts.where((a) => a.id == entry.key).firstOrNull;
                        if (acc != null) {
                          final spent = spentByAccount[entry.key] ?? 0.0;
                          final netRemaining = (entry.value - spent).clamp(0.0, double.infinity);
                          final effectiveAccBal = acc.balance;
                          if (netRemaining > effectiveAccBal + 0.005) {
                            deficitAccount = acc;
                            deficitAmount = netRemaining - effectiveAccBal;
                            break;
                          }
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
                              color: context.dangerColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: context.dangerColor.withValues(alpha: 0.5)),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.warning_amber_rounded, color: context.dangerColor, size: 22),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        context.trArgs('account_capacity_deficit', {'account': deficitAccount.name, 'amount': context.money(-deficitAmount, deficitAccount.currency)}),
                                        style: TextStyle(color: context.dangerColor, fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        context.tr('deficit_linked_warning'),
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
                                    backgroundColor: context.dangerColor,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    visualDensity: VisualDensity.compact,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  child: Text(context.tr('fix'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                ),
                              ],
                            ),
                          ),
                        ThreeDSurfaceCard(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(18),
                          borderRadius: 20,
                          customBorder: isOverAllocated
                              ? Border.all(color: context.dangerColor.withValues(alpha: 0.6), width: 1.5)
                              : null,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${context.tr('total_allocated')} ($headerTitle)',
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: context.textSecondary,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          context.sar(totalAllocated),
                                          style: GoogleFonts.outfit(
                                            color: context.accentText,
                                            fontSize: 22,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Builder(
                                    builder: (context) {
                                      final setCodes = budgets.where((b) => b.isActive).map((b) => b.categoryCode).toSet();
                                      return Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: context.accentSubtleBg,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: context.accentSubtleBorder),
                                        ),
                                        child: Text(
                                          '${setCodes.length}/${staticData.allCodes.length} ${context.tr('set')}',
                                          style: GoogleFonts.outfit(
                                            color: context.accentText,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                              if (hasBenchmark) ...[
                                const SizedBox(height: 14),
                                Divider(color: context.borderColor.withValues(alpha: 0.5), height: 1),
                                const SizedBox(height: 12),
                                // Row 1: Cycle Funding Capacity Benchmark
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Row(
                                        children: [
                                          Icon(
                                            isOverAllocated ? Icons.warning_amber_rounded : Icons.savings_outlined,
                                            size: 17,
                                            color: isOverAllocated ? context.dangerColor : context.electricTeal,
                                          ),
                                          const SizedBox(width: 6),
                                          Flexible(
                                            child: Text(
                                              context.tr('cycle_income_capacity'),
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: isOverAllocated ? context.dangerColor : context.textSecondary,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      context.sar(cycleFunding),
                                      style: GoogleFonts.outfit(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: context.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                                if (isCurrentCycle) ...[
                                  const SizedBox(height: 8),
                                  // Row 2: Live Remaining Operating Cash
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.account_balance_wallet_outlined,
                                              size: 17,
                                              color: context.accentText,
                                            ),
                                            const SizedBox(width: 6),
                                            Flexible(
                                              child: Text(
                                                context.tr('operating_cash_remaining'),
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: context.textSecondary,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Text(
                                        context.sar(displayOperatingCash),
                                        style: GoogleFonts.outfit(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          color: context.textPrimary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                const SizedBox(height: 10),
                                if (isOverAllocated) ...[
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: context.dangerColor.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: context.dangerColor.withValues(alpha: 0.3)),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(Icons.warning_amber_rounded, size: 16, color: context.dangerColor),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                context.trArgs('allocations_exceed_income', {'amount': context.sar(-fundingMargin)}),
                                                style: TextStyle(
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.bold,
                                                  color: context.dangerColor,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            ElevatedButton.icon(
                                              key: const Key('shrink_to_match_cash_button'),
                                              onPressed: () {
                                                RebalanceBudgetSheet.show(
                                                  context,
                                                  householdId: staticData.householdId,
                                                  cycleKey: _currentCycleKey,
                                                  budgets: budgets,
                                                  targetAvailableCash: cycleFunding,
                                                  onRebalanced: () => setState(() {
                                                    _staticFuture = _loadStaticData();
                                                  }),
                                                );
                                              },
                                              icon: const Icon(Icons.auto_fix_high_rounded, size: 14),
                                              label: Text(
                                                context.tr('shrink_to_match_cash'),
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                                              ),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: context.dangerColor,
                                                foregroundColor: Colors.white,
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                visualDensity: VisualDensity.compact,
                                                elevation: 0,
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                              ),
                                            ),
                                            if (staticData.isAdmin)
                                              OutlinedButton.icon(
                                                key: const Key('log_prior_spending_button'),
                                                onPressed: () {
                                                  _showPriorSpendingDialog(
                                                    householdId: staticData.householdId,
                                                    shortfall: -fundingMargin,
                                                    budgets: budgets,
                                                    allCodes: staticData.allCodes,
                                                  );
                                                },
                                              icon: const Icon(Icons.history_toggle_off_rounded, size: 14),
                                              label: Text(
                                                context.tr('apply_prior_spend_adjustment'),
                                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: context.textPrimary),
                                              ),
                                              style: OutlinedButton.styleFrom(
                                                side: BorderSide(color: context.borderColor),
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                visualDensity: VisualDensity.compact,
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ] else ...[
                                  Wrap(
                                    alignment: WrapAlignment.spaceBetween,
                                    runAlignment: WrapAlignment.center,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    spacing: 8,
                                    runSpacing: 4,
                                    children: [
                                      Text(
                                        context.trArgs('within_income_capacity', {'amount': context.sar(fundingMargin)}),
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: context.successText,
                                        ),
                                      ),
                                      if (hasOperatingCash && totalSpent > 0)
                                        Text(
                                          context.trArgs('bm_spent_vs_cash', {
                                            'spent': context.sar(totalSpent),
                                            'cash': context.sar(displayOperatingCash),
                                          }),
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            color: context.textSecondary,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ],
                            ],
                          ),
                        ),
                      ],
                    );
                  }

                final code = staticData.allCodes[i - 1]['code'] as String;
                final category = staticData.allCodes[i - 1]['category'] as String;
                final isSys = staticData.allCodes[i - 1]['is_system'] == 'true';
                final displayName = (!isSys && category.trim().isNotEmpty) ? category : context.trCat(code);
                final existing =
                    budgets.where((b) => b.categoryCode == code).firstOrNull;
                final systemSubs = kSubCategoriesByParent[code] ?? const <String>[];
                final customSubs = existing?.subAllocations.keys ?? const <String>[];
                final seenLabels = <String>{};
                final subCategories = <String>[];
                for (final sub in [...systemSubs, ...customSubs]) {
                  final label = context.trSub(sub).trim().toLowerCase();
                  if (label.isNotEmpty && seenLabels.add(label)) {
                    subCategories.add(sub);
                  }
                }
                final mappedAccount = liveAccounts
                    .where((a) => a.id == existing?.accountId)
                    .firstOrNull;

                final allocated = existing?.allocatedAmount ?? 0.0;
                final spent = existing?.spentAmount ?? 0.0;
                final ratio = (allocated > 0) ? (spent / allocated).clamp(0.0, 1.0) : 0.0;
                final isExceeded = spent > allocated && allocated > 0;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ThreeDSurfaceCard(
                    padding: const EdgeInsets.all(14),
                    borderRadius: 18,
                    onTap: () {
                      SubBudgetBreakdownSheet.show(
                        context,
                        householdId: staticData.householdId,
                        categoryCode: code,
                        categoryName: displayName,
                        cycleKey: _currentCycleKey,
                        allocatedAmount: allocated,
                        spentAmount: spent,
                        previousCycleDelta: existing?.previousCycleDelta ?? 0.0,
                      );
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            ThreeDIconPuck(
                              icon: _categoryIconFor(code),
                              size: 44,
                              iconColor: Colors.white,
                              isSquircle: true,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    displayName,
                                    style: GoogleFonts.outfit(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: context.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 2,
                                    children: [
                                      Text(
                                        existing != null
                                            ? context.sar(allocated)
                                            : context.tr('not_set'),
                                        style: GoogleFonts.outfit(
                                          color: existing != null
                                              ? (context.accentText)
                                              : context.textSecondary,
                                          fontSize: 13,
                                          fontWeight: existing != null ? FontWeight.w700 : FontWeight.normal,
                                        ),
                                      ),
                                      if (existing != null && spent > 0) ...[
                                        Text(
                                          '• ${context.tr('spent')}: ${context.sar(spent)}',
                                          style: GoogleFonts.outfit(
                                            color: isExceeded
                                                ? context.dangerColor
                                                : (context.textSecondary),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            if (staticData.isAdmin) ...[
                              IconButton(
                                icon: const Icon(Icons.tune_rounded),
                                color: context.accentText,
                                tooltip: context.tr('edit_budget'),
                                onPressed: () => _editBudget(staticData, existing, code),
                              ),
                              PopupMenuButton<String>(
                                key: const ValueKey('budget_row_menu'),
                                tooltip: context.tr('feed_more_actions'),
                                icon: Icon(Icons.more_vert_rounded, color: context.accentText),
                                onSelected: (v) {
                                  if (v == 'rename') {
                                    _renameCategory(staticData, code, category, isSys);
                                  } else if (v == 'deactivate') {
                                    _archiveCategory(staticData, code, category);
                                  }
                                },
                                itemBuilder: (_) => [
                                  PopupMenuItem(
                                    value: 'rename',
                                    child: Row(
                                      children: [
                                        Icon(Icons.edit_outlined, size: 18, color: context.accentText),
                                        const SizedBox(width: 10),
                                        Flexible(child: Text(context.tr('rename_category'))),
                                      ],
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'deactivate',
                                    child: Row(
                                      children: [
                                        Icon(Icons.archive_outlined, size: 18, color: context.warnText),
                                        const SizedBox(width: 10),
                                        Flexible(child: Text(context.tr('deactivate_category'))),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            Icon(context.isRtl ? Icons.chevron_left_rounded : Icons.chevron_right_rounded, size: 18, color: context.accentText),
                          ],
                        ),
                        if (existing != null && allocated > 0) ...[
                          const SizedBox(height: 12),
                          // 3D Recessed Progress Track
                          Container(
                            height: 6,
                            decoration: BoxDecoration(
                              color: context.borderColor.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                return Stack(
                                  children: [
                                    Container(
                                      width: constraints.maxWidth * ratio,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: isExceeded
                                              ? [context.dangerColor, Colors.red]
                                              : context.icedAccentGradient.colors,
                                        ),
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ],
                          const SizedBox(height: 8),
                          InkWell(
                            onTap: staticData.isAdmin
                                ? () => LinkAccountSheet.show(
                                      context,
                                      householdId: staticData.householdId,
                                      budget: existing,
                                      categoryCode: code,
                                      cycleKey: _currentCycleKey,
                                      categoryName: displayName,
                                      onMapped: () {
                                        setState(() {
                                          _staticFuture = _loadStaticData();
                                        });
                                      },
                                    )
                                : null,
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: mappedAccount != null
                                    ? (context.accentSubtleBg)
                                    : (context.chipBg),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: mappedAccount != null
                                      ? (context.accentSubtleBorder)
                                      : (context.borderColor),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    mappedAccount != null
                                        ? Icons.account_balance_wallet_outlined
                                        : Icons.link_off_outlined,
                                    size: 12,
                                    color: mappedAccount != null
                                        ? (context.accentText)
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
                                          ? (context.accentText)
                                          : context.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
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
                                  color: context.accentText,
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

class BudgetStaticData {
  final String householdId;
  final bool isAdmin;
  final List<Map<String, String>> allCodes;
  final double monthlyIncome;
  final List<Account> accounts;

  BudgetStaticData({
    required this.householdId,
    required this.isAdmin,
    required this.allCodes,
    this.monthlyIncome = 0.0,
    this.accounts = const [],
  });
}

typedef _BudgetStaticData = BudgetStaticData;
