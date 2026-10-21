import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/recurring_bill.dart';
import '../models/transaction_attribution.dart';
import '../services/api_service.dart';
import '../../main.dart';

/// Centralized reactive state provider for recurring bills, reservations, and payment status.
class RecurringBillsProvider extends ChangeNotifier {
  RecurringBillsProvider({
    Future<void> Function(Map<String, dynamic> row)? insertRow,
    String? Function()? currentUserId,
    ApiService? api,
  })  : _insertRow = insertRow,
        _currentUserId = currentUserId,
        _apiOverride = api;

  final Future<void> Function(Map<String, dynamic> row)? _insertRow;
  final String? Function()? _currentUserId;
  final ApiService? _apiOverride;

  ApiService get _api => _apiOverride ?? ApiService.instance;

  String? _householdId;
  RecurringBillsSummary? _summary;
  bool _isLoading = false;
  String? _error;
  DateTime? _lastUpdated;

  RecurringBillsSummary? get summary => _summary;
  bool get isLoading => _isLoading;

  /// Set when the last load failed; [summary] then still holds the bills from
  /// [lastUpdated], if any (UX-01: never shown as "no bills").
  String? get error => _error;
  DateTime? get lastUpdated => _lastUpdated;
  String? get householdId => _householdId;

  /// Initialize provider with active household ID and fetch bills.
  Future<void> init(String householdId) async {
    if (_householdId == householdId && _summary != null) return;
    if (_householdId != householdId) {
      // Never show another household's bills while this one loads.
      _summary = null;
      _lastUpdated = null;
    }
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
      final res = await _api.getRecurringBills(_householdId!);
      _summary = res;
      _isLoading = false;
      _error = null;
      _lastUpdated = DateTime.now();
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
      final row = buildBillPaymentRow(
        householdId: _householdId!,
        userId: _readUserId(),
        bill: bill,
        occurredAt: DateTime.now(),
      );
      final insert = _insertRow;
      if (insert != null) {
        await insert(row);
      } else {
        await supabase.from('transactions').insert(row);
      }
      await fetchBills(silent: true);
      return true;
    } catch (e) {
      debugPrint('[RecurringBillsProvider] Error recording bill payment: $e');
      return false;
    }
  }

  String? _readUserId() {
    final reader = _currentUserId;
    if (reader != null) return reader();
    try {
      return supabase.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  /// The row of a paid bill: a manual entry by the signed-in user, paid by
  /// them for the household, in the columns the settlement engine reads
  /// (FABLE2-APP-06: it used to carry no source or attribution at all).
  static Map<String, dynamic> buildBillPaymentRow({
    required String householdId,
    required String? userId,
    required RecurringBillItem bill,
    required DateTime occurredAt,
  }) {
    final attribution = directInsertAttribution(creatorId: userId);
    return {
      'household_id': householdId,
      if (userId != null && userId.isNotEmpty) 'user_id': userId,
      'merchant': bill.merchant,
      'amount': bill.averageAmount,
      'currency': 'SAR',
      'category_code': bill.categoryCode,
      'sub_category': bill.subCode,
      'timestamp': occurredAt.toUtc().toIso8601String(),
      'source': 'manual',
      ...attribution,
      // A manual row's payer is read from the end of its note.
      'raw_sms': manualAuditNote(
        head: 'Manual: ${bill.merchant}',
        payer: 'me',
        beneficiaryId: attribution['beneficiary_id']!,
        spentBy: attribution['spent_by']!,
      ),
    };
  }

  /// Forgets the household's bills (sign-out).
  void reset() {
    _householdId = null;
    _summary = null;
    _isLoading = false;
    _error = null;
    _lastUpdated = null;
    notifyListeners();
  }

  /// Testing helper
  @visibleForTesting
  void setSummaryForTesting(RecurringBillsSummary summary, {String? householdId}) {
    _summary = summary;
    if (householdId != null) _householdId = householdId;
    notifyListeners();
  }
}
