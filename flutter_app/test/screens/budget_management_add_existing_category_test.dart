// Add Category builds the code from the typed name, so typing the name of a
// category the household already has reaches that category. A switched-off one
// is offered back with the new budget; an active one is never overwritten.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/providers/account_provider.dart';
import 'package:budget_tracker/providers/budget_provider.dart';
import 'package:budget_tracker/providers/household_role_provider.dart';
import 'package:budget_tracker/providers/installment_provider.dart';
import 'package:budget_tracker/providers/recurring_bills_provider.dart';
import 'package:budget_tracker/providers/transaction_provider.dart';
import 'package:budget_tracker/screens/home/budget_management_screen.dart';
import 'package:budget_tracker/services/api_service.dart';
import 'package:budget_tracker/services/salary_cycle_service.dart';
import '../support/localized_app.dart';

const _grocery = CategoryItem(code: 'OPEX-GROCERY', name: 'Groceries & Supermarkets', isSystem: true);
const _fuel = CategoryItem(
  code: 'OPEX-FUEL',
  name: 'Fuel & Transport',
  isSystem: true,
  isActive: false,
  isFlexible: false,
  keywords: ['fuel', 'petrol'],
);

class _FakeApi extends ApiService {
  final List<Map<String, dynamic>> added = [];
  bool fuelActive = false;
  bool failFetch = false;

  @override
  Future<Map<String, List<CategoryItem>>> fetchHouseholdCategories(String householdId) async {
    if (failFetch) throw Exception('offline');
    return {
      'active': [_grocery, if (fuelActive) _fuel],
      'inactive': [if (!fuelActive) _fuel],
    };
  }

  @override
  Future<Map<String, dynamic>> addBudgetCategory({
    required String householdId,
    required String code,
    required String category,
    required double allocatedAmount,
    bool isFlexible = true,
    List<String> keywords = const [],
  }) async {
    added.add({
      'code': code,
      'category': category,
      'amount': allocatedAmount,
      'flexible': isFlexible,
      'keywords': keywords,
    });
    return {'status': 'success', 'category_code': code};
  }
}

final _staticData = BudgetStaticData(
  householdId: 'hh-1',
  isAdmin: true,
  allCodes: [
    {'code': 'OPEX-GROCERY', 'category': 'Groceries & Supermarkets', 'is_system': 'true'},
    {'code': 'OPEX-DINING', 'category': 'Dining & Cafes', 'is_system': 'true'},
  ],
  monthlyIncome: 5000.0,
);

Map<String, dynamic> _budgetRow(String code, double allocated) {
  final cycleKey = SalaryCycleService.currentCycle().key;
  return {
    'id': 'b-$code',
    'household_id': 'hh-1',
    'category_code': code,
    'allocated_amount': allocated,
    'spent_amount': 0.0,
    'is_active': true,
    'cycle_key': cycleKey,
    'month': '$cycleKey-01',
  };
}

Future<void> _pumpScreen(
  WidgetTester tester,
  _FakeApi api, {
  List<Map<String, dynamic>> budgets = const [],
  BudgetProvider? budgetProvider,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AccountProvider>(create: (_) => AccountProvider()),
        ChangeNotifierProvider<TransactionProvider>(create: (_) => TransactionProvider()),
        ChangeNotifierProvider<RecurringBillsProvider>(create: (_) => RecurringBillsProvider()),
        ChangeNotifierProvider<BudgetProvider>.value(value: budgetProvider ?? BudgetProvider(api: api)),
        ChangeNotifierProvider<InstallmentProvider>(create: (_) => InstallmentProvider()),
        ChangeNotifierProvider<HouseholdRoleProvider>(create: (_) => HouseholdRoleProvider()),
      ],
      child: localizedApp(
        BudgetManagementScreen(
          initialStaticData: _staticData,
          loadStaticDataOverride: () async => _staticData,
          budgetStreamOverride: (_) => Stream.value(budgets),
        ),
        lang: 'en',
        scaffold: false,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _submitNewCategory(WidgetTester tester, String name, String amount) async {
  await tester.tap(find.widgetWithText(FloatingActionButton, 'Add Category'));
  await tester.pumpAndSettle();
  final fields = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField));
  await tester.enterText(fields.at(0), name);
  await tester.enterText(fields.at(1), amount);
  await tester.tap(find.widgetWithText(ElevatedButton, 'Create Category'));
  await tester.pumpAndSettle();
}

