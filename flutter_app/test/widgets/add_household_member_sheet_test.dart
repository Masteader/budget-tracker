import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/widgets/settings/add_household_member_sheet.dart';

void main() {
  group('AddHouseholdMemberSheet Widget Tests', () {
    testWidgets('renders all fields and role chips', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AddHouseholdMemberSheet(),
          ),
        ),
      );

      expect(find.text('Add Household Member'), findsOneWidget);
      expect(find.byKey(const Key('add_member_name_input')), findsOneWidget);
      expect(find.byKey(const Key('add_member_allowance_input')), findsOneWidget);
      expect(find.byKey(const Key('role_chip_spouse')), findsOneWidget);
      expect(find.byKey(const Key('role_chip_roommate')), findsOneWidget);
      expect(find.byKey(const Key('role_chip_child')), findsOneWidget);
      expect(find.byKey(const Key('add_member_submit_button')), findsOneWidget);
    });

    testWidgets('submits manual member details when form is filled', (tester) async {
      String? submittedName;
      String? submittedRole;
      double? submittedAllowance;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AddHouseholdMemberSheet(
              onMemberAdded: ({
                required String name,
                required String relationship,
                required double monthlyAllowance,
                String? avatarIcon,
              }) async {
                submittedName = name;
                submittedRole = relationship;
                submittedAllowance = monthlyAllowance;
              },
            ),
          ),
        ),
      );

      // Enter name
      await tester.enterText(find.byKey(const Key('add_member_name_input')), 'Fatima');

      // Select Spouse role
      await tester.tap(find.byKey(const Key('role_chip_spouse')));
      await tester.pump();

      // Enter allowance
      await tester.enterText(find.byKey(const Key('add_member_allowance_input')), '1500');
      await tester.pump();

      // Submit
      final submitBtn = find.byKey(const Key('add_member_submit_button'));
      await tester.ensureVisible(submitBtn);
      await tester.pumpAndSettle();
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      expect(submittedName, equals('Fatima'));
      expect(submittedRole, equals('spouse'));
      expect(submittedAllowance, equals(1500.0));
    });

    testWidgets('disables or warns when name is empty', (tester) async {
      bool called = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AddHouseholdMemberSheet(
              onMemberAdded: ({
                required String name,
                required String relationship,
                required double monthlyAllowance,
                String? avatarIcon,
              }) async {
                called = true;
              },
            ),
          ),
        ),
      );

      // Attempt to submit empty name
      final submitBtn = find.byKey(const Key('add_member_submit_button'));
      await tester.ensureVisible(submitBtn);
      await tester.pumpAndSettle();
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      expect(called, isFalse);
    });
  });
}
