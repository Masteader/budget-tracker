// Owner decision 2026-11-05: an expense in an inactive or unbudgeted category
// is filed under it and counts in no budget. The feed and the edit sheet say
// "Unbudgeted"; the edit sheet offers an admin the existing budget dialog to
// activate the category and give it a budget.
import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/models/budget_coverage.dart';
import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/models/nafaqah.dart';
import 'package:budget_tracker/providers/budget_provider.dart';
import 'package:budget_tracker/providers/recurring_bills_provider.dart';
import 'package:budget_tracker/providers/transaction_provider.dart';
import 'package:budget_tracker/screens/home/edit_transaction_sheet.dart';
import 'package:budget_tracker/screens/home/transaction_feed_screen.dart';
import 'package:budget_tracker/services/salary_cycle_service.dart';
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

/// What an error message may carry and the log must not.
const _secret = 'Insufficient funds: balance (1234.56) owner@example.com';

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

    testWidgets('a failed read logs its type, never its message', (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      final log = <String>[];
      final original = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) log.add(message);
      };
      addTearDown(() => debugPrint = original);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<TransactionProvider>(create: (_) => _FakeTransactions([_tx('rent', 'OPEX-HOUSING', 2500)])),
          ChangeNotifierProvider<BudgetProvider>(create: (_) => BudgetProvider()),
          ChangeNotifierProvider<RecurringBillsProvider>(create: (_) => RecurringBillsProvider()),
        ],
        child: localizedApp(
          TransactionFeedScreen(
            householdId: 'h1',
            loadNafaqah: (_) async => throw Exception(_secret),
            loadBudgetCoverage: (_) async => throw Exception(_secret),
            loadCycles: (_) async => throw Exception(_secret),
            initialDatePeriod: 'ALL',
          ),
          lang: 'en',
          scaffold: false,
        ),
      ));
      await tester.pumpAndSettle();
      await tester.pumpWidget(localizedApp(
        EditTransactionSheet(
          transaction: _tx('rent', 'OPEX-HOUSING', 2500),
          isAdmin: true,
          loadBudgetCoverage: (_) async => throw Exception(_secret),
        ),
      ));
      await tester.pumpAndSettle();
      debugPrint = original;

      expect(log.where((l) => l.contains('TransactionFeed.budgetCoverage')), isNotEmpty);
      expect(log.where((l) => l.contains('TransactionFeed.familyContext')), isNotEmpty);
      expect(log.where((l) => l.contains('TransactionFeed.cycles')), isNotEmpty);
      expect(log.where((l) => l.contains('EditTransactionSheet.budgetCoverage')), isNotEmpty);
      expect(log.where((l) => l.contains('1234.56') || l.contains('owner@example.com')), isEmpty);
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
        activate: (context, householdId, categoryCode, cycleKey) async {
          calls.add('$householdId/$categoryCode/$cycleKey');
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
      // The expense's own cycle, which the server stamped on it.
      expect(calls, ['h1/OPEX-HOUSING/2026-11']);
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

  group('current cycle versus an older one', () {
    final current = SalaryCycleService.currentCycle();
    final previous = SalaryCycleService.cycleForInstant(current.start.subtract(const Duration(days: 1)));
    final older = SalaryCycleService.cycleForInstant(previous.start.subtract(const Duration(days: 1)));

    Transaction row(String id, String cycleKey, DateTime at) => Transaction.fromMap({
          'id': id,
          'household_id': 'h1',
          'amount': 75.0,
          'currency': 'SAR',
          'merchant': 'Store $id',
          'category_code': 'OPEX-CHARITY',
          'timestamp': at.toIso8601String(),
          'created_at': at.toIso8601String(),
          'cycle_key': cycleKey,
          'spent_by': 'both',
        });

    // Budgeting started last cycle: Grocery had a budget then and has one now.
    final coverage = BudgetCoverage.fromRows([
      {'category_code': 'OPEX-GROCERY', 'cycle_key': current.key, 'is_active': true},
      {'category_code': 'OPEX-GROCERY', 'cycle_key': previous.key, 'is_active': true},
    ]);

    Future<void> pumpSheet(WidgetTester tester, Transaction tx, {String lang = 'en', CategoryBudgetActivator? activate}) async {
      await tester.pumpWidget(localizedApp(
        EditTransactionSheet(
          transaction: tx,
          isAdmin: true,
          loadBudgetCoverage: (_) async => coverage,
          activateCategoryBudget: activate,
        ),
        lang: lang,
      ));
      await tester.pumpAndSettle();
    }

    for (final lang in const ['en', 'ar', 'ur']) {
      testWidgets('$lang: this cycle offers the action and says "this cycle"', (tester) async {
        final l = AppLocalizations(Locale(lang));
        await pumpSheet(tester, row('now', current.key, current.start.add(const Duration(hours: 2))), lang: lang);
        expect(find.byKey(const Key('edit_unbudgeted_notice')), findsOneWidget);
        expect(find.byKey(const Key('edit_unbudgeted_activate')), findsOneWidget);
        expect(find.text(l.get('unbudgeted_notice')), findsOneWidget);
      });

      testWidgets('$lang: an older row names its own cycle and offers no action', (tester) async {
        final l = AppLocalizations(Locale(lang));
        await pumpSheet(tester, row('then', previous.key, previous.start.add(const Duration(hours: 2))), lang: lang);
        expect(find.byKey(const Key('edit_unbudgeted_notice')), findsOneWidget);
        expect(find.byKey(const Key('edit_unbudgeted_activate')), findsNothing);
        expect(find.text(l.get('unbudgeted_notice')), findsNothing, reason: 'not "this cycle"');
        expect(find.text(l.get('unbudgeted_admin_only')), findsNothing);
        final label = l.cycleLabel(previous.key);
        expect(find.text(l.format('unbudgeted_notice_past', {'cycle': label})), findsOneWidget);
      });
    }

    testWidgets('an older row never opens the budget dialog of this cycle', (tester) async {
      var opened = 0;
      await pumpSheet(
        tester,
        row('then', previous.key, previous.start.add(const Duration(hours: 2))),
        activate: (context, householdId, code, cycleKey) async {
          opened++;
          return true;
        },
      );
      expect(find.text('Activate and budget'), findsNothing);
      expect(opened, 0);
    });

    testWidgets('a row from before the household budgeted at all is not marked', (tester) async {
      await pumpSheet(tester, row('before', older.key, older.start.add(const Duration(hours: 2))));
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
                UnbudgetedNotice(pastCycleLabel: AppLocalizations(Locale(lang)).cycleLabel('2026-10')),
              ],
            ),
            lang: lang,
            dark: dark,
          ));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(MediaQuery.textScalerOf(tester.element(find.byType(Column).first)).scale(10), 20);
          expect(find.byType(UnbudgetedNotice), findsNWidgets(3));
        });
      }
    }
  });
}
