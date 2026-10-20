import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/recurring_bill.dart';
import '../../models/installment_plan.dart';
import '../../models/models.dart';
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

  Future<double> fetchHouseholdIncome({
    required String householdId,
  }) async {
    final res = await baseClient.get('/households/$householdId/income');
    return (res['monthly_income'] as num?)?.toDouble() ?? 0.0;
  }

  Future<bool> updateHouseholdIncome({
    required String householdId,
    required double monthlyIncome,
  }) async {
    final res = await baseClient.put(
      '/households/$householdId/income',
      body: {'monthly_income': monthlyIncome},
    );
    return res['status'] == 'success';
  }

  Future<String> fetchHouseholdRolloverRule({
    required String householdId,
  }) async {
    final res = await baseClient.get('/households/$householdId/rollover-rule');
    return res['rollover_rule'] as String? ?? 'send_to_savings';
  }

  Future<bool> updateHouseholdRolloverRule({
    required String householdId,
    required String rolloverRule,
  }) async {
    final res = await baseClient.put(
      '/households/$householdId/rollover-rule',
      body: {'rollover_rule': rolloverRule},
    );
    return res['status'] == 'success';
  }

  Future<Map<String, dynamic>> fetchHouseholdSavingsSummary({
    required String householdId,
  }) async {
    return baseClient.get('/households/$householdId/savings-summary');
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

  Future<SettlementV2Summary> fetchSettlementV2({
    required String householdId,
    String? cycleStart,
  }) async {
    final params = <String, dynamic>{};
    if (cycleStart != null && cycleStart.isNotEmpty) {
      params['cycle_start'] = cycleStart;
    }
    final res = await baseClient.get(
      '/households/$householdId/settlement-v2',
      queryParams: params,
    );
    return SettlementV2Summary.fromMap(res);
  }

  Future<HouseholdInvite> createRoleInvite({
    required String householdId,
    required String role,
    String? targetMemberId,
  }) async {
    final res = await baseClient.post(
      '/households/$householdId/invites',
      {
        'role': role,
        if (targetMemberId != null && targetMemberId.isNotEmpty) 'target_member_id': targetMemberId,
      },
    );
    // FR-A-11: never invent a code locally; a code the server did not store
    // can never be redeemed. A refusal (403: admins only) or a network
    // failure throws [ApiRequestException].
    ApiRequestException.check(res);
    final code = res['invite_code'];
    if (code is! String || code.isEmpty) {
      throw const ApiRequestException('The server did not return an invite code.');
    }
    return HouseholdInvite.fromMap(res);
  }

  Future<HouseholdInvite> inspectInviteCode({
    required String code,
  }) async {
    final res = await baseClient.get('/households/invites/$code');
    return HouseholdInvite.fromMap(res);
  }

  Future<Map<String, dynamic>> claimMemberProfile({
    required String inviteCode,
    required String userId,
  }) async {
    return baseClient.post(
      '/households/invites/$inviteCode/claim',
      {'user_id': userId},
    );
  }

  Future<Map<String, dynamic>> recordReimbursementPayment({
    required ReimbursementRecordRequest request,
  }) async {
    return baseClient.post(
      '/households/${request.householdId}/reimbursements',
      request.toMap(),
    );
  }

  Future<List<HouseholdDependent>> fetchHouseholdDependents({
    required String householdId,
  }) async {
    final res = await baseClient.get('/households/$householdId/dependents');
    final list = res['dependents'] as List? ?? [];
    return list
        .map((e) => HouseholdDependent.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<HouseholdDependent?> createHouseholdDependent({
    required String householdId,
    required String name,
    String? avatarIcon,
    String? relationship,
    double? monthlyAllowance,
  }) async {
    final res = await baseClient.post(
      '/households/$householdId/dependents',
      {
        'name': name,
        if (avatarIcon != null) 'avatar_icon': avatarIcon,
        if (relationship != null) 'relationship': relationship,
        if (monthlyAllowance != null) 'monthly_allowance': monthlyAllowance,
      },
    );
    if (res['dependent'] != null) {
      return HouseholdDependent.fromMap(Map<String, dynamic>.from(res['dependent'] as Map));
    }
    return null;
  }

  Future<bool> deleteHouseholdDependent({
    required String householdId,
    required String dependentId,
  }) async {
    final res = await baseClient.delete(
      '/households/$householdId/dependents/$dependentId',
    );
    return res['status'] == 'success';
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

  /// Downloads the monthly statement PDF with the user's JWT (MOB-26).
  ///
  /// The backend has no signed-URL endpoint, so the bytes are fetched through
  /// the authenticated client instead of handing a bare URL to a browser.
  /// Throws [ApiDownloadException] on failure or when the body is not a PDF.
  Future<ApiBinaryResponse> downloadStatementPdf(String householdId, {String? cycleKey}) async {
    final res = await baseClient.getBinary(
      '/reports/statement-pdf',
      queryParams: {
        'household_id': householdId,
        if (cycleKey != null && cycleKey.isNotEmpty) 'cycle_key': cycleKey,
      },
      accept: 'application/pdf',
    );
    final bytes = res.bytes;
    final isPdf = bytes.length >= 4 &&
        bytes[0] == 0x25 && // %
        bytes[1] == 0x50 && // P
        bytes[2] == 0x44 && // D
        bytes[3] == 0x46; // F
    if (!isPdf) {
      throw const ApiDownloadException('The server did not return a PDF document.');
    }
    return res;
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
    return baseClient.delete(
      '/budgets/categories/${Uri.encodeComponent(categoryCode)}',
      queryParams: {'household_id': householdId},
      timeout: const Duration(seconds: 8),
    );
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
    return baseClient.patch(
      '/budgets/sub-categories',
      body: {
        'parent_code': parentCode,
        'sub_code': subCode,
        'name_en': nameEn,
        if (nameAr != null && nameAr.isNotEmpty) 'name_ar': nameAr,
      },
      timeout: const Duration(seconds: 10),
    );
  }

  Future<Map<String, dynamic>> removeSubCategory({
    required String householdId,
    required String parentCode,
    required String subCode,
    String? cycleKey,
  }) async {
    return baseClient.delete(
      '/budgets/sub-categories',
      queryParams: {
        'household_id': householdId,
        'parent_code': parentCode,
        'sub_code': subCode,
        if (cycleKey != null && cycleKey.isNotEmpty) 'cycle_key': cycleKey,
      },
      timeout: const Duration(seconds: 10),
    );
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

  /// Throws [ApiRequestException] when the server refuses the plan (403 for
  /// another member's transaction, 400, 5xx) or cannot be reached, so callers
  /// never act on a plan that was not created (FR-A-02).
  Future<InstallmentPlan> createInstallmentPlan(Map<String, dynamic> planData) async {
    final res = ApiRequestException.check(await baseClient.post('/budgets/installments', planData));
    final plan = InstallmentPlan.fromJson(res);
    if (plan.id.isEmpty) {
      throw const ApiRequestException('The server did not return the created plan.');
    }
    return plan;
  }

  /// The updated plan, or null when the payment was not recorded (FR-A-03).
  Future<InstallmentPlan?> payInstallment(String planId) async {
    try {
      final res = await baseClient.post('/budgets/installments/$planId/pay', {});
      if (res['status'] == 'error') return null;
      return InstallmentPlan.fromJson(res);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, List<CategoryItem>>> fetchHouseholdCategories({
    required String householdId,
  }) async {
    try {
      final res = await baseClient.get('/households/$householdId/categories');
      final activeList = (res['active'] as List? ?? [])
          .map((e) => CategoryItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      final inactiveList = (res['inactive'] as List? ?? [])
          .map((e) => CategoryItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      return {'active': activeList, 'inactive': inactiveList};
    } catch (_) {
      return {'active': [], 'inactive': []};
    }
  }

  Future<bool> toggleCategoryStatus({
    required String householdId,
    required String categoryCode,
    required bool isActive,
  }) async {
    try {
      final res = await baseClient.post('/households/$householdId/categories/toggle', {
        'category_code': categoryCode,
        'is_active': isActive,
      });
      return res['status'] == 'success';
    } catch (_) {
      return false;
    }
  }

  Future<bool> createCustomCategory({
    required String householdId,
    required String code,
    required String category,
    List<String> keywords = const [],
    bool isFlexible = false,
    double allocatedAmount = 0.0,
  }) async {
    try {
      final res = await baseClient.post('/households/$householdId/categories/custom', {
        'code': code,
        'category': category,
        'keywords': keywords,
        'is_flexible': isFlexible,
        'allocated_amount': allocatedAmount,
      });
      return res['status'] == 'success';
    } catch (_) {
      return false;
    }
  }

  Future<List<HouseholdMembership>> getUserHouseholds() async {
    try {
      final client = Supabase.instance.client;
      final res = await client.rpc('get_user_households');
      if (res is List) {
        return res
            .map((e) => HouseholdMembership.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList();
      }
    } catch (_) {
      try {
        final client = Supabase.instance.client;
        final uid = client.auth.currentUser?.id;
        if (uid != null) {
          final res = await client
              .from('household_memberships')
              .select('household_id, role, households(name)')
              .eq('user_id', uid);
          final activeHid = (await client
              .from('users')
              .select('household_id')
              .eq('id', uid)
              .maybeSingle())?['household_id'];
          return res.map((item) {
            final m = Map<String, dynamic>.from(item);
            final hh = Map<String, dynamic>.from((m['households'] as Map?) ?? {});
            final hid = m['household_id'] as String? ?? '';
            return HouseholdMembership(
              householdId: hid,
              householdName: hh['name'] as String? ?? 'Household',
              // The invite code is only ever served by get_user_households()
              // (admins only); never read it from the households table (DB-17).
              inviteCode: '',
              role: m['role'] as String? ?? 'member',
              isActive: hid == activeHid,
            );
          }).toList();
        }
      } catch (_) {}
    }
    return [];
  }

  /// Name and (for admins only) invite code of one of the caller's households,
  /// served by the `get_user_households()` RPC.
  Future<HouseholdMembership?> fetchHouseholdMembership(String householdId) async {
    final memberships = await getUserHouseholds();
    for (final m in memberships) {
      if (m.householdId == householdId) return m;
    }
    return null;
  }

  Future<bool> switchActiveHousehold(String householdId) async {
    try {
      final client = Supabase.instance.client;
      final res = await client.rpc(
        'switch_active_household',
        params: {'p_household_id': householdId},
      );
      if (res is Map && res['success'] == true) {
        return true;
      }
    } catch (_) {}
    return false;
  }
}
