// The dashboard opens the setup tutor once per phone, after the household has
// loaded, with the steps for the viewer's role.
import 'dart:async';

import 'package:budget_tracker/models/household_membership.dart';
import 'package:budget_tracker/models/household_setup.dart';
import 'package:budget_tracker/providers/budget_provider.dart';
import 'package:budget_tracker/providers/installment_provider.dart';
import 'package:budget_tracker/providers/recurring_bills_provider.dart';
import 'package:budget_tracker/providers/transaction_provider.dart';
import 'package:budget_tracker/screens/home/dashboard_screen.dart';
import 'package:budget_tracker/services/api_service.dart';
import 'package:budget_tracker/widgets/dashboard/household_setup_card.dart';
import 'package:budget_tracker/widgets/onboarding/app_setup_tutor_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_settings_supabase.dart';
import '../support/localized_app.dart';

final _http = FakeSettingsHttpClient();

class _FakeNavigator extends TutorNavigator {
  final opened = <TutorAction>[];

  @override
  Future<void> open(BuildContext context, TutorAction action, String householdId, {int? paydayDay}) async => opened.add(action);
}

var _setupLoads = 0;

const _wifeRoster = HouseholdRoster(
  householdId: 'h-1',
  householdType: kHouseholdTypeFamily,
  callerRole: 'member',
  nafaqahProviderUserId: 'h',
  members: [
    HouseholdMember(userId: 'h', role: 'admin', isNafaqahProvider: true),
    HouseholdMember(userId: 'w', financialRole: 'spouse', isSelf: true),
  ],
);

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    TestWidgetsFlutterBinding.ensureInitialized();
    await initFakeSettingsSupabase(_http);
  });

  setUp(() {
    _http.resetScenario();
    final originalApi = ApiService.instance;
    ApiService.instance = FakeSettingsApi();
    addTearDown(() => ApiService.instance = originalApi);
    _setupLoads = 0;
    HouseholdSetupPrefs.loadOverride = (_) async {
      _setupLoads++;
      return const HouseholdSetupData(paydayDay: 27, roster: _wifeRoster);
    };
    addTearDown(() => HouseholdSetupPrefs.loadOverride = null);
  });

  Future<void> pumpDashboard(WidgetTester tester, {TutorNavigator? navigator}) async {
    tester.view.physicalSize = const Size(600, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<TransactionProvider>(create: (_) => TransactionProvider()),
        ChangeNotifierProvider<RecurringBillsProvider>(create: (_) => RecurringBillsProvider()),
        ChangeNotifierProvider<BudgetProvider>(create: (_) => BudgetProvider()),
        ChangeNotifierProvider<InstallmentProvider>(create: (_) => InstallmentProvider()),
      ],
      child: localizedApp(
        BudgetDashboard(
          householdId: 'h-1',
          budgetStreamOverride: (_) => Stream.value(const []),
          tutorNavigator: navigator,
        ),
        lang: 'en',
        scaffold: false,
      ),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> disposeDashboard(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 1));
  }

  testWidgets('a wife sees her tutor once the household has loaded', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpDashboard(tester);

    expect(find.byType(AppSetupTutorDialog), findsOneWidget);
    expect(find.text('Step 1 of 6'), findsOneWidget);
    expect(find.byKey(const ValueKey('tutor_action_payday')), findsNothing);
    expect(find.byKey(const ValueKey('tutor_action_income')), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(AppSetupTutorDialog.prefKey), isTrue);
    await disposeDashboard(tester);
  });

  testWidgets('after a tutor action the dashboard reloads its setup', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final navigator = _FakeNavigator();
    await pumpDashboard(tester, navigator: navigator);
    final before = _setupLoads;
    expect(before, greaterThan(0));

    await tester.tap(find.byKey(const ValueKey('tutor_action_income')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(navigator.opened, [TutorAction.income]);
    expect(find.byType(AppSetupTutorDialog), findsNothing);
    expect(_setupLoads, before + 1);
    await disposeDashboard(tester);
  });

  testWidgets('a slow first load does not open the tutor over another screen; it opens on return', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final setup = Completer<HouseholdSetupData>();
    HouseholdSetupPrefs.loadOverride = (_) => setup.future;
    await pumpDashboard(tester);
    expect(find.byType(AppSetupTutorDialog), findsNothing);

    // The person opens another screen before the household has loaded.
    unawaited(tester.state<NavigatorState>(find.byType(Navigator)).push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('OTHER SCREEN')),
    )));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    setup.complete(const HouseholdSetupData(paydayDay: 27, roster: _wifeRoster));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('OTHER SCREEN'), findsOneWidget);
    expect(find.byType(AppSetupTutorDialog), findsNothing);
    expect((await SharedPreferences.getInstance()).getBool(AppSetupTutorDialog.prefKey), isNot(true),
        reason: 'not marked seen while it was not shown');

    // Back on the dashboard, it opens.
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(AppSetupTutorDialog), findsOneWidget);
    expect((await SharedPreferences.getInstance()).getBool(AppSetupTutorDialog.prefKey), isTrue);
    await disposeDashboard(tester);
  });

  testWidgets('a phone that has seen the tutor does not show it again', (tester) async {
    SharedPreferences.setMockInitialValues({AppSetupTutorDialog.prefKey: true});
    await pumpDashboard(tester);
    expect(find.byType(AppSetupTutorDialog), findsNothing);
    await disposeDashboard(tester);
  });
}
