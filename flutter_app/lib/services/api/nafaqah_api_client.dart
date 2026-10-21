import '../../models/nafaqah.dart';
import 'base_api_client.dart';

/// Family Nafaqah endpoints: the husband-owes-wife ledger and the wife's
/// personal allowance. Every call throws [NafaqahApiException] when the
/// server rejects it, so the UI never reports a write that did not happen.
class NafaqahApiClient {
  final BaseApiClient baseClient;

  NafaqahApiClient({BaseApiClient? baseClient}) : baseClient = baseClient ?? BaseApiClient();

  static Map<String, dynamic> _ok(Map<String, dynamic> res) {
    if (res['status'] == 'error') throw NafaqahApiException.fromResponse(res);
    return res;
  }

  Future<NafaqahSummary> fetchSummary({required String householdId, String? cycleKey}) async {
    final res = await baseClient.get(
      '/households/$householdId/nafaqah',
      queryParams: {if (cycleKey != null && cycleKey.isNotEmpty) 'cycle_key': cycleKey},
    );
    return NafaqahSummary.fromMap(_ok(res));
  }

  Future<NafaqahLedger> fetchLedger({required String householdId, String? wifeUserId}) async {
    final res = await baseClient.get(
      '/households/$householdId/nafaqah/reimbursements',
      queryParams: {if (wifeUserId != null && wifeUserId.isNotEmpty) 'wife_user_id': wifeUserId},
    );
    return NafaqahLedger.fromMap(_ok(res));
  }

  /// Records a partial or full repayment; returns the outstanding balance after it.
  Future<double> recordReimbursement({
    required String householdId,
    required double amount,
    required String paymentMethod,
    String? wifeUserId,
    String? notes,
  }) async {
    final res = await baseClient.post(
      '/households/$householdId/nafaqah/reimbursements',
      {
        'amount': double.parse(amount.toStringAsFixed(2)),
        'payment_method': paymentMethod,
        if (wifeUserId != null && wifeUserId.isNotEmpty) 'wife_user_id': wifeUserId,
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      },
      shouldSign: false,
    );
    return (_ok(res)['outstanding_after'] as num?)?.toDouble() ?? 0.0;
  }

  /// Chooses the household's Nafaqah provider (husband): a non-spouse member.
  /// Household admins only; the server answers 403 for anyone else and 422
  /// for a wife or a non-member.
  Future<NafaqahProviderChange> setProvider({required String householdId, required String userId}) async {
    final res = await baseClient.put(
      '/households/$householdId/nafaqah/provider',
      body: {'user_id': userId},
    );
    return NafaqahProviderChange.fromMap(_ok(res));
  }

  Future<AllowanceStatus> setAllowance({
    required String householdId,
    required double amount,
    String? wifeUserId,
    String? cycleKey,
  }) async {
    final res = await baseClient.put(
      '/households/$householdId/nafaqah/allowance',
      body: {
        'amount': double.parse(amount.toStringAsFixed(2)),
        if (wifeUserId != null && wifeUserId.isNotEmpty) 'wife_user_id': wifeUserId,
        if (cycleKey != null && cycleKey.isNotEmpty) 'cycle_key': cycleKey,
      },
    );
    return AllowanceStatus.fromMap(_ok(res));
  }
}
