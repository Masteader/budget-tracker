import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/models/models.dart';
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
}
