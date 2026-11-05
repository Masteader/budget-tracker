// The real AuthGate with the real provider and cleaner: what it does for account
// deletion at launch, when the household is ready, on sign-out and on resume.
import 'dart:async';

import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/main.dart';
import 'package:budget_tracker/models/account_deletion.dart';
import 'package:budget_tracker/providers/account_deletion_provider.dart';
import 'package:budget_tracker/services/account_deletion_service.dart';
import 'package:budget_tracker/services/household_resolver.dart';
import 'package:budget_tracker/services/local_account_data_cleaner.dart';
import 'package:budget_tracker/services/offline_queue_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'package:supabase_flutter/supabase_flutter.dart' as sb show User;

const _me = 'user-me';
const _other = 'user-other';
final _date = DateTime.utc(2030, 1, 1);

Session _session(String userId) => Session(
      accessToken: 'jwt-$userId',
      tokenType: 'bearer',
      user: sb.User(
        id: userId,
        appMetadata: const {},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: '2026-01-01T00:00:00Z',
      ),
    );

class _FakeService extends AccountDeletionService {
  AccountDeletionStatus status = AccountDeletionStatus.none;
  final Map<String, HouseholdDeletionMark> marks = {};
  int statusReads = 0;
  final markReads = <String>[];

  @override
  Future<AccountDeletionStatus> getStatus() async {
    statusReads++;
    return status;
  }

  @override
  Future<AccountDeletionPreflight> getPreflight() async => const AccountDeletionPreflight(deletion: AccountDeletionStatus.none);

  @override
  Future<HouseholdDeletionMark> readHouseholdMark(String householdId) async {
    markReads.add(householdId);
    return marks[householdId] ?? const HouseholdDeletionMark(readable: true);
  }

  @override
  Future<bool> accountRowExists() async => true;
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late OfflineQueueManager queue;
  late _FakeService service;
  late LocalAccountDataCleaner cleaner;
  late AccountDeletionProvider provider;
  late StreamController<AuthState> auth;
  late List<String> resolved;
  late String? remoteHousehold;
  String? signedInNow;

  Future<void> enqueueAs(String owner) async {
    await queue.enqueue(operationType: 'receipt', payload: {'user_id': owner, 'merchant': 'Shop'}, householdId: 'h-1');
  }

