import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../services/api_service.dart';

/// Centralized reactive state provider for salary cycle budgets, forecasts, and sub-budget allocations.
class BudgetProvider extends ChangeNotifier {
  String? _householdId;
  List<SalaryCycleInfo> _cycles = [];
  int _selectedCycleIndex = 0;
  List<CategoryBreakdownItem> _categories = [];
  Map<String, dynamic> _forecast = {};
  bool _isLoading = false;
  String? _error;

  // Getters
  bool get isLoading => _isLoading;
  String? get error => _error;
  List<SalaryCycleInfo> get cycles => _cycles;
  int get selectedCycleIndex => _selectedCycleIndex;
  List<CategoryBreakdownItem> get categories => _categories;
  Map<String, dynamic> get forecast => _forecast;

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
    _householdId = householdId;
    await refresh();
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
        _fetchForecast(),
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
      final res = await ApiService.instance.getSalaryCycles(_householdId!);
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

  Future<void> _fetchForecast() async {
    if (_householdId == null) return;
    try {
      _forecast = await ApiService.instance.getSalaryCycleForecast(_householdId!);
    } catch (e) {
      debugPrint('[BudgetProvider] Error fetching forecast: $e');
    }
  }

  Future<void> fetchBreakdown() async {
    if (_householdId == null) return;
    final currentKey = activeCycle?.cycleKey;
    try {
      final res = await ApiService.instance.getBudgetBreakdown(
        _householdId!,
        cycleKey: currentKey,
      );
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
    required Map<String, double> subAllocations,
  }) async {
    if (_householdId == null) return false;
    final cycleKey = activeCycle?.cycleKey;
    try {
      final res = await ApiService.instance.saveSubAllocations(
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
      final res = await ApiService.instance.addSubCategory(
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
      final res = await ApiService.instance.removeSubCategory(
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
      final res = await ApiService.instance.addBudgetCategory(
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
      final res = await ApiService.instance.archiveBudgetCategory(
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
