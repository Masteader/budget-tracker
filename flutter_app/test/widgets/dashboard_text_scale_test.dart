// UX-14: the dashboard survives 160% system text (common among older users):
// no overflow, values never truncated to "…7,100".
import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/models/household_dues.dart';
import 'package:budget_tracker/models/household_setup.dart';
import 'package:budget_tracker/models/installment_plan.dart';
import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/models/nafaqah.dart';
import 'package:budget_tracker/models/recurring_bill.dart';
import 'package:budget_tracker/providers/budget_provider.dart';
import 'package:budget_tracker/providers/recurring_bills_provider.dart';
import 'package:budget_tracker/providers/transaction_provider.dart';
import 'package:budget_tracker/services/salary_cycle_service.dart';
import 'package:budget_tracker/widgets/dashboard/app_bottom_nav_bar.dart';
import 'package:budget_tracker/widgets/card_error_state.dart';
import 'package:budget_tracker/widgets/dashboard/budget_hero_card.dart';
import 'package:budget_tracker/widgets/dashboard/family_reimbursement_card.dart';
import 'package:budget_tracker/widgets/dashboard/category_budget_card.dart';
import 'package:budget_tracker/widgets/dashboard/household_setup_card.dart';
import 'package:budget_tracker/widgets/dashboard/installment_plans_card.dart';
import 'package:budget_tracker/widgets/dashboard/multi_roommate_settlement_card.dart';
import 'package:budget_tracker/widgets/dashboard/over_budget_alerts.dart';
import 'package:budget_tracker/widgets/dashboard/recurring_bills_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Budget _b(String code, double allocated, double spent) => Budget.fromMap({
      'id': code,
      'household_id': 'hh',
      'month': '2026-11-01',
      'category_code': code,
      'allocated_amount': allocated,
      'spent_amount': spent,
      'remaining_amount': allocated - spent,
      'cycle_key': '2026-11',
    });

final _budgets = [
  _b('OPEX-GROCERY', 12000, 7100),
  _b('OPEX-SHOPPING', 1000, 1310),
  _b('OPEX-DINING', 800, 920),
];

Widget _phone(Widget child, {Locale locale = const Locale('ar'), double scale = 1.6}) {
  final bills = RecurringBillsProvider()
    ..setSummaryForTesting(
      const RecurringBillsSummary(
        cycleKey: '2026-11',
        cycleLabel: '',
        totalRecurringMonthly: 4350,
        paidThisCycle: 350,
        reservedAmount: 4000,
        bills: [
          RecurringBillItem(
            merchant: 'Housing Rent',
            normalizedMerchant: 'housing rent',
            categoryCode: 'OPEX-UTILITIES',
            subCode: 'rent',
            averageAmount: 4000,
            expectedDayOfMonth: 1,
            status: 'UPCOMING',
          ),
        ],
      ),
      householdId: 'hh',
    );
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<RecurringBillsProvider>.value(value: bills),
      ChangeNotifierProvider<TransactionProvider>.value(value: TransactionProvider()),
      ChangeNotifierProvider<BudgetProvider>.value(value: BudgetProvider()),
    ],
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('ar'), Locale('ur')],
      locale: locale,
      builder: (context, app) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: app!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: child),
        ),
      ),
    ),
  );
}

