// The whole Settings page at large text under real font metrics: a label wraps
// between words, never inside one ("Manag" / "e").
import 'package:budget_tracker/providers/locale_provider.dart';
import 'package:budget_tracker/providers/theme_provider.dart';
import 'package:budget_tracker/screens/settings/help_support_screen.dart';
import 'package:budget_tracker/screens/settings/settings_screen.dart';
import 'package:budget_tracker/services/api_service.dart';
import 'package:budget_tracker/services/offline_sync_service.dart';
import 'package:budget_tracker/widgets/settings/settings_section.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_settings_supabase.dart';
import '../support/settings_test_app.dart';

final _http = FakeSettingsHttpClient();

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    TestWidgetsFlutterBinding.ensureInitialized();
    await initFakeSettingsSupabase(_http);
    await loadRealFontMetrics();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final original = ApiService.instance;
    ApiService.instance = FakeSettingsApi();
    addTearDown(() => ApiService.instance = original);
  });

  for (final lang in ['en', 'ar', 'ur']) {
    for (final scale in [1.0, 1.5, 2.0]) {
      for (final width in [320.0, 390.0]) {
        testWidgets('settings, $lang x$scale, ${width.toInt()}px, every section open', (tester) async {
          OfflineSyncService.instance.pendingCountNotifier.value = 2;
          addTearDown(() => OfflineSyncService.instance.pendingCountNotifier.value = 0);
          useViewport(tester, width: width, height: 16000);
          await tester.pumpWidget(MultiProvider(
            providers: [
              ChangeNotifierProvider(create: (_) => ThemeProvider()),
              ChangeNotifierProvider(create: (_) => LocaleProvider()),
            ],
            child: settingsTestApp(const SettingsScreen(), lang: lang, scale: scale, scaffold: false),
          ));
          await settleFrames(tester);
          final folded = tester
              .widgetList<SettingsSection>(find.byType(SettingsSection))
              .where((s) => !s.initiallyExpanded)
              .map((s) => s.title)
              .toList()
              .reversed;
          for (final title in folded) {
            await tester.tap(find.text(title));
            await settleFrames(tester);
          }
          expect(tester.takeException(), isNull);
          expect(
            brokenWords(
              tester,
              find.byType(SettingsScreen),
              // Data, not words: an address or code may need to wrap anywhere.
              ignore: (t) => t.contains('@') || t == '--------',
            ),
            isEmpty,
          );
        });
      }
    }

    for (final scale in [1.5, 2.0]) {
      testWidgets('help, $lang x$scale, 390px', (tester) async {
        useViewport(tester, height: 4000);
        await tester.pumpWidget(settingsTestApp(const HelpSupportScreen(), lang: lang, scale: scale, scaffold: false));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        expect(brokenWords(tester, find.byType(HelpSupportScreen)), isEmpty);
      });
    }
  }
}
