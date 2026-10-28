import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/models/nafaqah.dart';
import 'package:budget_tracker/screens/home/edit_transaction_sheet.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

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
    expect(find.text('I paid for the home — he pays me back'), findsOneWidget);
    expect(find.text('Shared for the family: the husband owes the wife SAR 300.00.'), findsOneWidget);

    await tester.ensureVisible(find.text('For me personally — from my allowance'));
    await tester.tap(find.text('For me personally — from my allowance'));
    await tester.pump();
    expect(find.text("Personal: SAR 300.00 counted against the wife's allowance."), findsOneWidget);

    await tester.ensureVisible(find.text('My husband paid'));
    await tester.tap(find.text('My husband paid'));
    await tester.pump();
    expect(find.text("Household expense: the husband's responsibility, no debt."), findsOneWidget);
    expect(find.textContaining('50/50'), findsNothing);
  });

  testWidgets("the stored class wins on the husband's phone (her claim is kept)", (tester) async {
    // Recorded by the wife: 'me' is her, but the husband is viewing.
    await pumpSheet(tester, groceries(paidBy: 'me', beneficiary: 'both'), family('husband'),
        stored: {'nafaqah_class': kWifeReimbursable, 'nafaqah_spouse_id': 'u-wife'});
    await tester.pump();

    expect(find.text('Shared for the family: the husband owes the wife SAR 300.00.'), findsOneWidget);
    expect(find.text("My wife's personal purchase — from her allowance"), findsOneWidget);
  });

  // UX-03: one Nafaqah question in family mode, with real names.
  testWidgets('family mode asks one question with real names, no "who paid / for whom" rows', (tester) async {
    const summary = NafaqahSummary(
      mode: 'family_nafaqah',
      callerRole: 'wife',
      callerUserId: 'u-wife',
      husbandId: 'u-husband',
      husbandName: 'Ahmed',
      wives: [NafaqahWife(id: 'u-wife', displayName: 'Sara')],
    );
    await pumpSheet(tester, groceries(), summary, stored: {'nafaqah_class': kWifeReimbursable, 'nafaqah_spouse_id': 'u-wife'});
    await tester.pump();
    expect(find.text('Who paid, and for whom?'), findsOneWidget);
    expect(find.text('Ahmed paid'), findsOneWidget);
    expect(find.text('Who paid?'), findsNothing);
    expect(find.text('For whom?'), findsNothing);
    expect(find.text('The other person paid'), findsNothing);
    expect(find.text('Partner'), findsNothing);
    // The optional child row stays.
    expect(find.text('Sarah'), findsOneWidget);
  });

  testWidgets("the husband sees the wife's name", (tester) async {
    const summary = NafaqahSummary(
      mode: 'family_nafaqah',
      callerRole: 'husband',
      callerUserId: 'u-husband',
      husbandId: 'u-husband',
      wives: [NafaqahWife(id: 'u-wife', displayName: 'Sara')],
    );
    await pumpSheet(tester, groceries(), summary, stored: {'nafaqah_class': kWifeReimbursable, 'nafaqah_spouse_id': 'u-wife'});
    await tester.pump();
    expect(find.text('Sara paid for the home — I pay her back'), findsOneWidget);
    expect(find.text('I paid (household expense)'), findsOneWidget);
  });

  // UX-23: no default class is shown before the stored one is known.
  testWidgets('the Nafaqah choice shows a placeholder until the stored class is read', (tester) async {
    final pending = Completer<Map<String, dynamic>?>();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: EditTransactionSheet(
            transaction: groceries(),
            householdDependents: const [],
            nafaqah: family('husband'),
            loadNafaqahFields: (_) => pending.future,
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(find.byKey(const ValueKey('nafaqah_class_loading')), findsOneWidget);
    expect(find.byKey(const ValueKey('nafaqah_option_husband')), findsNothing);

    pending.complete({'nafaqah_class': kWifePersonal, 'nafaqah_spouse_id': 'u-wife'});
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('nafaqah_class_loading')), findsNothing);
    expect(find.byKey(const ValueKey('nafaqah_option_wife_personal')), findsOneWidget);
  });

  testWidgets('a stored class that cannot be read says so and can be retried', (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: EditTransactionSheet(
            transaction: groceries(),
            householdDependents: const [],
            nafaqah: family('husband'),
            loadNafaqahFields: (_) async {
              calls++;
              if (calls == 1) throw Exception('offline');
              return {'nafaqah_class': null, 'nafaqah_spouse_id': null};
            },
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.text("Couldn't read how this expense is classified."), findsOneWidget);
    expect(find.byKey(const ValueKey('nafaqah_option_husband')), findsNothing);

    final retryBtn = find.byKey(const ValueKey('nafaqah_class_retry'));
    await tester.ensureVisible(retryBtn);
    await tester.tap(retryBtn);
    await tester.pump();
    await tester.pump();
    expect(calls, 2);
    expect(find.byKey(const ValueKey('nafaqah_option_husband')), findsOneWidget);
  });

  testWidgets('a class carried by the feed row needs no extra read', (tester) async {
    var calls = 0;
    final tx = Transaction.fromMap({
      'id': 'tx-carried',
      'household_id': 'h1',
      'amount': 300,
      'currency': 'SAR',
      'merchant': 'Panda',
      'category_code': 'OPEX-GROCERY',
      'timestamp': DateTime.now().toIso8601String(),
      'created_at': DateTime.now().toIso8601String(),
      'nafaqah_class': kWifeReimbursable,
      'nafaqah_spouse_id': 'u-wife',
    });
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: EditTransactionSheet(
            transaction: tx,
            householdDependents: const [],
            nafaqah: family('husband'),
            loadNafaqahFields: (_) async {
              calls++;
              return null;
            },
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(calls, 0);
    expect(find.byKey(const ValueKey('nafaqah_class_loading')), findsNothing);
    expect(find.text('Shared for the family: the husband owes the wife SAR 300.00.'), findsOneWidget);
  });

  // FR-A-01: paid_by / beneficiary are relative to whoever recorded the row, so
  // they cannot decide the Nafaqah class on another phone. A stored "no class"
  // must stay "husband paid", otherwise an unrelated edit books a false debt.
  testWidgets("a husband-paid expense stays a household expense on the wife's phone", (tester) async {
    // Recorded by the husband: 'me' is him, but the wife is viewing.
    await pumpSheet(tester, groceries(paidBy: 'me', beneficiary: 'both'), family('wife'),
        stored: {'nafaqah_class': null, 'nafaqah_spouse_id': null});
    await tester.pump();

    expect(find.text("Household expense: the husband's responsibility, no debt."), findsOneWidget);
    expect(find.text('Shared for the family: the husband owes the wife SAR 300.00.'), findsNothing);
  });

  testWidgets("a wife-recorded 'husband paid' expense stays a household expense on the husband's phone",
      (tester) async {
    // Recorded by the wife as paid by her husband: 'partner' is him.
    await pumpSheet(tester, groceries(paidBy: 'partner', beneficiary: 'both'), family('husband'),
        stored: {'nafaqah_class': null, 'nafaqah_spouse_id': null});
    await tester.pump();

    expect(find.text("Household expense: the husband's responsibility, no debt."), findsOneWidget);
    expect(find.text('Shared for the family: the husband owes the wife SAR 300.00.'), findsNothing);
  });

  // FABLE-LOGIC-02: cutting a repaid wife advance is refused by the ledger
  // guard; the app explains it instead of showing a raw database error.
  group('Nafaqah ledger guard and missing provider', () {
    const guard = PostgrestException(
      message: 'Nafaqah ledger overpaid: advances 100.00 < repayments 200.00',
      code: '22023',
      hint: 'ledger_would_be_overpaid',
    );

    Future<void> pumpWithSeams(
      WidgetTester tester, {
      TransactionRowUpdater? updateRow,
      TransactionRowRemover? deleteRow,
    }) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: EditTransactionSheet(
              transaction: groceries(paidBy: 'me', beneficiary: 'both'),
              householdDependents: const ['Sarah'],
              nafaqah: family('wife'),
              loadNafaqahFields: (_) async => {'nafaqah_class': kWifeReimbursable, 'nafaqah_spouse_id': 'u-wife'},
              updateRow: updateRow,
              deleteRow: deleteRow,
            ),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump();
    }

    testWidgets('an edit refused by the guard is explained and not retried another way', (tester) async {
      final writes = <Map<String, dynamic>>[];
      await pumpWithSeams(tester, updateRow: (id, values) async {
        writes.add(values);
        throw guard;
      });

      await tester.enterText(find.byType(TextField).at(1), '100');
      await tester.ensureVisible(find.text('Save Changes'));
      await tester.tap(find.text('Save Changes'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(writes, hasLength(1), reason: 'the raw_sms fallback would be refused the same way');
      expect(find.textContaining('the husband has already repaid part of the wife'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('a delete refused by the guard is explained', (tester) async {
      var deletes = 0;
      await pumpWithSeams(tester, deleteRow: (id) async {
        deletes++;
        throw guard;
      });

      await tester.tap(find.byTooltip('Delete Transaction'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Delete'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(deletes, 1);
      expect(find.textContaining('the husband has already repaid part of the wife'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('a classification refused for a missing provider is explained', (tester) async {
      await pumpWithSeams(tester, updateRow: (id, values) async {
        throw const PostgrestException(
          message: 'This family has no Nafaqah provider',
          code: '23514',
          hint: 'no_nafaqah_provider',
        );
      });

      await tester.ensureVisible(find.text('Save Changes'));
      await tester.tap(find.text('Save Changes'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('no household provider (husband) yet'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });
  });

  testWidgets('roommate/partner households keep the shared-split preview', (tester) async {
    await pumpSheet(tester, groceries(), const NafaqahSummary(mode: 'not_family'));

    expect(find.text('Who paid, and for whom?'), findsNothing);
    expect(find.text('Who paid?'), findsOneWidget);
    expect(find.text('Shared 50/50: Partner will owe you SAR 150.00'), findsOneWidget);
  });
}
