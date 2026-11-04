import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:budget_tracker/services/auth_deep_link_policy.dart';

const _tokens = 'access_token=t&refresh_token=r&expires_in=3600&token_type=bearer';

const _eventChannel = EventChannel('com.llfbandit.app_links/events');

/// What `gotrue` stores when this device asked for the recovery email.
const _verifierKey = 'supabase.auth.token-code-verifier';

Map<String, dynamic> _userJson(String id) => {
      'id': id,
      'aud': 'authenticated',
      'app_metadata': <String, dynamic>{},
      'user_metadata': <String, dynamic>{},
      'created_at': '2026-01-01T00:00:00Z',
    };

class _MemoryAsyncStorage extends GotrueAsyncStorage {
  final values = <String, String>{};

  @override
  Future<String?> getItem({required String key}) async => values[key];

  @override
  Future<void> removeItem({required String key}) async => values.remove(key);

  @override
  Future<void> setItem({required String key, required String value}) async => values[key] = value;
}

/// The real supabase_flutter deep link path, with only the platform channel
/// and the network replaced.
class _Harness {
  final requests = <http.Request>[];
  final pkce = _MemoryAsyncStorage();
  final authStates = <AuthState>[];
  final authErrors = <Object>[];
  MockStreamHandlerEventSink? _links;
  StreamSubscription<AuthState>? _subscription;

  GoTrueClient get auth => Supabase.instance.client.auth;

