// Owner decision 2026-11-05: an expense in an inactive or unbudgeted category
// counts in totals but in no budget. The hero keeps its budget figures
// budgets-only and says, under them, how much the cycle spent outside any
// budget, so the cash picture stays honest.
import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/services/salary_cycle_service.dart';
import 'package:budget_tracker/theme/app_themes.dart';
import 'package:budget_tracker/widgets/dashboard/budget_hero_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Budget _budget(String code, double allocated, double spent) => Budget.fromMap({
      'id': code,
      'household_id': 'hh',
      'month': '2026-11-01',
      'category_code': code,
      'allocated_amount': allocated,
      'spent_amount': spent,
      'remaining_amount': allocated - spent,
      'cycle_key': '2026-11',
    });

final _budgets = [_budget('OPEX-GROCERY', 3000, 1200), _budget('OPEX-UTILITIES', 500, 0)];
final _now = DateTime.utc(2026, 11, 6, 9);

Widget _host(Widget child, {String lang = 'en', bool dark = false, double scale = 1.0}) => MaterialApp(
      locale: Locale(lang),
      theme: dark ? AppThemes.darkTheme : AppThemes.lightTheme,
      supportedLocales: const [Locale('en'), Locale('ar'), Locale('ur')],
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, app) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: app!,
      ),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

const _line = Key('hero_unbudgeted_line');

void main() {
  setUp(() => SalaryCycleService.paydayDay = 27);

  testWidgets('shows the cycle\'s unbudgeted spending under the budget figures', (tester) async {
    await tester.pumpWidget(_host(BudgetHeroCard(budgets: _budgets, now: _now, unbudgetedSpending: 2600)));
    await tester.pumpAndSettle();
    expect(find.byKey(_line), findsOneWidget);
    expect(find.text('Unbudgeted spending: SAR 2,600.00'), findsOneWidget);
  });

  testWidgets('the budget figures stay budgets-only', (tester) async {
    await tester.pumpWidget(_host(BudgetHeroCard(budgets: _budgets, now: _now)));
    await tester.pumpAndSettle();
    final without = [
      for (final t in tester.widgetList<Text>(find.byType(Text))) t.data,
    ];
    await tester.pumpWidget(_host(BudgetHeroCard(budgets: _budgets, now: _now, unbudgetedSpending: 2600)));
    await tester.pumpAndSettle();
    final withLine = [
      for (final t in tester.widgetList<Text>(find.byType(Text))) t.data,
    ]..remove('Unbudgeted spending: SAR 2,600.00');
    expect(withLine, without, reason: 'only the one line is added; allocated, spent and left are unchanged');
  });

  for (final value in [null, 0.0, 0.004]) {
    testWidgets('no line when there is nothing unbudgeted ($value)', (tester) async {
      await tester.pumpWidget(_host(BudgetHeroCard(budgets: _budgets, now: _now, unbudgetedSpending: value)));
      await tester.pumpAndSettle();
      expect(find.byKey(_line), findsNothing);
    });
  }

  testWidgets('Arabic and Urdu', (tester) async {
    await tester.pumpWidget(_host(BudgetHeroCard(budgets: _budgets, now: _now, unbudgetedSpending: 2600), lang: 'ar'));
    await tester.pumpAndSettle();
    expect(find.text('إنفاق خارج الميزانية: 2,600.00 ر.س'), findsOneWidget);
    await tester.pumpWidget(_host(BudgetHeroCard(budgets: _budgets, now: _now, unbudgetedSpending: 2600), lang: 'ur'));
    await tester.pumpAndSettle();
    expect(find.byKey(_line), findsOneWidget);
    expect(find.textContaining('بجٹ سے باہر خرچ'), findsOneWidget);
  });

  for (final lang in ['ar', 'en', 'ur']) {
    for (final dark in [false, true]) {
      testWidgets('320 px at 200% text ($lang, ${dark ? 'dark' : 'light'}): no overflow', (tester) async {
        tester.view.physicalSize = const Size(320 * 2, 900 * 2);
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(_host(
          BudgetHeroCard(budgets: _budgets, now: _now, monthlyIncome: 18000, unbudgetedSpending: 1234567.89),
          lang: lang,
          dark: dark,
          scale: 2.0,
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byKey(_line), findsOneWidget);
      });
    }
  }
}
