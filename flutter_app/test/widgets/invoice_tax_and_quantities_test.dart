import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/screens/home/edit_transaction_sheet.dart';
import 'package:budget_tracker/screens/scanner/receipt_scanner_sheet.dart';
import 'package:budget_tracker/widgets/transaction_item_breakdown_card.dart';
import '../support/localized_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Line Item Quantities and Breakdown Tests', () {
    testWidgets('TransactionItemBreakdownCard displays quantities and multiplied total for qty > 1', (tester) async {
      final items = [
        {'name': 'Bruger Meal', 'quantity': 1.0, 'price': 18.00},
        {'name': 'Sweet Mustard Sauce', 'quantity': 2.0, 'price': 1.00},
      ];

      await tester.pumpWidget(
        localizedApp(
          TransactionItemBreakdownCard(
            items: items,
            merchant: 'KFC',
            amount: 20.00,
            currency: 'SAR',
            categoryCode: 'OPEX-FOOD',
            initiallyExpanded: true,
          ),
          lang: 'en',
        ),
      );
      await tester.pumpAndSettle();

      // Should show '2x Sweet Mustard Sauce'
      expect(find.text('2x Sweet Mustard Sauce'), findsOneWidget);
      // Should show unit price calculation: '2 × SAR 1.00'
      expect(find.text('2 × SAR 1.00'), findsOneWidget);
      // Total for that row should be SAR 2.00
      expect(find.text('SAR 2.00'), findsOneWidget);
    });

    testWidgets('EditTransactionSheet allows incrementing and decrementing line item quantities', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      final tx = Transaction(
        id: 'tx-001',
        householdId: 'h-001',
        amount: 20.00,
        currency: 'SAR',
        merchant: 'KFC',
        categoryCode: 'OPEX-FOOD',
        timestamp: DateTime(2026, 10, 29),
        isReallocated: false,
        createdAt: DateTime(2026, 10, 29),
        source: 'manual',
        items: [
          {'name': 'Sweet Mustard Sauce', 'quantity': 1.0, 'price': 1.00},
        ],
      );

      await tester.pumpWidget(
        localizedApp(
          EditTransactionSheet(
            transaction: tx,
            householdDependents: const [],
          ),
          lang: 'en',
        ),
      );
      await tester.pumpAndSettle();

      // Initially shows 1x
      expect(find.text('1x'), findsOneWidget);

      // Tap + button on the item quantity stepper
      final addIcon = find.byKey(const ValueKey('qty_plus_0'));
      expect(addIcon, findsOneWidget);
      await tester.ensureVisible(addIcon);
      await tester.tap(addIcon);
      await tester.pumpAndSettle();

      // Quantity should now be 2x
      expect(find.text('2x'), findsOneWidget);
      // Line total calculation displayed
      expect(find.text('= SAR 2.00'), findsOneWidget);

      // Tap - button to decrement back to 1x
      final removeIcon = find.byKey(const ValueKey('qty_minus_0'));
      expect(removeIcon, findsOneWidget);
      await tester.ensureVisible(removeIcon);
      await tester.tap(removeIcon);
      await tester.pumpAndSettle();

      expect(find.text('1x'), findsOneWidget);
      expect(find.text('= SAR 2.00'), findsNothing);
    });
  });

  group('Invoice Tax (15% VAT) Toggle Tests', () {
    testWidgets('ReceiptScannerSheet displays 15% VAT toggle and updates calculation on toggle', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      const sheet = ReceiptScannerSheet(
        householdId: 'h-001',
        initialScanResult: {
          'merchant': 'KFC',
          'amount': 115.00,
          'category_code': 'OPEX-FOOD',
          'items': [
            {'name': 'Bruger Meal', 'quantity': 1.0, 'price': 100.00},
            {'name': 'Sweet Mustard Sauce', 'quantity': 1.0, 'price': 1.00},
            {'name': 'Sweet Mustard Sauce', 'quantity': 1.0, 'price': 1.00},
          ],
        },
      );

      await tester.pumpWidget(
        localizedApp(
          sheet,
          lang: 'en',
        ),
      );
      await tester.pumpAndSettle();

      // Verify consolidation combined the 2 identical Sweet Mustard Sauce items into 2x
      expect(find.text('2x Sweet Mustard Sauce'), findsOneWidget);

      // Verify Tax Toggle Card is visible
      final taxCardFinder = find.byKey(const ValueKey('invoice_tax_preview_card'));
      expect(taxCardFinder, findsOneWidget);
      expect(find.byKey(const ValueKey('invoice_tax_switch')), findsOneWidget);

      // 15% VAT of 115 is 15.00 SAR, Subtotal is 100.00 SAR
      expect(find.descendant(of: taxCardFinder, matching: find.text('SAR 15.00')), findsOneWidget);
      expect(find.descendant(of: taxCardFinder, matching: find.text('SAR 100.00')), findsOneWidget);

      // Toggle Tax OFF
      final taxSwitch = find.byKey(const ValueKey('invoice_tax_switch'));
      await tester.tap(taxSwitch);
      await tester.pumpAndSettle();

      // Should now show No Tax (0%) and SAR 0.00 in the tax preview card
      expect(find.descendant(of: taxCardFinder, matching: find.text('No Tax (0%)')), findsOneWidget);
      expect(find.descendant(of: taxCardFinder, matching: find.text('SAR 0.00')), findsOneWidget);
    });
  });
}
