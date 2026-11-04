// SettingsScreen with a real signed-in household (fake HTTP only): section
// order, what lives where, overflow in every language and theme, and the export
// flow's strings. UX-15 still holds: sections fold, nothing is removed.
import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/providers/locale_provider.dart';
import 'package:budget_tracker/providers/theme_provider.dart';
import 'package:budget_tracker/screens/settings/settings_screen.dart';
import 'package:budget_tracker/services/api_service.dart';
import 'package:budget_tracker/services/offline_sync_service.dart';
import 'package:budget_tracker/theme/app_themes.dart';
import 'package:budget_tracker/widgets/settings/payday_settings_card.dart';
import 'package:budget_tracker/widgets/settings/settings_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_settings_supabase.dart';

final _http = FakeSettingsHttpClient();
late FakeSettingsApi _api;

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}

Widget _app({String lang = 'en', bool dark = false, double scale = 1.0}) => MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
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
        home: const SettingsScreen(),
      ),
    );

/// A tall phone so the whole lazy ListView is built.
Future<void> _pump(WidgetTester tester, {String lang = 'en', bool dark = false, double scale = 1.0, double height = 12000, double width = 390}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(lang: lang, dark: dark, scale: scale));
  await _settle(tester);
}

/// The roster and settlement calls resolve over several microtask turns; there
/// are spinners, so pumpAndSettle would never return.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

List<String> _titles(WidgetTester tester) =>
    tester.widgetList<SettingsSection>(find.byType(SettingsSection)).map((s) => s.title).toList();

/// Opens each folded section, from the bottom up so positions stay on screen.
Future<void> _openAllSections(WidgetTester tester) async {
  final folded = tester
      .widgetList<SettingsSection>(find.byType(SettingsSection))
      .where((s) => !s.initiallyExpanded)
      .map((s) => s.title)
      .toList()
      .reversed;
  for (final title in folded) {
    await tester.ensureVisible(find.text(title));
    await tester.pump();
    await tester.tap(find.text(title));
    await _settle(tester);
  }
}

Finder _inSection(String title, Finder matching) => find.descendant(
      of: find.ancestor(of: find.text(title), matching: find.byType(SettingsSection)),
      matching: matching,
    );

/// Every permission is, and stays, denied.
class _DeniedPermissions extends PermissionHandlerPlatform {
  @override
  Future<PermissionStatus> checkPermissionStatus(Permission permission) async => PermissionStatus.denied;

