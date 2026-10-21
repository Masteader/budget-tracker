/// "Share invite": a message in the user's language with the household name,
/// the join code and how to use it, handed to the system share sheet
/// (WhatsApp, SMS, e-mail...). The second member is the whole point of a
/// family or roommate household, so inviting must not require retyping.
library;

import 'package:share_plus/share_plus.dart';

import '../l10n/app_localizations.dart';

/// Whether [code] is a real join code (8–16 letters/digits), not the
/// placeholder shown to members who cannot read it.
bool isShareableInviteCode(String? code) =>
    code != null && RegExp(r'^[A-Za-z0-9]{8,16}$').hasMatch(code.trim());

/// The invite message: household name, the code and the steps to join.
String inviteShareText(AppLocalizations l, {required String householdName, required String code}) {
  final name = householdName.trim().isEmpty ? l.get('set_my_household') : householdName.trim();
  return l.format('invite_share_text', {'household': name, 'code': code.trim()});
}

typedef ShareTextLauncher = Future<void> Function(String text, String subject);

Future<void> _systemShare(String text, String subject) async {
  await SharePlus.instance.share(ShareParams(text: text, subject: subject));
}

/// Opens the share sheet with the invite (injectable for tests).
Future<void> shareHouseholdInvite(
  AppLocalizations l, {
  required String householdName,
  required String code,
  ShareTextLauncher launcher = _systemShare,
}) {
  return launcher(
    inviteShareText(l, householdName: householdName, code: code),
    l.get('invite_share_subject'),
  );
}

/// The role a role-bound invite joins as ("الزوجة", "Roommate / Flatmate", ...).
String roleInviteLabel(AppLocalizations l, String role) => l.get(switch (role) {
      'spouse' || 'wife' => 'wife_spouse_title',
      'peer' || 'roommate' => 'invite_role_peer',
      _ => 'invite_role_family',
    });

/// The message of a role-bound invite: household, the role the code joins
/// as, the code and the steps to join.
String roleInviteShareText(
  AppLocalizations l, {
  required String householdName,
  required String code,
  required String role,
}) {
  final name = householdName.trim().isEmpty ? l.get('set_my_household') : householdName.trim();
  return l.format('role_invite_share_text', {'household': name, 'code': code.trim(), 'role': roleInviteLabel(l, role)});
}

/// Opens the share sheet with a role-bound invite (injectable for tests).
Future<void> shareRoleInvite(
  AppLocalizations l, {
  required String householdName,
  required String code,
  required String role,
  ShareTextLauncher launcher = _systemShare,
}) {
  return launcher(
    roleInviteShareText(l, householdName: householdName, code: code, role: role),
    l.get('invite_share_subject'),
  );
}
