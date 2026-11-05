// The feed's CSV export names what it holds in the reader's language.
import 'package:budget_tracker/l10n/app_localizations.dart';
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

void main() {
  for (final lang in ['en', 'ar', 'ur']) {
    testWidgets('$lang: the export dialog from the feed says "all records" in $lang', (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      final row = Transaction.fromMap({
        'id': 'tx-1',
        'household_id': 'h1',
        'amount': 150.0,
        'currency': 'SAR',
        'merchant': 'Store',
        'category_code': 'OPEX-GROCERY',
        'timestamp': DateTime(2026, 10, 28).toIso8601String(),
        'created_at': DateTime(2026, 10, 28).toIso8601String(),
        'spent_by': 'me',
      });
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<TransactionProvider>(create: (_) => _FakeTransactions([row])),
          ChangeNotifierProvider<BudgetProvider>(create: (_) => BudgetProvider()),
          ChangeNotifierProvider<RecurringBillsProvider>(create: (_) => RecurringBillsProvider()),
        ],
        child: localizedApp(
          TransactionFeedScreen(
            householdId: 'h1',
            loadNafaqah: (_) async => const NafaqahSummary(mode: 'standard'),
            loadCycles: (_) async => const {'cycles': <Object>[]},
          ),
          lang: lang,
          scaffold: false,
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('feed_more_menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byWidgetPredicate((w) => w is PopupMenuItem && w.value == 'csv'));
      await tester.pumpAndSettle();

      final l = AppLocalizations(Locale(lang));
      expect(find.text(l.format('csv_export_title', {'label': l.get('csv_export_all_records')})), findsOneWidget);
      if (lang != 'en') expect(find.textContaining('All Records'), findsNothing);
    });
  }
}
