// The partner settlement section of the real SettingsScreen, against a fake API
// that can hold a household's answer back: a settled debt must stay settled, and
// one household's debts must never appear under another (B4, B5, B6).
import 'dart:async';

import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/providers/locale_provider.dart';
import 'package:budget_tracker/providers/theme_provider.dart';
import 'package:budget_tracker/screens/settings/settings_screen.dart';
import 'package:budget_tracker/services/api/base_api_client.dart';
import 'package:budget_tracker/services/api_service.dart';
import 'package:budget_tracker/theme/app_themes.dart';
import 'package:budget_tracker/widgets/dashboard/multi_roommate_settlement_card.dart';
import 'package:budget_tracker/widgets/settings/household_roles_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_settings_supabase.dart';

const _a = fakeSettingsHouseholdId;
const _b = 'hh-2';

final _http = FakeSettingsHttpClient();
late FakeSettingsApi _api;
final _en = AppLocalizations(const Locale('en'));

class _DeniedPermissions extends PermissionHandlerPlatform {
  @override
  Future<PermissionStatus> checkPermissionStatus(Permission permission) async => PermissionStatus.denied;
}

SettlementV2Summary _roommate(String from, String to, double amount) => SettlementV2Summary(
      mode: 'multi_roommate',
      simplifiedDebts: [SimplifiedDebt(fromId: 'id-$from', toId: 'id-$to', fromName: from, toName: to, amount: amount)],
      pairwiseDebts: [PairwiseDebt(fromId: 'id-$from', toId: 'id-$to', fromName: from, toName: to, amount: amount)],
    );

const _settled = SettlementV2Summary(mode: 'multi_roommate');

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 12000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ChangeNotifierProvider(create: (_) => LocaleProvider()),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      theme: AppThemes.lightTheme,
      supportedLocales: const [Locale('en'), Locale('ar'), Locale('ur')],
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const SettingsScreen(),
    ),
  ));
  await _settle(tester);
}

Finder get _sectionTitle => find.text(_en.get('set_partner_settlement_section'));

Future<void> _openSettlement(WidgetTester tester) async {
  await tester.ensureVisible(_sectionTitle);
  await tester.tap(_sectionTitle);
  await _settle(tester);
}

Future<void> _switchTo(WidgetTester tester, String hid) async {
  await tester.ensureVisible(find.text(_en.get('join_with_code')));
  await tester.tap(find.text(_en.get('join_with_code')));
  await _settle(tester);
  await tester.tap(find.text('Household $hid'));
  await _settle(tester);
}

Finder get _settleButton => find.widgetWithText(ElevatedButton, _en.get('settle_now'));

Future<void> _recordSettlement(WidgetTester tester) async {
  await tester.ensureVisible(_settleButton.first);
  await tester.tap(_settleButton.first);
  await _settle(tester);
  await tester.tap(find.widgetWithText(ElevatedButton, _en.get('settle_record_payment')));
  await _settle(tester);
}

