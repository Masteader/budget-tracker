// The budget dialog saves through the backend (POST /budgets/sub-allocations),
// also for a category with no sub-categories: the server checks the category,
// switches it on before writing, and uses the household's payday cycle when the
// dialog has none. The dialog never writes budgets or category settings itself
// and never falls back to the phone's calendar month.
import 'dart:async';
import 'dart:convert';

import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/providers/budget_provider.dart';
import 'package:budget_tracker/providers/recurring_bills_provider.dart';
import 'package:budget_tracker/services/api_service.dart';
import 'package:budget_tracker/services/salary_cycle_service.dart';
import 'package:budget_tracker/widgets/sub_budget_allocation_dialog.dart';
import 'package:budget_tracker/widgets/transactions/unbudgeted_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_settings_supabase.dart';

/// Records every direct database write, and answers `budgets` reads from
/// [budgetRows] filtered by their `eq.` filters, as PostgREST would.
class _WritesClient extends FakeSettingsHttpClient {
  final writes = <String>[];

  /// The household's stored budget rows.
  List<Map<String, dynamic>> budgetRows = [];

  /// Makes the `budgets` read fail.
  bool failBudgetRead = false;

  /// When set, the `budgets` read answers only after it completes.
  Completer<void>? budgetGate;

  @override
  void resetScenario() {
    super.resetScenario();
    budgetRows = [];
    failBudgetRead = false;
    final gate = budgetGate;
    if (gate != null && !gate.isCompleted) gate.complete();
    budgetGate = null;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method != 'GET' && request.url.path.contains('/rest/v1/')) {
      writes.add('${request.method} ${request.url.pathSegments.last}');
    }
    if (request.method == 'GET' && request.url.path.endsWith('/rest/v1/budgets')) {
      if (budgetGate != null) await budgetGate!.future;
      if (failBudgetRead) {
        return _json(request, 500, {'message': 'raw budgets failure', 'code': 'XX000'});
      }
      final filters = {
        for (final e in request.url.queryParameters.entries)
          if (e.value.startsWith('eq.')) e.key: e.value.substring(3),
      };
      final rows = budgetRows
          .where((r) => filters.entries.every((f) => r[f.key]?.toString() == f.value))
          .toList();
      return _json(request, 200, rows);
    }
    return super.send(request);
  }

  http.StreamedResponse _json(http.BaseRequest request, int status, Object body) => http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(body))),
        status,
        request: request,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
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

  /// The cycles the server lists for the household (BudgetProvider).
  List<Map<String, dynamic>> cycles = const [];

  @override
  Future<Map<String, dynamic>> getSalaryCycles(String householdId, {int? paydayDay}) async => {'cycles': cycles};

  @override
  Future<int> getHouseholdPayday(String householdId) async => SalaryCycleService.defaultPaydayDay;

  @override
  Future<Map<String, dynamic>> getBudgetBreakdown(String householdId, {String? cycleKey}) async =>
      {'categories': const []};

  @override
  Future<Map<String, List<CategoryItem>>> fetchHouseholdCategories(String householdId) async =>
      {'active': const [], 'inactive': const []};
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
  Budget? existingBudget,
  ApiService? apiService,
  BudgetProvider? budgetProvider,
  Future<bool?> Function(BuildContext context)? opener,
  bool settle = true,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final run = _Run();
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => budgetProvider ?? BudgetProvider()),
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
              run.result = opener != null
                  ? await opener(context)
                  : await SubBudgetAllocationDialog.show(
                      context,
                      householdId: fakeSettingsHouseholdId,
                      categoryCode: categoryCode,
                      categoryName: 'Category',
                      cycleKey: cycleKey,
                      existingBudget: existingBudget,
                      apiService: apiService,
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
  if (settle) await tester.pumpAndSettle();
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

  testWidgets('a given API client both loads and saves', (tester) async {
    final global = _FakeApi(outcome: _Outcome.refused);
    ApiService.instance = global;
    final given = _FakeApi();
    final run = await _open(tester, categoryCode: 'OPEX-CHARITY', cycleKey: '2026-11', apiService: given);
    await tester.enterText(find.byType(TextField).first, '300');
    await tester.pump();
    await _save(tester);

    expect(given.calls, hasLength(1));
    expect(global.calls, isEmpty);
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

  // The server keeps the stored `_sinking_fund` when none is sent and clears
  // it when `{}` is sent; the dialog sends one only when it read what is
  // stored for the cycle, or when the user changed the setting.
  group('the stored sinking fund', () {
    const groceries = [
      {'sub_code': 'meat', 'name_en': 'Meat', 'name_ar': 'لحوم'},
      {'sub_code': 'dairy_eggs', 'name_en': 'Dairy', 'name_ar': 'ألبان'},
    ];
    const storedFund = {
      'meat': {'accumulate': true, 'base_amount': 80.0},
    };
    Map<String, dynamic> row({required String? cycleKey, required String month, Map<String, dynamic>? fund}) => {
          'id': 'b-$month-$cycleKey',
          'household_id': fakeSettingsHouseholdId,
          'category_code': 'OPEX-GROCERY',
          'cycle_key': cycleKey,
          'month': month,
          'sub_allocations': {'meat': 100, 'dairy_eggs': 50, if (fund != null) '_sinking_fund': fund},
        };

    Future<_FakeApi> editDairyAndSave(WidgetTester tester, {String? cycleKey, Budget? existingBudget}) async {
      final api = _FakeApi(subCategories: groceries);
      ApiService.instance = api;
      await _open(tester, categoryCode: 'OPEX-GROCERY', cycleKey: cycleKey, existingBudget: existingBudget);
      await tester.enterText(find.byType(TextField).at(1), '60');
      await tester.pump();
      await _save(tester);
      expect(api.calls, hasLength(1));
      return api;
    }

    testWidgets('read for the cycle: sent back unchanged when only an amount is edited', (tester) async {
      _http.budgetRows = [
        row(cycleKey: '2026-10', month: '2026-10-01', fund: const {
          'dairy_eggs': {'accumulate': true, 'base_amount': 5.0},
        }),
        row(cycleKey: '2026-11', month: '2026-11-01', fund: storedFund),
      ];
      final api = await editDairyAndSave(tester, cycleKey: '2026-11');
      expect(api.calls.single.subAllocations, {'meat': 100.0, 'dairy_eggs': 60.0});
      expect(api.calls.single.sinkingFund, storedFund);
    });

    testWidgets('a legacy row of the cycle (no cycle_key, its month) is read like the backend', (tester) async {
      _http.budgetRows = [row(cycleKey: null, month: '2026-11-01', fund: storedFund)];
      final api = await editDairyAndSave(tester, cycleKey: '2026-11');
      expect(api.calls.single.sinkingFund, storedFund);
    });

    testWidgets('the read fails but the stored row was handed in: sent back unchanged', (tester) async {
      _http.failBudgetRead = true;
      final api = await editDairyAndSave(
        tester,
        cycleKey: '2026-11',
        existingBudget: const Budget(
          id: 'b-1',
          householdId: fakeSettingsHouseholdId,
          month: '2026-11-01',
          categoryCode: 'OPEX-GROCERY',
          allocatedAmount: 150,
          spentAmount: 0,
          remainingAmount: 150,
          cycleKey: '2026-11',
          subAllocations: {'meat': 100, 'dairy_eggs': 50},
          metadata: {'_sinking_fund': storedFund},
        ),
      );
      expect(api.calls.single.sinkingFund, storedFund);
    });

    testWidgets('the read fails: no sinking fund is sent, so the stored one is kept', (tester) async {
      _http.budgetRows = [row(cycleKey: '2026-11', month: '2026-11-01', fund: storedFund)];
      _http.failBudgetRead = true;
      final api = await editDairyAndSave(tester, cycleKey: '2026-11');
      expect(api.calls.single.sinkingFund, isNull);
      expect(api.calls.single.subAllocations, {'meat': 0.0, 'dairy_eggs': 60.0});
    });

    testWidgets('the read times out: no sinking fund is sent', (tester) async {
      _http.budgetRows = [row(cycleKey: '2026-11', month: '2026-11-01', fund: storedFund)];
      _http.budgetGate = Completer<void>();
      final api = _FakeApi(subCategories: groceries);
      ApiService.instance = api;
      await _open(tester, categoryCode: 'OPEX-GROCERY', cycleKey: '2026-11', settle: false);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(1), '60');
      await tester.pump();
      await _save(tester);
      expect(api.calls, hasLength(1));
      expect(api.calls.single.sinkingFund, isNull);
    });

    testWidgets("no cycle key: another cycle's row is not guessed, no sinking fund is sent", (tester) async {
      _http.budgetRows = [row(cycleKey: '2026-10', month: '2026-10-01', fund: storedFund)];
      final api = await editDairyAndSave(tester);
      expect(api.calls.single.cycleKey, isNull);
      expect(api.calls.single.sinkingFund, isNull);
    });

    testWidgets('the read fails and the user switches a sinking fund on: it is sent', (tester) async {
      _http.failBudgetRead = true;
      final api = _FakeApi(subCategories: groceries);
      ApiService.instance = api;
      await _open(tester, categoryCode: 'OPEX-GROCERY', cycleKey: '2026-11');
      await tester.enterText(find.byType(TextField).at(0), '100');
      await tester.pump();
      await tester.tap(find.text(AppLocalizations(const Locale('en')).get('sinking_fund_toggle')).first);
      await tester.pump();
      await _save(tester);
      expect(api.calls.single.sinkingFund, {
        'meat': {'accumulate': true, 'base_amount': 100.0},
      });
    });

    testWidgets('read, then switched off by the user: sent empty, so it is cleared', (tester) async {
      _http.budgetRows = [row(cycleKey: '2026-11', month: '2026-11-01', fund: storedFund)];
      final api = _FakeApi(subCategories: groceries);
      ApiService.instance = api;
      await _open(tester, categoryCode: 'OPEX-GROCERY', cycleKey: '2026-11');
      final toggle = find.text(AppLocalizations(const Locale('en')).get('sinking_fund_badge'));
      expect(toggle, findsOneWidget, reason: 'the stored fund shows as on');
      await tester.tap(toggle);
      await tester.pump();
      await _save(tester);
      expect(api.calls.single.sinkingFund, isEmpty);
    });
  });

  // The unbudgeted badge saves into the server's open cycle, or lets the
  // server pick it; never into the phone's cached-payday cycle.
  group('the unbudgeted badge', () {
    Future<_FakeApi> budgetFromBadge(WidgetTester tester, List<Map<String, dynamic>> cycles) async {
      final api = _FakeApi()..cycles = cycles;
      ApiService.instance = api;
      final provider = BudgetProvider(api: api);
      await provider.init(fakeSettingsHouseholdId);
      await _open(
        tester,
        categoryCode: 'OPEX-CHARITY',
        budgetProvider: provider,
        opener: (context) => activateAndBudgetCategory(context, fakeSettingsHouseholdId, 'OPEX-CHARITY'),
      );
      await tester.enterText(find.byType(TextField).first, '300');
      await tester.pump();
      await _save(tester);
      expect(api.calls, hasLength(1));
      return api;
    }

    testWidgets("passes the server's open cycle", (tester) async {
      final cached = SalaryCycleService.currentCycle().key;
      final serverKey = cached == '2031-01' ? '2031-02' : '2031-01';
      final api = await budgetFromBadge(tester, [
        {'cycle_key': '2030-12', 'is_current': false},
        {'cycle_key': serverKey, 'is_current': true},
      ]);
      expect(api.calls.single.cycleKey, serverKey);
      expect(api.calls.single.cycleKey, isNot(cached));
    });

    testWidgets("no server cycle yet: passes no cycle, so the server picks the household's", (tester) async {
      final api = await budgetFromBadge(tester, const []);
      expect(api.calls.single.cycleKey, isNull);
    });
  });
}
