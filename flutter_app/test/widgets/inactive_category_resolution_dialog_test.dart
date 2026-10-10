import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/widgets/transactions/inactive_category_resolution_dialog.dart';

void main() {
  testWidgets('InactiveCategoryResolutionDialog shows both choices and triggers callbacks', (tester) async {
    bool reactivateTapped = false;
    bool changeCategoryTapped = false;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: InactiveCategoryResolutionDialog(
          categoryName: 'Dining',
          amount: 45.0,
          merchant: 'Al Baik',
          onReactivate: () => reactivateTapped = true,
          onChangeCategory: () => changeCategoryTapped = true,
        ),
      ),
    ));

    expect(find.textContaining('Dining'), findsWidgets);
    expect(find.textContaining('Al Baik'), findsOneWidget);
    expect(find.textContaining('45.00'), findsOneWidget);
    expect(find.text('Reactivate Category'), findsOneWidget);
    expect(find.text('File Under Other Category'), findsOneWidget);

    await tester.tap(find.text('Reactivate Category'));
    expect(reactivateTapped, isTrue);

    await tester.tap(find.text('File Under Other Category'));
    expect(changeCategoryTapped, isTrue);
  });
}
