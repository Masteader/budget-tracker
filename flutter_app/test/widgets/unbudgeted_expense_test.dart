// Owner decision 2026-11-05: an expense in an inactive or unbudgeted category
// is filed under it and counts in no budget. The feed and the edit sheet say
// "Unbudgeted"; the edit sheet offers an admin the existing budget dialog to
// activate the category and give it a budget.
import 'package:budget_tracker/models/budget_coverage.dart';
import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/models/nafaqah.dart';
import 'package:budget_tracker/providers/budget_provider.dart';
import 'package:budget_tracker/providers/recurring_bills_provider.dart';
import 'package:budget_tracker/providers/transaction_provider.dart';
import 'package:budget_tracker/screens/home/edit_transaction_sheet.dart';
import 'package:budget_tracker/screens/home/transaction_feed_screen.dart';
import 'package:budget_tracker/widgets/transactions/unbudgeted_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../support/localized_app.dart';

class _FakeTransactions extends TransactionProvider {
  _FakeTransactions(this._rows);
  final List<Transaction> _rows;
  @override
  List<Transaction> get transactions => _rows;
  @override
  bool get isLoading => false;
}

final _at = DateTime.now().subtract(const Duration(hours: 1));

Transaction _tx(String id, String code, double amount, {String? cls, bool settlement = false}) => Transaction.fromMap({
      'id': id,
      'household_id': 'h1',
      'amount': amount,
      'currency': 'SAR',
      'merchant': 'Store $id',
      'category_code': code,
      'timestamp': _at.toIso8601String(),
      'created_at': _at.toIso8601String(),
      'cycle_key': '2026-11',
      'spent_by': 'both',
      'nafaqah_class': cls,
      'nafaqah_spouse_id': cls == null ? null : 'u-wife',
      'is_settlement': settlement,
    });

final _coverage = BudgetCoverage.fromRows([
  {'category_code': 'OPEX-GROCERY', 'cycle_key': '2026-11', 'is_active': true},
  {'category_code': 'OPEX-HOUSING', 'cycle_key': '2026-11', 'is_active': false},
]);

const _roommates = NafaqahSummary(mode: 'roommates', callerRole: 'peer', callerUserId: 'u1');

