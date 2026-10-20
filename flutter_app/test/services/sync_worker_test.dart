import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:budget_tracker/services/offline_queue_manager.dart';
import 'package:budget_tracker/services/sync_worker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late OfflineQueueManager queueManager;
  late SyncWorker worker;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await OfflineQueueManager.createSchema(db);
    queueManager = OfflineQueueManager(customDb: db);
  });

  tearDown(() async {
    await db.close();
  });

  group('SyncWorker Tests', () {
    test('Drains queued items successfully and emits flushed count', () async {
      // Enqueue 2 items
      await queueManager.enqueue(
        operationType: 'chat',
        payload: {'message': 'Coffee 15 SAR'},
        householdId: 'h-1',
      );
      await queueManager.enqueue(
        operationType: 'receipt',
        payload: {'qr_code_raw': 'AQJTYW5k...'},
        householdId: 'h-1',
      );

      final dispatched = <String>[];
      worker = SyncWorker(
        queueManager: queueManager,
        customDispatcher: (item) async {
          dispatched.add(item.operationType);
          return {'status': 'success'};
        },
      );

      final flushedFuture = worker.onItemsFlushed.first;
      final count = await worker.drainQueue();

      expect(count, equals(2));
      expect(dispatched, equals(['chat', 'receipt']));
      expect(await flushedFuture, equals(2));

      final remaining = await queueManager.getPendingCount();
      expect(remaining, equals(0));
    });

    test('Handles failure during drain without dropping unrecoverable item prematurely', () async {
      final id = await queueManager.enqueue(
        operationType: 'chat',
        payload: {'message': 'Expense 50'},
        householdId: 'h-1',
      );

      worker = SyncWorker(
        queueManager: queueManager,
        customDispatcher: (item) async {
          throw Exception('Backend unreachable');
        },
      );

      final count = await worker.drainQueue();
      expect(count, equals(0));

      // MOB-09: an unreachable backend is transient; the item stays pending
      // and keeps its full retry budget (retry_count only counts rejections).
      final pending = await queueManager.getPendingItems();
      expect(pending.length, equals(1));
      expect(pending.first.id, equals(id));
      expect(pending.first.retryCount, equals(0));
      expect(pending.first.lastError, contains('Backend unreachable'));
    });

    // FR-A-04: a commit that failed online is queued only when a later replay
    // can succeed; a refusal (400/403/409/422) is shown, not parked offline.
    test('shouldQueueAfterOnlineFailure queues only transient failures', () {
      Map<String, dynamic> err(int? code) => {'status': 'error', if (code != null) 'status_code': code};
      expect(SyncWorker.shouldQueueAfterOnlineFailure(err(null)), isTrue); // offline / timeout
      expect(SyncWorker.shouldQueueAfterOnlineFailure(err(502)), isTrue);
      expect(SyncWorker.shouldQueueAfterOnlineFailure(err(500)), isTrue);
      expect(SyncWorker.shouldQueueAfterOnlineFailure(err(429)), isTrue);
      expect(SyncWorker.shouldQueueAfterOnlineFailure(err(400)), isFalse);
      expect(SyncWorker.shouldQueueAfterOnlineFailure(err(403)), isFalse);
      expect(SyncWorker.shouldQueueAfterOnlineFailure(err(409)), isFalse);
      expect(SyncWorker.shouldQueueAfterOnlineFailure(err(422)), isFalse);
      expect(SyncWorker.shouldQueueAfterOnlineFailure({'status': 'success'}), isFalse);
    });

    // FR-A-09: the backend answers 401 for missing/expired credentials and 403
    // only for "not a member / not allowed", which no retry can fix. Treating
    // that 403 as transient parked it at the head of the FIFO queue forever.
    test('a 403 refusal does not block later items in the queue', () async {
      final blocked = await queueManager.enqueue(
        operationType: 'chat',
        payload: {'message': 'Old household 10 SAR'},
        householdId: 'h-left',
      );
      final later = await queueManager.enqueue(
        operationType: 'chat',
        payload: {'message': 'Coffee 15 SAR'},
        householdId: 'h-1',
      );
      worker = SyncWorker(
        queueManager: queueManager,
        interItemDelay: Duration.zero,
        customDispatcher: (item) async => item.id == blocked
            ? {
                'status': 'error',
                'status_code': 403,
                'message': "Forbidden: You do not have access to this household's data.",
              }
            : {'status': 'success'},
      );

      expect(await worker.drainQueue(), 1);
      final pending = await queueManager.getPendingItems();
      expect(pending.map((i) => i.id), isNot(contains(later)));
      expect(pending.single.id, blocked);
      expect(pending.single.retryCount, 1, reason: 'a refusal uses the retry budget');
    });

    test("the legacy firewall's 403 for an unverifiable token stays transient", () {
      final r = SyncWorker.classifyResponse(
        {'status': 'error', 'status_code': 403, 'message': 'Untrusted endpoint access'},
        'chat',
      );
      expect(r.outcome, ReplayOutcome.transient);
    });

    test("another account's queued items wait for that account", () async {
      final mine = await queueManager.enqueue(
        operationType: 'chat',
        payload: {'message': 'Mine 5 SAR', 'user_id': 'u-me'},
        householdId: 'h-1',
      );
      final theirs = await queueManager.enqueue(
        operationType: 'chat',
        payload: {'message': 'Theirs 7 SAR', 'user_id': 'u-other'},
        householdId: 'h-2',
      );
      final replayed = <String>[];
      worker = SyncWorker(
        queueManager: queueManager,
        interItemDelay: Duration.zero,
        currentUserId: () => 'u-me',
        customDispatcher: (item) async {
          replayed.add(item.id);
          return {'status': 'success'};
        },
      );

      expect(await worker.drainQueue(), 1);
      expect(replayed, [mine]);
      final pending = await queueManager.getPendingItems();
      expect(pending.single.id, theirs);
      expect(pending.single.retryCount, 0);
    });

    test('isPermanentInsertError separates rejections from transport failures', () {
      PostgrestException pg(String? code) => PostgrestException(message: 'x', code: code);
      expect(SyncWorker.isPermanentInsertError(pg('42501')), isTrue); // creator / permission trigger
      expect(SyncWorker.isPermanentInsertError(pg('23514')), isTrue); // nafaqah pair check
      expect(SyncWorker.isPermanentInsertError(pg('PGRST204')), isTrue); // unknown column
      expect(SyncWorker.isPermanentInsertError(pg('23505')), isFalse); // already stored
      expect(SyncWorker.isPermanentInsertError(pg('PGRST301')), isFalse); // expired JWT
      expect(SyncWorker.isPermanentInsertError(pg('503')), isFalse);
      expect(SyncWorker.isPermanentInsertError(pg(null)), isFalse);
      expect(SyncWorker.isPermanentInsertError(Exception('socket')), isFalse);
    });

    test('a queued receipt replays with the key of the online attempt', () async {
      String? sentKey;
      await queueManager.enqueue(
        operationType: 'receipt',
        payload: {'images_base64': ['aGk=']},
        householdId: 'h-1',
        idempotencyKey: 'online-attempt-key',
      );
      worker = SyncWorker(
        queueManager: queueManager,
        interItemDelay: Duration.zero,
        customDispatcher: (item) async {
          sentKey = item.idempotencyKey;
          return {'status': 'success'};
        },
      );
      expect(await worker.drainQueue(), 1);
      expect(sentKey, 'online-attempt-key');
    });
  });
}
