import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/services/salary_cycle_service.dart';
import 'package:budget_tracker/widgets/dashboard/budget_hero_card.dart';
import 'package:flutter/material.dart';
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

Widget _host(List<Budget> budgets, DateTime now) => MaterialApp(
      localizationsDelegates: const [AppLocalizationsDelegate()],
      supportedLocales: const [Locale('en')],
      home: Scaffold(body: SingleChildScrollView(child: BudgetHeroCard(budgets: budgets, now: now))),
    );

void main() {
  setUp(() => SalaryCycleService.paydayDay = 27);

  testWidgets('hero carries the run-out forecast that SalaryCycleWidget used to show', (tester) async {
    // 6 Nov (Riyadh): day 11 of the 27 Oct – 26 Nov cycle; 2,200 spent → 200/day;
    // 800 left lasts 4 more days → runs out around 10 Nov, before payday.
    await tester.pumpWidget(_host([_budget('OPEX-DINING', 3000, 2200)], DateTime.utc(2026, 11, 6, 9)));
    await tester.pumpAndSettle();
    expect(find.text('Alert: Burn rate is high! Projected to run out around 10 Nov.'), findsOneWidget);
    expect(find.text('SAR 200 / day'), findsNothing, reason: 'daily burn is shown in the pace line, not repeated');
  });

  testWidgets('no run-out alert while the money lasts until payday', (tester) async {
    await tester.pumpWidget(_host([_budget('OPEX-DINING', 3000, 500)], DateTime.utc(2026, 11, 6, 9)));
    await tester.pumpAndSettle();
    expect(find.textContaining('run out around'), findsNothing);
  });
}
