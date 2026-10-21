import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/services/api/base_api_client.dart' show ApiRequestException;
import 'package:budget_tracker/widgets/settings/role_invite_dialog.dart';

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
}