  @override
  Future<Map<Permission, PermissionStatus>> requestPermissions(List<Permission> permissions) async => {
        for (final p in permissions) p: PermissionStatus.denied,
      };
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    TestWidgetsFlutterBinding.ensureInitialized();
    await initFakeSettingsSupabase(_http);
    PermissionHandlerPlatform.instance = _DeniedPermissions();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _http.transactions = const [];
    _http.memberCount = 2;
    OfflineSyncService.instance.pendingCountNotifier.value = 0;
    final original = ApiService.instance;
    _api = FakeSettingsApi();
    ApiService.instance = _api;
    addTearDown(() => ApiService.instance = original);
  });

  group('organization (ORG-01..04)', () {
    testWidgets('sections follow the agreed order', (tester) async {
      await _pump(tester);
      expect(_titles(tester), [
        'HOUSEHOLD & MEMBERSHIP',
        'SALARY & ACCOUNTS',
        'PARTNER SETTLEMENT',
        'APPEARANCE & LANGUAGE',
        'REMINDERS',
        'HARDWARE & APP PERMISSIONS',
        'REPORTS & OFFLINE QUEUE',
        'HELP & SUPPORT',
        'ACCOUNT',
      ]);
    });

    testWidgets('only household, appearance, help and account start open', (tester) async {
      await _pump(tester);
      final open = {
        for (final s in tester.widgetList<SettingsSection>(find.byType(SettingsSection))) s.title: s.initiallyExpanded,
      };
      expect(open, {
        'HOUSEHOLD & MEMBERSHIP': true,
        'SALARY & ACCOUNTS': false,
        'PARTNER SETTLEMENT': false,
        'APPEARANCE & LANGUAGE': true,
        'REMINDERS': false,
        'HARDWARE & APP PERMISSIONS': false,
        'REPORTS & OFFLINE QUEUE': false,
        'HELP & SUPPORT': true,
        'ACCOUNT': true,
      });
    });

    testWidgets('accounts live under money with the payday summary, not under household', (tester) async {
      await _pump(tester);
      expect(_inSection('HOUSEHOLD & MEMBERSHIP', find.text('Accounts & Balances')), findsNothing);
      expect(_inSection('HOUSEHOLD & MEMBERSHIP', find.text('Household Setup Checklist')), findsOneWidget);
      expect(_inSection('SALARY & ACCOUNTS', find.text('Payday: day 27 of the month')), findsOneWidget);

      await tester.tap(find.text('SALARY & ACCOUNTS'));
      await _settle(tester);
      expect(_inSection('SALARY & ACCOUNTS', find.text('Accounts & Balances')), findsOneWidget);
    });

    testWidgets('the account section holds the email and sign out, and is a real section', (tester) async {
      await _pump(tester);
      expect(_inSection('ACCOUNT', find.text(fakeSettingsEmail)), findsOneWidget);
      expect(_inSection('ACCOUNT', find.text('Sign Out')), findsOneWidget);
      expect(find.text('HOUSEHOLD & ACCOUNT'), findsNothing);
    });

    testWidgets('partner settlement stays hidden for a household of one', (tester) async {
      _http.memberCount = 1;
      await _pump(tester);
      expect(find.text('PARTNER SETTLEMENT'), findsNothing);
      expect(find.text('SALARY & ACCOUNTS'), findsOneWidget);
    });

    testWidgets('section storage keys never collide, in any language', (tester) async {
      for (final lang in ['en', 'ar', 'ur']) {
        await _pump(tester, lang: lang);
        final titles = _titles(tester);
        expect(titles.length, 9, reason: lang);
        expect(titles.toSet().length, titles.length, reason: lang);
      }
    });
  });

  group('no overflow in en/ar/ur, light/dark, default and large text', () {
    for (final lang in ['en', 'ar', 'ur']) {
      for (final dark in [false, true]) {
        for (final scale in [1.0, 1.5, 2.0]) {
          testWidgets('$lang ${dark ? 'dark' : 'light'} x$scale, every section open', (tester) async {
            OfflineSyncService.instance.pendingCountNotifier.value = 2;
            addTearDown(() => OfflineSyncService.instance.pendingCountNotifier.value = 0);
            await _pump(tester, lang: lang, dark: dark, scale: scale, height: 16000);
            await _openAllSections(tester);
            await _settle(tester);
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  });

  group('no overflow with the roommate settlement card', () {
    for (final lang in ['en', 'ar', 'ur']) {
      for (final dark in [false, true]) {
        testWidgets('$lang ${dark ? 'dark' : 'light'} x2.0', (tester) async {
          _api.settlement = const SettlementV2Summary(
            mode: 'multi_roommate',
            simplifiedDebts: [
              SimplifiedDebt(fromId: fakeSettingsUserId, toId: 'user-2', fromName: 'Owner', toName: 'Faisal Al-Qahtani', amount: 1250.5),
            ],
            pairwiseDebts: [
              PairwiseDebt(fromId: fakeSettingsUserId, toId: 'user-2', fromName: 'Owner', toName: 'Faisal Al-Qahtani', amount: 1250.5),
            ],
            roommateBalances: {'Owner': -1250.5, 'Faisal': 1250.5},
          );
          await _pump(tester, lang: lang, dark: dark, scale: 2.0, height: 12000);
          final l = AppLocalizations(Locale(lang));
          await tester.tap(find.text(l.get('set_partner_settlement_section')));
          await _settle(tester);
          expect(tester.takeException(), isNull);
          expect(find.text(l.get('roommate_settlements_title')), findsOneWidget);
        });
      }
    }
  });

  group('section identity survives a language change', () {
    Future<LocaleProvider> pumpLive(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 12000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final locale = LocaleProvider();
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider.value(value: locale),
        ],
        child: Consumer<LocaleProvider>(
          builder: (_, l, __) => MaterialApp(
            locale: l.currentLocale,
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
        ),
      ));
      await _settle(tester);
      return locale;
    }

    testWidgets('an opened section stays open and keeps its state; a folded one stays folded', (tester) async {
      await pumpLive(tester);
      await tester.tap(find.text('SALARY & ACCOUNTS'));
      await _settle(tester);
      final card = tester.state(find.byType(PaydaySettingsCard));
      expect(find.text('Export CSV'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('language_option_ar')));
      await _settle(tester);

      final ar = AppLocalizations(const Locale('ar'));
      expect(find.text(ar.get('set_money_section')), findsOneWidget);
      expect(find.text(ar.get('accounts_balances')), findsOneWidget, reason: 'the section re-folded');
      expect(identical(tester.state(find.byType(PaydaySettingsCard)), card), isTrue, reason: 'the body remounted');
      expect(find.text(ar.get('export_csv')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a section folded by the user stays folded', (tester) async {
      await pumpLive(tester);
      await tester.tap(find.text('HELP & SUPPORT'));
      await _settle(tester);
      expect(find.text('App Guide & Tutorial'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('language_option_ur')));
      await _settle(tester);

      final ur = AppLocalizations(const Locale('ur'));
      expect(find.text(ur.get('set_help_support')), findsOneWidget);
      expect(find.text(ur.get('set_app_guide_tutorial')), findsNothing);
    });

    testWidgets('ids are stable and unique, and do not change with the language', (tester) async {
      await _pump(tester);
      final en = tester.widgetList<SettingsSection>(find.byType(SettingsSection)).map((s) => s.id).toList();
      expect(en.toSet().length, 9);
      await _pump(tester, lang: 'ur');
      final ur = tester.widgetList<SettingsSection>(find.byType(SettingsSection)).map((s) => s.id).toList();
      expect(ur, en);
    });
  });

  group('dialogs opened from the page', () {
    for (final dark in [false, true]) {
      final mode = dark ? 'dark' : 'light';

      testWidgets('$mode: the create household hint reads', (tester) async {
        await _pump(tester, dark: dark);
        await tester.tap(find.text('New Household'));
        await _settle(tester);
        final ctx = tester.element(find.byType(AlertDialog));
        final field = tester.widget<TextField>(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)));
        final fill = Theme.of(ctx).inputDecorationTheme.fillColor!;
        expect(field.decoration!.hintStyle!.color, ctx.textSecondary);
        expect(_contrast(field.decoration!.hintStyle!.color!, fill), greaterThanOrEqualTo(4.5));
      });

      testWidgets('$mode: the join household hint reads', (tester) async {
        await _pump(tester, dark: dark);
        await tester.tap(find.text('Join with Code'));
        await _settle(tester);
        await tester.tap(find.text('Join Another Household'));
        await _settle(tester);
        final ctx = tester.element(find.byType(AlertDialog));
        final field = tester.widget<TextField>(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)));
        final fill = Theme.of(ctx).inputDecorationTheme.fillColor!;
        expect(field.decoration!.hintStyle!.color, ctx.textSecondary);
        expect(_contrast(field.decoration!.hintStyle!.color!, fill), greaterThanOrEqualTo(4.5));
      });

      testWidgets('$mode: the permission dialog uses the primary pair', (tester) async {
        await _pump(tester, dark: dark);
        await tester.tap(find.text('HARDWARE & APP PERMISSIONS'));
        await _settle(tester);
        await tester.tap(find.text('Grant Access').first);
        await _settle(tester);
        final ctx = tester.element(find.byType(AlertDialog));
        final btn = tester.widget<ElevatedButton>(
          find.ancestor(of: find.text('Open Settings'), matching: find.byWidgetPredicate((w) => w is ElevatedButton)),
        );
        expect(btn.style!.backgroundColor!.resolve({}), ctx.primaryButtonBg);
        expect(btn.style!.foregroundColor!.resolve({}), ctx.primaryButtonFg);
      });

      for (final lang in ['en', 'ar', 'ur']) {
        testWidgets('$mode $lang x2.0: the remove-dependent dialog fits and its danger button reads', (tester) async {
          await _pump(tester, lang: lang, dark: dark, scale: 2.0, height: 8000);
          final l = AppLocalizations(Locale(lang));
          await tester.tap(find.byIcon(Icons.close_rounded).first);
          await _settle(tester);
          expect(tester.takeException(), isNull);
          expect(find.text(l.get('set_remove_dependent')), findsOneWidget);
          final btn = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, l.get('set_remove')));
          expect(_contrast(btn.style!.foregroundColor!.resolve({})!, btn.style!.backgroundColor!.resolve({})!), greaterThanOrEqualTo(4.5));
        });
      }
    }
  });

  group('dialogs reached from the household card', () {
    for (final lang in ['en', 'ar', 'ur']) {
      for (final dark in [false, true]) {
        testWidgets('leave household dialog: $lang ${dark ? 'dark' : 'light'} x2.0 fits, danger button reads', (tester) async {
          await _pump(tester, lang: lang, dark: dark, scale: 2.0, height: 8000);
          final l = AppLocalizations(Locale(lang));
          await tester.tap(find.text(l.get('leave_household')));
          await _settle(tester);
          expect(tester.takeException(), isNull);

          final btn = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, l.get('leave')));
          final bg = btn.style!.backgroundColor!.resolve({})!;
          final fg = btn.style!.foregroundColor!.resolve({})!;
          expect(_contrast(fg, bg), greaterThanOrEqualTo(4.5));
        });
      }
    }
  });

  group('export (L10N-01, L10N-02)', () {
    Future<void> tapExport(WidgetTester tester, String lang) async {
      final l = AppLocalizations(Locale(lang));
      await tester.tap(find.text(l.get('reports_offline_queue')));
      await _settle(tester);
      await tester.tap(find.text(l.get('export_csv')));
      await _settle(tester);
    }

    for (final lang in ['en', 'ar', 'ur']) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('the export dialog fits a phone and uses the $lang label at x$scale', (tester) async {
          await _pump(tester, lang: lang, scale: scale);
          await tapExport(tester, lang);
          expect(tester.takeException(), isNull);
          final label = AppLocalizations(Locale(lang)).get('set_export_monthly_label');
          expect(find.textContaining(label), findsOneWidget);
          if (lang != 'en') expect(find.textContaining('Monthly Export'), findsNothing);
        });
      }

      testWidgets('a failed export shows the friendly $lang message, not the raw exception', (tester) async {
        _http.transactions = null;
        await _pump(tester, lang: lang);
        await tapExport(tester, lang);
        final l = AppLocalizations(Locale(lang));
        expect(find.text(l.get('load_error_generic')), findsOneWidget);
        expect(find.textContaining('PostgrestException'), findsNothing);
        expect(find.textContaining('raw server detail'), findsNothing);
        expect(find.byType(SnackBar), findsOneWidget);
      });
    }
  });

  group('colour tokens on the page, both modes', () {
    for (final dark in [false, true]) {
      final mode = dark ? 'dark' : 'light';

      testWidgets('$mode: primary buttons use the primary button pair', (tester) async {
        await _pump(tester, dark: dark);
        await tester.tap(find.text('SALARY & ACCOUNTS'));
        await _settle(tester);
        await tester.tap(find.text('REPORTS & OFFLINE QUEUE'));
        await _settle(tester);
        final ctx = tester.element(find.byType(SettingsScreen));
        for (final label in ['Manage', 'Export CSV']) {
          final btn = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, label));
          expect(btn.style!.backgroundColor!.resolve({}), ctx.primaryButtonBg, reason: label);
          expect(btn.style!.foregroundColor!.resolve({}), ctx.primaryButtonFg, reason: label);
        }
      });

      testWidgets('$mode: offline queue uses warning and primary tokens', (tester) async {
        OfflineSyncService.instance.pendingCountNotifier.value = 2;
        addTearDown(() => OfflineSyncService.instance.pendingCountNotifier.value = 0);
        await _pump(tester, dark: dark);
        await tester.tap(find.text('REPORTS & OFFLINE QUEUE'));
        await _settle(tester);
        final ctx = tester.element(find.byType(SettingsScreen));

        final cloud = tester.widget<Icon>(find.byIcon(Icons.cloud_off_rounded));
        expect(cloud.color, ctx.warnText);
        expect(_contrast(cloud.color!, ctx.cardBg), greaterThanOrEqualTo(4.5));

        final sync = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Sync Now'));
        expect(sync.style!.backgroundColor!.resolve({}), ctx.primaryButtonBg);
        expect(sync.style!.foregroundColor!.resolve({}), ctx.primaryButtonFg);
      });

      testWidgets('$mode: sign out uses the danger token and reads on the card', (tester) async {
        await _pump(tester, dark: dark);
        final ctx = tester.element(find.byType(SettingsScreen));
        final btn = tester.widget<OutlinedButton>(
          find.ancestor(of: find.text('Sign Out'), matching: find.byWidgetPredicate((w) => w is OutlinedButton)),
        );
        final fg = btn.style!.foregroundColor!.resolve({})!;
        expect(fg, ctx.dangerColor);
        expect(_contrast(fg, ctx.cardBg), greaterThanOrEqualTo(4.5));
      });

      testWidgets('$mode: selected theme and language options share one foreground', (tester) async {
        await _pump(tester, dark: dark);
        final ctx = tester.element(find.byType(SettingsScreen));
        final fill = ctx.accentText;

        // LocaleProvider starts on its default language; pick English explicitly.
        await tester.tap(find.byKey(const ValueKey('language_option_en')));
        await _settle(tester);
        await tester.tap(find.byKey(const ValueKey('theme_option_system')));
        await _settle(tester);

        final language = tester.widget<Text>(find.text('🇺🇸 English'));
        final theme = tester.widget<Text>(find.text('System Default'));
        expect(theme.style!.color, language.style!.color);
        expect(_contrast(theme.style!.color!, fill), greaterThanOrEqualTo(4.5));
        final icon = tester.widget<Icon>(find.byIcon(Icons.brightness_auto_rounded));
        expect(icon.color, theme.style!.color);
      });
    }
  });

  group('theme and language selectors', () {
    for (final lang in ['en', 'ar', 'ur']) {
      testWidgets('$lang: long theme labels wrap instead of being cut off at x1.5', (tester) async {
        await _pump(tester, lang: lang, scale: 1.5);
        final l = AppLocalizations(Locale(lang));
        for (final key in ['theme_system', 'theme_light', 'theme_dark']) {
          final text = tester.widget<Text>(find.text(l.get(key)));
          expect(text.overflow, isNot(TextOverflow.ellipsis), reason: key);
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('options are exposed as selectable buttons to screen readers', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);
      await tester.tap(find.byKey(const ValueKey('language_option_en')));
      await _settle(tester);
      expect(
        tester.getSemantics(find.byKey(const ValueKey('language_option_en'))),
        isSemantics(isButton: true, isSelected: true, hasTapAction: true),
      );
      handle.dispose();
    });
  });

  group('RTL details', () {
    testWidgets('the sign out icon mirrors in RTL, not in LTR', (tester) async {
      double scaleX() => tester
          .widget<Transform>(find.ancestor(of: find.byIcon(Icons.logout), matching: find.byType(Transform)).first)
          .transform
          .storage[0];
      await _pump(tester);
      expect(scaleX(), 1);
      await _pump(tester, lang: 'ar');
      expect(scaleX(), -1);
    });

    testWidgets('the checklist icon follows the reading direction', (tester) async {
      await _pump(tester);
      expect(find.byIcon(Icons.checklist_rounded), findsOneWidget);
      expect(find.byIcon(Icons.checklist_rtl_rounded), findsNothing);
      await _pump(tester, lang: 'ur');
      expect(find.byIcon(Icons.checklist_rtl_rounded), findsOneWidget);
    });
  });
}
