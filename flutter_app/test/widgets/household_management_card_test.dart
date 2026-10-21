import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/widgets/settings/household_management_card.dart';

import '../support/localized_app.dart';

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
      expect(find.text('Invite pending'), findsOneWidget);
      expect(find.text('•  SAR 1,500/mo'), findsOneWidget);
      expect(find.text('Add Member / Dependent'), findsOneWidget);
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
      expect(find.text('Admin'), findsWidgets);

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

  group('UX-10 / UX-15 / UX-19 / UX-24 / UX-29', () {
    HouseholdManagementCard card({String role = 'admin', List<HouseholdDependent> dependents = const []}) => HouseholdManagementCard(
          householdName: 'بيت أحمد',
          inviteCode: 'RIYADH01',
          userRole: role,
          householdId: 'h1',
          members: const [
            {'email': 'ahmed.abdulrahman.alqahtani@example.com', 'role': 'admin'},
            {'email': 'sara@example.com', 'role': 'member'},
          ],
          dependents: dependents,
          onCopyInviteCode: () {},
          onLeaveHousehold: () {},
          onSwitchHousehold: () {},
          onCreateHousehold: () {},
          onAddDependent: () {},
          onRemoveDependent: (_) {},
        );

    const child = HouseholdDependent(
      id: 'c1', householdId: 'h1', name: 'عبدالله بن أحمد بن عبدالرحمن', relationship: 'child',
      monthlyAllowance: 1500.0, avatarIcon: 'child', createdAt: null,
    );
    const spouse = HouseholdDependent(
      id: 's1', householdId: 'h1', name: 'سارة', relationship: 'spouse',
      monthlyAllowance: 0, avatarIcon: 'wife', createdAt: null,
    );

    testWidgets('roles are translated, children are dependents, not "waiting to join"', (tester) async {
      await tester.pumpWidget(localizedApp(card(dependents: const [child, spouse])));
      await tester.pumpAndSettle();
      expect(find.text('ADMIN'), findsNothing);
      expect(find.text('MEMBER'), findsNothing);
      expect(find.text('مشرف'), findsWidgets);
      expect(find.text('مُعال'), findsOneWidget);
      expect(find.text('بانتظار قبول الدعوة'), findsOneWidget); // the wife's pending invite only
      expect(find.text('•  1,500 ر.س/شهر'), findsOneWidget);
    });

    testWidgets('long names fit a 320 dp phone without overflow', (tester) async {
      tester.view.physicalSize = const Size(320 * 3, 900 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(localizedApp(card(dependents: const [child, spouse])));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('"add member" has a 48 dp target and no doubled "+"', (tester) async {
      await tester.pumpWidget(localizedApp(card()));
      await tester.pumpAndSettle();
      expect(find.text('إضافة عضو / مُعال'), findsOneWidget);
      expect(find.textContaining('+ '), findsNothing);
      final button = find.ancestor(of: find.text('إضافة عضو / مُعال'), matching: find.byType(TextButton));
      expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
    });

    // Coordinator item: the server refuses role invites from non-admins.
    testWidgets('"invite with role" is for admins only', (tester) async {
      await tester.pumpWidget(localizedApp(card(role: 'member'), lang: 'en'));
      await tester.pumpAndSettle();
      expect(find.text('Invite with Role'), findsNothing);
      await tester.pumpWidget(localizedApp(card(), lang: 'en'));
      await tester.pumpAndSettle();
      expect(find.text('Invite with Role'), findsOneWidget);
    });
  });
}
