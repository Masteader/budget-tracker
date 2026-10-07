import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:budget_tracker/services/offline_queue_manager.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late OfflineQueueManager queueManager;
  late Database db;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await OfflineQueueManager.createSchema(db);
    queueManager = OfflineQueueManager(customDb: db);
  });

  tearDown(() async {
    await db.close();
  });

  group('OfflineQueueManager Tests', () {
    test('Enqueues item and assigns SHA-256 idempotency key', () async {
      final id = await queueManager.enqueue(
        operationType: 'chat',
        payload: {'message': 'Spent 20 SAR on shawarma'},
        householdId: 'h-1',
      );

      expect(id, isNotNull);
      final count = await queueManager.getPendingCount();
      expect(count, equals(1));

      final items = await queueManager.getPendingItems();
      expect(items.length, equals(1));
      expect(items.first.operationType, equals('chat'));
      expect(items.first.payload['message'], equals('Spent 20 SAR on shawarma'));
      expect(items.first.status, equals('pending'));
      expect(items.first.idempotencyKey, isNotEmpty);
    });

    test('Prevents duplicate enqueue with identical payload and household', () async {
      final id1 = await queueManager.enqueue(
        operationType: 'chat',
        payload: {'message': 'Spent 20 SAR on shawarma'},
        householdId: 'h-1',
      );

      final id2 = await queueManager.enqueue(
        operationType: 'chat',
        payload: {'message': 'Spent 20 SAR on shawarma'},
        householdId: 'h-1',
      );

      // Should return the existing ID and not create a duplicate row
      expect(id1, equals(id2));
      final count = await queueManager.getPendingCount();
      expect(count, equals(1));
    });

    test('Transitions status: syncing -> failed (with retry increment) -> success', () async {
      final id = await queueManager.enqueue(
        operationType: 'receipt',
        payload: {'qr_code_raw': 'Invoice-123'},
        householdId: 'h-1',
      );

      // Mark syncing
      await queueManager.markSyncing(id!);
      var items = await queueManager.getPendingItems();
      expect(items.isEmpty, isTrue); // Only returns 'pending'

      // Mark failed once (transient failure, retries left)
      await queueManager.markFailed(id, error: 'Network timeout', maxRetries: 3);
      items = await queueManager.getPendingItems();
      expect(items.length, equals(1));
      expect(items.first.retryCount, equals(1));
      expect(items.first.status, equals('pending'));
      expect(items.first.lastError, equals('Network timeout'));

      // Mark failed until maxRetries
      await queueManager.markFailed(id, error: 'Network timeout', maxRetries: 2);
      items = await queueManager.getPendingItems();
      expect(items.isEmpty, isTrue); // Now status = 'failed', so not returned in pending

      // Mark success
      await queueManager.markSuccess(id);
      final count = await queueManager.getPendingCount();
      expect(count, equals(0));
    });
  });
}
