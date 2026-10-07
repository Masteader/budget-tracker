import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:budget_tracker/services/offline_queue_manager.dart';
import 'package:budget_tracker/services/sync_worker.dart';

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

      // Item should still be in queue with retry_count = 1
      final pending = await queueManager.getPendingItems();
      expect(pending.length, equals(1));
      expect(pending.first.id, equals(id));
      expect(pending.first.retryCount, equals(1));
      expect(pending.first.lastError, contains('Backend unreachable'));
    });
  });
}
