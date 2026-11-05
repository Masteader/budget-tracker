// Budgeting a category with no sub-categories (the "Activate and budget" path
// of an unbudgeted expense): the category is activated before its budget is
// written, so a failed activation never leaves a saved budget behind an error,
// and a budget row is never written for a category that stays inactive.
import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/providers/budget_provider.dart';
import 'package:budget_tracker/providers/recurring_bills_provider.dart';
import 'package:budget_tracker/services/api/base_api_client.dart';
import 'package:budget_tracker/services/api/budget_api_client.dart';
import 'package:budget_tracker/services/api_service.dart';
import 'package:budget_tracker/widgets/sub_budget_allocation_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_settings_supabase.dart';

/// Records every write and can refuse the category activation.
class _WritesClient extends FakeSettingsHttpClient {
  final writes = <String>[];
  bool failActivation = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (request.method != 'GET' && path.contains('/rest/v1/')) {
      final table = request.url.pathSegments.last;
      writes.add('${request.method} $table');
      if (table == 'household_category_settings' && failActivation) {
        return http.StreamedResponse(
          Stream.value('{"message":"raw server text","code":"42501"}'.codeUnits),
          403,
          request: request,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
    }
    return super.send(request);
  }
}

final _http = _WritesClient();

final _api = ApiService(
  budget: BudgetApiClient(
    baseClient: BaseApiClient(
      client: MockClient((_) async => http.Response('{"status": "success", "sub_categories": []}', 200)),
    ),
  ),
);

Future<bool?> _openAndSave(WidgetTester tester, {String lang = 'en'}) async {
  bool? result;
  var closed = false;
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
              result = await SubBudgetAllocationDialog.show(
                context,
                householdId: fakeSettingsHouseholdId,
                categoryCode: 'OPEX-CHARITY',
                categoryName: 'Charity',
                cycleKey: '2026-11',
                apiService: _api,
              );
              closed = true;
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
  await tester.enterText(find.byType(TextField).first, '300');
  await tester.pump();
  final save = find.byType(ElevatedButton).last;
  await tester.ensureVisible(save);
  await tester.tap(save);
  await tester.pumpAndSettle();
  return closed ? result : null;
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    TestWidgetsFlutterBinding.ensureInitialized();
    await initFakeSettingsSupabase(_http);
  });

  setUp(() {
    _http.resetScenario();
    _http.writes.clear();
    _http.failActivation = false;
  });

  testWidgets('activates the category first, then writes its budget', (tester) async {
    final result = await _openAndSave(tester);
    expect(result, isTrue);
    expect(_http.writes, ['POST household_category_settings', 'POST budgets']);
  });

  for (final lang in const ['en', 'ar', 'ur']) {
    testWidgets('$lang: a failed activation writes no budget and says it was not saved', (tester) async {
      _http.failActivation = true;
      final result = await _openAndSave(tester, lang: lang);
      final l = AppLocalizations(Locale(lang));

      expect(result, isNull, reason: 'the dialog stays open');
      expect(_http.writes, ['POST household_category_settings']);
      expect(find.text(l.get('sba_save_failed')), findsOneWidget);
      expect(find.textContaining('raw server text'), findsNothing);
      expect(find.textContaining('PostgrestException'), findsNothing);
      expect(find.text(l.get('sba_budget_saved')), findsNothing);
    });
  }
}
