// The budget dialog saves through the backend (POST /budgets/sub-allocations),
// also for a category with no sub-categories: the server checks the category,
// switches it on before writing, and uses the household's payday cycle when the
// dialog has none. The dialog never writes budgets or category settings itself
// and never falls back to the phone's calendar month.
import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/providers/budget_provider.dart';
import 'package:budget_tracker/providers/recurring_bills_provider.dart';
import 'package:budget_tracker/services/api_service.dart';
import 'package:budget_tracker/widgets/sub_budget_allocation_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_settings_supabase.dart';

/// Records every direct database write.
class _WritesClient extends FakeSettingsHttpClient {
  final writes = <String>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method != 'GET' && request.url.path.contains('/rest/v1/')) {
      writes.add('${request.method} ${request.url.pathSegments.last}');
    }
    return super.send(request);
  }
}

class _SaveCall {
  _SaveCall(this.householdId, this.categoryCode, this.subAllocations, this.cycleKey, this.allocatedAmount,
      this.sinkingFund);
  final String householdId;
  final String categoryCode;
  final Map<String, dynamic> subAllocations;
  final String? cycleKey;
  final double? allocatedAmount;
  final Map<String, dynamic>? sinkingFund;
}

enum _Outcome { saved, refused, notSaved }

class _FakeApi extends ApiService {
  _FakeApi({this.outcome = _Outcome.saved, this.subCategories = const []});
  final _Outcome outcome;
  final List<Map<String, dynamic>> subCategories;
  final calls = <_SaveCall>[];

  @override
  Future<Map<String, dynamic>> saveSubAllocations({
    required String householdId,
    required String categoryCode,
    required Map<String, dynamic> subAllocations,
    String? cycleKey,
    double? allocatedAmount,
    Map<String, dynamic>? sinkingFund,
  }) async {
    calls.add(_SaveCall(householdId, categoryCode, subAllocations, cycleKey, allocatedAmount, sinkingFund));
    switch (outcome) {
      case _Outcome.saved:
        return {'status': 'success'};
      case _Outcome.refused:
        throw Exception('403 CATEGORY_FORBIDDEN raw server text');
      case _Outcome.notSaved:
        return {'status': 'error', 'message': 'raw server text'};
    }
  }

  // No network in tests: the dialog loads the category's sub-categories.
  @override
  Future<List<Map<String, dynamic>>> getSubCategories(String parentCode, {String? householdId}) async =>
      subCategories;
}

final _http = _WritesClient();

class _Run {
  bool? result;
  bool closed = false;
  int onSavedCalls = 0;
}

Future<_Run> _open(
  WidgetTester tester, {
  required String categoryCode,
  String? cycleKey,
  String lang = 'en',
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final run = _Run();
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => BudgetProvider()),
      ChangeNotifierProvider(create: (_) => RecurringBillsProvider()),
    ],
    child: MaterialApp(
      locale: Locale(lang),
      supportedLocales: const [Locale('en'), Locale('ar'), Locale('ur')],
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              run.result = await SubBudgetAllocationDialog.show(
                context,
                householdId: fakeSettingsHouseholdId,
                categoryCode: categoryCode,
                categoryName: 'Category',
                cycleKey: cycleKey,
                onSaved: () => run.onSavedCalls++,
              );
              run.closed = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return run;
}

Future<void> _save(WidgetTester tester) async {
  final save = find.byType(ElevatedButton).last;
  await tester.ensureVisible(save);
  await tester.tap(save);
  await tester.pumpAndSettle();
}

