import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import 'package:budget_tracker/services/api/base_api_client.dart';
import 'package:budget_tracker/services/api_service.dart';
import 'package:budget_tracker/services/offline_queue_manager.dart';
import 'package:budget_tracker/services/sync_worker.dart';

/// Records every backend request made through a real [ApiService] stack.
class _Backend {
  final requests = <http.Request>[];
  final List<http.Response Function(http.Request)> script;
  _Backend(this.script);

  late final ApiService api = ApiService(
    base: BaseApiClient(
      client: MockClient((request) async {
        requests.add(request);
        final i = requests.length - 1;
        final responder = i < script.length ? script[i] : script.last;
        return responder(request);
      }),
      authTokenProvider: () => 'jwt',
    ),
  );

  Map<String, dynamic> body(int i) => jsonDecode(requests[i].body) as Map<String, dynamic>;
}

http.Response _json(Map<String, dynamic> body, [int code = 200]) => http.Response(jsonEncode(body), code);

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late Directory blobDir;
  late OfflineQueueManager queue;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await OfflineQueueManager.createSchema(db);
    blobDir = await Directory.systemTemp.createTemp('offline_blobs_test');
    queue = OfflineQueueManager(customDb: db, blobDirectoryProvider: () async => blobDir);
  });

  tearDown(() async {
    await db.close();
    if (await blobDir.exists()) await blobDir.delete(recursive: true);
  });

  SyncWorker worker(_Backend backend, {TransactionInserter? inserter}) => SyncWorker(
        queueManager: queue,
        api: backend.api,
        transactionInserter: inserter,
        interItemDelay: Duration.zero,
      );

  group('MOB-01 offline chat replay must commit, not preview', () {
    test('replay sends preview_only=false and deletes the row only after a committed success', () async {
      await queue.enqueue(operationType: 'chat', payload: {'message': 'Coffee 15 SAR'}, householdId: 'h-1');
      final backend = _Backend([(_) => _json({'status': 'success', 'transaction_id': 't-1'})]);

      final committed = await worker(backend).drainQueue();

      expect(committed, 1);
      expect(backend.body(0)['preview_only'], isFalse);
      expect(backend.body(0)['allow_duplicate'], isTrue);
      expect(await queue.getPendingCount(), 0);
    });

    test('a pending_confirmation answer is NOT treated as synced', () async {
      await queue.enqueue(operationType: 'chat', payload: {'message': 'Coffee 15 SAR'}, householdId: 'h-1');
      final backend = _Backend([(_) => _json({'status': 'pending_confirmation', 'amount': 15})]);

      final committed = await worker(backend).drainQueue();

      expect(committed, 0);
      final pending = await queue.getPendingItems();
      expect(pending, hasLength(1));
      expect(pending.single.retryCount, 1);
    });

    test('the local offline "preview" parse is a network failure, never a success', () {
      final result = SyncWorker.classifyResponse({'status': 'preview', 'amount': 15.0}, 'chat');
      expect(result.outcome, ReplayOutcome.transient);
    });
  });

  group('MOB-03 manual expense attribution survives offline replay', () {
    test('transaction_insert replays the exact row with client id and original timestamp', () async {
      final inserted = <Map<String, dynamic>>[];
      final id = await queue.enqueue(
        operationType: kTransactionInsertOperation,
        householdId: 'h-1',
        payload: {
          'amount': 87.5,
          'merchant': 'Tamimi',
          'category_code': 'OPEX-GROCERY',
          'spent_by': 'partner',
          'paid_by': 'wife',
          'beneficiary_type': 'household',
          'beneficiary_id': 'household',
          'timestamp': '2026-10-26T20:30:00.000Z',
        },
      );

      final committed = await worker(_Backend([(_) => _json({})]), inserter: (row) async => inserted.add(row)).drainQueue();

      expect(committed, 1);
      expect(inserted.single['paid_by'], 'wife');
      expect(inserted.single['beneficiary_type'], 'household');
      expect(inserted.single['household_id'], 'h-1');
      expect(inserted.single['id'], id);
      expect(inserted.single['timestamp'], '2026-10-26T20:30:00.000Z');
    });

    test('a unique violation on replay means the earlier attempt already committed', () async {
      await queue.enqueue(operationType: kTransactionInsertOperation, householdId: 'h-1', payload: {'amount': 10});

      final committed = await worker(
        _Backend([(_) => _json({})]),
        inserter: (row) async => throw const PostgrestException(message: 'duplicate key', code: '23505'),
      ).drainQueue();

      expect(committed, 1);
      expect(await queue.getPendingCount(), 0);
    });

    test('legacy chat rows forward spent_by / paid_by / category overrides', () async {
      await queue.enqueue(
        operationType: 'chat',
        householdId: 'h-1',
        payload: {
          'message': 'Tamimi SAR 87.50 in OPEX-GROCERY',
          'spent_by': 'partner',
          'paid_by': 'wife',
          'category_code': 'OPEX-GROCERY',
        },
      );
      final backend = _Backend([(_) => _json({'status': 'success'})]);

      await worker(backend).drainQueue();

      expect(backend.body(0)['spent_by'], 'partner');
      expect(backend.body(0)['paid_by'], 'partner');
      expect(backend.body(0)['category_code'], 'OPEX-GROCERY');
    });
  });

  group('MOB-04 rows orphaned in syncing by an app kill are replayed', () {
    test('drain recovers syncing rows left by a killed process', () async {
      final id = await queue.enqueue(operationType: 'chat', payload: {'message': 'Fuel 90'}, householdId: 'h-1');
      await queue.markSyncing(id!); // process killed here, before markSuccess/markFailed
      final backend = _Backend([(_) => _json({'status': 'success'})]);

      final committed = await worker(backend).drainQueue();

      expect(committed, 1);
      expect(backend.requests, hasLength(1));
      expect(await queue.getPendingCount(), 0);
    });
  });

  group('MOB-05 identical offline expenses are not silently merged', () {
    test('two identical purchases produce two queue rows', () async {
      final a = await queue.enqueue(operationType: 'chat', payload: {'message': 'Coffee 15'}, householdId: 'h-1');
      final b = await queue.enqueue(operationType: 'chat', payload: {'message': 'Coffee 15'}, householdId: 'h-1');

      expect(a, isNot(equals(b)));
      expect(await queue.getPendingCount(), 2);
    });

    test('an explicit idempotency key still collapses a double-submit of one action', () async {
      final a = await queue.enqueue(
          operationType: 'chat', payload: {'message': 'Coffee 15'}, householdId: 'h-1', idempotencyKey: 'form-1');
      final b = await queue.enqueue(
          operationType: 'chat', payload: {'message': 'Coffee 15'}, householdId: 'h-1', idempotencyKey: 'form-1');

      expect(a, equals(b));
      expect(await queue.getPendingCount(), 1);
    });
  });

  group('MOB-06 replay carries a stable idempotency key', () {
    test('a retried replay after a timeout reuses the same Idempotency-Key', () async {
      await queue.enqueue(operationType: 'chat', payload: {'message': 'Shawarma 22'}, householdId: 'h-1');
      final backend = _Backend([
        (_) => throw TimeoutException('server slow'),
        (_) => _json({'status': 'success'}),
      ]);
      final w = worker(backend);

      expect(await w.drainQueue(), 0);
      expect(await w.drainQueue(), 1);

      final k1 = backend.requests[0].headers['Idempotency-Key'];
      final k2 = backend.requests[1].headers['Idempotency-Key'];
      expect(k1, isNotNull);
      expect(k1, equals(k2));
    });
  });

  group('MOB-09 retry classification, poison messages and FIFO', () {
    test('network failures never exhaust the retry budget', () async {
      await queue.enqueue(operationType: 'chat', payload: {'message': 'Water 5'}, householdId: 'h-1');
      final backend = _Backend([(_) => throw const SocketException('Failed host lookup')]);
      final w = worker(backend);

      for (var i = 0; i < 8; i++) {
        await w.drainQueue();
      }

      final pending = await queue.getPendingItems();
      expect(pending, hasLength(1));
      expect(pending.single.retryCount, 0);
      expect(pending.single.lastError, contains('Failed host lookup'));
      expect(await queue.getFailedCount(), 0);
    });

    test('a transient failure halts the drain so later items do not overtake it', () async {
      await queue.enqueue(operationType: 'chat', payload: {'message': 'first'}, householdId: 'h-1');
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await queue.enqueue(operationType: 'chat', payload: {'message': 'second'}, householdId: 'h-1');
      final backend = _Backend([(_) => _json({'detail': 'Bad gateway'}, 503)]);

      await worker(backend).drainQueue();

      expect(backend.requests, hasLength(1));
      expect(backend.body(0)['message'], 'first');
      expect(await queue.getPendingCount(), 2);
    });

    test('a permanently rejected item is parked as failed after maxRetries and stops blocking', () async {
      await queue.enqueue(operationType: 'chat', payload: {'message': 'bad'}, householdId: 'h-1');
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await queue.enqueue(operationType: 'chat', payload: {'message': 'good'}, householdId: 'h-1');
      final backend = _Backend([
        (r) => (jsonDecode(r.body) as Map)['message'] == 'bad'
            ? _json({'detail': 'message and household_id are required.'}, 400)
            : _json({'status': 'success'}),
      ]);
      final w = SyncWorker(queueManager: queue, api: backend.api, maxPermanentRetries: 2, interItemDelay: Duration.zero);

      expect(await w.drainQueue(), 1); // good one commits, bad one burns 1/2
      expect(await w.drainQueue(), 0); // bad one burns 2/2 -> failed
      expect(await queue.getPendingCount(), 0);
      expect(await queue.getFailedCount(), 1);

      await queue.requeueFailed();
      expect(await queue.getPendingCount(), 1);
    });

    test('401 after a failed refresh keeps the item pending without burning retries', () {
      final r = SyncWorker.classifyResponse({'status': 'error', 'status_code': 401}, 'chat');
      expect(r.outcome, ReplayOutcome.transient);
    });
  });

  group('MOB-10 concurrent drains and large queues', () {
    test('a concurrent flush awaits the in-flight drain instead of returning 0', () async {
      await queue.enqueue(operationType: 'chat', payload: {'message': 'a'}, householdId: 'h-1');
      final gate = Completer<void>();
      final backend = _Backend([(_) => _json({'status': 'success'})]);
      final w = SyncWorker(
        queueManager: queue,
        interItemDelay: Duration.zero,
        customDispatcher: (item) async {
          await gate.future;
          return backend.api.postChatTransaction(message: 'a', householdId: 'h-1', previewOnly: false);
        },
      );

      final first = w.drainQueue();
      final second = w.drainQueue();
      gate.complete();

      expect(await first, 1);
      expect(await second, 1);
      expect(backend.requests, hasLength(1));
    });

    test('more than one batch (50) is drained in a single pass', () async {
      for (var i = 0; i < 60; i++) {
        await queue.enqueue(operationType: 'chat', payload: {'message': 'item $i'}, householdId: 'h-1');
      }
      final backend = _Backend([(_) => _json({'status': 'success'})]);

      expect(await worker(backend).drainQueue(), 60);
      expect(await queue.getPendingCount(), 0);
    });
  });

  group('MOB-11 receipt images are stored out of the SQLite row', () {
    test('images are offloaded to blob files, replayed, then deleted', () async {
      final big = base64Encode(List<int>.filled(3 * 1024 * 1024, 7)); // ~4 MB string
      final id = await queue.enqueue(
        operationType: 'receipt',
        householdId: 'h-1',
        payload: {'images_base64': [big], 'user_id': 'u-1'},
      );

      final raw = await db.query(OfflineQueueManager.tableName, where: 'id = ?', whereArgs: [id]);
      expect((raw.single['payload'] as String).length, lessThan(1024));
      expect(blobDir.listSync(), hasLength(1));

      final backend = _Backend([(_) => _json({'status': 'success'})]);
      expect(await worker(backend).drainQueue(), 1);
      expect((backend.body(0)['images_base64'] as List).single, equals(big));
      expect(blobDir.listSync(), isEmpty);
    });

    test('an unreadable row is quarantined instead of blocking the queue', () async {
      await db.insert(OfflineQueueManager.tableName, {
        'id': 'corrupt',
        'operation_type': 'chat',
        'payload': '{}',
        'household_id': 'h-1',
        'idempotency_key': 'k-corrupt',
        'status': 'pending',
        'retry_count': 'not-a-number',
        'created_at': '2026-01-01T00:00:00.000Z',
      });
      await queue.enqueue(operationType: 'chat', payload: {'message': 'ok'}, householdId: 'h-1');
      final backend = _Backend([(_) => _json({'status': 'success'})]);

      final committed = await worker(backend).drainQueue();

      expect(committed, 1);
      expect(await queue.getFailedCount(), 1);
    });
  });

  group('MOB-12 replay reports when the expense really happened', () {
    test('client_occurred_at carries the enqueue time, not the replay time', () async {
      await queue.enqueue(operationType: 'chat', payload: {'message': 'Dinner 120'}, householdId: 'h-1');
      final item = (await queue.getPendingItems()).single;
      final backend = _Backend([(_) => _json({'status': 'success'})]);

      await worker(backend).drainQueue();

      expect(backend.body(0)['client_occurred_at'], item.createdAt.toUtc().toIso8601String());
    });
  });
}
