import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/models/household_dues.dart';
import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/services/salary_cycle_service.dart';
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

Widget _host(
  List<Budget> budgets,
  DateTime now, {
  double? income,
  double? operatingCash,
  List<DueLine> dues = const [],
  VoidCallback? onDueTap,
  double? pendingCommitments,
  VoidCallback? onCommitmentsTap,
  Locale locale = const Locale('en'),
}) =>
    MaterialApp(
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('ar'), Locale('ur')],
      locale: locale,
      home: Scaffold(
        body: SingleChildScrollView(
          child: BudgetHeroCard(
            budgets: budgets,
            now: now,
            monthlyIncome: income,
            operatingCash: operatingCash,
            dueLines: dues,
            onDueTap: onDueTap,
            pendingCommitments: pendingCommitments,
            onCommitmentsTap: onCommitmentsTap,
          ),
        ),
      ),
    );

/// Every verdict the hero can give; exactly one is ever on screen.
const _verdictPrefixes = ['On track for payday', 'At this pace the money runs out', 'Over by'];

int _verdictCount(WidgetTester tester) =>
    _verdictPrefixes.fold(0, (n, p) => n + tester.widgetList(find.textContaining(p)).length);

void main() {
  setUp(() => SalaryCycleService.paydayDay = 27);

  testWidgets('UX-07: one verdict, one daily figure — the run-out forecast', (tester) async {
    // 6 Nov (Riyadh): day 11 of the 27 Oct – 26 Nov cycle; 2,200 spent → 200/day;
    // 800 left lasts 4 more days → runs out around 10 Nov, before payday.
    await tester.pumpWidget(_host([_budget('OPEX-DINING', 3000, 2200)], DateTime.utc(2026, 11, 6, 9)));
    await tester.pumpAndSettle();
    expect(find.text('At this pace the money runs out around 10 Nov'), findsOneWidget);
    expect(_verdictCount(tester), 1);
    // The only daily figure: 800 over the 21 days left.
    expect(find.text('SAR 38 a day until payday'), findsOneWidget);
    expect(find.textContaining('/d'), findsNothing, reason: 'no second (burn-rate) daily figure');
    expect(find.textContaining('Projected'), findsNothing, reason: 'no second verdict');
  });

  testWidgets('on track while the money lasts until payday', (tester) async {
    await tester.pumpWidget(_host([_budget('OPEX-DINING', 3000, 500)], DateTime.utc(2026, 11, 6, 9)));
    await tester.pumpAndSettle();
    expect(find.text('On track for payday'), findsOneWidget);
    expect(_verdictCount(tester), 1);
    expect(find.textContaining('run out'), findsNothing);
  });

  testWidgets('income-based: left until payday is income minus spending', (tester) async {
    await tester.pumpWidget(_host(
      [_budget('OPEX-DINING', 3000, 2200)],
      DateTime.utc(2026, 11, 6, 9),
      income: 12000,
    ));
    await tester.pumpAndSettle();
    expect(find.text('Left until payday'), findsOneWidget);
    expect(find.text('9,800.00'), findsOneWidget);
    expect(find.text('of SAR 12,000 income'), findsOneWidget);
    expect(find.text('On track for payday'), findsOneWidget);
  });

  testWidgets('operatingCash-based: grounds left until payday in real liquid cash', (tester) async {
    await tester.pumpWidget(_host(
      [_budget('OPEX-DINING', 3000, 1000)],
      DateTime.utc(2026, 11, 6, 9),
      income: 12000,
      operatingCash: 8000,
    ));
    await tester.pumpAndSettle();
    expect(find.text('Left until payday'), findsOneWidget);
    expect(find.text('8,000.00'), findsOneWidget);
    expect(find.text('of SAR 12,000 income'), findsOneWidget);
    expect(find.text('On track for payday'), findsOneWidget);
  });

  testWidgets('overspent: one "over by" verdict and no daily figure', (tester) async {
    await tester.pumpWidget(_host([_budget('OPEX-SHOPPING', 1000, 1310)], DateTime.utc(2026, 11, 6, 9)));
    await tester.pumpAndSettle();
    expect(find.text('Over by SAR 310.00 this cycle'), findsOneWidget);
    expect(_verdictCount(tester), 1);
    expect(find.textContaining('a day until payday'), findsNothing);
    expect(find.text('131% Spent'), findsOneWidget, reason: 'not clamped to 100%');
  });

  testWidgets('family mode: "Owed to Sara" line, tappable', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_host(
      [_budget('OPEX-GROCERY', 3000, 500)],
      DateTime.utc(2026, 11, 6, 9),
      dues: const [DueLine(kind: DueKind.owedToWife, name: 'Sara', amount: 386.4)],
      onDueTap: () => taps++,
    ));
    await tester.pumpAndSettle();
    expect(find.text('Owed to Sara: SAR 386.40'), findsOneWidget);
    await tester.tap(find.text('Owed to Sara: SAR 386.40'));
    expect(taps, 1);
  });

  testWidgets('family mode in Arabic: مستحق لـسارة', (tester) async {
    await tester.pumpWidget(_host(
      [_budget('OPEX-GROCERY', 3000, 500)],
      DateTime.utc(2026, 11, 6, 9),
      dues: const [DueLine(kind: DueKind.owedToWife, name: 'سارة', amount: 386.4)],
      locale: const Locale('ar'),
    ));
    await tester.pumpAndSettle();
    expect(find.text('مستحق لـسارة: 386.40 ر.س'), findsOneWidget);
    expect(find.text('المتبقي حتى الراتب'), findsNothing, reason: 'no income: budget-based label');
  });

  testWidgets('roommates: my balance with each roommate (UX-16)', (tester) async {
    await tester.pumpWidget(_host(
      [_budget('OPEX-GROCERY', 3000, 500)],
      DateTime.utc(2026, 11, 6, 9),
      dues: const [
        DueLine(kind: DueKind.iOwe, name: 'Faisal', amount: 198.67),
        DueLine(kind: DueKind.owedByRoommate, name: 'Imran', amount: 50),
      ],
    ));
    await tester.pumpAndSettle();
    expect(find.text('You owe Faisal SAR 198.67'), findsOneWidget);
    expect(find.text('Imran owes you SAR 50.00'), findsOneWidget);
  });

  testWidgets('no dues line when nothing is owed', (tester) async {
    await tester.pumpWidget(_host([_budget('OPEX-GROCERY', 3000, 500)], DateTime.utc(2026, 11, 6, 9)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Owed to'), findsNothing);
  });

  testWidgets('commitments deduction tip displays net remaining liquidity and handles tap', (tester) async {
    var commitmentsTapped = false;
    await tester.pumpWidget(_host(
      [_budget('OPEX-FOOD', 1000, 46)],
      DateTime.utc(2026, 11, 6, 9),
      income: 8941,
      pendingCommitments: 4462.00,
      onCommitmentsTap: () => commitmentsTapped = true,
    ));
    await tester.pumpAndSettle();

    // Available balance is 8,941 - 46 = 8,895.00
    expect(find.text('8,895.00'), findsOneWidget);

    // Tip: 8,895 - 4,462 = 4,433.00 net available
    final tipFinder = find.byKey(const Key('hero_commitments_tip'));
    expect(tipFinder, findsOneWidget);
    expect(find.textContaining('4,433.00'), findsOneWidget);
    expect(find.textContaining('4,462.00'), findsOneWidget);

    await tester.tap(tipFinder);
    expect(commitmentsTapped, isTrue);
  });
}
