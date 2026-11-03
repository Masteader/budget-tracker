import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:budget_tracker/widgets/sub_budget_breakdown_sheet.dart';
import '../support/localized_app.dart';

void main() {
  testWidgets('SubBudgetBreakdownSheet displays human categoryName and does not shadow with raw code', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Pump SubBudgetBreakdownSheet directly with a custom category
    await tester.pumpWidget(
      localizedApp(
        const SubBudgetBreakdownSheet(
          householdId: 'hh-test',
          categoryCode: 'CUSTOM-CAR_TRANSPORT',
          categoryName: 'Car and Transport',
          allocatedAmount: 1500.0,
          spentAmount: 500.0,
        ),
        scaffold: true,
        lang: 'en',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify "Car and Transport" is displayed on the header
    expect(find.text('Car and Transport'), findsOneWidget);

    // Verify raw code "CUSTOM-CAR_TRANSPORT" is NOT displayed anywhere
    expect(find.text('CUSTOM-CAR_TRANSPORT'), findsNothing);
  });
}
