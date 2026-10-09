import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../models/recurring_bill.dart';
import '../../models/installment_plan.dart';
import 'base_api_client.dart';

class BudgetApiClient {
  final BaseApiClient baseClient;

  BudgetApiClient({BaseApiClient? baseClient})
      : baseClient = baseClient ?? BaseApiClient();

  Future<RecurringBillsSummary> fetchRecurringBills({
    required String householdId,
    String? asOfDate,
  }) async {
    final params = <String, dynamic>{'household_id': householdId};
    if (asOfDate != null && asOfDate.isNotEmpty) {
      params['as_of_date'] = asOfDate;
    }
    final res = await baseClient.get('/budgets/recurring-bills', queryParams: params);
    return RecurringBillsSummary.fromMap(res);
  }

  Future<List<RecurringBillCandidate>> fetchRecurringBillCandidates({
    required String householdId,
  }) async {
    final res = await baseClient.get(
      '/budgets/recurring-bills/candidates',
      queryParams: {'household_id': householdId},
    );
    final list = res['candidates'] as List? ?? [];
    return list
        .map((e) => RecurringBillCandidate.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> toggleRecurringBill({
    required String householdId,
    required String categoryCode,
    required String subCode,
    required bool isRecurring,
    int? dueDay,
    String? customName,
  }) async {
    await baseClient.post(
      '/budgets/recurring-bills/toggle',
      {
        'household_id': householdId,
        'category_code': categoryCode,
        'sub_code': subCode,
        'is_recurring': isRecurring,
        if (dueDay != null) 'due_day': dueDay,
        if (customName != null) 'custom_name': customName,
      },
    );
  }

  Future<Map<String, dynamic>> fetchSalaryCycleForecast({
    required String householdId,
    int? paydayDay,
  }) async {
    final params = <String, dynamic>{'household_id': householdId};
    if (paydayDay != null) {
      params['payday_day'] = paydayDay;
    }
    return baseClient.get(
      '/budgets/salary-cycle-forecast',
      queryParams: params,
    );
  }

  Future<List<Map<String, dynamic>>> fetchSalaryCycles({
    required String householdId,
    int? paydayDay,
  }) async {
    final params = <String, dynamic>{'household_id': householdId};
    if (paydayDay != null) {
      params['payday_day'] = paydayDay;
    }
    final res = await baseClient.get(
      '/budgets/cycles',
      queryParams: params,
    );
    if (res['cycles'] is List) {
      return (res['cycles'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  Future<int> fetchHouseholdPayday({
    required String householdId,
  }) async {
    final res = await baseClient.get('/households/$householdId/payday');
    return (res['payday_day'] as num?)?.toInt() ?? 27;
  }

  Future<bool> updateHouseholdPayday({
    required String householdId,
    required int paydayDay,
  }) async {
    final res = await baseClient.put(
      '/households/$householdId/payday',
      body: {'payday_day': paydayDay},
    );
    return res['status'] == 'success';
  }

  Future<Map<String, dynamic>> fetchPartnerSettlement({
    required String householdId,
    double splitRatio = 0.5,
  }) async {
    return baseClient.get(
      '/households/$householdId/settlement',
      queryParams: {'split_ratio': splitRatio},
    );
  }

  Future<Map<String, dynamic>> fetchBudgetBreakdown({
    required String householdId,
    String? cycleKey,
  }) async {
    final params = <String, dynamic>{'household_id': householdId};
    if (cycleKey != null && cycleKey.isNotEmpty) {
      params['cycle_key'] = cycleKey;
    }
    return baseClient.get('/budgets/breakdown', queryParams: params);
  }

  Future<Map<String, dynamic>> simulateAffordability({
    required String householdId,
    required double targetAmount,
    String itemName = 'Item',
    String? categoryCode,
  }) async {
    return baseClient.post(
      '/budgets/simulate-affordability',
      {
        'household_id': householdId,
        'target_amount': targetAmount,
        'item_name': itemName,
        if (categoryCode != null) 'category_code': categoryCode,
      },
      shouldSign: false,
      timeout: const Duration(seconds: 8),
    );
  }

  Future<List<Map<String, dynamic>>> getGroceryPriceHistory(
    String householdId, {
    String? itemFilter,
  }) async {
    final res = await baseClient.get(
      '/analytics/price-history',
      queryParams: {
        'household_id': householdId,
        if (itemFilter != null && itemFilter.isNotEmpty) 'item_filter': itemFilter,
      },
      timeout: const Duration(seconds: 8),
    );
    if (res['items'] is List) {
      return (res['items'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  Future<Map<String, dynamic>> optimizeShoppingBasket(
    String householdId,
    List<String> items,
  ) async {
    final res = await baseClient.post(
      '/analytics/shopping-basket-optimize',
      {
        'household_id': householdId,
        'items': items,
      },
      shouldSign: false,
      timeout: const Duration(seconds: 10),
    );
    return res;
  }

  String getStatementPdfUrl(String householdId, {String? cycleKey}) {
    final query = cycleKey != null && cycleKey.isNotEmpty
        ? '?household_id=$householdId&cycle_key=$cycleKey'
        : '?household_id=$householdId';
    return '${baseClient.baseUrl}/reports/statement-pdf$query';
  }

  Future<Map<String, dynamic>> addBudgetCategory({
    required String householdId,
    required String code,
    required String category,
    required double allocatedAmount,
    bool isFlexible = true,
    List<String> keywords = const [],
  }) async {
    return baseClient.post(
      '/budgets/categories',
      {
        'household_id': householdId,
        'code': code,
        'category': category,
        'allocated_amount': allocatedAmount,
        'is_flexible': isFlexible,
        'keywords': keywords,
      },
      shouldSign: false,
      timeout: const Duration(seconds: 8),
    );
  }

  Future<Map<String, dynamic>> archiveBudgetCategory(
    String householdId,
    String categoryCode,
  ) async {
    try {
      final uri = Uri.parse('${baseClient.baseUrl}/budgets/categories/$categoryCode?household_id=$householdId');
      final response = await http
          .delete(uri, headers: baseClient.buildHeaders())
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return {'status': 'error', 'message': 'HTTP ${response.statusCode}'};
    } catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> saveSubAllocations({
    required String householdId,
    required String categoryCode,
    required Map<String, double> subAllocations,
    String? cycleKey,
  }) async {
    return baseClient.post(
      '/budgets/sub-allocations',
      {
        'household_id': householdId,
        'category_code': categoryCode,
        'sub_allocations': subAllocations,
        if (cycleKey != null && cycleKey.isNotEmpty) 'cycle_key': cycleKey,
      },
      shouldSign: false,
      timeout: const Duration(seconds: 10),
    );
  }

  Future<Map<String, dynamic>> addSubCategory({
    required String householdId,
    required String parentCode,
    required String nameEn,
    required double allocatedAmount,
    String? subCode,
    String? cycleKey,
  }) async {
    return baseClient.post(
      '/budgets/sub-categories',
      {
        'household_id': householdId,
        'parent_code': parentCode,
        'name_en': nameEn,
        'allocated_amount': allocatedAmount,
        if (subCode != null && subCode.isNotEmpty) 'sub_code': subCode,
        if (cycleKey != null && cycleKey.isNotEmpty) 'cycle_key': cycleKey,
      },
      shouldSign: false,
      timeout: const Duration(seconds: 10),
    );
  }

  Future<List<Map<String, dynamic>>> getSubCategories(String parentCode) async {
    final res = await baseClient.get(
      '/budgets/sub-categories',
      queryParams: {'parent_code': parentCode},
      timeout: const Duration(seconds: 10),
    );
    if (res['status'] == 'success' && res['sub_categories'] is List) {
      return (res['sub_categories'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  Future<Map<String, dynamic>> renameSubCategory({
    required String parentCode,
    required String subCode,
    required String nameEn,
    String? nameAr,
  }) async {
    final payload = jsonEncode({
      'parent_code': parentCode,
      'sub_code': subCode,
      'name_en': nameEn,
      if (nameAr != null && nameAr.isNotEmpty) 'name_ar': nameAr,
    });

    try {
      final response = await http
          .patch(
            Uri.parse('${baseClient.baseUrl}/budgets/sub-categories'),
            headers: baseClient.buildHeaders(),
            body: payload,
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return {'status': 'error', 'message': 'HTTP ${response.statusCode}: ${response.body}'};
    } catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> removeSubCategory({
    required String householdId,
    required String parentCode,
    required String subCode,
    String? cycleKey,
  }) async {
    try {
      final queryParams = {
        'household_id': householdId,
        'parent_code': parentCode,
        'sub_code': subCode,
        if (cycleKey != null && cycleKey.isNotEmpty) 'cycle_key': cycleKey,
      };
      final uri = Uri.parse('${baseClient.baseUrl}/budgets/sub-categories')
          .replace(queryParameters: queryParams);
      final response = await http
          .delete(uri, headers: baseClient.buildHeaders())
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return {'status': 'error', 'message': 'HTTP ${response.statusCode}: ${response.body}'};
    } catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }

  Future<List<InstallmentPlan>> fetchInstallments({required String householdId}) async {
    try {
      final res = await baseClient.get(
        '/budgets/installments',
        queryParams: {'household_id': householdId},
      );
      if (res['plans'] is List) {
        return (res['plans'] as List)
            .map((e) => InstallmentPlan.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<InstallmentPlan> createInstallmentPlan(Map<String, dynamic> planData) async {
    final res = await baseClient.post('/budgets/installments', planData);
    return InstallmentPlan.fromJson(res);
  }

  Future<InstallmentPlan?> payInstallment(String planId) async {
    try {
      final res = await baseClient.post('/budgets/installments/$planId/pay', {});
      return InstallmentPlan.fromJson(res);
    } catch (_) {
      return null;
    }
  }
}
