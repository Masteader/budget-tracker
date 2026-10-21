// UX-08: overspend is visible. 131% reads 131% (only the bar is clamped),
// the overspend amount is shown, and categories are sorted by risk.
import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/widgets/dashboard/category_budget_card.dart';
import 'package:budget_tracker/widgets/dashboard/over_budget_alerts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Budget _b(String code, double allocated, double spent) => Budget.fromMap({
      'id': code,
      'household_id': 'hh',
      'month': '2026-10-01',
      'category_code': code,
      'allocated_amount': allocated,
      'spent_amount': spent,
      'remaining_amount': allocated - spent,
      'cycle_key': '2026-10',
    });

Widget _app(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('ar'), Locale('ur')],
      locale: locale,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  group('Budget usage', () {
    test('the ratio is not clamped; the bar value is', () {
      final shopping = _b('OPEX-SHOPPING', 1000, 1310);
      expect(shopping.usageRatio, closeTo(1.31, 1e-9));
      expect(shopping.usagePercent, 1.0, reason: 'progress bars stay within 0..1');
      expect(shopping.isOverspent, isTrue);
      expect(shopping.overspentAmount, closeTo(310, 1e-9));
    });

    test('spending with no allocation is overspent by the whole amount', () {
      final b = _b('OPEX-MISC', 0, 50);
      expect(b.isOverspent, isTrue);
      expect(b.overspentAmount, 50);
    });

    test('within budget: not overspent', () {
      final b = _b('OPEX-FUEL', 500, 499.995);
      expect(b.isOverspent, isFalse);
      expect(b.overspentAmount, 0);
    });

    test('sorted by risk: overspent first (most over first), then by share used', () {
      final sorted = Budget.sortByRisk([
        _b('OPEX-FUEL', 500, 100), // 20%
        _b('OPEX-DINING', 800, 920), // 115%
        _b('OPEX-GROCERY', 2000, 1700), // 85%
        _b('OPEX-SHOPPING', 1000, 1310), // 131%
        _b('OPEX-HEALTH', 300, 0), // 0%
      ]);
      expect(sorted.map((b) => b.categoryCode), [
        'OPEX-SHOPPING',
        'OPEX-DINING',
        'OPEX-GROCERY',
        'OPEX-FUEL',
        'OPEX-HEALTH',
      ]);
    });
  });

  testWidgets('category card reads 131% and the overspend amount', (tester) async {
    await tester.pumpWidget(_app(CategoryBudgetCard(budget: _b('OPEX-SHOPPING', 1000, 1310), householdId: 'hh')));
    await tester.pumpAndSettle();
    expect(find.text('131%'), findsOneWidget);
    expect(find.text('100%'), findsNothing);
    expect(find.text('Over by SAR 310.00'), findsOneWidget);
  });

  testWidgets('category card within budget has no overspend line', (tester) async {
    await tester.pumpWidget(_app(CategoryBudgetCard(budget: _b('OPEX-FUEL', 500, 250), householdId: 'hh')));
    await tester.pumpAndSettle();
    expect(find.text('50%'), findsOneWidget);
    expect(find.textContaining('Over by'), findsNothing);
  });

  testWidgets('Arabic overspend line uses the riyal formatter', (tester) async {
    await tester.pumpWidget(_app(
      CategoryBudgetCard(budget: _b('OPEX-SHOPPING', 1000, 1310), householdId: 'hh'),
      locale: const Locale('ar'),
    ));
    await tester.pumpAndSettle();
    expect(find.text('تجاوز بـ 310.00 ر.س'), findsOneWidget);
  });

  testWidgets('over-budget alerts list the top 3 overspent categories, most over first', (tester) async {
    var showAll = 0;
    await tester.pumpWidget(_app(OverBudgetAlerts(
      budgets: [
        _b('OPEX-FUEL', 500, 100),
        _b('OPEX-DINING', 800, 920),
        _b('OPEX-SHOPPING', 1000, 1310),
        _b('OPEX-GROCERY', 1000, 1050),
        _b('OPEX-HEALTH', 100, 200),
      ],
      onShowAll: () => showAll++,
    )));
    await tester.pumpAndSettle();
    expect(find.text('Over budget (4)'), findsOneWidget);
    // Health is 200% (most over), then Shopping 131%, Dining 115%; Grocery is the 4th.
    final rows = tester.widgetList<Text>(find.byKey(const Key('over_budget_row'))).map((t) => t.data).toList();
    expect(rows, [
      'Health & Pharmacy: over by SAR 100.00',
      'Shopping & Retail: over by SAR 310.00',
      'Dining & Cafes: over by SAR 120.00',
    ]);
    await tester.tap(find.text('Show all'));
    expect(showAll, 1);
  });

  testWidgets('no over-budget alerts when nothing is overspent', (tester) async {
    await tester.pumpWidget(_app(OverBudgetAlerts(budgets: [_b('OPEX-FUEL', 500, 100)], onShowAll: () {})));
    await tester.pumpAndSettle();
    expect(find.byType(Container), findsNothing);
  });
}