void main() {
  setUp(() => SalaryCycleService.paydayDay = 27);

  Future<void> pumpPhone(WidgetTester tester, Widget child, {Locale locale = const Locale('ar')}) async {
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_phone(child, locale: locale));
    await tester.pumpAndSettle();
  }

  for (final locale in const [Locale('ar'), Locale('en'), Locale('ur')]) {
    testWidgets('hero at 160% text (${locale.languageCode}): no overflow, tiles stacked, values whole', (tester) async {
      await pumpPhone(
        tester,
        BudgetHeroCard(
          budgets: _budgets,
          monthlyIncome: 18000,
          now: DateTime.utc(2026, 11, 6, 9),
          dueLines: const [DueLine(kind: DueKind.owedToWife, name: 'سارة', amount: 386.4)],
          onDueTap: () {},
        ),
        locale: locale,
      );
      expect(tester.takeException(), isNull);
      // Stacked: the two tiles share no row.
      final tiles = find.byWidgetPredicate((w) => w.runtimeType.toString() == '_StatCapsule');
      expect(tiles, findsNWidgets(2));
      expect(tester.getTopLeft(tiles.at(0)).dy, lessThan(tester.getTopLeft(tiles.at(1)).dy));
    });
  }

  testWidgets('hero at normal text keeps the tiles side by side', (tester) async {
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_phone(BudgetHeroCard(budgets: _budgets, now: DateTime.utc(2026, 11, 6, 9)), scale: 1.0));
    await tester.pumpAndSettle();
    final tiles = find.byWidgetPredicate((w) => w.runtimeType.toString() == '_StatCapsule');
    expect(tester.getTopLeft(tiles.at(0)).dy, tester.getTopLeft(tiles.at(1)).dy);
  });

  testWidgets('category card, over-budget alerts and installments at 160% text', (tester) async {
    await pumpPhone(
      tester,
      Column(
        children: [
          OverBudgetAlerts(budgets: _budgets, onShowAll: () {}),
          CategoryBudgetCard(budget: _budgets[1], householdId: 'hh'),
          InstallmentPlansCard(
            now: DateTime.utc(2026, 10, 21, 9),
            plans: [
              InstallmentPlan(
                id: 'p',
                householdId: 'hh',
                merchant: 'United Electronics Co. eXtra',
                provider: 'Tamara',
                totalAmount: 7408,
                installmentCount: 4,
                monthlyAmount: 1852,
                paidInstallments: 1,
                dayOfMonth: 27,
                startDate: '2026-10-01',
                status: 'ACTIVE',
              ),
            ],
          ),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('recurring bills, roommates and setup cards at 160% text', (tester) async {
    await pumpPhone(
      tester,
      Column(
        children: [
          const RecurringBillsCard(householdId: 'hh'),
          const MultiRoommateSettlementCard(
            householdId: 'hh',
            currentUserId: 'a',
            summary: SettlementV2Summary(
              mode: 'multi_roommate',
              simplifiedDebts: [
                SimplifiedDebt(fromId: 'a', toId: 'b', fromName: 'أحمد', toName: 'فيصل', amount: 198.67),
              ],
            ),
          ),
          HouseholdSetupCard(
            householdId: 'hh',
            data: HouseholdSetupData(
              paydayDay: 27,
              monthlyIncome: 0,
              roster: HouseholdRoster.fromMap({
                'household_id': 'hh',
                'household_type': 'family',
                'caller_role': 'admin',
                'members': [
                  {'user_id': 'u', 'role': 'admin', 'is_self': true},
                ],
              }),
            ),
            hasBudgets: false,
            onChanged: () {},
          ),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Nafaqah card and an error card at 160% text', (tester) async {
    await pumpPhone(
      tester,
      Column(
        children: [
          FamilyReimbursementCard(
            householdId: 'hh',
            summary: NafaqahSummary.fromMap({
              'mode': 'family_nafaqah',
              'caller_role': 'husband',
              'caller_user_id': 'u-h',
              'can_record_reimbursement': true,
              'can_set_allowance': true,
              'cycle_key': '2026-11',
              'wives': [
                {
                  'id': 'u-w',
                  'display_name': 'سارة',
                  'reimbursement': {'gross_advanced': 686.4, 'reimbursed': 300, 'outstanding': 386.4},
                  'allowance': {'is_set': true, 'allocated': 1000, 'spent': 645, 'remaining': 355},
                }
              ],
            }),
          ),
          CardErrorState(title: 'x', message: 'y', onRetry: () {}),
          CardErrorBanner(lastUpdated: DateTime(2026, 10, 21, 21, 40), onRetry: () {}),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('bottom navigation at 160% text: icons only, no overflow', (tester) async {
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    var selected = 0;
    await tester.pumpWidget(_phone(
      StatefulBuilder(
        builder: (context, setState) => AppBottomNavBar(
          selectedIndex: selected,
          onSelected: (i) => setState(() => selected = i),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('الرئيسية'), findsNothing, reason: 'labels hidden above 1.3×');
    await tester.tap(find.byKey(const Key('nav_item_3')));
    await tester.pump();
    expect(selected, 3);
  });

  testWidgets('bottom navigation at normal text shows the labels', (tester) async {
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_phone(AppBottomNavBar(selectedIndex: 0, onSelected: (_) {}), scale: 1.0, locale: const Locale('en')));
    await tester.pumpAndSettle();
    expect(find.text('Dashboard'), findsOneWidget);
  });
}
