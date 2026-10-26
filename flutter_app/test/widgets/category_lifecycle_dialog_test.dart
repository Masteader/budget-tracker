import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/widgets/categories/category_lifecycle_dialog.dart';
import 'package:budget_tracker/l10n/app_localizations.dart';

void main() {
  Widget buildHarness({
    required String categoryCode,
    required String currentName,
    required int transactionCount,
    required void Function(CategoryLifecycleAction action, String newName) onConfirm,
  }) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const [AppLocalizationsDelegate()],
      home: Scaffold(
        body: CategoryLifecycleDialog(
          categoryCode: categoryCode,
          currentName: currentName,
          transactionCount: transactionCount,
          onConfirm: onConfirm,
        ),
      ),
    );
  }

  testWidgets('CategoryLifecycleDialog displays both choices and defaults to replaceAndArchive', (tester) async {
    CategoryLifecycleAction? confirmedAction;
    String? confirmedName;

    await tester.pumpWidget(buildHarness(
      categoryCode: 'OPEX-GROCERY',
      currentName: 'Groceries',
      transactionCount: 15,
      onConfirm: (action, newName) {
        confirmedAction = action;
        confirmedName = newName;
      },
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Groceries'), findsWidgets);
    expect(find.textContaining('15'), findsWidgets);
    expect(find.text('Replace & Archive Old (Recommended)'), findsOneWidget);
    expect(find.text('Rename Only'), findsOneWidget);

    // Enter a new name in text field
    final textField = find.byType(TextField);
    expect(textField, findsOneWidget);
    await tester.enterText(textField, 'Supermarkets');
    await tester.pumpAndSettle();

    // Tap confirm button
    final confirmBtn = find.text('Save');
    expect(confirmBtn, findsOneWidget);
    await tester.tap(confirmBtn);
    await tester.pumpAndSettle();

    expect(confirmedAction, equals(CategoryLifecycleAction.replaceAndArchive));
    expect(confirmedName, equals('Supermarkets'));
  });

  testWidgets('CategoryLifecycleDialog can select renameOnly and submit', (tester) async {
    CategoryLifecycleAction? confirmedAction;
    String? confirmedName;

    await tester.pumpWidget(buildHarness(
      categoryCode: 'OPEX-GROCERY',
      currentName: 'Groceries',
      transactionCount: 15,
      onConfirm: (action, newName) {
        confirmedAction = action;
        confirmedName = newName;
      },
    ));
    await tester.pumpAndSettle();

    // Select "Rename Only" radio tile
    await tester.tap(find.text('Rename Only'));
    await tester.pumpAndSettle();

    final textField = find.byType(TextField);
    await tester.enterText(textField, 'Food & Groceries');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(confirmedAction, equals(CategoryLifecycleAction.renameOnly));
    expect(confirmedName, equals('Food & Groceries'));
  });
}
