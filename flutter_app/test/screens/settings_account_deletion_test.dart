// The account deletion flow from the real SettingsScreen, through the real
// provider and service, with Supabase's HTTP answered in the process. Payloads are
// the shapes supabase/migrations/20261105000200_account_deletion_rpcs.sql builds.
import 'dart:async';

import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/providers/account_deletion_provider.dart';
import 'package:budget_tracker/providers/locale_provider.dart';
import 'package:budget_tracker/providers/theme_provider.dart';
import 'package:budget_tracker/screens/onboarding/household_screen.dart';
import 'package:budget_tracker/screens/settings/settings_screen.dart';
import 'package:budget_tracker/services/api_service.dart';
import 'package:budget_tracker/services/local_account_data_cleaner.dart';
import 'package:budget_tracker/services/offline_queue_manager.dart';
import 'package:budget_tracker/services/offline_sync_service.dart';
import 'package:budget_tracker/services/salary_cycle_service.dart';
import 'package:budget_tracker/theme/app_themes.dart';
import 'package:budget_tracker/providers/budget_provider.dart';
import 'package:budget_tracker/providers/transaction_provider.dart';
import 'package:budget_tracker/widgets/settings/account_deletion_flow.dart';
import 'package:budget_tracker/widgets/settings/household_roles_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import '../support/fake_settings_supabase.dart';
import '../support/settings_test_app.dart' show contrast;

final _http = FakeSettingsHttpClient();

const _scheduledFor = '2026-12-05T10:00:00+00:00';

class _DeniedPermissions extends PermissionHandlerPlatform {
  @override
  Future<PermissionStatus> checkPermissionStatus(Permission permission) async => PermissionStatus.denied;
}

class _FakeSync extends OfflineSyncService {
  _FakeSync() : super.withQueue(OfflineQueueManager());

  int unsynced = 0;
  int flushes = 0;
  int unsyncedAfterFlush = 0;

  @override
  Future<int> updatePendingCount() async => unsynced;

  @override
  Future<int> unsyncedCount() async => unsynced;

  @override
  Future<int> flushQueue() async {
    flushes++;
    unsynced = unsyncedAfterFlush;
    return 0;
  }

  @override
  Future<int> claimOwnerlessItems() async => 0;
}

class _FakeLauncher extends UrlLauncherPlatform {
  final launched = <String>[];
  final modes = <PreferredLaunchMode>[];
  bool fails = false;

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    modes.add(options.mode);
    return !fails;
  }

  @override
  Future<bool> canLaunch(String url) => throw StateError('needs a declared scheme on Android and iOS');
}

class _SpyCleaner extends LocalAccountDataCleaner {
  _SpyCleaner() : super(cancelReminders: () async {}, deleteStatements: () async {}, clearSignedUrls: () {});

  final wiped = <String>[];

  @override
  Future<bool> wipeForUser(String userId, {Iterable<String> householdIds = const []}) async {
    wiped.add(userId);
    await clearFlag(userId);
    return true;
  }
}

late _FakeSync _sync;
late _SpyCleaner _cleaner;
late AccountDeletionProvider _provider;
late _FakeLauncher _launcher;

Map<String, Object?> _household(String id, String name, String position, {List<Map<String, Object?>> candidates = const []}) => {
      'household_id': id,
      'household_name': name,
      'position': position,
      'needs_choice': position == 'primary_admin',
      'candidates': candidates,
    };

Map<String, Object?> _candidate(String id, String name, {bool pending = false}) =>
    {'user_id': id, 'display_name': name, 'pending_deletion': pending};

void _setHouseholds(List<Map<String, Object?>> households) {
  _http.rpcResults['get_account_deletion_preflight'] = {
    'deletion': const {'status': 'none', 'can_cancel': false},
    'households': households,
  };
}

Map<String, Object?> _scheduledStatus({List<Map<String, Object?>> marked = const []}) => {
      'request_id': 'r-1',
      'status': 'scheduled',
      'requested_at': '2026-11-05T10:00:00+00:00',
      'scheduled_for': _scheduledFor,
      'locale': 'en',
      'can_cancel': true,
      'marked_households': marked,
    };

/// Answers the request as the RPC does, and the status reads after it.
void _acceptRequest({List<Map<String, Object?>> marked = const []}) {
  _http.rpcResults['request_account_deletion'] = {..._scheduledStatus(marked: marked), 'success': true, 'already_requested': false};
}

AppLocalizations _l(String lang) => AppLocalizations(Locale(lang));

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 14; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Widget _app(Widget home, {String lang = 'en', bool dark = false, double scale = 1.0}) => MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
        ChangeNotifierProvider<AccountDeletionProvider>.value(value: _provider),
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
        builder: (context, page) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
          child: page!,
        ),
        home: home,
      ),
    );

Future<void> _pump(WidgetTester tester, {String lang = 'en', bool dark = false, double scale = 1.0, double width = 390}) async {
  tester.view.physicalSize = Size(width, 12000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(const SettingsScreen(), lang: lang, dark: dark, scale: scale));
  await _settle(tester);
  _provider.load();
  await _settle(tester);
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  final target = find.byKey(ValueKey(key));
  expect(target, findsOneWidget, reason: key);
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.tap(target);
  await _settle(tester);
}

Future<void> _openFlow(WidgetTester tester) => _tapKey(tester, 'account_deletion_open');
Future<void> _continue(WidgetTester tester) => _tapKey(tester, 'account_deletion_continue');

Future<void> _enterPassword(WidgetTester tester, [String password = fakeSettingsPassword]) async {
  await tester.enterText(find.byKey(const ValueKey('account_deletion_password')), password);
  await _continue(tester);
}

Future<void> _typeWord(WidgetTester tester, String word) async {
  await tester.enterText(find.byKey(const ValueKey('account_deletion_word')), word);
  await _tapKey(tester, 'account_deletion_confirm');
}

Finder get _flow => find.byType(AccountDeletionFlowScreen);
Finder get _passwordStep => find.byKey(const ValueKey('account_deletion_password'));
Finder get _wordStep => find.byKey(const ValueKey('account_deletion_word'));
Finder get _pendingCard => find.byKey(const ValueKey('account_deletion_pending'));
Finder get _deleteButton => find.byKey(const ValueKey('account_deletion_open'));
Finder get _cancelButton => find.byKey(const ValueKey('account_deletion_cancel'));
Finder _text(String text) => find.textContaining(text);

