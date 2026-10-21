// UX-04 / UX-11 / UX-19: the feed shows who owes whom in a family, groups
// rows by day, keeps amounts neutral and gives every control a 48 dp target.
import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/models/nafaqah.dart';
import 'package:budget_tracker/providers/budget_provider.dart';
import 'package:budget_tracker/providers/recurring_bills_provider.dart';
import 'package:budget_tracker/providers/transaction_provider.dart';
import 'package:budget_tracker/screens/home/transaction_feed_screen.dart';
import 'package:budget_tracker/theme/app_themes.dart';
import 'package:budget_tracker/widgets/transactions/nafaqah_feed_badge.dart';
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

Transaction _tx(String id, double amount, DateTime at, {String? cls, String? spouse, bool settlement = false}) =>
    Transaction.fromMap({
      'id': id,
      'household_id': 'h1',
      'amount': amount,
      'currency': 'SAR',
      'merchant': 'Store $id',
      'category_code': 'OPEX-GROCERY',
      'timestamp': at.toIso8601String(),
      'created_at': at.toIso8601String(),
      'spent_by': 'both',
      'nafaqah_class': cls,
      'nafaqah_spouse_id': spouse,
      'is_settlement': settlement,
    });

const _family = NafaqahSummary(
  mode: 'family_nafaqah',
  callerRole: 'husband',
  callerUserId: 'u-husband',
  husbandId: 'u-husband',
  wives: [NafaqahWife(id: 'u-wife', displayName: 'سارة')],
);

void main() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day, 10, 30);
  final yesterday = today.subtract(const Duration(days: 1));
  final older = today.subtract(const Duration(days: 5));

  Future<void> pumpFeed(WidgetTester tester, List<Transaction> rows,
      {NafaqahSummary summary = _family, String lang = 'ar'}) async {
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
        TransactionFeedScreen(householdId: 'h1', loadNafaqah: (_) async => summary),
        lang: lang,
        scaffold: false,
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('family: Nafaqah badges replace "shared" on every row', (tester) async {
    await pumpFeed(tester, [
      _tx('a', 342.75, today, cls: kWifeReimbursable, spouse: 'u-wife'),
      _tx('b', 120, today, cls: kWifePersonal, spouse: 'u-wife'),
      _tx('c', 80, yesterday),
      _tx('d', 200, older, settlement: true),
    ]);
    expect(find.text('مستحق لـسارة'), findsOneWidget);
    expect(find.text('من مصروف سارة'), findsOneWidget);
    expect(find.text('مصروف البيت'), findsOneWidget);
    expect(find.text('تسوية'), findsOneWidget);
    expect(find.text('مشترك'), findsNothing);
  });

  testWidgets('rows are grouped under Today / Yesterday / the date', (tester) async {
    await pumpFeed(tester, [
      _tx('a', 10, today),
      _tx('b', 20, yesterday),
      _tx('c', 30, older),
    ]);
    expect(find.text('اليوم'), findsOneWidget);
    expect(find.text('أمس'), findsOneWidget);
    expect(find.byKey(const ValueKey('feed_day_header')), findsNWidgets(3));
    final todayY = tester.getTopLeft(find.text('اليوم')).dy;
    final yesterdayY = tester.getTopLeft(find.text('أمس')).dy;
    expect(todayY, lessThan(yesterdayY));
  });

  testWidgets('amounts are neutral ink, not alarm red', (tester) async {
    await pumpFeed(tester, [_tx('a', 342.75, today)]);
    final amount = tester.widget<Text>(find.text('342.75 ر.س'));
    expect(amount.style?.color, AppThemes.brandLightText);
  });

  testWidgets('export lives in the overflow menu; the sort control is 48 dp tall', (tester) async {
    await pumpFeed(tester, [_tx('a', 10, today)]);
    expect(find.text('تصدير CSV'), findsNothing);
    final sort = find.byKey(const ValueKey('feed_sort_button'));
    expect(tester.getSize(sort).height, greaterThanOrEqualTo(48));
    await tester.tap(find.byKey(const ValueKey('feed_more_menu')));
    await tester.pumpAndSettle();
    expect(find.text('تصدير CSV'), findsOneWidget);
    expect(find.text('تصدير PDF'), findsOneWidget);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  });

  testWidgets('roommates keep the shared badge and get no Nafaqah wording', (tester) async {
    await pumpFeed(tester, [_tx('a', 10, today)], summary: const NafaqahSummary(mode: 'not_family'));
    expect(find.text('مصروف البيت'), findsNothing);
    expect(find.byKey(const ValueKey('feed_badge_household')), findsNothing);
  });

  testWidgets('family filter: only what is owed to the wife', (tester) async {
    await pumpFeed(tester, [
      _tx('a', 342.75, today, cls: kWifeReimbursable, spouse: 'u-wife'),
      _tx('c', 80, today),
    ]);
    await tester.tap(find.byTooltip('تصفية وترتيب'));
    await tester.pumpAndSettle();
    final owed = find.text('مستحق لـسارة').last;
    await tester.ensureVisible(owed);
    await tester.tap(owed);
    await tester.pumpAndSettle();
    await tester.tap(find.text('تطبيق التصفية'));
    await tester.pumpAndSettle();
    expect(find.text('Store a'), findsOneWidget);
    expect(find.text('Store c'), findsNothing);
  });

  test('grouping keeps the order and splits on local days', () {
    final groups = groupTransactionsByDay([_tx('a', 1, today), _tx('b', 1, today), _tx('c', 1, older)]);
    expect(groups.map((g) => g.transactions.length), [2, 1]);
  });
}
