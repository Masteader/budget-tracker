// The Export button of the real SettingsScreen: which cycle it asks for and what
// the dialog says about it (B1, B2, B3, S4).
import 'dart:async';

import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/providers/locale_provider.dart';
import 'package:budget_tracker/providers/theme_provider.dart';
import 'package:budget_tracker/screens/settings/settings_screen.dart';
import 'package:budget_tracker/services/api_service.dart';
import 'package:budget_tracker/services/salary_cycle_service.dart';
import 'package:budget_tracker/theme/app_themes.dart';
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
final _nov5 = DateTime.utc(2026, 11, 5, 9);

class _DeniedPermissions extends PermissionHandlerPlatform {
  @override
  Future<PermissionStatus> checkPermissionStatus(Permission permission) async => PermissionStatus.denied;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> _pump(WidgetTester tester, {String lang = 'en'}) async {
  tester.view.physicalSize = const Size(390, 12000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ChangeNotifierProvider(create: (_) => LocaleProvider()),
    ],
    child: MaterialApp(
      locale: Locale(lang),
      theme: AppThemes.lightTheme,
      supportedLocales: const [Locale('en'), Locale('ar'), Locale('ur')],
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: SettingsScreen(clock: () => _nov5),
    ),
  ));
  await _settle(tester);
}

Future<void> _openReports(WidgetTester tester, String lang) async {
  await tester.tap(find.text(AppLocalizations(Locale(lang)).get('reports_offline_queue')));
  await _settle(tester);
}

Future<void> _tapExport(WidgetTester tester, {String lang = 'en'}) async {
  await tester.tap(find.text(AppLocalizations(Locale(lang)).get('export_csv')));
  await _settle(tester);
}

