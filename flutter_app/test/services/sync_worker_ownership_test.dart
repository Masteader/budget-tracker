// Whose queue items are counted and replayed, against a real SQLite queue:
// signed out nothing drains, and one account is never told about, or replays,
// another account's items (S2, S3).
import 'dart:convert';

import 'package:budget_tracker/services/offline_queue_manager.dart';
import 'package:budget_tracker/services/sync_worker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late OfflineQueueManager queue;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await OfflineQueueManager.createSchema(db);
    queue = OfflineQueueManager(customDb: db);
  });

  tearDown(() async => db.close());

  Future<String> enqueue({String? owner, String message = 'Coffee 15 SAR'}) async => (await queue.enqueue(
        operationType: 'chat',
        payload: {'message': message, if (owner != null) 'user_id': owner},
        householdId: 'h-1',
      ))!;

  Future<void> park(String id) => db.update(OfflineQueueManager.tableName, {'status': 'failed'}, where: 'id = ?', whereArgs: [id]);

  Future<Map<String, Object?>> rowOf(String id) async => (await db.query(OfflineQueueManager.tableName, where: 'id = ?', whereArgs: [id])).first;

  group('counts belong to the current user (S2)', () {
    test('user B is not told about A\'s items', () async {
      await enqueue(owner: 'a');
      await enqueue(owner: 'a');
      await enqueue(owner: 'b');
      expect(await queue.getUnsyncedCount(userId: 'b'), 1);
      expect(await queue.getPendingCount(userId: 'b'), 1);
      expect(await queue.getUnsyncedCount(userId: 'a'), 2);
      expect(await queue.getPendingCount(), 3, reason: 'without a user the device-wide count is unchanged');
    });

    test('parked failed items count as unsynced, not as pending', () async {
      await enqueue(owner: 'a');
      await park(await enqueue(owner: 'a'));
      await park(await enqueue(owner: 'b'));
      expect(await queue.getUnsyncedCount(userId: 'a'), 2);
      expect(await queue.getPendingCount(userId: 'a'), 1);
    });

    test('items without an owner count for whoever would replay them', () async {
      await enqueue();
      expect(await queue.getUnsyncedCount(userId: 'a'), 1);
      expect(await queue.getUnsyncedCount(userId: 'b'), 1);
    });

    test('an empty owner is no owner', () async {
      await queue.enqueue(operationType: 'chat', payload: const {'message': 'x', 'user_id': ''}, householdId: 'h-1');
      await queue.enqueue(operationType: 'chat', payload: const {'message': 'y', 'user_id': null}, householdId: 'h-1');
      expect(await queue.getUnsyncedCount(userId: 'b'), 2);
    });

    test('the worker\'s notifier and count use the signed-in user', () async {
      await enqueue(owner: 'a');
      await park(await enqueue(owner: 'a'));
      await enqueue(owner: 'b');
      final worker = SyncWorker(queueManager: queue, currentUserId: () => 'a', customDispatcher: (_) async => const {'status': 'success'});
      expect(await worker.updatePendingCount(), 1);
      expect(worker.pendingCountNotifier.value, 1);
      expect(await worker.unsyncedCount(), 2);
    });
  });

  group('signed out, nothing drains (S3)', () {
    test('the connectivity listener at the login screen touches nothing', () async {
      final id = await enqueue(owner: 'a');
      var dispatched = 0;
      final worker = SyncWorker(
        queueManager: queue,
        currentUserId: () => null,
        interItemDelay: Duration.zero,
        customDispatcher: (_) async {
          dispatched++;
          return const {'status': 'success'};
        },
      );
      expect(await worker.drainQueue(), 0);
      expect(dispatched, 0);
      final row = await rowOf(id);
      expect(row['status'], 'pending');
      expect(row['retry_count'], 0);
    });

    test('five connectivity flips at the login screen do not park a refused expense', () async {
      final id = await enqueue(owner: 'a');
      var signedIn = false;
      final worker = SyncWorker(
        queueManager: queue,
        currentUserId: () => signedIn ? 'a' : null,
        interItemDelay: Duration.zero,
        customDispatcher: (_) async => throw const PostgrestException(message: 'new row violates row-level security policy', code: '42501'),
      );
      for (var flip = 0; flip < 5; flip++) {
        await worker.drainQueue();
      }
      final row = await rowOf(id);
      expect(row['status'], 'pending');
      expect(row['retry_count'], 0);
      expect(await queue.getFailedCount(), 0);

      signedIn = true;
      await worker.drainQueue();
      expect((await rowOf(id))['retry_count'], 1, reason: 'a signed-in refusal does count');
    });

    test('an empty user id is signed out', () async {
      await enqueue(owner: 'a');
      var dispatched = 0;
      final worker = SyncWorker(
        queueManager: queue,
        currentUserId: () => '',
        customDispatcher: (_) async {
          dispatched++;
          return const {'status': 'success'};
        },
      );
      await worker.drainQueue();
      expect(dispatched, 0);
    });

    test('the items drain after signing back in', () async {
      final id = await enqueue(owner: 'a');
      String? user;
      final worker = SyncWorker(
        queueManager: queue,
        currentUserId: () => user,
        interItemDelay: Duration.zero,
        customDispatcher: (_) async => const {'status': 'success'},
      );
      expect(await worker.drainQueue(), 0);
      user = 'a';
      expect(await worker.drainQueue(), 1);
      expect(await db.query(OfflineQueueManager.tableName, where: 'id = ?', whereArgs: [id]), isEmpty);
    });

    test('a sign-out during a drain stops the remaining replays', () async {
      await enqueue(owner: 'a', message: 'first');
      final second = await enqueue(owner: 'a', message: 'second');
      String? user = 'a';
      final worker = SyncWorker(
        queueManager: queue,
        currentUserId: () => user,
        interItemDelay: Duration.zero,
        customDispatcher: (_) async {
          user = null;
          return const {'status': 'success'};
        },
      );
      expect(await worker.drainQueue(), 1);
      final row = await rowOf(second);
      expect(row['status'], 'pending');
      expect(row['retry_count'], 0);
    });

    test('an interrupted item is not reset while signed out', () async {
      final id = await enqueue(owner: 'a');
      await queue.markSyncing(id);
      final worker = SyncWorker(queueManager: queue, currentUserId: () => null, customDispatcher: (_) async => const {'status': 'success'});
      await worker.drainQueue();
      expect((await rowOf(id))['status'], 'syncing');
    });
  });

  group('ownerless legacy items wait for the account that signed out (S3)', () {
    test('after claiming, the next account leaves them alone and the owner replays them', () async {
      final id = await enqueue(message: 'legacy');
      final replayedBy = <String>[];
      var user = 'a';
      final worker = SyncWorker(
        queueManager: queue,
        currentUserId: () => user,
        interItemDelay: Duration.zero,
        customDispatcher: (_) async {
          replayedBy.add(user);
          return const {'status': 'success'};
        },
      );
      expect(await worker.claimOwnerlessItems(), 1);

      user = 'b';
      expect(await worker.drainQueue(), 0);
      expect(await worker.unsyncedCount(), 0, reason: 'B is not told about it either');
      expect(replayedBy, isEmpty);
      expect((await rowOf(id))['status'], 'pending');

      user = 'a';
      expect(await worker.drainQueue(), 1);
      expect(replayedBy, ['a']);
    });

    test('claiming keeps the rest of the payload and touches no owned or parked data', () async {
      final legacy = await enqueue(message: 'legacy');
      final mine = await enqueue(owner: 'a', message: 'mine');
      final theirs = await enqueue(owner: 'b', message: 'theirs');
      final parked = await enqueue(message: 'parked');
      await park(parked);
      final theirsBefore = (await rowOf(theirs))['payload'];

      expect(await queue.claimOwnerlessItems('a'), 2);

      expect(jsonDecode((await rowOf(legacy))['payload'] as String), {'message': 'legacy', 'user_id': 'a'});
      expect(jsonDecode((await rowOf(mine))['payload'] as String), {'message': 'mine', 'user_id': 'a'});
      expect((await rowOf(theirs))['payload'], theirsBefore);
      expect((await rowOf(parked))['status'], 'failed');
      expect(jsonDecode((await rowOf(parked))['payload'] as String)['user_id'], 'a');
    });

    test('a payload that does not parse is never overwritten', () async {
      final id = await enqueue(message: 'x');
      await db.update(OfflineQueueManager.tableName, {'payload': 'not json'}, where: 'id = ?', whereArgs: [id]);
      expect(await queue.claimOwnerlessItems('a'), 0);
      expect((await rowOf(id))['payload'], 'not json');
    });

    test('signed out, nothing is claimed', () async {
      final id = await enqueue(message: 'legacy');
      final worker = SyncWorker(queueManager: queue, currentUserId: () => null);
      expect(await worker.claimOwnerlessItems(), 0);
      expect(jsonDecode((await rowOf(id))['payload'] as String).containsKey('user_id'), isFalse);
    });
  });
}
