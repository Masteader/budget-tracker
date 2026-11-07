// The dashboard lists the cycle's budgets like the budget screen: an empty
// budget row of a category the household switched off is not shown, one that
// still carries money is, and custom categories show their own name.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/providers/account_provider.dart';
import 'package:budget_tracker/providers/budget_provider.dart';
import 'package:budget_tracker/providers/installment_provider.dart';
import 'package:budget_tracker/providers/recurring_bills_provider.dart';
import 'package:budget_tracker/providers/transaction_provider.dart';
import 'package:budget_tracker/screens/home/dashboard_screen.dart';
import 'package:budget_tracker/services/api_service.dart';
import 'package:budget_tracker/services/salary_cycle_service.dart';
import 'package:budget_tracker/widgets/dashboard/category_budget_card.dart';
import '../support/localized_app.dart';

class _CategoriesApi extends ApiService {
  @override
  Future<Map<String, List<CategoryItem>>> fetchHouseholdCategories(String householdId) async => {
        'active': const [
          CategoryItem(code: 'OPEX-GROCERY', name: 'Groceries & Supermarkets', isSystem: true),
          CategoryItem(code: 'CUSTOM-CAR_TRANSPORT', name: 'Car & Transport', isSystem: false),
        ],
        'inactive': const [
          CategoryItem(code: 'OPEX-FUEL', name: 'Fuel & Transport', isSystem: true, isActive: false),
        ],
      };
}

Map<String, dynamic> _row(String code, {double allocated = 0, double delta = 0}) {
  final cycleKey = SalaryCycleService.currentCycle().key;
  return {
    'id': 'b-$code',
    'household_id': 'test-hid',
    'category_code': code,
    'allocated_amount': allocated,
    'spent_amount': 0.0,
    'previous_cycle_delta': delta,
    'is_active': true,
    'cycle_key': cycleKey,
    'month': '$cycleKey-01',
  };
}

Future<void> _pumpDashboard(WidgetTester tester, List<Map<String, dynamic>> rows) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final budgets = BudgetProvider(api: _CategoriesApi());
  await budgets.getHouseholdCategories('test-hid');

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AccountProvider>(create: (_) => AccountProvider()),
        ChangeNotifierProvider<TransactionProvider>(create: (_) => TransactionProvider()),
        ChangeNotifierProvider<RecurringBillsProvider>(create: (_) => RecurringBillsProvider()),
        ChangeNotifierProvider<BudgetProvider>.value(value: budgets),
        ChangeNotifierProvider<InstallmentProvider>(create: (_) => InstallmentProvider()),
      ],
      child: localizedApp(
        BudgetDashboard(householdId: 'test-hid', budgetStreamOverride: (_) => Stream.value(rows)),
        lang: 'en',
        scaffold: false,
      ),
    ),
  );
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await _scrollToEnd(tester);
}

/// Category codes the dashboard lists as budget cards, after scrolling to the end
/// so the lazily built list has built every card.
Set<String> _listedCodes(WidgetTester tester) {
  return tester
      .widgetList<CategoryBudgetCard>(find.byType(CategoryBudgetCard, skipOffstage: false))
      .map((c) => c.budget.categoryCode)
      .toSet();
}

Future<void> _scrollToEnd(WidgetTester tester) async {
  final position = tester.state<ScrollableState>(find.byType(Scrollable).first).position;
  var previous = -1.0;
  for (var i = 0; i < 20 && position.maxScrollExtent != previous; i++) {
    previous = position.maxScrollExtent;
    position.jumpTo(position.maxScrollExtent);
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  // The first-run tutorial would cover the dashboard.
  setUp(() => SharedPreferences.setMockInitialValues({'has_seen_setup_tutor_v2': true}));

  testWidgets('an empty budget row of a switched-off category is not listed', (tester) async {
    await _pumpDashboard(tester, [
      _row('OPEX-GROCERY', allocated: 1000),
      _row('CUSTOM-CAR_TRANSPORT', allocated: 500),
      _row('OPEX-FUEL'),
    ]);

    expect(_listedCodes(tester), {'OPEX-GROCERY', 'CUSTOM-CAR_TRANSPORT'});
    expect(find.text('Car & Transport', skipOffstage: false), findsWidgets);
    expect(find.textContaining('CUSTOM-', skipOffstage: false), findsNothing);
  });

  testWidgets('a switched-off category that carries a rollover stays listed', (tester) async {
    await _pumpDashboard(tester, [
      _row('OPEX-GROCERY', allocated: 1000),
      _row('OPEX-FUEL', delta: 50),
    ]);

    expect(_listedCodes(tester), {'OPEX-GROCERY', 'OPEX-FUEL'});
  });
}