Map<String, dynamic> _row(int i, double amount, {String key = '2026-11', String hid = _a, bool? settlement, String? nafaqahClass}) => {
      'id': 'tx-$i',
      'household_id': hid,
      'cycle_key': key,
      'timestamp': '2026-11-01T10:00:00Z',
      'merchant': 'M$i',
      'amount': amount,
      if (settlement != null) 'is_settlement': settlement,
      'nafaqah_class': nafaqahClass,
    };

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    TestWidgetsFlutterBinding.ensureInitialized();
    await initFakeSettingsSupabase(_http);
    PermissionHandlerPlatform.instance = _DeniedPermissions();
  });

  setUp(() {
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

  group('the cycle exported (B3)', () {
    for (final payday in [10, 27, 1, 15, 16, 31]) {
      testWidgets('payday $payday asks for its own cycle on 5 Nov', (tester) async {
        _http.paydayByHousehold[_a] = payday;
        await _pump(tester);
        await _openReports(tester, 'en');
        await _tapExport(tester);
        final expected = SalaryCycleService.currentCycle(now: _nov5, paydayDay: payday).key;
        expect(_http.lastTransactionRequest!.url.queryParameters['cycle_key'], 'eq.$expected');
      });
    }

    testWidgets('payday 10 selects 2026-10 even with the device cache saying 27 and the payday read not finished', (tester) async {
      SharedPreferences.setMockInitialValues({'payday_day': 27});
      SalaryCycleService.paydayDay = 27;
      _http.paydayByHousehold[_a] = 10;
      _http.transactions = [_row(1, 40, key: '2026-10'), _row(2, 999, key: '2026-11')];
      await _pump(tester);
      await _openReports(tester, 'en');
      await _tapExport(tester);
      expect(_http.lastTransactionRequest!.url.queryParameters['cycle_key'], 'eq.2026-10');
      expect(find.textContaining('10 Oct'), findsOneWidget);
      expect(find.textContaining('9 Nov'), findsOneWidget);
    });

    testWidgets('a payday that cannot be read stops the export: no guessed cycle', (tester) async {
      _http.failPaydayRead = true;
      _http.transactions = [_row(1, 40)];
      await _pump(tester);
      await _openReports(tester, 'en');
      await _tapExport(tester);
      expect(_http.transactionRequests, isEmpty);
      expect(find.byType(AlertDialog), findsNothing);
      final l = AppLocalizations(const Locale('en'));
      expect(find.text(l.get('load_error_generic')), findsOneWidget);
      expect(find.textContaining('raw payday failure'), findsNothing);
    });

    for (final lang in ['en', 'ar', 'ur']) {
      testWidgets('$lang: the dialog names the cycle by its dates, not a generic label', (tester) async {
        _http.paydayByHousehold[_a] = 10;
        _http.transactions = [_row(1, 40, key: '2026-10')];
        await _pump(tester, lang: lang);
        await _openReports(tester, lang);
        await _tapExport(tester, lang: lang);
        expect(tester.takeException(), isNull);
        final l = AppLocalizations(Locale(lang));
        final cycle = SalaryCycleService.currentCycle(now: _nov5, paydayDay: 10);
        expect(find.textContaining(l.cycleRange(cycle.start, cycle.end, now: _nov5)), findsOneWidget);
        expect(find.textContaining('Monthly Export'), findsNothing);
      });

      testWidgets('$lang: a cycle with no rows says so, with no empty dialog', (tester) async {
        _http.paydayByHousehold[_a] = 10;
        await _pump(tester, lang: lang);
        await _openReports(tester, lang);
        await _tapExport(tester, lang: lang);
        final l = AppLocalizations(Locale(lang));
        final cycle = SalaryCycleService.currentCycle(now: _nov5, paydayDay: 10);
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.text(l.format('set_export_empty_cycle', {'cycle': l.cycleRange(cycle.start, cycle.end, now: _nov5)})), findsOneWidget);
      });

      testWidgets('$lang: a failed export shows the friendly message, not the raw exception', (tester) async {
        _http.transactions = null;
        await _pump(tester, lang: lang);
        await _openReports(tester, lang);
        await _tapExport(tester, lang: lang);
        final l = AppLocalizations(Locale(lang));
        expect(find.text(l.get('load_error_generic')), findsOneWidget);
        expect(find.textContaining('PostgrestException'), findsNothing);
        expect(find.textContaining('raw server detail'), findsNothing);
        expect(find.byType(SnackBar), findsOneWidget);
      });
    }
  });

  testWidgets('the dialog total matches the other cycle views: settlements and wife personal left out (B2)', (tester) async {
    _http.transactions = [
      _row(1, 5000),
      _row(2, 700, settlement: true),
      _row(3, 300, nafaqahClass: 'wife_personal'),
    ];
    await _pump(tester);
    await _openReports(tester, 'en');
    await _tapExport(tester);
    final l = AppLocalizations(const Locale('en'));
    final summary = l.format('csv_export_summary', {'transactions': l.plural('transactions_count', 1), 'amount': l.sar(5000)});
    expect(find.text(summary), findsOneWidget);
    expect(find.textContaining('M2'), findsNothing);
    expect(find.textContaining('M3'), findsNothing);
  });

  // A small cap keeps bodies small: large ones are decoded in an isolate that a
  // widget test's fake clock never waits for. Scale is covered by the paging test.
  testWidgets('rows beyond the server cap all reach the dialog (B1)', (tester) async {
    _http.rowCap = 2;
    _http.transactions = [for (var i = 0; i < 5; i++) _row(i, 10)];
    await _pump(tester);
    await _openReports(tester, 'en');
    await _tapExport(tester);
    final l = AppLocalizations(const Locale('en'));
    final summary = l.format('csv_export_summary', {'transactions': l.plural('transactions_count', 5), 'amount': l.sar(50)});
    expect(find.text(summary), findsOneWidget);
    expect(_http.transactionRequests.length, greaterThan(1));
    expect(_http.lastTransactionRequest!.url.queryParameters['order'], contains('id.'));
  });

  group('a switch during the export (S4)', () {
    Future<void> switchToB(WidgetTester tester) async {
      final l = AppLocalizations(const Locale('en'));
      await tester.tap(find.text(l.get('join_with_code')));
      await _settle(tester);
      await tester.tap(find.text('Household $_b'));
      await _settle(tester);
    }

    testWidgets('household A\'s rows are not shown on household B\'s page', (tester) async {
      _http.transactions = [_row(1, 5000)];
      final gate = Completer<void>();
      _http.transactionGate = gate;
      await _pump(tester);
      await _openReports(tester, 'en');
      await _tapExport(tester);
      expect(_http.transactionRequests, isNotEmpty);

      await switchToB(tester);
      _http.transactionGate = null;
      gate.complete();
      await _settle(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.textContaining('M1'), findsNothing);
    });

    testWidgets('household A\'s failure is not reported on household B\'s page', (tester) async {
      _http.transactions = null;
      final gate = Completer<void>();
      _http.transactionGate = gate;
      await _pump(tester);
      await _openReports(tester, 'en');
      await _tapExport(tester);

      await switchToB(tester);
      _http.transactionGate = null;
      gate.complete();
      await _settle(tester);
      expect(find.text(AppLocalizations(const Locale('en')).get('set_export_failed')), findsNothing);
    });

    testWidgets('after the switch the export uses the new household and its payday', (tester) async {
      _http.paydayByHousehold[_a] = 27;
      _http.paydayByHousehold[_b] = 10;
      _http.transactions = [_row(1, 40, key: '2026-10', hid: _b)];
      await _pump(tester);
      await _openReports(tester, 'en');
      await switchToB(tester);
      await _tapExport(tester);
      final q = _http.lastTransactionRequest!.url.queryParameters;
      expect(q['household_id'], 'eq.$_b');
      expect(q['cycle_key'], 'eq.2026-10');
      expect(find.byType(AlertDialog), findsOneWidget);
    });
  });
}
