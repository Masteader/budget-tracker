import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/recurring_bill.dart';
import '../services/api_service.dart';
import '../../main.dart';

/// Centralized reactive state provider for recurring bills, reservations, and payment status.
class RecurringBillsProvider extends ChangeNotifier {
  String? _householdId;
  RecurringBillsSummary? _summary;
  bool _isLoading = false;
  String? _error;

  RecurringBillsSummary? get summary => _summary;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get householdId => _householdId;

  /// Initialize provider with active household ID and fetch bills.
  Future<void> init(String householdId) async {
    if (_householdId == householdId && _summary != null) return;
    _householdId = householdId;
    await fetchBills();
  }

  /// Re-fetch recurring bills and reservation details from the API.
  Future<void> fetchBills({bool silent = false}) async {
    if (_householdId == null) return;
    if (!silent) {
      _isLoading = true;
      _error = null;
      notifyListeners();
    }

    try {
      final res = await ApiService.instance.getRecurringBills(_householdId!);
      _summary = res;
      _isLoading = false;
      _error = null;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _error = e.toString();
      debugPrint('[RecurringBillsProvider] Error fetching bills: $e');
      notifyListeners();
    }
  }

  /// Records a bill payment as a transaction and immediately updates recurring bills state.
  Future<bool> recordBillPayment(RecurringBillItem bill) async {
    if (_householdId == null) return false;
    try {
      await supabase.from('transactions').insert({
        'household_id': _householdId,
        'merchant': bill.merchant,
        'amount': bill.averageAmount,
        'category_code': bill.categoryCode,
        'sub_category': bill.subCode,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });
      await fetchBills(silent: true);
      return true;
    } catch (e) {
      debugPrint('[RecurringBillsProvider] Error recording bill payment: $e');
      return false;
    }
  }

  /// Testing helper
  @visibleForTesting
  void setSummaryForTesting(RecurringBillsSummary summary, {String? householdId}) {
    _summary = summary;
    if (householdId != null) _householdId = householdId;
    notifyListeners();
  }
}
