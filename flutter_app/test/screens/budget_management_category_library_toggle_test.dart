// The Category Library switch goes through the backend only and reports a refusal:
// the category stays where it was and the failure is shown, never a success.
import 'dart:async';

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
import '../support/localized_app.dart';

class _FakeApi extends ApiService {
  _FakeApi({required this.accept, this.answer});
  final bool accept;
  final Completer<bool>? answer; // when set, the server answers only when the test completes it
  final List<String> toggles = [];

  @override
  Future<Map<String, List<CategoryItem>>> fetchHouseholdCategories(String householdId) async => {
        'active': const [CategoryItem(code: 'OPEX-GROCERY', name: 'Groceries & Supermarkets', isSystem: true)],
        'inactive': const [CategoryItem(code: 'OPEX-FUEL', name: 'Fuel', isSystem: true, isActive: false)],
      };

  @override
  Future<bool> toggleCategoryStatus({
    required String householdId,
    required String categoryCode,
    required bool isActive,
  }) async {
    toggles.add('$categoryCode=$isActive');
    final pending = answer;
    return pending == null ? accept : await pending.future;
  }
}

final _staticData = BudgetStaticData(
  householdId: 'hh-1',
  isAdmin: true,
  allCodes: [
    {'code': 'OPEX-GROCERY', 'category': 'Groceries & Supermarkets', 'is_system': 'true'},
  ],
  monthlyIncome: 5000.0,
);

Future<void> _activateFuelInLibrary(WidgetTester tester, _FakeApi api) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AccountProvider>(create: (_) => AccountProvider()),
        ChangeNotifierProvider<TransactionProvider>(create: (_) => TransactionProvider()),
        ChangeNotifierProvider<RecurringBillsProvider>(create: (_) => RecurringBillsProvider()),
        ChangeNotifierProvider<BudgetProvider>(create: (_) => BudgetProvider(api: api)),
        ChangeNotifierProvider<InstallmentProvider>(create: (_) => InstallmentProvider()),
        ChangeNotifierProvider<HouseholdRoleProvider>(create: (_) => HouseholdRoleProvider()),
      ],
      child: localizedApp(
        BudgetManagementScreen(
          initialStaticData: _staticData,
          loadStaticDataOverride: () async => _staticData,
          budgetStreamOverride: (_) => Stream.value(const []),
        ),
        lang: 'en',
        scaffold: false,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));

  await tester.tap(find.byTooltip('Category Library'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Library / Inactive (1)'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, 'Activate'));
  await tester.pump();
  if (api.answer == null) await tester.pumpAndSettle();
}

void main() {
  late ApiService original;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    original = ApiService.instance;
  });
  tearDown(() => ApiService.instance = original);

  testWidgets('a refused switch keeps the category inactive and says it failed', (tester) async {
    final api = _FakeApi(accept: false);
    ApiService.instance = api;
    await _activateFuelInLibrary(tester, api);

    expect(api.toggles, ['OPEX-FUEL=true']);
    // Shown on top of the sheet, not behind it (hitTestable: the user can see and touch it).
    expect(find.text('Failed to update category').hitTestable(), findsOneWidget);
    expect(find.text('Category "Fuel" activated.'), findsNothing);
    expect(find.text('Library / Inactive (1)'), findsOneWidget, reason: 'Fuel is moved back to the inactive list');
  });

  testWidgets('an accepted switch is reported as activated', (tester) async {
    final api = _FakeApi(accept: true);
    ApiService.instance = api;
    await _activateFuelInLibrary(tester, api);

    expect(api.toggles, ['OPEX-FUEL=true']);
    expect(find.text('Category "Fuel" activated.').hitTestable(), findsOneWidget);
    expect(find.text('Failed to update category'), findsNothing);
  });

  testWidgets('a refusal that arrives after the sheet is closed is still shown', (tester) async {
    final answer = Completer<bool>();
    final api = _FakeApi(accept: false, answer: answer);
    ApiService.instance = api;
    await _activateFuelInLibrary(tester, api);

    // Close the sheet (tap the barrier above it) before the server answers.
    await tester.tapAt(const Offset(540, 100));
    await tester.pumpAndSettle();
    expect(find.text('Category Library'), findsNothing);

    answer.complete(false);
    await tester.pumpAndSettle();
    expect(find.text('Failed to update category').hitTestable(), findsOneWidget);
  });
}