  Future<List<String?>> queueOwners() async {
    final items = await queue.getPendingItems();
    return items.map((i) => i.ownerId).toList();
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await OfflineQueueManager.createSchema(db);
    queue = OfflineQueueManager(customDb: db);
    service = _FakeService();
    cleaner = LocalAccountDataCleaner(queue: queue, cancelReminders: () async {}, deleteStatements: () async {}, clearSignedUrls: () {});
    signedInNow = _me;
    provider = AccountDeletionProvider(service: service, cleaner: cleaner, currentUserId: () => signedInNow, clock: () => DateTime.utc(2026, 11, 5));
    auth = StreamController<AuthState>();
    resolved = [];
    remoteHousehold = 'h-1';
  });

  tearDown(() async {
    await auth.close();
    await db.close();
  });

  Widget gate() => ChangeNotifierProvider<AccountDeletionProvider>.value(
        value: provider,
        child: MaterialApp(
          localizationsDelegates: const [AppLocalizationsDelegate()],
          home: AuthGate(
            authStates: auth.stream,
            resolver: HouseholdResolver(fetchRemote: (uid) async {
              resolved.add(uid);
              return remoteHousehold;
            }),
            loginBuilder: (_) => const Text('login'),
            onboardingBuilder: (_) => const Text('onboarding'),
            homeBuilder: (_) => const Text('home'),
            onHouseholdReady: (_, __) {},
            onSignedOut: (_) {},
          ),
        ),
      );

  // The database work runs on real futures, outside the fake clock.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 15; i++) {
      await tester.pumpAndSettle();
      await tester.runAsync(() async => Future<void>.delayed(const Duration(milliseconds: 20)));
    }
    await tester.pumpAndSettle();
  }

  group('when the household is ready', () {
    testWidgets('reads the status and the mark of that household', (tester) async {
      service.status = AccountDeletionStatus(state: AccountDeletionState.scheduled, scheduledFor: _date, canCancel: true);
      service.marks['h-1'] = HouseholdDeletionMark(readable: true, scheduledFor: _date);
      await tester.pumpWidget(gate());
      auth.add(AuthState(AuthChangeEvent.initialSession, _session(_me)));
      await settle(tester);

      expect(find.text('home'), findsOneWidget);
      expect(provider.isPending, isTrue);
      expect(provider.householdDeletionDate('h-1'), _date);
    });

    testWidgets('a user with no household still gets the status', (tester) async {
      remoteHousehold = null;
      service.status = AccountDeletionStatus(state: AccountDeletionState.scheduled, scheduledFor: _date, canCancel: true);
      await tester.pumpWidget(gate());
      auth.add(AuthState(AuthChangeEvent.initialSession, _session(_me)));
      await settle(tester);

      expect(find.text('onboarding'), findsOneWidget);
      expect(provider.isPending, isTrue);
    });

    testWidgets('token refreshes do not read the status again', (tester) async {
      await tester.pumpWidget(gate());
      auth.add(AuthState(AuthChangeEvent.initialSession, _session(_me)));
      await settle(tester);
      final reads = service.statusReads;
      expect(reads, 1);

      auth.add(AuthState(AuthChangeEvent.tokenRefreshed, _session(_me)));
      auth.add(AuthState(AuthChangeEvent.signedIn, _session(_me)));
      await settle(tester);
      expect(service.statusReads, reads, reason: 're-authenticating in the flow is the same user');
    });
  });

  group('signing out', () {
    testWidgets('while pending wipes this user and leaves the other account', (tester) async {
      service.status = AccountDeletionStatus(state: AccountDeletionState.scheduled, scheduledFor: _date, canCancel: true);
      await tester.runAsync(() async {
        await enqueueAs(_me);
        await enqueueAs(_other);
      });
      await tester.pumpWidget(gate());
      auth.add(AuthState(AuthChangeEvent.initialSession, _session(_me)));
      await settle(tester);
      expect(provider.isPending, isTrue);

      signedInNow = null;
      auth.add(const AuthState(AuthChangeEvent.signedOut, null));
      await settle(tester);

      expect(find.text('login'), findsOneWidget);
      final owners = await tester.runAsync(queueOwners);
      expect(owners, [_other]);
      expect(await tester.runAsync(() => cleaner.readFlag(_me)), isNull);
      expect(provider.isPending, isFalse);
      expect(provider.isLoaded, isFalse);
    });

    testWidgets('with nothing pending keeps every queued item', (tester) async {
      await tester.runAsync(() => enqueueAs(_me));
      await tester.pumpWidget(gate());
      auth.add(AuthState(AuthChangeEvent.initialSession, _session(_me)));
      await settle(tester);

      signedInNow = null;
      auth.add(const AuthState(AuthChangeEvent.signedOut, null));
      await settle(tester);

      expect(await tester.runAsync(queueOwners), [_me]);
      expect(provider.isLoaded, isFalse);
    });

    testWidgets('a stream error is not a sign-out and wipes nothing', (tester) async {
      service.status = AccountDeletionStatus(state: AccountDeletionState.scheduled, scheduledFor: _date, canCancel: true);
      await tester.runAsync(() => enqueueAs(_me));
      await tester.pumpWidget(gate());
      auth.add(AuthState(AuthChangeEvent.initialSession, _session(_me)));
      await settle(tester);

      auth.addError(Exception('offline token refresh failed'));
      await settle(tester);

      expect(await tester.runAsync(queueOwners), [_me]);
      expect(provider.isPending, isTrue);
    });
  });

  group('at launch', () {
    testWidgets('wipes a flagged account whose date has passed, signed in or not on screen', (tester) async {
      signedInNow = null;
      await tester.runAsync(() async {
        await enqueueAs(_other);
        await cleaner.setFlag(_other, DateTime.utc(2026, 1, 1));
      });
      await tester.pumpWidget(gate());
      await settle(tester);

      expect(await tester.runAsync(queueOwners), isEmpty);
      expect(await tester.runAsync(() => cleaner.readFlag(_other)), isNull);
    });

    testWidgets('leaves a flagged account whose date is ahead', (tester) async {
      signedInNow = null;
      await tester.runAsync(() async {
        await enqueueAs(_other);
        await cleaner.setFlag(_other, DateTime.utc(2030, 1, 1));
      });
      await tester.pumpWidget(gate());
      await settle(tester);

      expect(await tester.runAsync(queueOwners), [_other]);
    });

    testWidgets('leaves the signed-in user: the server decides for them', (tester) async {
      await tester.runAsync(() async {
        await enqueueAs(_me);
        await cleaner.setFlag(_me, DateTime.utc(2026, 1, 1));
      });
      service.status = AccountDeletionStatus(state: AccountDeletionState.scheduled, scheduledFor: DateTime.utc(2026, 1, 1), canCancel: true);
      await tester.pumpWidget(gate());
      auth.add(AuthState(AuthChangeEvent.initialSession, _session(_me)));
      await settle(tester);

      expect(await tester.runAsync(queueOwners), [_me]);
      expect(provider.isPending, isTrue);
    });
  });

  group('on resume', () {
    testWidgets('reads the status and the household again', (tester) async {
      await tester.pumpWidget(gate());
      auth.add(AuthState(AuthChangeEvent.initialSession, _session(_me)));
      await settle(tester);
      final statusReads = service.statusReads;
      final markReads = service.markReads.length;
      service.status = AccountDeletionStatus(state: AccountDeletionState.scheduled, scheduledFor: _date, canCancel: true);
      service.marks['h-1'] = HouseholdDeletionMark(readable: true, scheduledFor: _date);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);

      expect(service.statusReads, statusReads + 1);
      expect(service.markReads.length, markReads + 1);
      expect(provider.isPending, isTrue);
      expect(provider.householdDeletionDate('h-1'), _date);
    });

    testWidgets('a household that vanished moves to the next one the server names', (tester) async {
      await tester.pumpWidget(gate());
      auth.add(AuthState(AuthChangeEvent.initialSession, _session(_me)));
      await settle(tester);
      expect(resolved, [_me]);

      remoteHousehold = 'h-2';
      service.marks['h-1'] = const HouseholdDeletionMark(readable: false);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);

      expect(resolved, [_me, _me], reason: 'the active household is resolved again');
      expect(find.text('home'), findsOneWidget);
      expect(service.markReads.last, 'h-2', reason: 'the new household is initialised');
    });

    testWidgets('a household that vanished with nothing left goes to onboarding', (tester) async {
      await tester.pumpWidget(gate());
      auth.add(AuthState(AuthChangeEvent.initialSession, _session(_me)));
      await settle(tester);

      remoteHousehold = null;
      service.marks['h-1'] = const HouseholdDeletionMark(readable: false);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);

      expect(find.text('onboarding'), findsOneWidget);
    });

    testWidgets('a household still there does not resolve again', (tester) async {
      await tester.pumpWidget(gate());
      auth.add(AuthState(AuthChangeEvent.initialSession, _session(_me)));
      await settle(tester);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);

      expect(resolved, [_me]);
    });

    testWidgets('signed out, resuming reads nothing', (tester) async {
      await tester.pumpWidget(gate());
      await settle(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);
      expect(service.statusReads, 0);
    });
  });
}
