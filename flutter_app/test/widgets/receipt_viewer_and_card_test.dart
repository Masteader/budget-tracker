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

  testWidgets('TransactionItemBreakdownCard shows ZATCA QR badge and opens dialog', (tester) async {
    const rawQr = 'AQZTYWxsYWgCCzMxMDEyMzQ1Njc4AzEwMjAyNC0xMC0wOFQyMTowMDowMFoEMTAwLjAwBTE1LjAw';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TransactionItemBreakdownCard(
            merchant: 'Sallah Store',
            amount: 115.00,
            qrCodeRaw: rawQr,
          ),
        ),
      ),
    );

    // Verify ZATCA QR badge is shown
    expect(find.text('ZATCA QR'), findsOneWidget);

    // Tap the badge to open the dialog
    await tester.tap(find.text('ZATCA QR'));
    await tester.pumpAndSettle();

    // Verify dialog content
    expect(find.text('Saudi ZATCA QR'), findsOneWidget);
    expect(find.text('Copy Base64'), findsOneWidget);
  });
}
