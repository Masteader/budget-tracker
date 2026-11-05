import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/main.dart';
import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/providers/transaction_provider.dart';
import 'package:budget_tracker/services/household_resolver.dart';

Session _session(String userId) => Session(
      accessToken: 'jwt-$userId',
      tokenType: 'bearer',
      user: User(
        id: userId,
        appMetadata: const {},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: '2026-01-01T00:00:00Z',
      ),
    );

Widget _app(Widget home) => MaterialApp(
      localizationsDelegates: const [AppLocalizationsDelegate()],
      home: home,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('MOB-15 AuthGate', () {
    testWidgets('token refresh events do not re-query the household or rebuild the dashboard', (tester) async {
      final auth = StreamController<AuthState>();
      var lookups = 0;
      var readyCalls = 0;
      var homeBuilds = 0;

      await tester.pumpWidget(_app(AuthGate(
        authStates: auth.stream,
        resolver: HouseholdResolver(fetchRemote: (uid) async {
          lookups++;
          return 'h-1';
        }),
        loginBuilder: (_) => const Text('login'),
        onboardingBuilder: (_) => const Text('onboarding'),
        homeBuilder: (_) {
          homeBuilds++;
          return const Text('home');
        },
        onHouseholdReady: (_, __) => readyCalls++,
        onSignedOut: (_) {},
      )));

      auth.add(AuthState(AuthChangeEvent.initialSession, _session('u-1')));
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
      final buildsAfterStart = homeBuilds;

      for (var i = 0; i < 3; i++) {
        auth.add(AuthState(AuthChangeEvent.tokenRefreshed, _session('u-1')));
        await tester.pumpAndSettle();
        expect(find.byType(CircularProgressIndicator), findsNothing);
      }

      expect(lookups, 1);
      expect(readyCalls, 1);
      expect(find.text('home'), findsOneWidget);
      // The dashboard subtree is rebuilt in place, never replaced by a spinner.
      expect(homeBuilds - buildsAfterStart, lessThanOrEqualTo(3));
      await auth.close();
    });

    testWidgets('offline start with a cached household opens the dashboard, not onboarding', (tester) async {
      SharedPreferences.setMockInitialValues({HouseholdResolver.cacheKeyFor('u-1'): 'h-cached'});
      final auth = StreamController<AuthState>();
      String? readyFor;

      await tester.pumpWidget(_app(AuthGate(
        authStates: auth.stream,
        resolver: HouseholdResolver(fetchRemote: (uid) async => throw const SocketException('offline')),
        loginBuilder: (_) => const Text('login'),
        onboardingBuilder: (_) => const Text('onboarding'),
        homeBuilder: (_) => const Text('home'),
        onHouseholdReady: (_, hid) => readyFor = hid,
        onSignedOut: (_) {},
      )));
      auth.add(AuthState(AuthChangeEvent.initialSession, _session('u-1')));
      await tester.pumpAndSettle();

      expect(find.text('home'), findsOneWidget);
      expect(find.text('onboarding'), findsNothing);
      expect(readyFor, 'h-cached');
      await auth.close();
    });

    testWidgets('offline start without cache shows retry instead of onboarding', (tester) async {
      final auth = StreamController<AuthState>();
      var online = false;

      await tester.pumpWidget(_app(AuthGate(
        authStates: auth.stream,
        resolver: HouseholdResolver(fetchRemote: (uid) async {
          if (!online) throw const SocketException('offline');
          return 'h-1';
        }),
        loginBuilder: (_) => const Text('login'),
        onboardingBuilder: (_) => const Text('onboarding'),
        homeBuilder: (_) => const Text('home'),
        onHouseholdReady: (_, __) {},
        onSignedOut: (_) {},
      )));
      auth.add(AuthState(AuthChangeEvent.initialSession, _session('u-1')));
      await tester.pumpAndSettle();

      expect(find.text('onboarding'), findsNothing);
      expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);

      online = true;
      await tester.tap(find.byIcon(Icons.refresh_rounded));
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
      await auth.close();
    });

    testWidgets('a user without a household is sent to onboarding', (tester) async {
      final auth = StreamController<AuthState>();
      await tester.pumpWidget(_app(AuthGate(
        authStates: auth.stream,
        resolver: HouseholdResolver(fetchRemote: (uid) async => null),
        loginBuilder: (_) => const Text('login'),
        onboardingBuilder: (_) => const Text('onboarding'),
        homeBuilder: (_) => const Text('home'),
        onHouseholdReady: (_, __) {},
        onSignedOut: (_) {},
      )));
      auth.add(AuthState(AuthChangeEvent.initialSession, _session('u-1')));
      await tester.pumpAndSettle();
      expect(find.text('onboarding'), findsOneWidget);
      await auth.close();
    });

    testWidgets('MOB-16: signing out resets household state; the next account re-resolves', (tester) async {
      final auth = StreamController<AuthState>();
      final lookups = <String>[];
      var signedOutCalls = 0;
      final ready = <String>[];

      await tester.pumpWidget(_app(AuthGate(
        authStates: auth.stream,
        resolver: HouseholdResolver(fetchRemote: (uid) async {
          lookups.add(uid);
          return uid == 'u-1' ? 'h-1' : 'h-2';
        }),
        loginBuilder: (_) => const Text('login'),
        onboardingBuilder: (_) => const Text('onboarding'),
        homeBuilder: (_) => const Text('home'),
        onHouseholdReady: (_, hid) => ready.add(hid),
        onSignedOut: (_) => signedOutCalls++,
      )));

      auth.add(AuthState(AuthChangeEvent.initialSession, _session('u-1')));
      await tester.pumpAndSettle();
      auth.add(const AuthState(AuthChangeEvent.signedOut, null));
      await tester.pumpAndSettle();
      expect(find.text('login'), findsOneWidget);
      expect(signedOutCalls, 1);

      auth.add(AuthState(AuthChangeEvent.signedIn, _session('u-2')));
      await tester.pumpAndSettle();
      expect(lookups, ['u-1', 'u-2']);
      expect(ready, ['h-1', 'h-2']);
      await auth.close();
    });
  });

  group('auth stream errors', () {
    late StreamController<AuthState> auth;
    late int signedOutCalls;

    setUp(() {
      auth = StreamController<AuthState>();
      signedOutCalls = 0;
    });
    tearDown(() => auth.close());

    Widget gate({Locale? locale}) => MaterialApp(
          locale: locale,
          supportedLocales: const [Locale('en'), Locale('ar'), Locale('ur')],
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: AuthGate(
            authStates: auth.stream,
            resolver: HouseholdResolver(fetchRemote: (uid) async => 'h-1'),
            loginBuilder: (_) => const Scaffold(body: Text('login')),
            onboardingBuilder: (_) => const Text('onboarding'),
            homeBuilder: (_) => const Scaffold(body: Text('home')),
            recoveryBuilder: (_) => const Text('recovery'),
            onHouseholdReady: (_, __) {},
            onSignedOut: (_) => signedOutCalls++,
          ),
        );

    testWidgets('an error keeps a signed-in user on the dashboard and resets nothing', (tester) async {
      await tester.pumpWidget(gate());
      auth.add(AuthState(AuthChangeEvent.initialSession, _session('u-1')));
      await tester.pumpAndSettle();

      auth.addError(const AuthException('x'));
      await tester.pumpAndSettle();

      expect(find.text('home'), findsOneWidget);
      expect(find.text('login'), findsNothing);
      expect(signedOutCalls, 0);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('an error delivered in the same frame as the session keeps the session', (tester) async {
      // Late subscribers get the auth stream's history replayed in one burst.
      await tester.pumpWidget(gate());
      auth.add(AuthState(AuthChangeEvent.initialSession, _session('u-1')));
      auth.addError(const AuthException('x'));
      await tester.pumpAndSettle();

      expect(find.text('home'), findsOneWidget);
      expect(signedOutCalls, 0);
    });

    testWidgets('an offline refresh failure of an expired token keeps the user in the app', (tester) async {
      // The refresh token still works once back online; gotrue keeps the session.
      await tester.pumpWidget(gate());
      auth.add(AuthState(AuthChangeEvent.initialSession, _session('u-1')));
      await tester.pumpAndSettle();

      auth.addError(AuthRetryableFetchException(message: 'offline'));
      await tester.pumpAndSettle();

      expect(find.text('home'), findsOneWidget);
      expect(signedOutCalls, 0);
    });

    testWidgets('an error during password recovery stays on the recovery screen', (tester) async {
      await tester.pumpWidget(gate());
      auth.add(AuthState(AuthChangeEvent.passwordRecovery, _session('u-1')));
      await tester.pumpAndSettle();

      auth.addError(const AuthException('x'));
      await tester.pumpAndSettle();

      expect(find.text('recovery'), findsOneWidget);
    });

    testWidgets('a real sign-out after an error still goes to login', (tester) async {
      await tester.pumpWidget(gate());
      auth.add(AuthState(AuthChangeEvent.initialSession, _session('u-1')));
      await tester.pumpAndSettle();
      auth.addError(const AuthException('x'));
      await tester.pumpAndSettle();

      auth.add(const AuthState(AuthChangeEvent.signedOut, null));
      await tester.pumpAndSettle();

      expect(find.text('login'), findsOneWidget);
      expect(find.text('home'), findsNothing);
      expect(signedOutCalls, 1);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('a really expired session still goes to login', (tester) async {
      await tester.pumpWidget(gate());
      auth.add(AuthState(AuthChangeEvent.initialSession, _session('u-1')));
      await tester.pumpAndSettle();

      auth.add(const AuthState(AuthChangeEvent.signedOut, null, signOutReason: SignOutReason.sessionExpired));
      await tester.pumpAndSettle();

      expect(find.text('login'), findsOneWidget);
      expect(signedOutCalls, 1);
    });

    testWidgets('an error after signing out is not protected by the old session', (tester) async {
      await tester.pumpWidget(gate());
      auth.add(AuthState(AuthChangeEvent.initialSession, _session('u-1')));
      await tester.pumpAndSettle();
      auth.add(const AuthState(AuthChangeEvent.signedOut, null));
      await tester.pumpAndSettle();

      auth.addError(const AuthException('x'));
      await tester.pumpAndSettle();

      expect(find.text('login'), findsOneWidget);
      expect(find.text('home'), findsNothing);
      expect(signedOutCalls, 1);
    });

    for (final (locale, title) in const [
      (Locale('en'), 'Authentication Error'),
      (Locale('ar'), 'خطأ في المصادقة'),
      (Locale('ur'), 'تصدیق میں خرابی'),
    ]) {
      testWidgets('with no session an error shows login and a message once (${locale.languageCode})', (tester) async {
        await tester.pumpWidget(gate(locale: locale));
        auth.add(const AuthState(AuthChangeEvent.initialSession, null));
        await tester.pumpAndSettle();
        expect(find.byType(SnackBar), findsNothing);

        auth.addError(const AuthException('raw server text'));
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 750));

        expect(find.text('login'), findsOneWidget);
        expect(find.text(title), findsOneWidget);
        final message = AppLocalizations(locale).get('auth_sign_in_unverified');
        expect(find.text(message), findsOneWidget);
        expect(find.text('raw server text'), findsNothing);

        await tester.pump(const Duration(seconds: 5));
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        expect(find.byType(SnackBar), findsNothing);

        // A rebuild is not a second error.
        await tester.pumpWidget(gate(locale: locale));
        await tester.pumpAndSettle();
        expect(find.byType(SnackBar), findsNothing);
      });
    }

    testWidgets('signing in after an error reaches the dashboard', (tester) async {
      await tester.pumpWidget(gate());
      auth.addError(const AuthException('x'));
      await tester.pumpAndSettle();
      expect(find.text('login'), findsOneWidget);

      auth.add(AuthState(AuthChangeEvent.signedIn, _session('u-1')));
      await tester.pumpAndSettle();

      expect(find.text('home'), findsOneWidget);
    });
  });

  group('MOB-16 TransactionProvider.reset', () {
    test('drops the previous account transactions', () {
      final provider = TransactionProvider();
      provider.addTransaction(Transaction.fromMap({
        'id': 't-1',
        'household_id': 'h-1',
        'amount': 10,
        'timestamp': '2026-10-01T10:00:00Z',
        'created_at': '2026-10-01T10:00:00Z',
      }));
      expect(provider.transactions, hasLength(1));

      provider.reset();

      expect(provider.transactions, isEmpty);
      expect(provider.filteredTransactions, isEmpty);
    });
  });
}
