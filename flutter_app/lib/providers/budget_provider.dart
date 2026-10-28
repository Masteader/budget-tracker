import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/salary_cycle_service.dart';

/// Centralized reactive state provider for salary cycle budgets and sub-budget allocations.
///
/// The pace and verdict shown on the dashboard come from one place only,
/// [PaydayOutlook] (UX-07); the server burn-rate forecast is not fetched.
class BudgetProvider extends ChangeNotifier {
  String? _householdId;
  List<SalaryCycleInfo> _cycles = [];
  int _selectedCycleIndex = 0;
  List<CategoryBreakdownItem> _categories = [];
  bool _isLoading = false;
  String? _error;
  int _breakdownGeneration = 0;
  final ApiService? _apiOverride;

  BudgetProvider({ApiService? api}) : _apiOverride = api;

  ApiService get _api => _apiOverride ?? ApiService.instance;

  // Getters
  bool get isLoading => _isLoading;
  String? get error => _error;
  List<SalaryCycleInfo> get cycles => _cycles;
  int get selectedCycleIndex => _selectedCycleIndex;
  List<CategoryBreakdownItem> get categories => _categories;

  SalaryCycleInfo? get activeCycle {
    if (_cycles.isEmpty) return null;
    if (_selectedCycleIndex >= 0 && _selectedCycleIndex < _cycles.length) {
      return _cycles[_selectedCycleIndex];
    }
    return _cycles.first;
  }

  double get totalAllocated => _categories.fold(0.0, (acc, c) => acc + c.allocatedAmount);
  double get totalSpent => _categories.fold(0.0, (acc, c) => acc + c.spentAmount);
  double get totalRemaining => _categories.fold(0.0, (acc, c) => acc + c.remainingAmount);

  Future<void> init(String householdId) async {
    if (_householdId == householdId && _cycles.isNotEmpty) return;
    if (_householdId != householdId) {
      // Never show another household's budgets while the new ones load.
      _clearData();
    }
    _householdId = householdId;
    await refresh();
  }

  /// Drops all cached household data (sign-out / household switch).
  void reset() {
    _householdId = null;
    _clearData();
    notifyListeners();
  }

  void _clearData() {
    _breakdownGeneration++;
    _cycles = [];
    _selectedCycleIndex = 0;
    _categories = [];
    _error = null;
    _isLoading = false;
  }

  Future<void> selectCycle(int index) async {
    if (index < 0 || index >= _cycles.length) return;
    _selectedCycleIndex = index;
    notifyListeners();
    await fetchBreakdown();
  }

  Future<void> refresh() async {
    if (_householdId == null) return;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await Future.wait([
        _fetchCycles(),
        _fetchPayday(),
      ]);
      await fetchBreakdown();
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _error = e.toString();
      debugPrint('[BudgetProvider] Error refreshing budgets: $e');
      notifyListeners();
    }
  }

  Future<void> _fetchCycles() async {
    if (_householdId == null) return;
    try {
      final res = await _api.getSalaryCycles(_householdId!);
      if (res['cycles'] != null) {
        _cycles = (res['cycles'] as List)
            .map((c) => SalaryCycleInfo.fromMap(Map<String, dynamic>.from(c as Map)))
            .toList();
        final currentIdx = _cycles.indexWhere((c) => c.isCurrent);
        if (currentIdx != -1) {
          _selectedCycleIndex = currentIdx;
        }
      }
    } catch (e) {
      debugPrint('[BudgetProvider] Error fetching cycles: $e');
    }
  }

  /// Keeps the client cycle arithmetic on the household's real payday.
  Future<void> _fetchPayday() async {
    if (_householdId == null) return;
    try {
      final payday = await _api.getHouseholdPayday(_householdId!);
      // Applied in memory synchronously; persisting to preferences must not
      // hold up the budget refresh.
      unawaited(SalaryCycleService.cachePayday(payday));
    } catch (e) {
      debugPrint('[BudgetProvider] Error fetching payday: $e');
    }
  }

  Future<void> fetchBreakdown() async {
    if (_householdId == null) return;
    final currentKey = activeCycle?.cycleKey;
    final generation = ++_breakdownGeneration;
    try {
      final res = await _api.getBudgetBreakdown(
        _householdId!,
        cycleKey: currentKey,
      );
      // A newer selectCycle()/refresh() superseded this request: drop the
      // stale response instead of showing another cycle's categories.
      if (generation != _breakdownGeneration) return;
      if (res['categories'] != null) {
        _categories = (res['categories'] as List)
            .map((cat) => CategoryBreakdownItem.fromMap(Map<String, dynamic>.from(cat as Map)))
            .toList();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[BudgetProvider] Error fetching breakdown: $e');
    }
  }

  Future<bool> saveSubAllocations({
    required String categoryCode,
    required Map<String, dynamic> subAllocations,
  }) async {
    if (_householdId == null) return false;
    final cycleKey = activeCycle?.cycleKey;
    try {
      final res = await _api.saveSubAllocations(
        householdId: _householdId!,
        categoryCode: categoryCode,
        subAllocations: subAllocations,
        cycleKey: cycleKey,
      );
      if (res['status'] == 'success') {
        await fetchBreakdown();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[BudgetProvider] Error saving sub-allocations: $e');
      return false;
    }
  }

  Future<bool> addSubCategory({
    required String parentCode,
    required String nameEn,
    required double allocatedAmount,
    String? subCode,
  }) async {
    if (_householdId == null) return false;
    final cycleKey = activeCycle?.cycleKey;
    try {
      final res = await _api.addSubCategory(
        householdId: _householdId!,
        parentCode: parentCode,
        nameEn: nameEn,
        allocatedAmount: allocatedAmount,
        subCode: subCode,
        cycleKey: cycleKey,
      );
      if (res['status'] == 'success') {
        await fetchBreakdown();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[BudgetProvider] Error adding sub-category: $e');
      return false;
    }
  }

  Future<bool> removeSubCategory({
    required String parentCode,
    required String subCode,
  }) async {
    if (_householdId == null) return false;
    final cycleKey = activeCycle?.cycleKey;
    try {
      final res = await _api.removeSubCategory(
        householdId: _householdId!,
        parentCode: parentCode,
        subCode: subCode,
        cycleKey: cycleKey,
      );
      if (res['status'] == 'success') {
        await fetchBreakdown();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[BudgetProvider] Error removing sub-category: $e');
      return false;
    }
  }

  Future<bool> addCategory({
    required String code,
    required String category,
    required double allocatedAmount,
    bool isFlexible = true,
  }) async {
    if (_householdId == null) return false;
    try {
      final res = await _api.addBudgetCategory(
        householdId: _householdId!,
        code: code,
        category: category,
        allocatedAmount: allocatedAmount,
        isFlexible: isFlexible,
      );
      if (res['status'] == 'success') {
        await refresh();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[BudgetProvider] Error adding category: $e');
      return false;
    }
  }

  Future<bool> archiveCategory(String categoryCode) async {
    if (_householdId == null) return false;
    try {
      final res = await _api.archiveBudgetCategory(
        _householdId!,
        categoryCode,
      );
      if (res['status'] == 'success') {
        await refresh();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[BudgetProvider] Error archiving category: $e');
      return false;
    }
  }
}
