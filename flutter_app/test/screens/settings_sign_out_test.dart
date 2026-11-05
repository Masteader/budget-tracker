// Signing out of the real SettingsScreen with unsynced items (S1, S2, S3, S14).
// "Signed out" means the auth session really ended (no current user), not merely
// that no dialog appeared.
import 'dart:async';

import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/providers/locale_provider.dart';
import 'package:budget_tracker/providers/theme_provider.dart';
import 'package:budget_tracker/screens/settings/settings_screen.dart';
import 'package:budget_tracker/services/api_service.dart';
import 'package:budget_tracker/services/offline_queue_manager.dart';
import 'package:budget_tracker/services/offline_sync_service.dart';
import 'package:budget_tracker/theme/app_themes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../support/fake_settings_supabase.dart';

final _http = FakeSettingsHttpClient();

class _DeniedPermissions extends PermissionHandlerPlatform {
  @override
  Future<PermissionStatus> checkPermissionStatus(Permission permission) async => PermissionStatus.denied;
}

class _FakeSync extends OfflineSyncService {
  _FakeSync() : super.withQueue(OfflineQueueManager());

  /// What the queue really holds for this user, parked items included.
  int unsynced = 0;
  final calls = <String>[];
  Completer<void>? gate;
  Object? failure;

  @override
  Future<int> updatePendingCount() async {
    calls.add('update');
    if (gate != null) await gate!.future;
    if (failure != null) throw failure!;
    return unsynced;
  }

  @override
  Future<int> unsyncedCount() async {
    calls.add('count');
    return unsynced;
  }

  @override
  Future<int> claimOwnerlessItems() async {
    calls.add('claim');
    return 0;
  }
}

late _FakeSync _sync;

bool get _signedOut => Supabase.instance.client.auth.currentUser == null;
bool get _stillSignedIn => Supabase.instance.client.auth.currentUser?.id == fakeSettingsUserId;

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
      home: const SettingsScreen(),
    ),
  ));
  await _settle(tester);
}

Future<void> _tapSignOut(WidgetTester tester, {String lang = 'en'}) async {
  final button = find.ancestor(
    of: find.text(AppLocalizations(Locale(lang)).get('sign_out')),
    matching: find.byType(OutlinedButton),
  );
  await tester.ensureVisible(button);
  await tester.tap(button);
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
    await resetFakeSettingsAuth();
    _http.resetScenario();
    final originalApi = ApiService.instance;
    ApiService.instance = FakeSettingsApi();
    addTearDown(() => ApiService.instance = originalApi);
    final originalSync = OfflineSyncService.instance;
    _sync = _FakeSync();
    OfflineSyncService.instance = _sync;
    addTearDown(() => OfflineSyncService.instance = originalSync);
  });

  testWidgets('with nothing unsynced it signs out straight away', (tester) async {
    await _pump(tester);
    await _tapSignOut(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(_signedOut, isTrue);
  });

  testWidgets('Cancel keeps the user signed in', (tester) async {
    _sync.unsynced = 3;
    await _pump(tester);
    await _tapSignOut(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(_stillSignedIn, isTrue);

    await tester.tap(find.text('Cancel'));
    await _settle(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(_stillSignedIn, isTrue);
    expect(_sync.calls, isNot(contains('claim')));
  });

  testWidgets('dismissing the dialog keeps the user signed in', (tester) async {
    _sync.unsynced = 1;
    await _pump(tester);
    await _tapSignOut(tester);
    await tester.tapAt(const Offset(5, 5));
    await _settle(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(_stillSignedIn, isTrue);
  });

  testWidgets('confirming signs out, after leaving ownerless items with this account', (tester) async {
    _sync.unsynced = 2;
    await _pump(tester);
    await _tapSignOut(tester);
    final en = AppLocalizations(const Locale('en'));
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text(en.get('sign_out'))));
    await _settle(tester);
    expect(_signedOut, isTrue);
    expect(_sync.calls.last, 'claim');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a receipt the notifier has not heard of still warns (S1)', (tester) async {
    _sync.unsynced = 2;
    _sync.pendingCountNotifier.value = 0;
    await _pump(tester);
    await _tapSignOut(tester);
    final en = AppLocalizations(const Locale('en'));
    expect(find.text(en.plural('sign_out_unsynced_warning', 2)), findsOneWidget);
    expect(_stillSignedIn, isTrue);
    expect(_sync.calls.take(2), ['update', 'count']);
  });

  testWidgets('the warning names what the queue says for this user, not the notifier (S2)', (tester) async {
    _sync.unsynced = 0;
    _sync.pendingCountNotifier.value = 5;
    await _pump(tester);
    await _tapSignOut(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(_signedOut, isTrue);
  });

  testWidgets('a queue that cannot be read falls back to the last known count', (tester) async {
    _sync.failure = StateError('queue unavailable');
    _sync.pendingCountNotifier.value = 4;
    await _pump(tester);
    await _tapSignOut(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(_stillSignedIn, isTrue);
  });

  testWidgets('leaving the page during the count neither signs out nor throws', (tester) async {
    _sync.unsynced = 2;
    _sync.gate = Completer<void>();
    await _pump(tester);
    await _tapSignOut(tester);

    await tester.pumpWidget(const SizedBox());
    _sync.gate!.complete();
    await _settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.byType(AlertDialog), findsNothing);
    expect(_stillSignedIn, isTrue);
  });

  for (final lang in ['ar', 'ur']) {
    testWidgets('$lang: the warning is localized', (tester) async {
      _sync.unsynced = 2;
      await _pump(tester, lang: lang);
      await _tapSignOut(tester, lang: lang);
      final l = AppLocalizations(Locale(lang));
      expect(find.text(l.get('sign_out_unsynced_title')), findsOneWidget);
      expect(find.text(l.plural('sign_out_unsynced_warning', 2)), findsOneWidget);
      expect(find.textContaining('Unsynced'), findsNothing);
    });
  }
}
