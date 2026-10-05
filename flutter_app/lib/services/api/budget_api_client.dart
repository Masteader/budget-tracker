import 'base_api_client.dart';

class BudgetApiClient {
  final BaseApiClient baseClient;

  BudgetApiClient({BaseApiClient? baseClient})
      : baseClient = baseClient ?? BaseApiClient();

  Future<Map<String, dynamic>> fetchSalaryCycleForecast({
    required String householdId,
  }) async {
    return baseClient.get(
      '/budgets/salary-cycle-forecast',
      queryParams: {'household_id': householdId},
    );
  }

  Future<List<Map<String, dynamic>>> fetchSalaryCycles({
    required String householdId,
  }) async {
    final res = await baseClient.get(
      '/budgets/cycles',
      queryParams: {'household_id': householdId},
    );
    if (res['cycles'] is List) {
      return (res['cycles'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
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
}
