import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/models/nafaqah.dart';
import 'package:budget_tracker/providers/budget_provider.dart';
import 'package:budget_tracker/providers/recurring_bills_provider.dart';
import 'package:budget_tracker/providers/transaction_provider.dart';
import 'package:budget_tracker/screens/home/transaction_feed_screen.dart';
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

Transaction _txWithCycle(String id, double amount, DateTime at, {String? cycleKey}) =>
    Transaction.fromMap({
      'id': id,
      'household_id': 'h1',
      'amount': amount,
      'currency': 'SAR',
      'merchant': 'Store $id',
      'category_code': 'OPEX-GROCERY',
      'timestamp': at.toIso8601String(),
      'created_at': at.toIso8601String(),
      'spent_by': 'me',
      'cycle_key': cycleKey,
    });

void main() {
  testWidgets('TransactionFeedScreen filters transactions by active salary cycle', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final mockCycles = {
      'current_cycle': {
        'cycle_key': '2026-11',
        'cycle_start': '2026-10-27',
        'cycle_end': '2026-11-26',
        'label': 'November 2026 Budget',
        'month_name': 'November 2026',
        'payday_day': 27,
        'is_current': true,
      },
      'cycles': [
        {
          'cycle_key': '2026-11',
          'cycle_start': '2026-10-27',
          'cycle_end': '2026-11-26',
          'label': 'November 2026 Budget',
          'month_name': 'November 2026',
          'payday_day': 27,
          'is_current': true,
        },
        {
          'cycle_key': '2026-10',
          'cycle_start': '2026-09-27',
          'cycle_end': '2026-10-26',
          'label': 'October 2026 Budget',
          'month_name': 'October 2026',
          'payday_day': 27,
          'is_current': false,
        },
      ],
      'payday_day': 27,
    };

    // Rows: tx1 in new cycle 2026-11, tx2 in mid-October 2026-10
    final rows = [
      _txWithCycle('tx-new', 150.0, DateTime(2026, 10, 28), cycleKey: '2026-11'),
      _txWithCycle('tx-mid-oct', 3352.0, DateTime(2026, 10, 12), cycleKey: '2026-10'),
    ];

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<TransactionProvider>(create: (_) => _FakeTransactions(rows)),
        ChangeNotifierProvider<BudgetProvider>(create: (_) => BudgetProvider()),
        ChangeNotifierProvider<RecurringBillsProvider>(create: (_) => RecurringBillsProvider()),
      ],
      child: localizedApp(
        TransactionFeedScreen(
          householdId: 'h1',
          loadNafaqah: (_) async => const NafaqahSummary(mode: 'standard'),
          loadCycles: (_) async => mockCycles,
        ),
        lang: 'en',
        scaffold: false,
      ),
    ));

    await tester.pumpAndSettle();

    // In current cycle (2026-11), tx-new is visible, but tx-mid-oct is filtered out!
    expect(find.text('Store tx-new'), findsOneWidget);
    expect(find.text('Store tx-mid-oct'), findsNothing);

    // Now tap Previous cycle chevron on the SalaryCycleSelectorBar to navigate to 2026-10
    final prevChevron = find.byIcon(Icons.chevron_left_rounded);
    expect(prevChevron, findsOneWidget);
    await tester.tap(prevChevron);
    await tester.pumpAndSettle();

    // Now in October cycle (2026-10): tx-mid-oct is visible, tx-new is hidden!
    expect(find.text('Store tx-mid-oct'), findsOneWidget);
    expect(find.text('Store tx-new'), findsNothing);
  });
}
