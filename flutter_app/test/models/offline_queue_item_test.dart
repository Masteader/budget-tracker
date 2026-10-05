import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/models/offline_queue_item.dart';

void main() {
  group('OfflineQueueItem Tests', () {
    test('Calculates deterministic SHA-256 idempotency key', () {
      final key1 = OfflineQueueItem.generateIdempotencyKey(
        operationType: 'sms',
        householdId: 'house-123',
        payload: {'raw_sms': 'Purchased 150 SAR at Tamimi', 'sender': 'AlRajhiBank'},
      );
      final key2 = OfflineQueueItem.generateIdempotencyKey(
        operationType: 'sms',
        householdId: 'house-123',
        payload: {'raw_sms': 'Purchased 150 SAR at Tamimi', 'sender': 'AlRajhiBank'},
      );
      final keyDiff = OfflineQueueItem.generateIdempotencyKey(
        operationType: 'sms',
        householdId: 'house-123',
        payload: {'raw_sms': 'Purchased 200 SAR at Tamimi', 'sender': 'AlRajhiBank'},
      );

      expect(key1, isNotEmpty);
      expect(key1, equals(key2));
      expect(key1, isNot(equals(keyDiff)));
      expect(key1.length, equals(64)); // SHA-256 hex string
    });

    test('Serializes to map and deserializes correctly', () {
      final now = DateTime.now();
      final item = OfflineQueueItem(
        id: 'test-uuid-1',
        operationType: 'chat',
        payload: {'message': 'Spent 45 on coffee', 'spent_by': 'Fahad'},
        householdId: 'house-99',
        idempotencyKey: 'hash-abc',
        status: 'pending',
        retryCount: 0,
        createdAt: now,
        lastError: null,
      );

      final map = item.toMap();
      final reconstituted = OfflineQueueItem.fromMap(map);

      expect(reconstituted.id, equals('test-uuid-1'));
      expect(reconstituted.operationType, equals('chat'));
      expect(reconstituted.payload['message'], equals('Spent 45 on coffee'));
      expect(reconstituted.payload['spent_by'], equals('Fahad'));
      expect(reconstituted.householdId, equals('house-99'));
      expect(reconstituted.idempotencyKey, equals('hash-abc'));
      expect(reconstituted.status, equals('pending'));
      expect(reconstituted.retryCount, equals(0));
      expect(reconstituted.lastError, isNull);
    });

    test('copyWith updates state correctly', () {
      final item = OfflineQueueItem(
        id: 'test-uuid-2',
        operationType: 'receipt',
        payload: {'images': ['base64']},
        householdId: 'house-99',
        idempotencyKey: 'hash-123',
        status: 'pending',
        retryCount: 0,
        createdAt: DateTime.now(),
      );

      final syncingItem = item.copyWith(status: 'syncing');
      expect(syncingItem.status, equals('syncing'));
      expect(syncingItem.retryCount, equals(0));

      final failedItem = item.copyWith(
        status: 'failed',
        retryCount: 1,
        lastError: 'HTTP 500 Server error',
      );
      expect(failedItem.status, equals('failed'));
      expect(failedItem.retryCount, equals(1));
      expect(failedItem.lastError, equals('HTTP 500 Server error'));
    });
  });
}