/// Whether a choice row is drawn as chosen.
bool _chosen(String key) => find
    .descendant(of: find.byKey(ValueKey(key)), matching: find.byIcon(Icons.radio_button_checked_rounded))
    .evaluate()
    .isNotEmpty;

List<FakeRpcCall> get _requests => _http.rpcCalls.where((c) => c.function == 'request_account_deletion').toList();

void _expectNoRawServerText() {
  expect(find.textContaining('raw server text'), findsNothing);
  expect(find.textContaining('raw auth server text'), findsNothing);
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
    await resetFakeSettingsAuth();
    _http.authCalls.clear();
    final originalApi = ApiService.instance;
    ApiService.instance = FakeSettingsApi();
    addTearDown(() => ApiService.instance = originalApi);
    final originalSync = OfflineSyncService.instance;
    _sync = _FakeSync();
    OfflineSyncService.instance = _sync;
    addTearDown(() => OfflineSyncService.instance = originalSync);
    _launcher = _FakeLauncher();
    UrlLauncherPlatform.instance = _launcher;
    _cleaner = _SpyCleaner();
    _provider = AccountDeletionProvider(cleaner: _cleaner);
    _http.rpcResults['get_account_deletion_status'] = const {'status': 'none', 'can_cancel': false};
    _setHouseholds([_household('h-m', 'Flat 5', 'member')]);
  });

  group('the Account section', () {
    testWidgets('with nothing pending offers Delete account and no Cancel', (tester) async {
      await _pump(tester);
      expect(_deleteButton, findsOneWidget);
      expect(_cancelButton, findsNothing);
      expect(_pendingCard, findsNothing);
    });

    testWidgets('a pending user sees the date and Cancel, without opening anything', (tester) async {
      _http.rpcResults['get_account_deletion_status'] = _scheduledStatus();
      await _pump(tester);
      expect(_pendingCard, findsOneWidget);
      expect(_text('5 December 2026'), findsOneWidget);
      expect(_cancelButton, findsOneWidget);
      expect(_deleteButton, findsNothing);
      expect(_text(_l('en').get('del_cancel_only_note')), findsOneWidget);
    });

    testWidgets('lists the households that go with the account', (tester) async {
      _http.rpcResults['get_account_deletion_status'] = _scheduledStatus(marked: [
        {'household_id': 'h-1', 'household_name': 'Home', 'scheduled_for': _scheduledFor},
      ]);
      await _pump(tester);
      expect(_text('Home'), findsWidgets);
      expect(_text(_l('en').format('del_pending_marked', {'names': 'Home'})), findsOneWidget);
    });

    for (final status in ['processing', 'failed']) {
      testWidgets('$status shows the date and says it can no longer be cancelled', (tester) async {
        _http.rpcResults['get_account_deletion_status'] = {'status': status, 'scheduled_for': _scheduledFor, 'can_cancel': false};
        await _pump(tester);
        expect(_text('5 December 2026'), findsOneWidget);
        expect(_cancelButton, findsNothing);
        expect(find.byKey(const ValueKey('account_deletion_in_progress')), findsOneWidget);
      });
    }

    testWidgets('offline, a user this device knows is pending still sees the date and Cancel', (tester) async {
      await _cleaner.setFlag(fakeSettingsUserId, DateTime.utc(2026, 12, 5, 10));
      _http.rpcOffline.add('get_account_deletion_status');
      await _pump(tester);
      expect(_text('5 December 2026'), findsOneWidget);
      expect(_cancelButton, findsOneWidget);
      expect(_text(_l('en').get('del_pending_offline_note')), findsOneWidget);
    });

    testWidgets('Cancel cancels, clears the local flag and brings Delete account back', (tester) async {
      _http.rpcResults['get_account_deletion_status'] = _scheduledStatus();
      _http.rpcResults['cancel_account_deletion'] = const {'success': true, 'cancelled': true, 'status': 'none', 'can_cancel': false};
      await _pump(tester);
      expect(await _cleaner.readFlag(fakeSettingsUserId), isNotNull);

      await _tapKey(tester, 'account_deletion_cancel');

      expect(_http.rpcCalls.where((c) => c.function == 'cancel_account_deletion'), hasLength(1));
      expect(_pendingCard, findsNothing);
      expect(_deleteButton, findsOneWidget);
      expect(_text(_l('en').get('del_cancelled')), findsOneWidget);
      expect(await _cleaner.readFlag(fakeSettingsUserId), isNull);
      expect(_cleaner.wiped, isEmpty);
    });

    testWidgets('Cancel refused because it already started says so, never the raw text', (tester) async {
      _http.rpcResults['get_account_deletion_status'] = _scheduledStatus();
      _http.rpcRefusals['cancel_account_deletion'] = const FakeRpcRefusal('deletion_in_progress');
      await _pump(tester);
      _http.rpcResults['get_account_deletion_status'] = {'status': 'processing', 'scheduled_for': _scheduledFor, 'can_cancel': false};

      await _tapKey(tester, 'account_deletion_cancel');

      expect(_text(_l('en').get('del_err_in_progress')), findsWidgets);
      expect(_pendingCard, findsOneWidget);
      expect(_cancelButton, findsNothing, reason: 'nothing left to press');
      _expectNoRawServerText();
    });

    testWidgets('Cancel with no connection keeps it pending and says why', (tester) async {
      _http.rpcResults['get_account_deletion_status'] = _scheduledStatus();
      _http.rpcOffline.add('cancel_account_deletion');
      await _pump(tester);

      await _tapKey(tester, 'account_deletion_cancel');

      expect(_text(_l('en').get('del_err_network')), findsOneWidget);
      expect(_pendingCard, findsOneWidget);
      expect(_cancelButton, findsOneWidget);
    });
  });

  group('the four household positions', () {
    testWidgets('regular member: says they leave, warns about settlement, asks no choice', (tester) async {
      _setHouseholds([_household('h-m', 'Flat 5', 'member')]);
      _acceptRequest();
      await _pump(tester);
      await _openFlow(tester);

      expect(_text(_l('en').format('del_pos_member', {'name': 'Flat 5'})), findsOneWidget);
      expect(find.byKey(const ValueKey('account_deletion_settlement_warning')), findsOneWidget);
      expect(find.byKey(const ValueKey('account_deletion_household_warning')), findsNothing);

      await _continue(tester);
      expect(_passwordStep, findsOneWidget, reason: 'no household choice for a member');
      await _enterPassword(tester);
      await _typeWord(tester, 'DELETE');

      expect(_requests.single.params['p_household_choices'], isEmpty);
    });

    testWidgets('sole member: says the household goes, no choice, no survivors to warn about', (tester) async {
      _setHouseholds([_household('h-s', 'Alone', 'sole_member')]);
      _acceptRequest();
      await _pump(tester);
      await _openFlow(tester);

      expect(_text(_l('en').format('del_pos_sole', {'name': 'Alone'})), findsOneWidget);
      expect(find.byKey(const ValueKey('account_deletion_household_warning')), findsOneWidget);
      expect(find.byKey(const ValueKey('account_deletion_settlement_warning')), findsNothing);

      await _continue(tester);
      expect(_passwordStep, findsOneWidget);
      await _enterPassword(tester);
      await _typeWord(tester, 'DELETE');
      expect(_requests.single.params['p_household_choices'], isEmpty);
    });

    testWidgets('co-admin: says they leave and the household stays, asks no choice', (tester) async {
      _setHouseholds([_household('h-c', 'Co', 'co_admin')]);
      _acceptRequest();
      await _pump(tester);
      await _openFlow(tester);

      expect(_text(_l('en').format('del_pos_coadmin', {'name': 'Co'})), findsOneWidget);
      expect(find.byKey(const ValueKey('account_deletion_settlement_warning')), findsOneWidget);

      await _continue(tester);
      expect(_passwordStep, findsOneWidget);
      await _enterPassword(tester);
      await _typeWord(tester, 'DELETE');
      expect(_requests.single.params['p_household_choices'], isEmpty);
    });

    testWidgets('primary admin handing over: warned, chooses a named member, and that is what is sent', (tester) async {
      _setHouseholds([
        _household('h-p', 'Villa', 'primary_admin', candidates: [_candidate('u-2', 'Salem'), _candidate('u-3', 'Noura')]),
      ]);
      _acceptRequest();
      await _pump(tester);
      await _openFlow(tester);

      expect(_text(_l('en').format('del_pos_primary', {'name': 'Villa'})), findsOneWidget);
      expect(find.byKey(const ValueKey('account_deletion_household_warning')), findsOneWidget);
      expect(_text(_l('en').get('del_household_delete_warning')), findsOneWidget);

      await _continue(tester);
      expect(_passwordStep, findsNothing, reason: 'the choice comes first');
      expect(_text('Villa'), findsOneWidget);

      await _tapKey(tester, 'account_deletion_action_transfer_h-p');
      expect(_text('Salem'), findsOneWidget);
      expect(_text(_l('en').get('del_choice_transfer_note')), findsOneWidget);
      await _tapKey(tester, 'account_deletion_successor_h-p_u-3');
      expect(_chosen('account_deletion_successor_h-p_u-3'), isTrue);
      expect(_chosen('account_deletion_successor_h-p_u-2'), isFalse);
      await _continue(tester);

      expect(_passwordStep, findsOneWidget);
      await _enterPassword(tester);
      await _typeWord(tester, 'DELETE');
      expect(_requests.single.params['p_household_choices'], [
        {'household_id': 'h-p', 'action': 'transfer', 'successor_user_id': 'u-3'},
      ]);
    });

    testWidgets('primary admin deleting: warned again that it all goes, and delete is what is sent', (tester) async {
      _setHouseholds([
        _household('h-p', 'Villa', 'primary_admin', candidates: [_candidate('u-2', 'Salem')]),
      ]);
      _acceptRequest();
      await _pump(tester);
      await _openFlow(tester);
      await _continue(tester);

      await _tapKey(tester, 'account_deletion_action_delete_h-p');
      expect(_text(_l('en').get('del_household_delete_warning')), findsOneWidget);
      await _continue(tester);
      await _enterPassword(tester);
      await _typeWord(tester, 'DELETE');

      final choices = _requests.single.params['p_household_choices'] as List;
      expect(choices, [
        {'household_id': 'h-p', 'action': 'delete'},
      ]);
    });

    testWidgets('choosing delete after picking a member sends no successor', (tester) async {
      _setHouseholds([
        _household('h-p', 'Villa', 'primary_admin', candidates: [_candidate('u-2', 'Salem')]),
      ]);
      _acceptRequest();
      await _pump(tester);
      await _openFlow(tester);
      await _continue(tester);
      await _tapKey(tester, 'account_deletion_action_transfer_h-p');
      await _tapKey(tester, 'account_deletion_successor_h-p_u-2');
      await _tapKey(tester, 'account_deletion_action_delete_h-p');
      await _continue(tester);
      await _enterPassword(tester);
      await _typeWord(tester, 'DELETE');

      expect(_requests.single.params['p_household_choices'], [
        {'household_id': 'h-p', 'action': 'delete'},
      ]);
    });

    testWidgets('several households: only the primary one asks, and each choice stays with its household', (tester) async {
      _setHouseholds([
        _household('h-m', 'As member', 'member'),
        _household('h-p1', 'First', 'primary_admin', candidates: [_candidate('u-2', 'Salem')]),
        _household('h-p2', 'Second', 'primary_admin', candidates: [_candidate('u-3', 'Noura')]),
      ]);
      _acceptRequest();
      await _pump(tester);
      await _openFlow(tester);
      await _continue(tester);

      await _tapKey(tester, 'account_deletion_action_transfer_h-p1');
      await _tapKey(tester, 'account_deletion_successor_h-p1_u-2');
      await _continue(tester);
      expect(_passwordStep, findsNothing, reason: 'the second household is not decided');
      expect(_text(_l('en').get('del_err_choice_missing')), findsOneWidget);

      await _tapKey(tester, 'account_deletion_action_delete_h-p2');
      await _continue(tester);
      await _enterPassword(tester);
      await _typeWord(tester, 'DELETE');

      expect(_requests.single.params['p_household_choices'], [
        {'household_id': 'h-p1', 'action': 'transfer', 'successor_user_id': 'u-2'},
        {'household_id': 'h-p2', 'action': 'delete'},
      ]);
    });
  });

  group('choosing a successor', () {
    Future<void> toChoice(WidgetTester tester) async {
      await _pump(tester);
      await _openFlow(tester);
      await _continue(tester);
    }

    testWidgets('continuing with nothing chosen stays on the step', (tester) async {
      _setHouseholds([
        _household('h-p', 'Villa', 'primary_admin', candidates: [_candidate('u-2', 'Salem')]),
      ]);
      await toChoice(tester);
      await _continue(tester);
      expect(_passwordStep, findsNothing);
      expect(_text(_l('en').get('del_err_choice_missing')), findsOneWidget);
    });

    testWidgets('handing over with no member picked stays on the step', (tester) async {
      _setHouseholds([
        _household('h-p', 'Villa', 'primary_admin', candidates: [_candidate('u-2', 'Salem')]),
      ]);
      await toChoice(tester);
      await _tapKey(tester, 'account_deletion_action_transfer_h-p');
      await _continue(tester);
      expect(_passwordStep, findsNothing);
      expect(_text(_l('en').get('del_err_choice_missing')), findsOneWidget);
    });

    testWidgets('a pending member is shown but cannot be chosen', (tester) async {
      _setHouseholds([
        _household('h-p', 'Villa', 'primary_admin', candidates: [_candidate('u-2', 'Salem', pending: true), _candidate('u-3', 'Noura')]),
      ]);
      await toChoice(tester);
      await _tapKey(tester, 'account_deletion_action_transfer_h-p');

      expect(_text('Salem'), findsOneWidget);
      expect(_text(_l('en').get('del_choice_pending_label')), findsOneWidget);
      await _tapKey(tester, 'account_deletion_successor_h-p_u-2');
      expect(_chosen('account_deletion_successor_h-p_u-2'), isFalse, reason: 'a pending member cannot be picked');
      await _continue(tester);

      expect(_passwordStep, findsNothing, reason: 'the tap on a pending member chose nobody');
      expect(_text(_l('en').get('del_err_choice_missing')), findsOneWidget);
    });

    testWidgets('with only pending members the household can only be deleted', (tester) async {
      _setHouseholds([
        _household('h-p', 'Villa', 'primary_admin', candidates: [_candidate('u-2', 'Salem', pending: true)]),
      ]);
      _acceptRequest();
      await toChoice(tester);

      expect(find.byKey(const ValueKey('account_deletion_no_successor_h-p')), findsOneWidget);
      await _tapKey(tester, 'account_deletion_action_transfer_h-p');
      expect(_text('Salem'), findsNothing, reason: 'handing over cannot be selected');

      await _tapKey(tester, 'account_deletion_action_delete_h-p');
      await _continue(tester);
      expect(_passwordStep, findsOneWidget);
    });

    testWidgets('a member without a display name is still named', (tester) async {
      _setHouseholds([
        _household('h-p', 'Villa', 'primary_admin', candidates: [
          {'user_id': 'u-2', 'display_name': null, 'pending_deletion': false},
        ]),
      ]);
      await toChoice(tester);
      await _tapKey(tester, 'account_deletion_action_transfer_h-p');
      final tile = find.byKey(const ValueKey('account_deletion_successor_h-p_u-2'));
      expect(find.descendant(of: tile, matching: find.text(_l('en').get('member'))), findsOneWidget);
    });
  });

  group('re-authentication', () {
    Future<void> toReauth(WidgetTester tester) async {
      await _pump(tester);
      await _openFlow(tester);
      await _continue(tester);
    }

    testWidgets('a wrong password stays on the step, says so, and asks nothing of the server', (tester) async {
      await toReauth(tester);
      await _enterPassword(tester, 'wrong');

      expect(_passwordStep, findsOneWidget);
      expect(_wordStep, findsNothing);
      expect(_text(_l('en').get('del_err_wrong_password')), findsOneWidget);
      expect(_requests, isEmpty);
      expect(Supabase.instance.client.auth.currentUser?.id, fakeSettingsUserId, reason: 'still signed in');
      _expectNoRawServerText();
    });

    testWidgets('an empty password stays on the step and is not sent', (tester) async {
      await toReauth(tester);
      await _continue(tester);
      expect(_passwordStep, findsOneWidget);
      expect(_http.authCalls, isEmpty);
    });

    testWidgets('the right password goes on to the typed word, for this account\'s email', (tester) async {
      await toReauth(tester);
      await _enterPassword(tester);
      expect(_wordStep, findsOneWidget);
      expect(_http.authCalls, ['password:$fakeSettingsEmail']);
    });

    testWidgets('the fallback emails a code that creates no user, and only the right code goes on', (tester) async {
      await toReauth(tester);
      await _tapKey(tester, 'account_deletion_forgot');
      expect(_http.authCalls.single, 'otp:$fakeSettingsEmail:false');
      expect(_text(fakeSettingsEmail), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('account_deletion_code')), '000000');
      await _continue(tester);
      expect(_wordStep, findsNothing);
      expect(_text(_l('en').get('del_err_wrong_code')), findsOneWidget);
      _expectNoRawServerText();

      await tester.enterText(find.byKey(const ValueKey('account_deletion_code')), fakeSettingsEmailCode);
      await _continue(tester);
      expect(_wordStep, findsOneWidget);
      expect(_http.authCalls.last, 'verify:$fakeSettingsEmail:email');
    });

    testWidgets('can go back from the code to the password', (tester) async {
      await toReauth(tester);
      await _tapKey(tester, 'account_deletion_forgot');
      await _tapKey(tester, 'account_deletion_use_password');
      expect(_passwordStep, findsOneWidget);
    });

    testWidgets('sending the code too often says so and stays on the password', (tester) async {
      await toReauth(tester);
      _http.authFailure = (status: 429, code: 'over_email_send_rate_limit');
      await _tapKey(tester, 'account_deletion_forgot');
      expect(_passwordStep, findsOneWidget);
      expect(_text(_l('en').get('del_err_rate_limited')), findsOneWidget);
    });
  });

  group('the typed word', () {
    Future<void> toWord(WidgetTester tester) async {
      await _pump(tester);
      await _openFlow(tester);
      await _continue(tester);
      await _enterPassword(tester);
      expect(_wordStep, findsOneWidget);
    }

    testWidgets('a mismatch stays on the step and never reaches the server', (tester) async {
      await toWord(tester);
      await _typeWord(tester, 'DELET');
      expect(_wordStep, findsOneWidget);
      expect(_pendingCard, findsNothing);
      expect(_text(_l('en').get('del_err_confirmation_mismatch')), findsOneWidget);
      expect(_requests, isEmpty);
      expect(_provider.isPending, isFalse);
    });

    testWidgets('empty stays on the step and never reaches the server', (tester) async {
      await toWord(tester);
      await _tapKey(tester, 'account_deletion_confirm');
      expect(_wordStep, findsOneWidget);
      expect(_requests, isEmpty);
    });

    testWidgets('a mismatch the server finds also stays on the step', (tester) async {
      _http.rpcRefusals['request_account_deletion'] = const FakeRpcRefusal('confirmation_mismatch');
      await toWord(tester);
      await _typeWord(tester, 'DELETE');
      expect(_wordStep, findsOneWidget);
      expect(_text(_l('en').get('del_err_confirmation_mismatch')), findsOneWidget);
      expect(_provider.isPending, isFalse);
      _expectNoRawServerText();
    });

    testWidgets('a login too old for the server goes back to re-authenticate', (tester) async {
      _http.rpcRefusals['request_account_deletion'] =
          const FakeRpcRefusal('reauthentication_required', code: '42501', status: 403);
      await toWord(tester);
      await _typeWord(tester, 'DELETE');
      expect(_passwordStep, findsOneWidget);
      expect(_wordStep, findsNothing);
      expect(_text(_l('en').get('del_err_reauth_required')), findsOneWidget);
      _expectNoRawServerText();
    });

    testWidgets('a successor who went pending meanwhile goes back to the choice, now unselectable', (tester) async {
      _setHouseholds([
        _household('h-p', 'Villa', 'primary_admin', candidates: [_candidate('u-2', 'Salem'), _candidate('u-3', 'Noura')]),
      ]);
      _http.rpcRefusals['request_account_deletion'] = const FakeRpcRefusal('successor_pending_deletion');
      await _pump(tester);
      await _openFlow(tester);
      await _continue(tester);
      await _tapKey(tester, 'account_deletion_action_transfer_h-p');
      await _tapKey(tester, 'account_deletion_successor_h-p_u-2');
      await _continue(tester);
      await _enterPassword(tester);
      _setHouseholds([
        _household('h-p', 'Villa', 'primary_admin', candidates: [_candidate('u-2', 'Salem', pending: true), _candidate('u-3', 'Noura')]),
      ]);
      await _typeWord(tester, 'DELETE');

      expect(_wordStep, findsNothing);
      expect(_text(_l('en').get('del_err_successor_pending')), findsOneWidget);
      expect(_text(_l('en').get('del_choice_pending_label')), findsOneWidget);
      expect(_chosen('account_deletion_successor_h-p_u-2'), isFalse, reason: 'the old pick is cleared');
      await _continue(tester);
      expect(_passwordStep, findsNothing, reason: 'the old pick no longer counts');
      _expectNoRawServerText();
    });

    testWidgets('no connection stays on the step, says so, and nothing is scheduled', (tester) async {
      _http.rpcOffline.add('request_account_deletion');
      await toWord(tester);
      await _typeWord(tester, 'DELETE');
      expect(_wordStep, findsOneWidget);
      expect(_text(_l('en').get('del_err_network')), findsOneWidget);
      expect(_provider.isPending, isFalse);
      expect(await _cleaner.readFlag(fakeSettingsUserId), isNull);
    });

    testWidgets('an unknown refusal gets the generic message, never the raw text', (tester) async {
      _http.rpcRefusals['request_account_deletion'] = const FakeRpcRefusal('something_new');
      await toWord(tester);
      await _typeWord(tester, 'DELETE');
      expect(_text(_l('en').get('del_err_generic')), findsOneWidget);
      _expectNoRawServerText();
    });

    testWidgets('a request the server took but whose answer was lost shows the date, not an error', (tester) async {
      await toWord(tester);
      // The request reaches the server; only its answer never arrives.
      _http.rpcOffline.add('request_account_deletion');
      _http.rpcResults['get_account_deletion_status'] = _scheduledStatus();

      await _typeWord(tester, 'DELETE');

      expect(_wordStep, findsNothing);
      expect(find.descendant(of: _flow, matching: _text('5 December 2026')), findsOneWidget);
      expect(find.descendant(of: _flow, matching: _cancelButton), findsOneWidget);
      expect(_text(_l('en').get('del_err_network')), findsNothing);
      expect(_provider.isPending, isTrue);
      await _tapKey(tester, 'account_deletion_done');
      expect(_pendingCard, findsOneWidget);
    });

    testWidgets('a lost answer with nothing scheduled rereads the status and stays on the step', (tester) async {
      await toWord(tester);
      _http.rpcOffline.add('request_account_deletion');
      final statusReads = _http.rpcCalls.where((c) => c.function == 'get_account_deletion_status').length;

      await _typeWord(tester, 'DELETE');

      expect(_http.rpcCalls.where((c) => c.function == 'get_account_deletion_status').length, greaterThan(statusReads));
      expect(_wordStep, findsOneWidget);
      expect(_text(_l('en').get('del_err_network')), findsOneWidget);
      expect(_provider.isPending, isFalse);
    });

    testWidgets('two quick taps on Delete send one request', (tester) async {
      _acceptRequest();
      await toWord(tester);
      await tester.enterText(_wordStep, 'DELETE');
      final confirm = find.byKey(const ValueKey('account_deletion_confirm'));
      await tester.ensureVisible(confirm);
      await tester.pump();
      // The first request is still on its way when the second tap lands.
      _http.rpcGate = Completer<void>();
      await tester.tap(confirm);
      await tester.tap(confirm);
      _http.rpcGate!.complete();
      await _settle(tester);
      expect(_requests, hasLength(1));
      expect(_provider.isPending, isTrue);
    });
  });

  group('closing the flow', () {
    testWidgets('leaving without scheduling rereads the status, so Settings shows the truth', (tester) async {
      await _pump(tester);
      await _openFlow(tester);
      // Scheduled meanwhile, e.g. by a request whose answer was lost.
      _http.rpcResults['get_account_deletion_status'] = _scheduledStatus();
      await tester.tap(find.byType(BackButton));
      await _settle(tester);

      expect(_flow, findsNothing);
      expect(_pendingCard, findsOneWidget);
      expect(_deleteButton, findsNothing);
    });
  });

  group('the status after household changes', () {
    int statusReads() => _http.rpcCalls.where((c) => c.function == 'get_account_deletion_status').length;

    testWidgets('a role change rereads it', (tester) async {
      await _pump(tester);
      expect(_deleteButton, findsOneWidget);
      final before = statusReads();
      // E.g. primary admin handed over: the server's answer is different now.
      _http.rpcResults['get_account_deletion_status'] = _scheduledStatus();

      tester.widget<HouseholdRolesCard>(find.byType(HouseholdRolesCard)).onRolesChanged!();
      await _settle(tester);

      expect(statusReads(), greaterThan(before));
      expect(_pendingCard, findsOneWidget);
    });

    testWidgets('leaving a household rereads it', (tester) async {
      var left = 0;
      tester.view.physicalSize = const Size(390, 12000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(SettingsScreen(onLeftHousehold: (_) => left++)));
      await _settle(tester);
      await _provider.load();
      await _settle(tester);
      final before = statusReads();
      _http.rpcResults['get_account_deletion_status'] = _scheduledStatus();

      final leave = find.text(_l('en').get('leave_household')).first;
      await tester.ensureVisible(leave);
      await tester.pump();
      await tester.tap(leave);
      await _settle(tester);
      await tester.tap(find.text(_l('en').get('leave')));
      await _settle(tester);

      expect(_http.rpcCalls.where((c) => c.function == 'leave_household'), hasLength(1));
      expect(left, 1);
      expect(statusReads(), greaterThan(before));
      expect(_provider.isPending, isTrue);
    });
  });

  group('double taps in re-authentication', () {
    testWidgets('two quick taps on Continue check the password once', (tester) async {
      await _pump(tester);
      await _openFlow(tester);
      await _continue(tester);
      await tester.enterText(_passwordStep, fakeSettingsPassword);
      final next = find.byKey(const ValueKey('account_deletion_continue'));
      await tester.ensureVisible(next);
      await tester.pump();
      _http.authGate = Completer<void>();
      await tester.tap(next);
      await tester.tap(next);
      _http.authGate!.complete();
      await _settle(tester);
      expect(_http.authCalls, ['password:$fakeSettingsEmail']);
      expect(_wordStep, findsOneWidget);
    });

    testWidgets('two quick taps on the email code send one code', (tester) async {
      await _pump(tester);
      await _openFlow(tester);
      await _continue(tester);
      final forgot = find.byKey(const ValueKey('account_deletion_forgot'));
      await tester.ensureVisible(forgot);
      await tester.pump();
      _http.authGate = Completer<void>();
      await tester.tap(forgot);
      await tester.tap(forgot);
      _http.authGate!.complete();
      await _settle(tester);
      expect(_http.authCalls, ['otp:$fakeSettingsEmail:false']);
    });
  });

  testWidgets('a code that cannot be sent says so, never that the password is wrong', (tester) async {
    await _pump(tester);
    await _openFlow(tester);
    await _continue(tester);
    _http.authFailure = (status: 400, code: 'validation_failed');
    await _tapKey(tester, 'account_deletion_forgot');
    expect(_text(_l('en').get('del_err_code_not_sent')), findsOneWidget);
    expect(_text(_l('en').get('del_err_wrong_password')), findsNothing);
    _expectNoRawServerText();
  });

  group('the result', () {
    Future<void> complete(WidgetTester tester) async {
      _acceptRequest();
      await _pump(tester);
      await _openFlow(tester);
      await _continue(tester);
      await _enterPassword(tester);
      await _typeWord(tester, 'DELETE');
    }

    testWidgets('shows the date and Cancel, says only Cancel cancels, and sets the flag', (tester) async {
      await complete(tester);
      expect(find.descendant(of: _flow, matching: _text('5 December 2026')), findsOneWidget);
      expect(find.descendant(of: _flow, matching: _cancelButton), findsOneWidget);
      expect(find.descendant(of: _flow, matching: _text(_l('en').get('del_cancel_only_note'))), findsOneWidget);
      expect(_provider.isPending, isTrue);
      expect((await _cleaner.readFlag(fakeSettingsUserId))!.scheduledFor.toUtc(), DateTime.utc(2026, 12, 5, 10));
    });

    testWidgets('Done returns to Settings, which now shows the date and Cancel', (tester) async {
      await complete(tester);
      await _tapKey(tester, 'account_deletion_done');
      expect(_flow, findsNothing);
      expect(_pendingCard, findsOneWidget);
      expect(_deleteButton, findsNothing);
    });

    testWidgets('Cancel in the result returns to Settings with Delete account back', (tester) async {
      _http.rpcResults['cancel_account_deletion'] = const {'success': true, 'cancelled': true, 'status': 'none', 'can_cancel': false};
      await complete(tester);
      await _tapKey(tester, 'account_deletion_cancel');
      expect(_flow, findsNothing);
      expect(_deleteButton, findsOneWidget);
      expect(_provider.isPending, isFalse);
    });

    testWidgets('opening the flow when already pending goes straight to the date', (tester) async {
      await _pump(tester);
      _http.rpcResults['get_account_deletion_status'] = _scheduledStatus();
      _http.rpcResults['get_account_deletion_preflight'] = {'deletion': _scheduledStatus(), 'households': const []};
      await _openFlow(tester);
      expect(_text('5 December 2026'), findsWidgets);
      expect(_passwordStep, findsNothing);
      expect(find.byKey(const ValueKey('account_deletion_progress')), findsNothing);
    });
  });

  group('moving through the flow', () {
    testWidgets('the app bar back goes one step back, then out', (tester) async {
      await _pump(tester);
      await _openFlow(tester);
      await _continue(tester);
      expect(_passwordStep, findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await _settle(tester);
      expect(_flow, findsOneWidget);
      expect(_passwordStep, findsNothing);

      await tester.tap(find.byType(BackButton));
      await _settle(tester);
      expect(_flow, findsNothing);
      expect(_provider.isPending, isFalse);
    });

    testWidgets('a preflight that fails says so and can be retried', (tester) async {
      _http.rpcOffline.add('get_account_deletion_preflight');
      await _pump(tester);
      await _openFlow(tester);
      expect(_text(_l('en').get('del_err_network')), findsOneWidget);

      _http.rpcOffline.clear();
      await tester.tap(find.text(_l('en').get('try_again')));
      await _settle(tester);
      expect(find.byKey(const ValueKey('account_deletion_continue')), findsOneWidget);
    });

    testWidgets('step counter skips the choice step for a member', (tester) async {
      await _pump(tester);
      await _openFlow(tester);
      expect(_text(_l('en').format('del_step_of', {'current': 1, 'total': 3})), findsOneWidget);
    });

    testWidgets('step counter counts the choice step for an admin', (tester) async {
      _setHouseholds([
        _household('h-p', 'Villa', 'primary_admin', candidates: [_candidate('u-2', 'Salem')]),
      ]);
      await _pump(tester);
      await _openFlow(tester);
      expect(_text(_l('en').format('del_step_of', {'current': 1, 'total': 4})), findsOneWidget);
    });
  });

  group('sync first', () {
    testWidgets('pending items offer a sync without blocking Continue', (tester) async {
      _sync.unsynced = 2;
      await _pump(tester);
      await _openFlow(tester);
      expect(find.byKey(const ValueKey('account_deletion_sync_first')), findsOneWidget);

      await _continue(tester);
      expect(_passwordStep, findsOneWidget, reason: 'not synced, and not blocked');
      expect(_sync.flushes, 0);
    });

    testWidgets('syncing really flushes the queue and reports the outcome', (tester) async {
      _sync.unsynced = 2;
      await _pump(tester);
      await _openFlow(tester);
      await _tapKey(tester, 'account_deletion_sync_now');
      expect(_sync.flushes, 1);
      expect(_text(_l('en').get('del_sync_first_done')), findsOneWidget);
      expect(find.byKey(const ValueKey('account_deletion_sync_now')), findsNothing);
    });

    testWidgets('items that still cannot sync say so and still do not block', (tester) async {
      _sync.unsynced = 2;
      _sync.unsyncedAfterFlush = 1;
      await _pump(tester);
      await _openFlow(tester);
      await _tapKey(tester, 'account_deletion_sync_now');
      expect(_text(_l('en').get('del_sync_first_still')), findsOneWidget);
      await _continue(tester);
      expect(_passwordStep, findsOneWidget);
    });

    testWidgets('nothing pending shows nothing', (tester) async {
      await _pump(tester);
      await _openFlow(tester);
      expect(find.byKey(const ValueKey('account_deletion_sync_first')), findsNothing);
    });
  });

  group('signing out while pending', () {
    Future<void> tapSignOut(WidgetTester tester) async {
      final button = find.ancestor(of: find.text(_l('en').get('sign_out')), matching: find.byType(OutlinedButton));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await _settle(tester);
    }

    testWidgets('with unsynced items, warns that they are lost rather than that they wait', (tester) async {
      _http.rpcResults['get_account_deletion_status'] = _scheduledStatus();
      _sync.unsynced = 2;
      await _pump(tester);
      await tapSignOut(tester);
      expect(_text(_l('en').get('del_sign_out_wipe_warning')), findsOneWidget);
      expect(_text(_l('en').plural('sign_out_unsynced_warning', 2)), findsNothing);
      await tester.tap(find.text(_l('en').get('cancel')));
      await _settle(tester);
    });

    testWidgets('with nothing pending, the usual warning stays', (tester) async {
      _sync.unsynced = 2;
      await _pump(tester);
      await tapSignOut(tester);
      expect(_text(_l('en').get('del_sign_out_wipe_warning')), findsNothing);
      await tester.tap(find.text(_l('en').get('cancel')));
      await _settle(tester);
    });
  });

  group('three languages and RTL', () {
    const words = {'en': 'DELETE', 'ar': 'حذف', 'ur': 'حذف کریں'};

    for (final lang in const ['ar', 'en', 'ur']) {
      testWidgets('$lang: the whole flow in that language, with its word and locale', (tester) async {
        _setHouseholds([
          _household('h-p', 'Villa', 'primary_admin', candidates: [_candidate('u-2', 'Salem')]),
        ]);
        _acceptRequest();
        await _pump(tester, lang: lang);
        final l = _l(lang);

        await _openFlow(tester);
        expect(Directionality.of(tester.element(_flow)), lang == 'en' ? TextDirection.ltr : TextDirection.rtl);
        expect(_text(l.get('del_cancel_only_note')), findsOneWidget);
        expect(_text(l.get('del_settlement_warning')), findsOneWidget);
        expect(_text(l.get('del_household_delete_warning')), findsOneWidget);
        await _continue(tester);
        await _tapKey(tester, 'account_deletion_action_transfer_h-p');
        await _tapKey(tester, 'account_deletion_successor_h-p_u-2');
        await _continue(tester);

        expect(_text(l.format('del_reauth_body', {'email': fakeSettingsEmail})), findsOneWidget);
        await _enterPassword(tester, 'wrong');
        expect(_text(l.get('del_err_wrong_password')), findsOneWidget);
        await _enterPassword(tester);

        expect(l.get('del_confirm_word'), words[lang]);
        expect(_text(l.format('del_typed_body', {'word': words[lang]})), findsOneWidget);
        await _typeWord(tester, 'nope');
        expect(_text(l.get('del_err_confirmation_mismatch')), findsOneWidget);
        await _typeWord(tester, words[lang]!);

        expect(_requests.single.params['p_locale'], lang);
        expect(_requests.single.params['p_confirmation'], words[lang]);
        expect(find.descendant(of: _flow, matching: _cancelButton), findsOneWidget);
        expect(_text(l.get('del_result_title')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('$lang: the date is written in that language', (tester) async {
        _http.rpcResults['get_account_deletion_status'] = _scheduledStatus();
        await _pump(tester, lang: lang);
        final shown = _l(lang).format('del_pending_date', {'date': _l(lang).date(SalaryCycleService.riyadhDate(DateTime.parse(_scheduledFor)), 'd MMMM yyyy')});
        expect(_text(shown), findsOneWidget);
      });
    }

    testWidgets('the Arabic and Urdu copy says signing in does not cancel', (tester) async {
      expect(_l('ar').get('del_cancel_only_note'), contains('تسجيل الدخول لا يلغي'));
      expect(_l('ur').get('del_cancel_only_note'), contains('لاگ ان'));
      expect(_l('en').get('del_cancel_only_note'), contains('Signing in does not cancel'));
    });

    testWidgets('an Arabic user may also type the English word: the server accepts it', (tester) async {
      _acceptRequest();
      await _pump(tester, lang: 'ar');
      await _openFlow(tester);
      await _continue(tester);
      await _enterPassword(tester);
      await _typeWord(tester, 'delete');
      expect(_requests.single.params['p_confirmation'], 'delete');
    });
  });

  group('layout at 320px and x2.0 text', () {
    for (final lang in const ['ar', 'en', 'ur']) {
      for (final dark in const [false, true]) {
        testWidgets('$lang ${dark ? 'dark' : 'light'}: every step renders without overflow', (tester) async {
          _setHouseholds([
            _household('h-m', 'A household with a really rather long name indeed', 'member'),
            _household('h-p', 'Villa with a long name too', 'primary_admin', candidates: [
              _candidate('u-2', 'A member with a very long display name here'),
              _candidate('u-3', 'Pending member with a long name', pending: true),
            ]),
          ]);
          _sync.unsynced = 3;
          _acceptRequest(marked: [
            {'household_id': 'h-p', 'household_name': 'Villa with a long name too', 'scheduled_for': _scheduledFor},
          ]);
          await _pump(tester, lang: lang, dark: dark, scale: 2.0, width: 320);
          expect(tester.takeException(), isNull, reason: 'settings');

          await _openFlow(tester);
          expect(tester.takeException(), isNull, reason: 'consequences');
          await _continue(tester);
          await _tapKey(tester, 'account_deletion_action_transfer_h-p');
          expect(tester.takeException(), isNull, reason: 'choice');
          await _tapKey(tester, 'account_deletion_successor_h-p_u-2');
          await _continue(tester);
          expect(tester.takeException(), isNull, reason: 'password');
          await _tapKey(tester, 'account_deletion_forgot');
          expect(tester.takeException(), isNull, reason: 'code');
          await _tapKey(tester, 'account_deletion_use_password');
          await _enterPassword(tester);
          expect(tester.takeException(), isNull, reason: 'typed word');
          await _typeWord(tester, _l(lang).get('del_confirm_word'));
          expect(tester.takeException(), isNull, reason: 'result');
          expect(find.descendant(of: _flow, matching: _cancelButton), findsOneWidget);

          await _tapKey(tester, 'account_deletion_done');
          expect(_pendingCard, findsOneWidget);
          expect(tester.takeException(), isNull, reason: 'pending section');
        });
      }
    }
  });

  group('light and dark', () {
    for (final dark in const [false, true]) {
      testWidgets('${dark ? 'dark' : 'light'}: the date, the note and Cancel are readable on their surface', (tester) async {
        _http.rpcResults['get_account_deletion_status'] = _scheduledStatus();
        await _pump(tester, dark: dark);
        final card = tester.widget<Container>(_pendingCard);
        final surface = (card.decoration! as BoxDecoration).color!;
        for (final text in tester.widgetList<Text>(find.descendant(of: _pendingCard, matching: find.byType(Text)))) {
          if (text.style?.color == null) continue;
          expect(contrast(text.style!.color!, surface), greaterThanOrEqualTo(4.5), reason: text.data);
        }
        final button = tester.widget<ElevatedButton>(_cancelButton);
        final states = <WidgetState>{};
        final bg = button.style!.backgroundColor!.resolve(states)!;
        final fg = button.style!.foregroundColor!.resolve(states)!;
        expect(contrast(fg, bg), greaterThanOrEqualTo(4.5));
      });
    }
  });

  group('public links', () {
    testWidgets('open the real deletion and privacy pages, in the app language', (tester) async {
      await _pump(tester, lang: 'ur');
      await _tapKey(tester, 'account_deletion_page_link');
      await _tapKey(tester, 'privacy_page_link');
      expect(_launcher.launched, [
        'https://budget.fmsco.com.sa/delete-account?lang=ur',
        'https://budget.fmsco.com.sa/?lang=ur#privacy',
      ]);
      expect(_launcher.modes, everyElement(PreferredLaunchMode.externalApplication));
    });

    testWidgets('stay available to a pending user', (tester) async {
      _http.rpcResults['get_account_deletion_status'] = _scheduledStatus();
      await _pump(tester);
      expect(find.byKey(const ValueKey('account_deletion_page_link')), findsOneWidget);
      expect(find.byKey(const ValueKey('privacy_page_link')), findsOneWidget);
    });

    testWidgets('a page that cannot open says so', (tester) async {
      _launcher.fails = true;
      await _pump(tester);
      await _tapKey(tester, 'privacy_page_link');
      expect(_text(_l('en').get('del_link_failed')), findsOneWidget);
    });
  });

  group('a user with no household', () {
    Future<void> pumpOnboarding(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => BudgetProvider()),
          ChangeNotifierProvider(create: (_) => TransactionProvider()),
        ],
        child: _app(const HouseholdScreen()),
      ));
      _provider.load();
      await _settle(tester);
    }

    testWidgets('can still start a deletion, because Settings is out of reach', (tester) async {
      _setHouseholds([]);
      _acceptRequest();
      await pumpOnboarding(tester);
      await _tapKey(tester, 'household_account_deletion');
      expect(find.byKey(const ValueKey('account_deletion_settlement_warning')), findsNothing);
      await _continue(tester);
      await _enterPassword(tester);
      await _typeWord(tester, 'DELETE');
      expect(_requests.single.params['p_household_choices'], isEmpty);
    });

    testWidgets('when pending reaches the date and Cancel', (tester) async {
      _http.rpcResults['get_account_deletion_status'] = _scheduledStatus();
      _http.rpcResults['get_account_deletion_preflight'] = {'deletion': _scheduledStatus(), 'households': const []};
      _http.rpcResults['cancel_account_deletion'] = const {'success': true, 'cancelled': true, 'status': 'none', 'can_cancel': false};
      await pumpOnboarding(tester);
      await _tapKey(tester, 'household_account_deletion');
      expect(_text('5 December 2026'), findsOneWidget);
      await _tapKey(tester, 'account_deletion_cancel');
      expect(_provider.isPending, isFalse);
    });
  });
}