void main() {
  late ApiService original;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    TestWidgetsFlutterBinding.ensureInitialized();
    await initFakeSettingsSupabase(_http);
  });

  setUp(() {
    original = ApiService.instance;
    _http.resetScenario();
    _http.writes.clear();
  });

  tearDown(() => ApiService.instance = original);

  testWidgets('no sub-categories: the amount is saved through the API in the dialog cycle', (tester) async {
    final api = _FakeApi();
    ApiService.instance = api;
    final run = await _open(tester, categoryCode: 'OPEX-CHARITY', cycleKey: '2026-11');
    await tester.enterText(find.byType(TextField).first, '300');
    await tester.pump();
    await _save(tester);

    expect(api.calls, hasLength(1));
    final call = api.calls.single;
    expect(call.householdId, fakeSettingsHouseholdId);
    expect(call.categoryCode, 'OPEX-CHARITY');
    expect(call.subAllocations, isEmpty);
    expect(call.allocatedAmount, 300.0);
    expect(call.cycleKey, '2026-11');
    expect(call.sinkingFund, isEmpty, reason: 'sent empty, so a switched-off sinking fund is cleared');
    expect(_http.writes, isEmpty, reason: 'nothing is written to the database directly');
    expect(run.result, isTrue);
    expect(run.onSavedCalls, 1);
  });

  testWidgets('no cycle: no cycle key is sent, so the server uses the payday cycle', (tester) async {
    final api = _FakeApi();
    ApiService.instance = api;
    final run = await _open(tester, categoryCode: 'OPEX-CHARITY');
    await tester.enterText(find.byType(TextField).first, '120');
    await tester.pump();
    await _save(tester);

    expect(api.calls, hasLength(1));
    expect(api.calls.single.cycleKey, isNull);
    expect(api.calls.single.allocatedAmount, 120.0);
    expect(_http.writes, isEmpty);
    expect(run.result, isTrue);
  });

  testWidgets('no sub-categories: the parent sinking fund is sent', (tester) async {
    final api = _FakeApi();
    ApiService.instance = api;
    await _open(tester, categoryCode: 'OPEX-CHARITY', cycleKey: '2026-11');
    await tester.enterText(find.byType(TextField).first, '300');
    await tester.pump();
    await tester.tap(find.byType(Switch));
    await tester.pump();
    await _save(tester);

    expect(api.calls.single.sinkingFund, {
      '_parent': {'accumulate': true, 'base_amount': 300.0},
    });
    expect(api.calls.single.subAllocations, isEmpty);
    expect(_http.writes, isEmpty);
  });

  testWidgets('sub-categories: amounts and the sinking fund are sent apart', (tester) async {
    final api = _FakeApi(subCategories: [
      {'sub_code': 'meat', 'name_en': 'Meat', 'name_ar': 'لحوم'},
      {'sub_code': 'dairy_eggs', 'name_en': 'Dairy', 'name_ar': 'ألبان'},
    ]);
    ApiService.instance = api;
    final run = await _open(tester, categoryCode: 'OPEX-GROCERY');
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '100');
    await tester.enterText(fields.at(1), '50');
    await tester.pump();
    await tester.tap(find.text(AppLocalizations(const Locale('en')).get('sinking_fund_toggle')).first);
    await tester.pump();
    await _save(tester);

    expect(api.calls, hasLength(1));
    final call = api.calls.single;
    expect(call.categoryCode, 'OPEX-GROCERY');
    expect(call.subAllocations, {'meat': 100.0, 'dairy_eggs': 50.0});
    expect(call.allocatedAmount, isNull, reason: 'the sum of the sub-categories is the parent amount');
    expect(call.sinkingFund, {
      'meat': {'accumulate': true, 'base_amount': 100.0},
    });
    expect(call.cycleKey, isNull);
    expect(_http.writes, isEmpty);
    expect(run.result, isTrue);
  });

  for (final outcome in const [_Outcome.refused, _Outcome.notSaved]) {
    for (final lang in const ['en', 'ar', 'ur']) {
      testWidgets('$lang ${outcome.name}: says it was not saved and stays open', (tester) async {
        final api = _FakeApi(outcome: outcome);
        ApiService.instance = api;
        final run = await _open(tester, categoryCode: 'OPEX-CHARITY', cycleKey: '2026-11', lang: lang);
        await tester.enterText(find.byType(TextField).first, '300');
        await tester.pump();
        await _save(tester);
        final l = AppLocalizations(Locale(lang));

        expect(api.calls, hasLength(1));
        expect(run.closed, isFalse, reason: 'the dialog stays open');
        expect(run.onSavedCalls, 0);
        expect(find.text(l.get('sba_save_failed')), findsOneWidget);
        expect(find.text(l.get('sba_budget_saved')), findsNothing);
        expect(find.textContaining('raw server text'), findsNothing);
        expect(_http.writes, isEmpty);
      });
    }
  }
}
