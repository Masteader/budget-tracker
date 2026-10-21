// UX-12: the scanned total and category can be corrected before saving.
import 'package:budget_tracker/widgets/scanner/receipt_review_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/localized_app.dart';

void main() {
  group('ReceiptReviewEdits', () {
    test('unchanged values send nothing', () {
      final e = ReceiptReviewEdits.from(scannedAmount: 82.5, scannedCategory: 'OPEX-GROCERY', amountText: '82.50', chosenCategory: 'OPEX-GROCERY');
      expect(e.invalid, isFalse);
      expect(e.amount, isNull);
      expect(e.categoryCode, isNull);
    });

    test('a corrected total and category are sent', () {
      final e = ReceiptReviewEdits.from(scannedAmount: 82.5, scannedCategory: 'OPEX-GROCERY', amountText: '85.25', chosenCategory: 'OPEX-SHOPPING');
      expect(e.amount, 85.25);
      expect(e.categoryCode, 'OPEX-SHOPPING');
    });

    test('Arabic digits are read; zero or text is invalid', () {
      expect(ReceiptReviewEdits.from(scannedAmount: 1, amountText: '٨٥٫٢٥').amount, 85.25);
      expect(ReceiptReviewEdits.from(scannedAmount: 1, amountText: '0').invalid, isTrue);
      expect(ReceiptReviewEdits.from(scannedAmount: 1, amountText: 'abc').invalid, isTrue);
    });
  });

  testWidgets('the editor shows the total and lets the category change (Arabic)', (tester) async {
    final ctrl = TextEditingController(text: '82.50');
    String? chosen;
    await tester.pumpWidget(localizedApp(
      ReceiptReviewEditor(amountController: ctrl, categoryCode: 'OPEX-GROCERY', onCategoryChanged: (c) => chosen = c),
    ));
    await tester.pumpAndSettle();
    expect(find.text('الإجمالي'), findsOneWidget);
    expect(find.text('البقالة والتموينات'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('receipt_review_category')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('التسوق والمشتريات').last);
    await tester.pumpAndSettle();
    expect(chosen, 'OPEX-SHOPPING');
    await tester.enterText(find.byKey(const ValueKey('receipt_review_amount')), '85.25');
    expect(ctrl.text, '85.25');
  });

  testWidgets('an invalid total says so', (tester) async {
    await tester.pumpWidget(localizedApp(
      ReceiptReviewEditor(
        amountController: TextEditingController(text: '0'),
        categoryCode: 'OPEX-GROCERY',
        onCategoryChanged: (_) {},
        amountInvalid: true,
      ),
      lang: 'en',
    ));
    await tester.pumpAndSettle();
    expect(find.text('Enter an amount greater than 0.'), findsOneWidget);
  });
}
