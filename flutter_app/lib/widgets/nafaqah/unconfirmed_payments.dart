import 'package:flutter/foundation.dart';

import '../../models/account.dart';

/// What a sheet that can move money sent when its answer was lost (review
/// R2-02).
///
/// While the sheet is open it keeps its request key and what it sent, and
/// offers only to send exactly that again (review R1-06): the server records a
/// key once and answers a retry as the first time. Closing the sheet must not
/// forget them. Reopened with a fresh key, the same payment could be recorded a
/// second time if the first did go through. So they stay here, one entry per
/// slot (a wife's repayment, her request, the approval of one request, one
/// former member's record), until a definite answer, and the sheet reopens
/// holding them. Kept for the app
/// session: after a restart the card shows what the server stored.
class UnconfirmedPayments {
  UnconfirmedPayments._();

  static final Map<String, UnconfirmedPayment> _held = {};

  /// A repayment to [wifeUserId] in [householdId].
  static String repaymentSlot(String householdId, String wifeUserId) => 'repay|$householdId|$wifeUserId';

  /// [wifeUserId]'s own request ("I received X") in [householdId].
  static String requestSlot(String householdId, String wifeUserId) => 'ask|$householdId|$wifeUserId';

  /// The approval of her request [requestId] in [householdId] (review R3-02).
  static String approvalSlot(String householdId, String requestId) => 'approve|$householdId|$requestId';

  /// A payment of the former member's record [debtId] in [householdId].
  static String formerMemberPaymentSlot(String householdId, String debtId) => 'fmd|$householdId|$debtId';

  /// What [slot] sent without an answer, if anything.
  static UnconfirmedPayment? of(String slot) => _held[slot];

  /// The answer to [payment] was lost: keep it until a definite one.
  static void hold(String slot, UnconfirmedPayment payment) => _held[slot] = payment;

  /// A definite answer came (recorded, or refused): a new key is safe again.
  static void settle(String slot) => _held.remove(slot);

  @visibleForTesting
  static void reset() => _held.clear();
}

/// One call whose answer was lost: its key and exactly what it sent.
@immutable
class UnconfirmedPayment {
  final String requestKey;
  final double amount;
  final String method;

  /// The account it was paid from; null for her request, which moves nothing.
  final Account? account;

  /// The wife account it credits (a repayment, an approval) or she named (her
  /// request); null for a former member's payment.
  final String? wifeAccountId;

  const UnconfirmedPayment({
    required this.requestKey,
    required this.amount,
    required this.method,
    this.account,
    this.wifeAccountId,
  });
}
