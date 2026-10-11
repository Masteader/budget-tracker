import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/screens/home/edit_transaction_sheet.dart';

void main() {
  testWidgets('EditTransactionSheet displays subcategory dropdown and child beneficiary chips', (tester) async {
    final tx = Transaction(
      id: 'tx-1',
      householdId: 'h1',
      amount: 50.0,
      currency: 'SAR',
      merchant: 'Al Baik',
      categoryCode: 'OPEX-DINING',
      subCategory: 'restaurants_dinners',
      timestamp: DateTime.now(),
      isReallocated: false,
      createdAt: DateTime.now(),
      paidBy: 'me',
      beneficiary: 'Sarah',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: EditTransactionSheet(
              transaction: tx,
              householdDependents: const ['Sarah', 'Fahad'],
            ),
          ),
        ),
      ),
    );

    expect(find.text('Sub-Category'), findsOneWidget);
    expect(find.text('Sarah'), findsOneWidget);
  });
}
