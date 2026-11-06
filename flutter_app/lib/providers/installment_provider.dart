import 'dart:async';
import 'package:flutter/foundation.dart';
import '../main.dart';
import '../models/installment_plan.dart';
import '../services/api_service.dart';

/// Centralized reactive state provider for BNPL & installment plans (Tamara, Tabby, Bank).
class InstallmentProvider extends ChangeNotifier {
  InstallmentProvider({ApiService? api, @visibleForTesting Future<List<dynamic>> Function(String planId)? deleteRow})
      : _apiOverride = api,
        _deleteRowOverride = deleteRow;

  final ApiService? _apiOverride;

  /// Deletes the plan row and returns the rows it reached (a Supabase delete by default).
  final Future<List<dynamic>> Function(String planId)? _deleteRowOverride;
  ApiService get _api => _apiOverride ?? ApiService.instance;

  String? _householdId;
  List<InstallmentPlan> _plans = [];
  bool _isLoading = false;
  String? _error;
  DateTime? _lastUpdated;

  List<InstallmentPlan> get plans => _plans;
  bool get isLoading => _isLoading;

  /// Set when the last load failed; [plans] then still holds the plans from
  /// [lastUpdated], if any.
  String? get error => _error;
  DateTime? get lastUpdated => _lastUpdated;

  /// Plans were loaded at least once for this household (an empty list then
  /// really means "no plans").
  bool get hasLoaded => _lastUpdated != null;
  String? get householdId => _householdId;
  bool get isInitialized => _householdId != null;

  /// Initialize provider with active household ID and fetch plans.
  Future<void> init(String householdId) async {
    final changed = _householdId != householdId;
    if (changed) {
      _plans = [];
      _lastUpdated = null;
      _error = null;
    }
    _householdId = householdId;
    if (changed || !hasLoaded) {
      await fetchPlans();
    }
  }

  /// Re-fetch installment plans from the API (rows only, R10: legacy notes are
  /// never reconstructed into plans on the client). A failure keeps the last
  /// plans and sets [error] (UX-01: never an empty "all cleared" list).
  Future<void> fetchPlans({bool silent = false}) async {
    if (_householdId == null || _householdId!.isEmpty) return;
    if (!silent) {
      _isLoading = true;
      _error = null;
      notifyListeners();
    }
    final householdId = _householdId!;
    try {
      final plans = await _api.getInstallments(householdId);
      if (householdId != _householdId) return; // switched household meanwhile
      _plans = plans;
      _error = null;
      _lastUpdated = DateTime.now();
    } catch (e) {
      if (householdId != _householdId) return;
      _error = e.toString();
      debugPrint('[InstallmentProvider] getInstallments error: $e');
    }
    _isLoading = false;
    notifyListeners();
  }

  /// Creates a new installment plan and refreshes active plans.
  /// Updates an existing installment plan.
  Future<InstallmentPlan> updatePlan(String planId, Map<String, dynamic> updateData) async {
    try {
      final plan = await _api.updateInstallmentPlan(planId, updateData);
      await fetchPlans(silent: true);
      return plan;
    } catch (e) {
      debugPrint('[InstallmentProvider] Error updating installment plan: $e');
      rethrow;
    }
  }

  Future<InstallmentPlan> createPlan(Map<String, dynamic> planData) async {
    try {
      final plan = await _api.createInstallmentPlan(planData);
      await fetchPlans(silent: true);
      return plan;
    } catch (e) {
      debugPrint('[InstallmentProvider] Error creating installment plan: $e');
      rethrow;
    }
  }

  /// Records an installment payment towards a plan.
  Future<bool> recordPayment(String planId) async {
    try {
      final plan = await _api.payInstallment(planId);
      await fetchPlans(silent: true);
      // null: the server did not record the payment (FR-A-03).
      return plan != null;
    } catch (e) {
      debugPrint('[InstallmentProvider] Error recording installment payment: $e');
      return false;
    }
  }

  /// Deletes an installment plan. True when the delete reached the plan;
  /// false when it reached no row: the plan is gone, or it is one the viewer
  /// no longer reads (the plan of a wife's personal purchase is read only by
  /// her, her husband and an admin who is not a wife; owner decision
  /// 2026-11-06), which RLS filters out without an error. Either way the list
  /// reloads. A failed delete throws.
  Future<bool> deletePlan(String planId) async {
    try {
      final deleteRow = _deleteRowOverride ??
          (String id) async => await supabase.from('installment_plans').delete().eq('id', id).select('id');
      final rows = await deleteRow(planId);
      await fetchPlans(silent: true);
      return rows.isNotEmpty;
    } catch (e) {
      debugPrint('[InstallmentProvider] Error deleting installment plan: $e');
      rethrow;
    }
  }

  /// Forgets the household's plans (sign-out).
  void reset() {
    _householdId = null;
    _plans = [];
    _isLoading = false;
    _error = null;
    _lastUpdated = null;
    notifyListeners();
  }

  /// Testing helper
  @visibleForTesting
  void setPlansForTesting(List<InstallmentPlan> testPlans, {String? householdId}) {
    _plans = testPlans;
    _lastUpdated = DateTime.now();
    if (householdId != null) _householdId = householdId;
    notifyListeners();
  }
}
