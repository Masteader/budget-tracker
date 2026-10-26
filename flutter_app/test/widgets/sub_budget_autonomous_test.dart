import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/widgets/sub_budget_allocation_dialog.dart';
import 'package:budget_tracker/l10n/app_localizations.dart';

void main() {
  Widget buildHarness({
    required String categoryCode,
    required String categoryName,
    Map<String, double>? subAllocations,
  }) {
    Budget? budget;
    if (subAllocations != null) {
      budget = Budget(
        id: 'b-1',
        householdId: 'h-123',
        categoryCode: categoryCode,
        allocatedAmount: subAllocations.values.fold(0.0, (a, b) => a + b),
        spentAmount: 0.0,
        remainingAmount: subAllocations.values.fold(0.0, (a, b) => a + b),
        month: '2026-10-01',
        subAllocations: subAllocations,
      );
    }

    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const [AppLocalizationsDelegate()],
      home: Scaffold(
        body: SubBudgetAllocationDialog(
          householdId: 'h-123',
          categoryCode: categoryCode,
          categoryName: categoryName,
          existingBudget: budget,
        ),
      ),
    );
  }

  testWidgets('Allows editing and deleting sub-categories for autonomous custom envelopes', (tester) async {
    await tester.pumpWidget(buildHarness(
      categoryCode: 'CUSTOM-GROCERY',
      categoryName: 'Groceries',
      subAllocations: {
        'sub-apples': 50.0,
        'sub-oranges': 75.0,
      },
    ));
    await tester.pumpAndSettle();

    // Verify sub-budget dialog renders
    expect(find.byType(SubBudgetAllocationDialog), findsOneWidget);

    // Verify that the delete icon is present for sub-category items
    final deleteIcons = find.byIcon(Icons.delete_outline_rounded);
    expect(deleteIcons, findsWidgets);

    // Verify that the edit icon is present for sub-category items
    final editIcons = find.byIcon(Icons.edit_outlined);
    expect(editIcons, findsWidgets);

    // Verify tapping edit on a custom envelope subcategory opens the rename dialog
    await tester.tap(editIcons.first);
    await tester.pumpAndSettle();

    expect(find.text('Rename Sub-Category'), findsOneWidget);
    final dialogCancel = find.descendant(of: find.byType(AlertDialog), matching: find.text('Cancel'));
    expect(dialogCancel, findsOneWidget);

    // Cancel rename dialog
    await tester.tap(dialogCancel);
    await tester.pumpAndSettle();
  });

  testWidgets('System category displays delete and edit buttons for starter sub-allocations', (tester) async {
    await tester.pumpWidget(buildHarness(
      categoryCode: 'OPEX-GROCERY',
      categoryName: 'Groceries',
    ));
    await tester.pumpAndSettle();

    // Verify that the delete icon is visible for preloaded system sub-categories
    // so the household can remove unwanted envelopes from their allocation
    final deleteIcons = find.byIcon(Icons.delete_outline_rounded);
    expect(deleteIcons, findsWidgets);

    // Verify edit icon is also visible
    final editIcons = find.byIcon(Icons.edit_outlined);
    expect(editIcons, findsWidgets);

    // Tapping delete opens confirmation dialog
    await tester.tap(deleteIcons.first);
    await tester.pumpAndSettle();

    expect(find.text('Remove Sub-Category?'), findsOneWidget);
    final removeConfirm = find.descendant(of: find.byType(AlertDialog), matching: find.text('Remove'));
    expect(removeConfirm, findsOneWidget);

    // Cancel removal
    final dialogCancel = find.descendant(of: find.byType(AlertDialog), matching: find.text('Cancel'));
    await tester.tap(dialogCancel);
    await tester.pumpAndSettle();
  });
}
