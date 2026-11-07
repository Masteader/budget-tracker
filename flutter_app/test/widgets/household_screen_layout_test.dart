// "Your Household" fits a 320x568 phone at text scale 2.0, with the keyboard
// open and the invite banner showing, in every language, and uses the
// Velvet Burgundy theme (emerald is for safe/surplus only).
import 'dart:convert';

import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/providers/budget_provider.dart';
import 'package:budget_tracker/providers/transaction_provider.dart';
import 'package:budget_tracker/screens/onboarding/household_screen.dart';
import 'package:budget_tracker/services/api/base_api_client.dart';
import 'package:budget_tracker/services/api/budget_api_client.dart';
import 'package:budget_tracker/services/api_service.dart';
import 'package:budget_tracker/theme/app_themes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

ApiService _api() => ApiService(
      budget: BudgetApiClient(
        baseClient: BaseApiClient(
          client: MockClient((request) async {
            if (request.url.path.endsWith('/FATIMA01')) {
              return http.Response(
                jsonEncode({
                  'household_id': 'hh-123',
                  'invite_code': 'FATIMA01',
                  'role': 'spouse',
                  'target_member_id': 'dep-fatima',
                  'target_member_name': 'Fatima Abdulrahman Al-Qahtani',
                  'is_valid': true,
                }),
                200,
              );
            }
            return http.Response('{"error": "not found"}', 404);
          }),
        ),
      ),
    );

Widget _app({required String lang, bool dark = false, double scale = 2.0}) => MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => BudgetProvider()),
        ChangeNotifierProvider(create: (_) => TransactionProvider()),
      ],
      child: MaterialApp(
        locale: Locale(lang),
        theme: dark ? AppThemes.darkTheme : AppThemes.lightTheme,
        supportedLocales: const [Locale('en'), Locale('ar'), Locale('ur')],
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: HouseholdScreen(apiService: _api()),
      ),
    );

Future<void> _pump(WidgetTester tester, Widget app) async {
  tester.view.physicalSize = const Size(640, 1136); // 320x568 logical
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
}

ButtonStyle _bigButtonStyle(WidgetTester tester, String label) {
  final button = tester.widget<ButtonStyleButton>(
    find.ancestor(of: find.text(label), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)).first,
  );
  return button.style!;
}

void main() {
  for (final lang in ['en', 'ar', 'ur']) {
    final l = AppLocalizations(Locale(lang));

    testWidgets('[$lang] the Create tab fits and its button is reachable', (tester) async {
      await _pump(tester, _app(lang: lang));
      expect(tester.takeException(), isNull);
      final create = find.text(l.get('hh_create_household'));
      await tester.scrollUntilVisible(create, 100, scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(create.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('[$lang] the Join tab fits with the keyboard open and the invite banner showing', (tester) async {
      await _pump(tester, _app(lang: lang));
      await tester.ensureVisible(find.byType(Tab).last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Tab).last);
      await tester.pumpAndSettle();
      // The keyboard opens: 300 of the 568 logical pixels.
      tester.view.viewInsets = const FakeViewPadding(bottom: 600);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byType(TextField).last, 'FATIMA01');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('targeted_claim_banner')), findsOneWidget);
      expect(tester.takeException(), isNull);

      final join = find.text(l.get('join_household'));
      await tester.scrollUntilVisible(join, 100, scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(join.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('[$lang] a wrapped button label is not clipped', (tester) async {
      await _pump(tester, _app(lang: lang, scale: 3.0));
      expect(tester.takeException(), isNull);
      final label = find.text(l.get('hh_create_household'));
      final button = find.ancestor(of: label, matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)).first;
      expect(tester.getSize(button).height, greaterThanOrEqualTo(tester.getSize(label).height));
      expect(tester.getSize(button).height, greaterThanOrEqualTo(52));
    });
  }

  for (final dark in [false, true]) {
    testWidgets('${dark ? 'dark' : 'light'}: burgundy buttons and tabs, no emerald', (tester) async {
      await _pump(tester, _app(lang: 'en', dark: dark, scale: 1.0));
      final ctx = tester.element(find.byType(HouseholdScreen));
      final style = _bigButtonStyle(tester, 'Create Household');
      expect(style.backgroundColor?.resolve({}), ctx.primaryButtonBg);
      expect(style.foregroundColor?.resolve({}), ctx.primaryButtonFg);
      final tabBar = tester.widget<TabBar>(find.byType(TabBar));
      expect(tabBar.indicatorColor, ctx.accentText);
      expect(tabBar.labelColor, ctx.accentText);
      expect(tabBar.indicatorColor, isNot(AppThemes.success));
    });
  }
}
