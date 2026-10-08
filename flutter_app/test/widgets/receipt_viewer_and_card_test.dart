import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/widgets/transaction_item_breakdown_card.dart';

void main() {
  testWidgets('TransactionItemBreakdownCard shows Receipt badge when receiptUrl is present', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TransactionItemBreakdownCard(
            merchant: 'Tamimi Markets',
            amount: 145.50,
            receiptUrl: 'https://example.com/receipt.jpg',
          ),
        ),
      ),
    );

    expect(find.text('View Receipt'), findsOneWidget);
    expect(find.byIcon(Icons.receipt_long_rounded), findsOneWidget);
  });

  testWidgets('TransactionItemBreakdownCard hides Receipt badge when receiptUrl is null', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TransactionItemBreakdownCard(
            merchant: 'Tamimi Markets',
            amount: 145.50,
            receiptUrl: null,
          ),
        ),
      ),
    );

    expect(find.text('Receipt'), findsNothing);
  });
}
