/// Helper function to enforce Islamic compliance for wife expenses:
/// Wife personal allowance and wife reimbursable expenses must NEVER be linked
/// to a household shared account. They may only be linked to the wife's OWN
/// non-shared personal account (Rule 02 §3.2, §3.3, Rule 04 §4).
library;

import 'account.dart';

const String kWifePersonal = 'wife_personal';
const String kWifeReimbursable = 'wife_reimbursable';

String? accountForNafaqahClass(
  String? cls,
  String? accountId, {
  List<Account> accounts = const [],
  String? spouseId,
}) {
  if (cls != kWifePersonal && cls != kWifeReimbursable) return accountId;
  final acc = accounts.where((a) => a.id == accountId).firstOrNull;
  return (acc != null && !acc.isSharedPool && acc.ownerUserId == spouseId) ? accountId : null;
}
