/// Builds the `public.transactions` row for a manually entered expense.
///
/// The same row is used for the online insert and, unchanged, for the offline
/// queue replay (`transaction_insert`), so both paths store identical data:
/// * `id` is generated on the device, which makes a replay after a timed-out
///   insert collide on the primary key instead of booking the expense twice;
/// * `timestamp` is an explicit UTC instant (a bare local ISO string would be
///   read by Postgres as UTC and shift Riyadh evenings into the next day and,
///   on the 26th, into the next salary cycle);
/// * the payer is kept in the `raw_sms` audit trail (`PaidBy:` tag) that the
///   app and the settlement engine already parse, because `transactions` has
///   no `paid_by` column.
library;

Map<String, dynamic> buildManualExpenseRow({
  required String id,
  required String householdId,
  required String? userId,
  required double amount,
  required String merchant,
  required String? categoryCode,
  required String spentBy,
  required String paidBy,
  required String beneficiaryType,
  required String beneficiaryId,
  required String? accountId,
  required DateTime occurredAt,
  String? nafaqahClass,
  String? nafaqahSpouseId,
}) {
  final auditPayer = manualPayerAuditTag(paidBy);
  return {
    'id': id,
    'household_id': householdId,
    if (userId != null && userId.isNotEmpty) 'user_id': userId,
    'amount': amount,
    'currency': 'SAR',
    'merchant': merchant,
    'category_code': categoryCode,
    'spent_by': spentBy,
    'beneficiary_type': beneficiaryType,
    'beneficiary_id': beneficiaryId,
    'account_id': accountId,
    'source': 'manual',
    'timestamp': occurredAt.toUtc().toIso8601String(),
    'raw_sms': 'Manual: $merchant | PaidBy: $auditPayer | Beneficiary: $beneficiaryId | SpentBy: $spentBy',
    'items': [
      {'name': merchant, 'price': amount, 'quantity': 1}
    ],
    // Family (Nafaqah): wife_reimbursable = the husband owes her, wife_personal
    // = charged to her allowance. Both columns are set together or not at all.
    if (nafaqahClass != null && nafaqahSpouseId != null && nafaqahSpouseId.isNotEmpty) ...{
      'nafaqah_class': nafaqahClass,
      'nafaqah_spouse_id': nafaqahSpouseId,
    },
  };
}

/// Maps the manual-entry payer to the `PaidBy:` vocabulary (`me`/`partner`)
/// understood by [Transaction.fromMap] and the settlement engine. In family
/// mode the wife is the partner; a roommate payer keeps their member id.
String manualPayerAuditTag(String paidBy) {
  final v = paidBy.trim().toLowerCase();
  if (v == 'wife' || v == 'husband') return 'partner';
  return paidBy.trim();
}
