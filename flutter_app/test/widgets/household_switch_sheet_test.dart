import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/models/household_membership.dart';
import 'package:budget_tracker/widgets/settings/household_switch_sheet.dart';

void main() {
  testWidgets('renders list of households and triggers switch callback', (tester) async {
    final memberships = [
      const HouseholdMembership(
        householdId: 'hh-1',
        householdName: 'Personal Flat',
        inviteCode: 'CODE1',
        role: 'admin',
        isActive: true,
      ),
      const HouseholdMembership(
        householdId: 'hh-2',
        householdName: "Parents' Villa",
        inviteCode: 'CODE2',
        role: 'member',
        isActive: false,
      ),
    ];

    String? switchedId;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HouseholdSwitchSheetContent(
            memberships: memberships,
            currentHouseholdId: 'hh-1',
            onSwitch: (id) => switchedId = id,
            onJoinNew: () {},
            onCreateNew: () {},
          ),
        ),
      ),
    );

    expect(find.text('Personal Flat'), findsOneWidget);
    expect(find.text("Parents' Villa"), findsOneWidget);
    expect(find.text('ACTIVE'), findsOneWidget);

    await tester.tap(find.text("Parents' Villa"));
    await tester.pumpAndSettle();

    expect(switchedId, 'hh-2');
  });
}
