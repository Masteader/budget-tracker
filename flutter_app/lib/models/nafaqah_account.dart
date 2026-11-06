/// Helper function to enforce Islamic compliance for wife expenses:
/// Wife personal allowance and wife reimbursable expenses must NEVER be linked
/// to a household shared account. They may only be linked to the wife's OWN
/// non-shared personal account, or the wife account assigned to her (Rule 02
/// §3.2, §3.3, Rule 04 §4).
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
  if (acc == null || acc.isSharedPool) return null;
  // Her own account, or the wife account her husband assigned to her
  // (migration 20261105001300, section 12).
  final hers = acc.isWifeAccount ? acc.assignedWifeId == spouseId : acc.ownerUserId == spouseId;
  return hers ? accountId : null;
}
