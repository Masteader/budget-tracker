import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/models/nafaqah.dart';
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

  testWidgets('EditTransactionSheet selects Shopping & Retail for OPEX-SHOPPING transaction', (tester) async {
    final tx = Transaction(
      id: 'tx-noon-shoes',
      householdId: 'h1',
      amount: 100.0,
      currency: 'SAR',
      merchant: 'Noon',
      categoryCode: 'OPEX-SHOPPING',
      subCategory: 'clothing_fashion',
      timestamp: DateTime.now(),
      isReallocated: false,
      createdAt: DateTime.now(),
      paidBy: 'me',
      beneficiary: 'me',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: EditTransactionSheet(
              transaction: tx,
              householdDependents: const [],
            ),
          ),
        ),
      ),
    );

    expect(find.text('Shopping & Retail'), findsOneWidget);
  });

  Transaction groceries({String paidBy = 'me', String beneficiary = 'both'}) => Transaction(
        id: 'tx-family',
        householdId: 'h1',
        amount: 300.0,
        currency: 'SAR',
        merchant: 'Panda',
        categoryCode: 'OPEX-GROCERY',
        timestamp: DateTime.now(),
        isReallocated: false,
        createdAt: DateTime.now(),
        paidBy: paidBy,
        beneficiary: beneficiary,
      );

  NafaqahSummary family(String role) => NafaqahSummary(
        mode: 'family_nafaqah',
        callerRole: role,
        callerUserId: role == 'wife' ? 'u-wife' : 'u-husband',
        wives: const [NafaqahWife(id: 'u-wife')],
      );

  Future<void> pumpSheet(WidgetTester tester, Transaction tx, NafaqahSummary summary,
      {Map<String, dynamic>? stored}) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: EditTransactionSheet(
            transaction: tx,
            householdDependents: const ['Sarah'],
            nafaqah: summary,
            loadNafaqahFields: (_) async => stored,
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('family mode never offers a 50/50 split (wife paid for the household)', (tester) async {
    await pumpSheet(tester, groceries(), family('wife'));

    expect(find.textContaining('50/50'), findsNothing);
    expect(find.text('Shared for family (husband reimburses)'), findsOneWidget);
    expect(find.text('Shared for the family: the husband owes the wife SAR 300.00.'), findsOneWidget);

    await tester.ensureVisible(find.text('Personal (from my allowance)'));
    await tester.tap(find.text('Personal (from my allowance)'));
    await tester.pump();
    expect(find.text("Personal: SAR 300.00 counted against the wife's allowance."), findsOneWidget);

    await tester.ensureVisible(find.text('Husband paid (household expense)'));
    await tester.tap(find.text('Husband paid (household expense)'));
    await tester.pump();
    expect(find.text("Household expense: the husband's Nafaqah, no debt."), findsOneWidget);
    expect(find.textContaining('50/50'), findsNothing);
  });

  testWidgets("the stored class wins on the husband's phone (her claim is kept)", (tester) async {
    // Recorded by the wife: 'me' is her, but the husband is viewing.
    await pumpSheet(tester, groceries(paidBy: 'me', beneficiary: 'both'), family('husband'),
        stored: {'nafaqah_class': kWifeReimbursable, 'nafaqah_spouse_id': 'u-wife'});
    await tester.pump();

    expect(find.text('Shared for the family: the husband owes the wife SAR 300.00.'), findsOneWidget);
    expect(find.text('Personal (from her allowance)'), findsOneWidget);
  });

  testWidgets('roommate/partner households keep the shared-split preview', (tester) async {
    await pumpSheet(tester, groceries(), const NafaqahSummary(mode: 'not_family'));

    expect(find.text('Shared for family (husband reimburses)'), findsNothing);
    expect(find.text('Shared 50/50: Partner will owe you SAR 150.00'), findsOneWidget);
  });
}