  /// [coldStartLink] is delivered as soon as the observer starts listening,
  /// the way the Android and iOS plugins hand over the launch link.
  Future<void> start({String? coldStartLink, Session? signedInAs}) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockStreamHandler(
      _eventChannel,
      MockStreamHandler.inline(onListen: (_, sink) {
        _links = sink;
        if (coldStartLink != null) sink.success(coldStartLink);
      }),
    );
    await Supabase.initialize(
      url: 'https://example.test',
      publishableKey: 'anon',
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/token')) {
          return http.Response(
            jsonEncode({
              'access_token': 'recovered',
              'refresh_token': 'recovered-refresh',
              'expires_in': 3600,
              'token_type': 'bearer',
              'user': _userJson('owner'),
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path.endsWith('/recover')) {
          return http.Response('{}', 200, headers: {'content-type': 'application/json'});
        }
        return http.Response(jsonEncode(_userJson('attacker')), 200, headers: {'content-type': 'application/json'});
      }),
      authOptions: FlutterAuthClientOptions(
        localStorage: const EmptyLocalStorage(),
        pkceAsyncStorage: pkce,
        autoRefreshToken: false,
        detectSessionInUriPredicate: isTrustedAuthDeepLink,
      ),
    );
    _subscription = auth.onAuthStateChange.listen(authStates.add, onError: authErrors.add);
    await pumpEventQueue();
  }

  Future<void> deliver(String link) async {
    _links!.success(link);
    await pumpEventQueue();
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    await Supabase.instance.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockStreamHandler(_eventChannel, null);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('isTrustedAuthDeepLink', () {
    const accepted = <String>[
      'budgettracker://reset-password?code=abc',
      'budgettracker://reset-password/?code=abc',
      'budgettracker://auth-callback?code=abc',
      'budgettracker://login?code=abc',
      'io.supabase.budgettracker://login-callback/?code=abc',
      'io.supabase.budgettracker://reset-password?code=abc',
      'BudgetTracker://LOGIN?code=abc',
      // landing_page.py keeps the query when it hands a recovery link over.
      'budgettracker://reset-password?type=recovery&code=abc',
      // How Supabase reports an expired link.
      'budgettracker://reset-password#error=access_denied&error_code=otp_expired&error_description=Email+link+is+invalid',
      'budgettracker://login?error_description=denied',
    ];
    for (final link in accepted) {
      test('accepts $link', () => expect(isTrustedAuthDeepLink(Uri.parse(link)), isTrue));
    }

    const rejected = <String>[
      // Bug 1: tokens in a link, in the query and in the fragment.
      'budgettracker://login?$_tokens',
      'budgettracker://login#$_tokens',
      'budgettracker://auth-callback?$_tokens',
      'io.supabase.budgettracker://login-callback/#$_tokens',
      // landing_page.py's token shape for a link not issued through PKCE.
      'budgettracker://reset-password#$_tokens&type=recovery',
      // Tokens riding along with an accepted parameter.
      'budgettracker://login?code=abc&access_token=t',
      'budgettracker://login?code=abc#$_tokens',
      'budgettracker://login?error=x&access_token=t',
      'budgettracker://login#error=x&$_tokens',
      'budgettracker://login?code=abc&refresh_token=r',
      'budgettracker://login?code=abc&provider_token=p',
      'budgettracker://login?co%64e=abc&acces%73_token=t',
      // Bug 2: unexpected hosts.
      'budgettracker://anything?error=x',
      'budgettracker://anything?code=abc',
      'budgettracker://login@anything?code=abc',
      'budgettracker:login?code=abc',
      'budgettracker:///login?code=abc',
      // Other schemes and hosts.
      'https://login?code=abc',
      'https://budget.fmsco.com.sa/auth/confirm?code=abc',
      'evil://login?code=abc',
      'budgettrackerx://login?code=abc',
      // No usable parameter.
      'budgettracker://login',
      'budgettracker://reset-password',
      'budgettracker://login?code=',
      'budgettracker://login#code=abc',
      'budgettracker://reset-password?token_hash=h&type=recovery',
      // Malformed UTF-8 fails closed instead of throwing.
      'budgettracker://login?code=%ff',
      'budgettracker://login?code=abc#x=%ff',
    ];
    for (final link in rejected) {
      test('rejects $link', () => expect(isTrustedAuthDeepLink(Uri.parse(link)), isFalse));
    }
  });

  group('deep links through the real supabase_flutter path', () {
    late _Harness harness;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      harness = _Harness();
    });
    tearDown(() => harness.stop());

    for (final link in const [
      'budgettracker://login?$_tokens',
      'budgettracker://reset-password#$_tokens&type=recovery',
      'budgettracker://login?code=abc#$_tokens',
    ]) {
      test('a crafted link saves no session and contacts nobody: $link', () async {
        await harness.start();
        await harness.deliver(link);

        expect(harness.auth.currentSession, isNull);
        expect(harness.requests, isEmpty);
        expect(harness.authStates.map((s) => s.event), isNot(contains(AuthChangeEvent.signedIn)));
        expect(harness.authStates.map((s) => s.event), isNot(contains(AuthChangeEvent.passwordRecovery)));
      });
    }

    test('a crafted token link at cold start saves no session', () async {
      await harness.start(coldStartLink: 'budgettracker://login?$_tokens');

      expect(harness.auth.currentSession, isNull);
      expect(harness.requests, isEmpty);
    });

    test('an error link on an unexpected host never reaches gotrue', () async {
      await harness.start();
      await harness.deliver('budgettracker://anything?error=x');

      expect(harness.authErrors, isEmpty);
    });

    test('an expired-link error from Supabase reaches the auth stream', () async {
      await harness.start();
      await harness.deliver('budgettracker://reset-password#error=access_denied&error_code=otp_expired');

      expect(harness.authErrors, hasLength(1));
      expect(harness.auth.currentSession, isNull);
      expect(harness.requests, isEmpty);
    });

    test('password reset from the background: the app asks, then the emailed code opens recovery', () async {
      await harness.start();
      await harness.auth.resetPasswordForEmail('owner@example.test', redirectTo: 'budgettracker://reset-password');
      expect(harness.pkce.values[_verifierKey], endsWith('/passwordRecovery'));
      final verifier = harness.pkce.values[_verifierKey]!.split('/').first;

      await harness.deliver('budgettracker://reset-password?code=abc');

      expect(harness.auth.currentSession?.user.id, 'owner');
      expect(harness.authStates.last.event, AuthChangeEvent.passwordRecovery);
      final exchange = harness.requests.singleWhere((r) => r.url.path.endsWith('/token'));
      expect(jsonDecode(exchange.body), {'auth_code': 'abc', 'code_verifier': verifier});
      expect(harness.requests.where((r) => r.url.path.endsWith('/user')), isEmpty);
    });

    test('password reset from cold start: the launch link opens recovery', () async {
      harness.pkce.values[_verifierKey] = 'verifier/passwordRecovery';

      await harness.start(coldStartLink: 'budgettracker://reset-password?code=abc');

      expect(harness.auth.currentSession?.user.id, 'owner');
      expect(harness.authStates.last.event, AuthChangeEvent.passwordRecovery);
    });

    for (final link in const [
      'budgettracker://auth-callback?code=abc',
      'budgettracker://login?code=abc',
      'io.supabase.budgettracker://login-callback/?code=abc',
    ]) {
      test('a login callback signs in on every declared target: $link', () async {
        harness.pkce.values[_verifierKey] = 'verifier/signedIn';
        await harness.start();

        await harness.deliver(link);

        expect(harness.auth.currentSession?.user.id, 'owner');
        expect(harness.authStates.last.event, AuthChangeEvent.signedIn);
      });
    }

    test('a code without this device\'s verifier saves no session', () async {
      await harness.start();
      await harness.deliver('budgettracker://login?code=attacker-code');

      expect(harness.auth.currentSession, isNull);
      expect(harness.authErrors, hasLength(1));
      expect(harness.requests, isEmpty);
    });
  });

  test('main.dart passes the predicate to Supabase, and PKCE stays on', () {
    expect(File('lib/main.dart').readAsStringSync(), contains('detectSessionInUriPredicate: isTrustedAuthDeepLink'));
    expect(const FlutterAuthClientOptions().authFlowType, AuthFlowType.pkce);
  });

  test('landing_page.py hands over only hash or search on reset-password', () {
    final page = File('../ai_service/landing_page.py').readAsStringSync();
    expect(page, contains("'budgettracker://reset-password' + (hash || search)"));
    expect(page, contains('href="budgettracker://login"'));
    expect(isTrustedAuthDeepLink(Uri.parse('budgettracker://login')), isFalse);
  });

  test('every budgettracker host in the Android manifest is accepted, and nothing else', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final declared = RegExp(r'android:scheme="budgettracker" android:host="([^"]+)"')
        .allMatches(manifest)
        .map((match) => match.group(1)!)
        .toSet();
    expect(declared, {'reset-password', 'auth-callback', 'login'});
    expect(manifest, contains('android:scheme="io.supabase.budgettracker"'));
    for (final host in declared) {
      expect(isTrustedAuthDeepLink(Uri.parse('budgettracker://$host?code=abc')), isTrue, reason: host);
    }
  });
}