Future<void> _resumeApp(WidgetTester tester) async {
  for (final state in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
  await _settle(tester);
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    TestWidgetsFlutterBinding.ensureInitialized();
    await initFakeSettingsSupabase(_http);
    PermissionHandlerPlatform.instance = _DeniedPermissions();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    _http.resetScenario();
    final original = ApiService.instance;
    _api = FakeSettingsApi()
      ..memberships = const [
        HouseholdMembership(householdId: _a, householdName: 'Household $_a', inviteCode: 'AAAAAAAA', role: 'admin', isActive: true),
        HouseholdMembership(householdId: _b, householdName: 'Household $_b', inviteCode: 'BBBBBBBB', role: 'admin'),
      ]
      ..onSwitched = (hid) => _http.activeHouseholdId = hid;
    ApiService.instance = _api;
    addTearDown(() => ApiService.instance = original);
  });

  group('a settled debt stays settled (B4)', () {
    setUp(() {
      _api.byHousehold[_a] = _roommate('Faisal', 'Imran', 300);
      _api.onRecordPayment = (_) async {
        _api.byHousehold[_a] = _settled;
        return const {'status': 'success'};
      };
    });

    testWidgets('resuming the app after settling does not bring the debt back', (tester) async {
      await _pump(tester);
      await _openSettlement(tester);
      expect(find.textContaining('Faisal'), findsWidgets);

      await _recordSettlement(tester);
      expect(find.text(_en.get('settle_all_settled')), findsOneWidget);

      // The return from STC Pay: the page rebuilds with what its parent holds.
      await _resumeApp(tester);
      expect(find.text(_en.get('settle_all_settled')), findsOneWidget);
      expect(_settleButton, findsNothing);
      expect(find.byKey(const Key('roommate_debt_title')), findsNothing);
    });

    testWidgets('the section refetches through onSettled', (tester) async {
      await _pump(tester);
      await _openSettlement(tester);
      expect(tester.widget<MultiRoommateSettlementCard>(find.byType(MultiRoommateSettlementCard)).onSettled, isNotNull);
      final before = _api.settlementCallCount;

      await _recordSettlement(tester);
      // The card's own reload, and the section's through onSettled.
      expect(_api.settlementCallCount, before + 2);

      // What the section holds is fresh too: rebuilds and new cards agree.
      await tester.tap(_sectionTitle);
      await _settle(tester);
      await tester.tap(_sectionTitle);
      await _settle(tester);
      expect(find.text(_en.get('settle_all_settled')), findsOneWidget);
    });

    testWidgets('while the refetch is running the settled debt cannot be tapped', (tester) async {
      await _pump(tester);
      await _openSettlement(tester);
      final hold = Completer<void>();
      _api.holds[_a] = hold;

      await _recordSettlement(tester);
      expect(_settleButton, findsNothing);
      expect(find.byKey(const Key('roommate_debt_title')), findsNothing);

      hold.complete();
      await _settle(tester);
      expect(find.text(_en.get('settle_all_settled')), findsOneWidget);
    });

    testWidgets('a timeout after the server committed: reloaded, nothing left to tap twice', (tester) async {
      var recorded = 0;
      _api.onRecordPayment = (_) async {
        // The server stores the row; its answer is lost on the way back.
        recorded++;
        _api.byHousehold[_a] = _settled;
        throw const ApiRequestException('timed out', noResponse: true);
      };
      await _pump(tester);
      await _openSettlement(tester);
      final before = _api.settlementCallCount;

      await _recordSettlement(tester);

      expect(recorded, 1);
      expect(find.text(_en.get('settle_unconfirmed_msg')), findsOneWidget);
      expect(find.text(_en.get('settle_record_failed_msg')), findsNothing);
      expect(find.widgetWithText(ElevatedButton, _en.get('settle_record_payment')), findsNothing);
      expect(_api.settlementCallCount, before + 2, reason: 'the card and the section both reload');
      expect(find.text(_en.get('settle_all_settled')), findsOneWidget);
      expect(_settleButton, findsNothing);
    });

    testWidgets('a failed refetch offers Retry, not the debt that was just settled', (tester) async {
      await _pump(tester);
      await _openSettlement(tester);
      _api.failingHouseholds.add(_a);

      await _recordSettlement(tester);
      expect(_settleButton, findsNothing);
      expect(find.byKey(const Key('roommate_debt_title')), findsNothing);
      expect(find.text(_en.get('roles_retry')), findsOneWidget);

      _api.failingHouseholds.remove(_a);
      await tester.tap(find.text(_en.get('roles_retry')));
      await _settle(tester);
      expect(find.text(_en.get('settle_all_settled')), findsOneWidget);
    });
  });

  group('no household mixing (B5)', () {
    testWidgets('a failed fetch after a switch shows Retry and nothing of the old household', (tester) async {
      _api.byHousehold[_a] = _roommate('Ali', 'Omar', 900);
      await _pump(tester);
      await _openSettlement(tester);
      expect(find.textContaining('Ali'), findsWidgets);

      _api.failingHouseholds.add(_b);
      await _switchTo(tester, _b);

      expect(find.textContaining('Ali'), findsNothing);
      expect(find.byType(MultiRoommateSettlementCard), findsNothing);
      expect(find.text(_en.get('roles_retry')), findsOneWidget);

      _api.failingHouseholds.remove(_b);
      _api.byHousehold[_b] = _roommate('Sami', 'Nasser', 50);
      await tester.tap(find.text(_en.get('roles_retry')));
      await _settle(tester);
      expect(find.textContaining('Sami'), findsWidgets);
      expect(tester.widget<MultiRoommateSettlementCard>(find.byType(MultiRoommateSettlementCard)).householdId, _b);
    });

    testWidgets('after a switch the section is empty until the new household answers', (tester) async {
      _api.byHousehold[_a] = _roommate('Ali', 'Omar', 900);
      await _pump(tester);
      await _openSettlement(tester);

      final slowB = Completer<SettlementV2Summary>();
      _api.gates[_b] = slowB;
      await _switchTo(tester, _b);
      expect(find.textContaining('Ali'), findsNothing);
      expect(find.byType(MultiRoommateSettlementCard), findsNothing);

      slowB.complete(_roommate('Sami', 'Nasser', 50));
      await _settle(tester);
      expect(find.textContaining('Sami'), findsWidgets);
    });

    testWidgets('settling after a switch records against the new household', (tester) async {
      _api.byHousehold[_a] = _roommate('Ali', 'Omar', 900);
      _api.byHousehold[_b] = _roommate('Sami', 'Nasser', 50);
      ReimbursementRecordRequest? recorded;
      _api.onRecordPayment = (req) async {
        recorded = req;
        return const {'status': 'success'};
      };
      await _pump(tester);
      await _openSettlement(tester);
      await _switchTo(tester, _b);
      await _recordSettlement(tester);
      expect(recorded!.householdId, _b);
      expect(recorded!.payerId, 'id-Sami');
    });
  });

  group('a late answer cannot land on the wrong household (B6)', () {
    testWidgets('the slow answer of a household that was never opened', (tester) async {
      _api.byHousehold[_b] = _roommate('Sami', 'Nasser', 50);
      final slowA = Completer<SettlementV2Summary>();
      _api.gates[_a] = slowA;
      await _pump(tester);
      await _switchTo(tester, _b);
      await _settle(tester);
      await _openSettlement(tester);
      expect(find.textContaining('Sami'), findsWidgets);
      slowA.complete(_roommate('Ali', 'Omar', 900));
      await _settle(tester);
      expect(find.textContaining('Ali'), findsNothing);
    });

    testWidgets('a request really in flight when the switch happens', (tester) async {
      _api.byHousehold[_b] = _roommate('Sami', 'Nasser', 50);
      final slowA = Completer<SettlementV2Summary>();
      _api.gates[_a] = slowA;
      await _pump(tester);
      await _openSettlement(tester);
      expect(_api.gates, isEmpty, reason: 'the request for A must be in flight');

      await _switchTo(tester, _b);
      expect(find.textContaining('Sami'), findsWidgets);

      slowA.complete(_roommate('Ali', 'Omar', 900));
      await _settle(tester);
      expect(find.textContaining('Ali'), findsNothing);
      expect(find.textContaining('Sami'), findsWidgets);
    });

    testWidgets('a late failure of the old household does not put Retry over the new one', (tester) async {
      _api.byHousehold[_b] = _roommate('Sami', 'Nasser', 50);
      final slowA = Completer<SettlementV2Summary>();
      _api.gates[_a] = slowA;
      await _pump(tester);
      await _openSettlement(tester);
      await _switchTo(tester, _b);

      slowA.completeError(Exception('late failure'));
      await _settle(tester);
      expect(find.text(_en.get('roles_retry')), findsNothing);
      expect(find.textContaining('Sami'), findsWidgets);
    });

    testWidgets('within one household an older failure cannot replace a newer answer', (tester) async {
      _api.byHousehold[_a] = _roommate('First', 'Debt', 10);
      await _pump(tester);
      await _openSettlement(tester);

      final older = Completer<SettlementV2Summary>();
      _api.gates[_a] = older;
      tester.widget<HouseholdRolesCard>(find.byType(HouseholdRolesCard)).onNafaqahProviderChanged!(null);
      await _settle(tester);

      _api.byHousehold[_a] = _roommate('Newest', 'Debt', 20);
      tester.widget<HouseholdRolesCard>(find.byType(HouseholdRolesCard)).onNafaqahProviderChanged!(null);
      await _settle(tester);

      older.completeError(Exception('late failure'));
      await _settle(tester);
      expect(find.text(_en.get('roles_retry')), findsNothing);
      expect(find.textContaining('Newest'), findsWidgets);
    });

    testWidgets('within one household an older answer cannot replace a newer one', (tester) async {
      _api.byHousehold[_a] = _roommate('First', 'Debt', 10);
      await _pump(tester);
      await _openSettlement(tester);

      final older = Completer<SettlementV2Summary>();
      _api.gates[_a] = older;
      tester.widget<HouseholdRolesCard>(find.byType(HouseholdRolesCard)).onNafaqahProviderChanged!(null);
      await _settle(tester);

      _api.byHousehold[_a] = _roommate('Newest', 'Debt', 20);
      tester.widget<HouseholdRolesCard>(find.byType(HouseholdRolesCard)).onNafaqahProviderChanged!(null);
      await _settle(tester);
      expect(find.textContaining('Newest'), findsWidgets);

      older.complete(_roommate('Stale', 'Debt', 30));
      await _settle(tester);
      expect(find.textContaining('Stale'), findsNothing);
      expect(find.textContaining('Newest'), findsWidgets);
    });
  });

  group('fetched when opened (TASK-03)', () {
    testWidgets('nothing is fetched until the section opens, then once across rebuilds', (tester) async {
      await _pump(tester);
      expect(_api.settlementCallCount, 0);

      await _openSettlement(tester);
      expect(_api.settlementCallCount, 1);

      await tester.tap(find.text(_en.get('set_money_section')));
      await _settle(tester);
      await _resumeApp(tester);
      expect(_api.settlementCallCount, 1);
    });

    testWidgets('a provider change refetches', (tester) async {
      await _pump(tester);
      await _openSettlement(tester);
      final before = _api.settlementCallCount;
      tester.widget<HouseholdRolesCard>(find.byType(HouseholdRolesCard)).onNafaqahProviderChanged!(null);
      await _settle(tester);
      expect(_api.settlementCallCount, before + 1);
    });

    testWidgets('a role change refetches', (tester) async {
      await _pump(tester);
      await _openSettlement(tester);
      final before = _api.settlementCallCount;
      tester.widget<HouseholdRolesCard>(find.byType(HouseholdRolesCard)).onRolesChanged!();
      await _settle(tester);
      expect(_api.settlementCallCount, before + 1);
    });

    testWidgets('a provider change that fails to refresh offers Retry', (tester) async {
      _api.byHousehold[_a] = _roommate('Faisal', 'Imran', 300);
      await _pump(tester);
      await _openSettlement(tester);
      _api.failingHouseholds.add(_a);
      tester.widget<HouseholdRolesCard>(find.byType(HouseholdRolesCard)).onNafaqahProviderChanged!(null);
      await _settle(tester);
      expect(find.text(_en.get('roles_retry')), findsOneWidget);
      expect(_settleButton, findsNothing);
    });

    testWidgets('an answer after the section closed is dropped without an error', (tester) async {
      final slow = Completer<SettlementV2Summary>();
      _api.gates[_a] = slow;
      await _pump(tester);
      await _openSettlement(tester);
      await tester.tap(_sectionTitle);
      await _settle(tester);

      slow.complete(_roommate('Ali', 'Omar', 900));
      await _settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Ali'), findsNothing);
    });

    testWidgets('a failure after the section closed is dropped without an error', (tester) async {
      final slow = Completer<SettlementV2Summary>();
      _api.gates[_a] = slow;
      await _pump(tester);
      await _openSettlement(tester);
      await tester.tap(_sectionTitle);
      await _settle(tester);

      slow.completeError(Exception('late'));
      await _settle(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a failed fetch shows the localized message and Retry recovers', (tester) async {
      _api.failSettlement = true;
      await _pump(tester);
      await _openSettlement(tester);
      expect(find.text(_en.get('load_error_generic')), findsOneWidget);
      expect(find.text(_en.get('roles_retry')), findsOneWidget);

      _api.failSettlement = false;
      final before = _api.settlementCallCount;
      await tester.tap(find.text(_en.get('roles_retry')));
      await _settle(tester);
      expect(find.text(_en.get('load_error_generic')), findsNothing);
      expect(_api.settlementCallCount, before + 1);
    });
  });
}
