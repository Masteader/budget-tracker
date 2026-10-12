import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/installment_plan.dart';
import '../services/api_service.dart';
import '../../main.dart';

/// Centralized reactive state provider for BNPL & installment plans (Tamara, Tabby, Bank).
class InstallmentProvider extends ChangeNotifier {
  String? _householdId;
  List<InstallmentPlan> _plans = [];
  bool _isLoading = false;
  String? _error;

  List<InstallmentPlan> get plans => _plans;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get householdId => _householdId;
  bool get isInitialized => _householdId != null;

  /// Initialize provider with active household ID and fetch plans.
  Future<void> init(String householdId) async {
    final changed = _householdId != householdId;
    _householdId = householdId;
    if (changed || _plans.isEmpty) {
      await fetchPlans();
    }
  }

  /// Re-fetch installment plans from the API or Supabase fallback.
  Future<void> fetchPlans({bool silent = false}) async {
    if (_householdId == null || _householdId!.isEmpty) return;
    if (!silent) {
      _isLoading = true;
      _error = null;
      notifyListeners();
    }

    try {
      final apiPlans = await ApiService.instance.getInstallments(_householdId!);
      if (apiPlans.isNotEmpty) {
        _plans = apiPlans;
        _isLoading = false;
        _error = null;
        notifyListeners();
        return;
      }
    } catch (e) {
      debugPrint('[InstallmentProvider] API getInstallments error: $e');
    }

    // Fallback: Check Supabase transactions for financed purchases
    try {
      final rows = await supabase
          .from('transactions')
          .select('id, amount, merchant, timestamp, raw_sms, category_code')
          .eq('household_id', _householdId!)
          .like('raw_sms', '%Financed via%');

      final result = <InstallmentPlan>[];
      for (final r in (rows as List)) {
        final raw = (r['raw_sms'] as String? ?? '');
        final regex = RegExp(
          r'Financed via\s+([^:]+):\s*Installment\s*(\d+)\s*of\s*(\d+)\.?\s*(?:Full price:\s*(?:SAR\s*)?([0-9,.]+))?',
          caseSensitive: false,
        );
        final match = regex.firstMatch(raw);
        final provider = match?.group(1)?.trim() ??
            (raw.toLowerCase().contains('tamara') ? 'Tamara' : 'Tabby');
        final paid = int.tryParse(match?.group(2) ?? '1') ?? 1;
        final count = int.tryParse(match?.group(3) ?? '4') ?? 4;
        final monthly = (r['amount'] as num?)?.toDouble() ?? 0.0;
        final totalParsed = match?.group(4) != null
            ? double.tryParse(match!.group(4)!.replaceAll(',', ''))
            : null;
        final total = totalParsed ?? (monthly * count);

        result.add(InstallmentPlan(
          id: 'plan-${(r['id'] as String).substring(0, 8)}',
          householdId: _householdId!,
          merchant: r['merchant'] as String? ?? 'Installment Purchase',
          provider: provider,
          totalAmount: total,
          installmentCount: count,
          monthlyAmount: monthly > 0 ? monthly : (total / count),
          paidInstallments: paid,
          dayOfMonth: 27,
          startDate: (r['timestamp'] as String? ??
                  DateTime.now().toIso8601String())
              .substring(0, 10),
          status: paid >= count ? 'COMPLETED' : 'ACTIVE',
          categoryCode: r['category_code'] as String? ?? 'OPEX-SHOPPING',
          originalTransactionId: r['id'] as String?,
          notes: raw,
        ));
      }
      _plans = result;
      _isLoading = false;
      _error = null;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _error = e.toString();
      debugPrint('[InstallmentProvider] Error fetching fallback plans: $e');
      notifyListeners();
    }
  }

  /// Creates a new installment plan and refreshes active plans.
  Future<InstallmentPlan> createPlan(Map<String, dynamic> planData) async {
    try {
      final plan = await ApiService.instance.createInstallmentPlan(planData);
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
      await ApiService.instance.payInstallment(planId);
      await fetchPlans(silent: true);
      return true;
    } catch (e) {
      debugPrint('[InstallmentProvider] Error recording installment payment: $e');
      return false;
    }
  }

  /// Testing helper
  @visibleForTesting
  void setPlansForTesting(List<InstallmentPlan> testPlans, {String? householdId}) {
    _plans = testPlans;
    if (householdId != null) _householdId = householdId;
    notifyListeners();
  }
}
