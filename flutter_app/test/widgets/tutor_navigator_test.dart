// The real TutorNavigator opens the right screen or sheet for each action.
// The screens' data comes from the fake Supabase and API used by the
// settings tests; only the type of what opens is checked here.
import 'package:budget_tracker/providers/account_provider.dart';
import 'package:budget_tracker/providers/budget_provider.dart';
import 'package:budget_tracker/providers/household_role_provider.dart';
import 'package:budget_tracker/providers/installment_provider.dart';
import 'package:budget_tracker/providers/recurring_bills_provider.dart';
import 'package:budget_tracker/providers/transaction_provider.dart';
import 'package:budget_tracker/screens/accounts/accounts_overview_screen.dart';
import 'package:budget_tracker/screens/home/budget_management_screen.dart';
import 'package:budget_tracker/services/api_service.dart';
import 'package:budget_tracker/services/salary_cycle_service.dart';
import 'package:budget_tracker/widgets/accounts/record_income_sheet.dart';
import 'package:budget_tracker/widgets/onboarding/tutor_navigator.dart';
import 'package:budget_tracker/models/tutor_viewer.dart';
import 'package:budget_tracker/widgets/settings/household_roles_card.dart';
import 'package:budget_tracker/widgets/settings/payday_settings_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_settings_supabase.dart';
import '../support/localized_app.dart';

final _http = FakeSettingsHttpClient();

/// A household whose payday (the 25th) differs from the phone's cached one.
class _Payday25Api extends FakeSettingsApi {
  @override
  Future<int> getHouseholdPayday(String householdId) async => 25;
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    TestWidgetsFlutterBinding.ensureInitialized();
    await initFakeSettingsSupabase(_http);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _http.resetScenario();
    final originalApi = ApiService.instance;
    ApiService.instance = FakeSettingsApi();
    addTearDown(() => ApiService.instance = originalApi);
  });

  const expected = <TutorAction, Type>{
    TutorAction.payday: PaydaySettingsCard,
    TutorAction.income: RecordIncomeSheet,
    TutorAction.accounts: AccountsOverviewScreen,
    TutorAction.budgets: BudgetManagementScreen,
    TutorAction.roles: HouseholdRolesCard,
  };

  Future<void> pumpAndOpen(WidgetTester tester, Future<void> Function(BuildContext) open) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(localizedApp(
      Builder(
        builder: (context) => Center(
          child: TextButton(
            key: const ValueKey('go'),
            onPressed: () => open(context),
            child: const SizedBox(width: 40, height: 40),
          ),
        ),
      ),
      lang: 'en',
    ));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('go')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  group("the payday editor opens on the household's payday (review R2-2)", () {
    late int cached;
    setUp(() {
      cached = SalaryCycleService.paydayDay;
      SalaryCycleService.paydayDay = 27;
      ApiService.instance = _Payday25Api();
    });
    tearDown(() => SalaryCycleService.paydayDay = cached);

    testWidgets('the payday it is given', (tester) async {
      await pumpAndOpen(tester, (context) => const TutorNavigator().open(context, TutorAction.payday, fakeSettingsHouseholdId, paydayDay: 25));
      expect(tester.widget<PaydaySettingsCard>(find.byType(PaydaySettingsCard)).initialPayday, 25);
    });

    testWidgets("without one, the household's own, not the phone's cached day", (tester) async {
      await pumpAndOpen(tester, (context) => const TutorNavigator().open(context, TutorAction.payday, fakeSettingsHouseholdId));
      expect(tester.widget<PaydaySettingsCard>(find.byType(PaydaySettingsCard)).initialPayday, 25);
    });
  });

  for (final entry in expected.entries) {
    testWidgets('${entry.key.name} opens ${entry.value}', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AccountProvider>(create: (_) => AccountProvider()),
          ChangeNotifierProvider<TransactionProvider>(create: (_) => TransactionProvider()),
          ChangeNotifierProvider<RecurringBillsProvider>(create: (_) => RecurringBillsProvider()),
          ChangeNotifierProvider<BudgetProvider>(create: (_) => BudgetProvider()),
          ChangeNotifierProvider<InstallmentProvider>(create: (_) => InstallmentProvider()),
          ChangeNotifierProvider<HouseholdRoleProvider>(
            create: (_) => HouseholdRoleProvider(loadMemberships: () async => const [], currentUserId: () => fakeSettingsUserId),
          ),
        ],
        child: localizedApp(
          Builder(
            builder: (context) => Center(
              child: TextButton(
                key: const ValueKey('go'),
                onPressed: () => const TutorNavigator().open(context, entry.key, fakeSettingsHouseholdId),
                child: const SizedBox(width: 40, height: 40),
              ),
            ),
          ),
          lang: 'en',
        ),
      ));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('go')));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(find.byType(entry.value), findsOneWidget);

      // Leave nothing running: the screens start loaders and timers.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(minutes: 1));
    });
  }
}
