import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/widgets/settings/household_management_card.dart';

void main() {
  group('HouseholdManagementCard Widget Tests', () {
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
  });
}
