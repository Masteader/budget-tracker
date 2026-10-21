import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/services/api/base_api_client.dart' show ApiRequestException;
import 'package:budget_tracker/widgets/settings/role_invite_dialog.dart';
import 'package:budget_tracker/services/household_invite_share.dart' show ShareTextLauncher;
import 'package:flutter/services.dart';

import '../support/localized_app.dart';

void main() {
  testWidgets('RoleInviteDialog allows selecting role and renders options', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RoleInviteDialog(
            householdId: 'hh-role-123',
          ),
        ),
      ),
    );

    expect(find.text('Generate Role Invite'), findsOneWidget);
    expect(find.text('Wife / Spouse'), findsOneWidget);
    expect(find.text('Roommate / Flatmate'), findsOneWidget);
    expect(find.text('Family Dependent'), findsOneWidget);
    expect(find.text('Generate Invite Code'), findsOneWidget);
  });

  testWidgets('RoleInviteDialog generates invite and displays code', (tester) async {
    HouseholdInvite? created;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoleInviteDialog(
            householdId: 'hh-role-123',
            createInvite: (hid, role, {targetMemberId}) async =>
                HouseholdInvite(householdId: hid, inviteCode: 'ABCD1234', role: role),
            onInviteGenerated: (inv) {
              created = inv;
            },
          ),
        ),
      ),
    );

    // Tap Spouse chip
    await tester.tap(find.text('Wife / Spouse'));
    await tester.pumpAndSettle();

    // Tap generate
    await tester.tap(find.text('Generate Invite Code'));
    await tester.pumpAndSettle();

    expect(find.text('Copy Code'), findsOneWidget);
    expect(created, isNotNull);
    expect(created!.role, equals('spouse'));
  });

  // FR-A-11: a refused or failed request must not show an invented code that
  // can never be redeemed.
  testWidgets('RoleInviteDialog shows an error and no code when the server refuses', (tester) async {
    HouseholdInvite? created;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoleInviteDialog(
            householdId: 'hh-role-123',
            createInvite: (hid, role, {targetMemberId}) async =>
                throw const ApiRequestException('Forbidden: Admin access required for this household.', statusCode: 403),
            onInviteGenerated: (inv) => created = inv,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Generate Invite Code'));
    await tester.pumpAndSettle();

    expect(created, isNull);
    expect(find.text('Copy Code'), findsNothing);
    expect(find.textContaining('INV'), findsNothing);
    expect(find.text('Generate Invite Code'), findsOneWidget, reason: 'the user can retry');
  });

  // Backend: an invite whose role does not fit the household type is refused
  // with 409 {"detail": {"code": "invite_role_mismatch"}}.
  testWidgets('an invite role that does not fit the household type is explained', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoleInviteDialog(
            householdId: 'hh-role-123',
            createInvite: (hid, role, {targetMemberId}) async =>
                throw const ApiRequestException('Server response error (409)', statusCode: 409, code: 'invite_role_mismatch'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Generate Invite Code'));
    await tester.pumpAndSettle();
    expect(find.textContaining('does not fit the household type'), findsOneWidget);
  });

  // Coordinator item: share a role-bound invite, naming the role.
  Future<void> generate(WidgetTester tester, {ShareTextLauncher? share, String lang = 'en'}) async {
    await tester.pumpWidget(localizedApp(
      RoleInviteDialog(
        householdId: 'hh-role-123',
        householdName: 'Villa 7',
        createInvite: (hid, role, {targetMemberId}) async => HouseholdInvite(householdId: hid, inviteCode: 'ABCD1234', role: role),
        shareInvite: share,
      ),
      lang: lang,
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('rid_generate')));
    await tester.pumpAndSettle();
  }

  testWidgets('the generated role invite can be shared, naming the role and household', (tester) async {
    String? text;
    String? subject;
    await generate(tester, lang: 'ar', share: (t, s) async {
      text = t;
      subject = s;
    });
    final share = find.byKey(const ValueKey('rid_share_invite'));
    expect(share, findsOneWidget);
    await tester.tap(share);
    await tester.pumpAndSettle();
    expect(text, contains('ABCD1234'));
    expect(text, contains('Villa 7'));
    expect(text, contains('الزوجة'));
    expect(text, contains('الانضمام لمنزل'));
    expect(subject, isNotEmpty);
  });

  testWidgets('without a share target the message is copied instead', (tester) async {
    String? clip;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clip = (call.arguments as Map)['text'] as String?;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await generate(tester, share: (t, s) async => throw Exception('no share target'));
    await tester.tap(find.byKey(const ValueKey('rid_share_invite')));
    await tester.pumpAndSettle();
    expect(clip, contains('ABCD1234'));
    expect(clip, contains('Wife / Spouse'));
    await tester.pump(const Duration(seconds: 5));
  });
}