void main() {
  late ApiService original;
  late _FakeApi api;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    original = ApiService.instance;
    api = _FakeApi();
    ApiService.instance = api;
  });
  tearDown(() => ApiService.instance = original);

  testWidgets('typing a switched-off category offers it back; cancel adds nothing', (tester) async {
    await _pumpScreen(tester, api);
    await _submitNewCategory(tester, 'Fuel', '300');

    expect(find.text('Category already exists'), findsOneWidget);
    expect(find.textContaining('"Fuel" is in your Category Library (inactive)'), findsOneWidget);
    expect(api.added, isEmpty);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
    await tester.pumpAndSettle();

    expect(api.added, isEmpty);
    expect(find.widgetWithText(ElevatedButton, 'Create Category'), findsOneWidget,
        reason: 'the Add Category dialog stays open to change the name');
  });

  testWidgets('confirming activates the existing category with the new budget', (tester) async {
    await _pumpScreen(tester, api);
    await _submitNewCategory(tester, 'Fuel', '300');

    await tester.tap(find.widgetWithText(ElevatedButton, 'Activate'));
    await tester.pumpAndSettle();

    // The existing definition goes back unchanged: its name, keywords and flexible flag.
    expect(api.added, [
      {
        'code': 'OPEX-FUEL',
        'category': 'Fuel & Transport',
        'amount': 300.0,
        'flexible': false,
        'keywords': ['fuel', 'petrol'],
      },
    ]);
    expect(find.text('Category Activated'), findsOneWidget);
  });

  testWidgets('a name of an active category is refused, its budget untouched', (tester) async {
    await _pumpScreen(tester, api);
    await _submitNewCategory(tester, 'groceries & supermarkets', '50');

    expect(api.added, isEmpty);
    expect(find.text('Category already exists'), findsOneWidget);
    expect(find.textContaining('is already in your budget'), findsOneWidget);
  });

  testWidgets('a new name is added at once under its generated code', (tester) async {
    await _pumpScreen(tester, api);
    await _submitNewCategory(tester, 'Gym', '200');

    expect(find.text('Category already exists'), findsNothing);
    expect(api.added, [
      {'code': 'OPEX-GYM', 'category': 'Gym', 'amount': 200.0, 'flexible': true, 'keywords': ['gym', 'opex-gym']},
    ]);
  });

  testWidgets('an active category reached by its generated code is refused', (tester) async {
    await _pumpScreen(tester, api);
    await _submitNewCategory(tester, 'Grocery', '50'); // OPEX-GROCERY

    expect(api.added, isEmpty);
    expect(find.textContaining('is already in your budget'), findsOneWidget);
  });

  testWidgets('the check reads fresh categories, not a list cached before a change', (tester) async {
    final provider = BudgetProvider(api: api);
    await provider.getHouseholdCategories('hh-1'); // cached: Fuel inactive
    api.fuelActive = true; // switched on elsewhere (chat, another device)

    await _pumpScreen(tester, api, budgetProvider: provider);
    await _submitNewCategory(tester, 'Fuel', '300');

    expect(api.added, isEmpty, reason: 'the active Fuel budget must not be overwritten');
    expect(find.textContaining('is already in your budget'), findsOneWidget);
  });

  testWidgets('when categories cannot be loaded nothing is added', (tester) async {
    api.failFetch = true;
    await _pumpScreen(tester, api);
    await _submitNewCategory(tester, 'Fuel', '300');

    expect(api.added, isEmpty);
    expect(find.text('Add Failed'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Create Category'), findsOneWidget,
        reason: 'the dialog stays open to try again');
  });

  testWidgets('the set counter ignores a budget row of a category the screen does not list', (tester) async {
    await _pumpScreen(tester, api, budgets: [
      _budgetRow('OPEX-GROCERY', 1000),
      _budgetRow('OPEX-FUEL', 0), // stray active row of a switched-off category
    ]);

    expect(find.textContaining('1/2'), findsOneWidget);
    expect(find.textContaining('2/2'), findsNothing);
  });
}
