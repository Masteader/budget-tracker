import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
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
