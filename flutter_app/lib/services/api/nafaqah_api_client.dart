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

  /// The husband (or an admin) records a partial or full repayment, paid from
  /// [accountId] into her wife account [wifeAccountId] (migration
  /// 20261105001300, section 12): his account goes down and hers up by the
  /// amount, her own accounts never change and no budget moves. Returns the
  /// outstanding balance after it. [requestKey] is made once per sheet: a
  /// retry is recorded once.
  Future<double> recordReimbursement({
    required String householdId,
    required double amount,
    required String paymentMethod,
    required String accountId,
    required String requestKey,
    String? wifeAccountId,
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
        'account_id': accountId,
        'request_key': requestKey,
        if (wifeAccountId != null && wifeAccountId.isNotEmpty) 'wife_account_id': wifeAccountId,
      },
      shouldSign: false,
    );
    return (_ok(res)['outstanding_after'] as num?)?.toDouble() ?? 0.0;
  }

  /// Her husband makes her a wife account (his, in SAR, empty, assigned to
  /// [wifeUserId]); returns its id.
  Future<String> createWifeAccount({
    required String householdId,
    required String wifeUserId,
    required String name,
  }) async {
    final res = await baseClient.post(
      '/households/$householdId/nafaqah/wife-accounts',
      {'wife_user_id': wifeUserId, 'name': name.trim()},
      shouldSign: false,
    );
    return _ok(res)['id']?.toString() ?? '';
  }

  /// Reverses a tracked repayment in full: the money goes back to the account
  /// it left and the amount is owed again. Returns what is owed after it.
  Future<double> reverseReimbursement({
    required String householdId,
    required String reimbursementId,
    required String requestKey,
  }) async {
    final res = await baseClient.post(
      '/households/$householdId/nafaqah/reimbursements/${Uri.encodeComponent(reimbursementId)}/reversal',
      {'request_key': requestKey},
      shouldSign: false,
    );
    return (_ok(res)['outstanding_after'] as num?)?.toDouble() ?? 0.0;
  }

  static String _requestsPath(String householdId) => '/households/$householdId/nafaqah/reimbursement-requests';

  /// The wife marks what she received into her wife account [wifeAccountId]:
  /// a pending request. Nothing moves until the husband or an admin approves it.
  Future<void> createReimbursementRequest({
    required String householdId,
    required double amount,
    required String paymentMethod,
    required String requestKey,
    String? wifeAccountId,
  }) async {
    _ok(await baseClient.post(
      _requestsPath(householdId),
      {
        'amount': double.parse(amount.toStringAsFixed(2)),
        'payment_method': paymentMethod,
        'request_key': requestKey,
        if (wifeAccountId != null && wifeAccountId.isNotEmpty) 'wife_account_id': wifeAccountId,
      },
      shouldSign: false,
    ));
  }

  /// She cancels her own pending request.
  Future<void> cancelReimbursementRequest({required String householdId, required String requestId}) async {
    _ok(await baseClient.post('${_requestsPath(householdId)}/${Uri.encodeComponent(requestId)}/cancel', const {},
        shouldSign: false));
  }

  /// The husband or an admin approves her request from [accountId]: exactly
  /// the requested amount, into the wife account she named, or
  /// [wifeAccountId], another of hers. Returns what is owed after it.
  Future<double> approveReimbursementRequest({
    required String householdId,
    required String requestId,
    required String accountId,
    required String requestKey,
    String? wifeAccountId,
  }) async {
    final res = await baseClient.post(
      '${_requestsPath(householdId)}/${Uri.encodeComponent(requestId)}/approve',
      {
        'account_id': accountId,
        'request_key': requestKey,
        if (wifeAccountId != null && wifeAccountId.isNotEmpty) 'wife_account_id': wifeAccountId,
      },
      shouldSign: false,
    );
    return (_ok(res)['outstanding_after'] as num?)?.toDouble() ?? 0.0;
  }

  /// The husband or an admin declines her request, with an optional reason.
  Future<void> declineReimbursementRequest({
    required String householdId,
    required String requestId,
    String? reason,
  }) async {
    _ok(await baseClient.post(
      '${_requestsPath(householdId)}/${Uri.encodeComponent(requestId)}/decline',
      {if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim()},
      shouldSign: false,
    ));
  }

  static String _debtPath(String householdId, String debtId) =>
      '/households/$householdId/nafaqah/former-member-debts/${Uri.encodeComponent(debtId)}';

  /// Records a payment of what was owed to a former member: an amount, a method
  /// and [accountId], the account it is paid from (its balance goes down). No
  /// budget changes. [requestKey] is made once per sheet and reused on every
  /// retry, so the server records it once.
  Future<FormerMemberDebtReceipt> recordFormerMemberDebtPayment({
    required String householdId,
    required String debtId,
    required double amount,
    required String paymentMethod,
    required String requestKey,
    required String accountId,
  }) async {
    final res = await baseClient.post(
      '${_debtPath(householdId, debtId)}/payments',
      {
        'amount': double.parse(amount.toStringAsFixed(2)),
        'payment_method': paymentMethod,
        'request_key': requestKey,
        'account_id': accountId,
      },
      shouldSign: false,
    );
    return FormerMemberDebtReceipt.fromMap(_ok(res));
  }

  /// Reverses a tracked payment of a former member's record: the money goes
  /// back to its account and the amount back to what remains (a settled record
  /// opens again).
  Future<FormerMemberDebtReceipt> reverseFormerMemberDebtPayment({
    required String householdId,
    required String debtId,
    required String eventId,
    required String requestKey,
  }) async {
    final res = await baseClient.post(
      '${_debtPath(householdId, debtId)}/payments/${Uri.encodeComponent(eventId)}/reversal',
      {'request_key': requestKey},
      shouldSign: false,
    );
    return FormerMemberDebtReceipt.fromMap(_ok(res));
  }

  /// Records that the former member waived what remained (إبراء): the record
  /// closes as waived and no money moves.
  Future<FormerMemberDebtReceipt> waiveFormerMemberDebt({
    required String householdId,
    required String debtId,
    required String requestKey,
  }) async {
    final res = await baseClient.post(
      '${_debtPath(householdId, debtId)}/waiver',
      {'request_key': requestKey},
      shouldSign: false,
    );
    return FormerMemberDebtReceipt.fromMap(_ok(res));
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
