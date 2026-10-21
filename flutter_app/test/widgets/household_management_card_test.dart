import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/widgets/settings/household_management_card.dart';

void main() {
  group('HouseholdManagementCard Widget Tests', () {
    testWidgets('renders Household & Living Group section with roles and pre-account status', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: HouseholdManagementCard(
                householdName: 'My Household',
                inviteCode: 'ABC12345',
                userRole: 'admin',
                householdId: 'h1',
                members: const [
                  {'email': 'owner@family.com', 'role': 'admin'},
                ],
                dependents: const [
                  HouseholdDependent(
                    id: '1',
                    householdId: 'h1',
                    name: 'Sarah',
                    relationship: 'spouse',
                    monthlyAllowance: 1500.0,
                    avatarIcon: 'wife',
                    createdAt: null,
                  ),
                ],
                onCopyInviteCode: () {},
                onLeaveHousehold: () {},
                onSwitchHousehold: () {},
                onCreateHousehold: () {},
                onAddDependent: () {},
                onRemoveDependent: (_) {},
              ),
            ),
          ),
        ),
      );
      expect(find.text('HOUSEHOLD & LIVING GROUP MEMBERS'), findsOneWidget);
      expect(find.text('Sarah'), findsOneWidget);
      expect(find.text('Wife / Spouse'), findsOneWidget);
      expect(find.text('Pre-Account Profile'), findsOneWidget);
      expect(find.text('•  1500 SAR/mo'), findsOneWidget);
      expect(find.text('+ Add Member / Dependent'), findsOneWidget);
      expect(find.byIcon(Icons.person_add_alt_1_rounded), findsWidgets);
    });

    testWidgets('Renders household details, invite code, and actions', (tester) async {
      bool copied = false;
      bool leaveTapped = false;
      bool switchTapped = false;
      bool createTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: HouseholdManagementCard(
                householdName: 'Riyadh Villa',
                inviteCode: 'RIYADH01',
                userRole: 'admin',
                members: const [
                  {'email': 'owner@example.com', 'role': 'admin'},
                  {'email': 'partner@example.com', 'role': 'member'},
                ],
                onCopyInviteCode: () => copied = true,
                onLeaveHousehold: () => leaveTapped = true,
                onSwitchHousehold: () => switchTapped = true,
                onCreateHousehold: () => createTapped = true,
              ),
            ),
          ),
        ),
      );

      // Verify household name and role badge
      expect(find.text('Riyadh Villa'), findsOneWidget);
      expect(find.text('Admin'), findsOneWidget);

      // Verify invite code
      expect(find.text('RIYADH01'), findsOneWidget);

      // Verify members
      expect(find.text('owner@example.com'), findsOneWidget);
      expect(find.text('partner@example.com'), findsOneWidget);

      // Tap copy code
      final copyBtn = find.widgetWithText(OutlinedButton, 'Copy Code');
      expect(copyBtn, findsOneWidget);
      await tester.tap(copyBtn);
      await tester.pump();
      expect(copied, isTrue);

      // Verify leave, switch, and create buttons
      expect(find.widgetWithText(TextButton, 'Leave Household'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Leave Household'));
      await tester.pump();
      expect(leaveTapped, isTrue);

      expect(find.widgetWithText(OutlinedButton, 'Join with Code'), findsOneWidget);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Join with Code'));
      await tester.pump();
      expect(switchTapped, isTrue);

      expect(find.widgetWithText(ElevatedButton, 'New Household'), findsOneWidget);
      await tester.tap(find.widgetWithText(ElevatedButton, 'New Household'));
      await tester.pump();
      expect(createTapped, isTrue);
    });

    testWidgets('Share invite appears for a readable code and calls back', (tester) async {
      var shared = 0;
      Widget card(String code) => MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: HouseholdManagementCard(
                  householdName: 'Riyadh Villa',
                  inviteCode: code,
                  userRole: 'admin',
                  members: const [
                    {'email': 'owner@example.com', 'role': 'admin'},
                  ],
                  onCopyInviteCode: () {},
                  onShareInvite: () => shared++,
                  onLeaveHousehold: () {},
                  onSwitchHousehold: () {},
                  onCreateHousehold: () {},
                ),
              ),
            ),
          );

      await tester.pumpWidget(card('RIYADH01'));
      expect(find.widgetWithText(OutlinedButton, 'Copy Code'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('share_invite_button')));
      await tester.pump();
      expect(shared, 1);
      expect(find.text('Share invite'), findsOneWidget);

      // Members see a masked code: nothing to share.
      await tester.pumpWidget(card('--------'));
      expect(find.byKey(const ValueKey('share_invite_button')), findsNothing);
    });
  });
}