void main() {
  group('feed', () {
    Future<void> pumpFeed(WidgetTester tester, List<Transaction> rows, {String lang = 'en'}) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<TransactionProvider>(create: (_) => _FakeTransactions(rows)),
          ChangeNotifierProvider<BudgetProvider>(create: (_) => BudgetProvider()),
          ChangeNotifierProvider<RecurringBillsProvider>(create: (_) => RecurringBillsProvider()),
        ],
        child: localizedApp(
          TransactionFeedScreen(
            householdId: 'h1',
            loadNafaqah: (_) async => _roommates,
            loadBudgetCoverage: (_) async => _coverage,
            initialDatePeriod: 'ALL',
          ),
          lang: lang,
          scaffold: false,
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('marks only expenses in an inactive or unbudgeted category', (tester) async {
      await pumpFeed(tester, [
        _tx('rent', 'OPEX-HOUSING', 2500), // inactive budget row
        _tx('zakat', 'OPEX-CHARITY', 100), // no budget row
        _tx('panda', 'OPEX-GROCERY', 120), // budgeted
        _tx('settle', 'OPEX-CHARITY', 50, settlement: true), // never in a budget anyway
      ]);
      expect(find.byKey(const ValueKey('feed_badge_unbudgeted')), findsNWidgets(2));
      expect(find.text('Unbudgeted'), findsNWidgets(2));
    });

    testWidgets('Arabic', (tester) async {
      await pumpFeed(tester, [_tx('rent', 'OPEX-HOUSING', 2500)], lang: 'ar');
      expect(find.text('خارج الميزانية'), findsOneWidget);
    });

    testWidgets('nothing is marked while the budgets are unknown', (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<TransactionProvider>(create: (_) => _FakeTransactions([_tx('rent', 'OPEX-HOUSING', 2500)])),
          ChangeNotifierProvider<BudgetProvider>(create: (_) => BudgetProvider()),
          ChangeNotifierProvider<RecurringBillsProvider>(create: (_) => RecurringBillsProvider()),
        ],
        child: localizedApp(
          TransactionFeedScreen(
            householdId: 'h1',
            loadNafaqah: (_) async => _roommates,
            loadBudgetCoverage: (_) async => throw Exception('offline'),
            initialDatePeriod: 'ALL',
          ),
          lang: 'en',
          scaffold: false,
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Unbudgeted'), findsNothing);
    });
  });

  group('edit sheet', () {
    Future<void> pumpSheet(WidgetTester tester, Transaction tx,
        {required bool admin,
        String lang = 'en',
        bool dark = false,
        Future<BudgetCoverage> Function(String)? load,
        CategoryBudgetActivator? activate}) async {
      await tester.pumpWidget(localizedApp(
        EditTransactionSheet(
          transaction: tx,
          isAdmin: admin,
          loadBudgetCoverage: load ?? (_) async => _coverage,
          activateCategoryBudget: activate,
        ),
        lang: lang,
        dark: dark,
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('an admin sees "Unbudgeted" and the action, which opens the budget flow', (tester) async {
      final calls = <String>[];
      var budgeted = false;
      await pumpSheet(
        tester,
        _tx('rent', 'OPEX-HOUSING', 2500),
        admin: true,
        load: (_) async => budgeted
            ? BudgetCoverage.fromRows([
                {'category_code': 'OPEX-HOUSING', 'cycle_key': '2026-11', 'is_active': true},
              ])
            : _coverage,
        activate: (context, householdId, categoryCode) async {
          calls.add('$householdId/$categoryCode');
          budgeted = true;
          return true;
        },
      );
      expect(find.byKey(const Key('edit_unbudgeted_notice')), findsOneWidget);
      expect(find.text('Unbudgeted'), findsOneWidget);
      final action = find.text('Activate and budget');
      expect(action, findsOneWidget);
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(calls, ['h1/OPEX-HOUSING']);
      // Budgeted now: the notice goes.
      expect(find.byKey(const Key('edit_unbudgeted_notice')), findsNothing);
    });

    testWidgets('a member sees "Unbudgeted" without the action', (tester) async {
      await pumpSheet(tester, _tx('zakat', 'OPEX-CHARITY', 100), admin: false);
      expect(find.byKey(const Key('edit_unbudgeted_notice')), findsOneWidget);
      expect(find.text('Activate and budget'), findsNothing);
      expect(find.text('A household admin can give this category a budget.'), findsOneWidget);
    });

    testWidgets('a budgeted expense and a wife\'s personal purchase show nothing', (tester) async {
      await pumpSheet(tester, _tx('panda', 'OPEX-GROCERY', 120), admin: true);
      expect(find.byKey(const Key('edit_unbudgeted_notice')), findsNothing);
      await pumpSheet(tester, _tx('abaya', 'OPEX-HOUSING', 90, cls: 'wife_personal'), admin: true);
      expect(find.byKey(const Key('edit_unbudgeted_notice')), findsNothing);
    });
  });

  group('320 px at 200% text', () {
    for (final lang in ['ar', 'en', 'ur']) {
      for (final dark in [false, true]) {
        testWidgets('badge and notice ($lang, ${dark ? 'dark' : 'light'}): no overflow', (tester) async {
          tester.view.physicalSize = const Size(320 * 2, 900 * 2);
          tester.view.devicePixelRatio = 2;
          addTearDown(tester.view.reset);
          tester.platformDispatcher.textScaleFactorTestValue = 2.0;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await tester.pumpWidget(localizedApp(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Wrap(spacing: 6, runSpacing: 4, children: [UnbudgetedBadge()]),
                UnbudgetedNotice(onActivate: () {}),
                const UnbudgetedNotice(),
              ],
            ),
            lang: lang,
            dark: dark,
          ));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(MediaQuery.textScalerOf(tester.element(find.byType(Column).first)).scale(10), 20);
          expect(find.byType(UnbudgetedNotice), findsNWidgets(2));
        });
      }
    }
  });
}
