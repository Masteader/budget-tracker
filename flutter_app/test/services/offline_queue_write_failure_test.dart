// MOB-28: a failed write to the offline queue must surface as an error, never
// as a silent null that screens turn into "Saved offline".
import 'dart:io';

import 'package:budget_tracker/services/offline_queue_manager.dart';
import 'package:budget_tracker/services/offline_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  Future<Database> openQueueDb() async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await OfflineQueueManager.createSchema(db);
    return db;
  }

  test('enqueueOrThrow throws when SQLite rejects the write', () async {
    final db = await openQueueDb();
    await db.close(); // every statement on a closed database fails
    final queue = OfflineQueueManager(customDb: db);

    expect(await queue.enqueue(operationType: 'chat', payload: {'message': 'x'}, householdId: 'h-1'), isNull,
        reason: 'legacy API still returns null');
    await expectLater(
      queue.enqueueOrThrow(operationType: 'chat', payload: {'message': 'x'}, householdId: 'h-1'),
      throwsA(isA<OfflineQueueWriteException>()),
    );
  });

  test('enqueueOrThrow throws when the receipt image blob cannot be written', () async {
    final db = await openQueueDb();
    final tmp = await Directory.systemTemp.createTemp('mob28');
    addTearDown(() => tmp.delete(recursive: true));
    final blocker = File('${tmp.path}/not_a_dir');
    await blocker.writeAsString('file in the way');
    final queue = OfflineQueueManager(customDb: db, blobDirectoryProvider: () async => Directory(blocker.path));

    await expectLater(
      queue.enqueueOrThrow(
        operationType: 'receipt',
        payload: {OfflineQueueManager.inlineImagesKey: ['aGVsbG8=']},
        householdId: 'h-1',
      ),
      throwsA(isA<OfflineQueueWriteException>()),
    );
    expect(await queue.getPendingCount(), 0);
    await db.close();
  });

  test('OfflineSyncService.enqueue returns the id on success', () async {
    final db = await openQueueDb();
    final service = OfflineSyncService.withQueue(OfflineQueueManager(customDb: db));

    final id = await service.enqueue(endpoint: 'chat', payload: {'message': 'Coffee 15'}, householdId: 'h-1');

    expect(id, isNotEmpty);
    expect(service.pendingCountNotifier.value, 1);
    await db.close();
  });

  test('OfflineSyncService.enqueue throws instead of returning null on failure', () async {
    final db = await openQueueDb();
    await db.close();
    final service = OfflineSyncService.withQueue(OfflineQueueManager(customDb: db));

    await expectLater(
      service.enqueue(endpoint: 'chat', payload: {'message': 'Coffee 15'}, householdId: 'h-1'),
      throwsA(isA<OfflineQueueWriteException>()),
    );
  });

  group('screens only report "saved offline" after a successful queue write', () {
    String read(String path) => File(path).readAsStringSync();

    test('chat awaits the queue write before replying', () {
      final src = read('lib/screens/chat/chat_entry_screen.dart');
      final enqueue = src.indexOf('OfflineSyncService.instance.enqueue');
      expect(src.substring(enqueue - 20, enqueue), contains('await'));
      expect(src.indexOf("context.tr('chat_offline_queued')"), greaterThan(enqueue));
      expect(src, contains("context.tr('offline_queue_failed')"));
    });

    test('receipt scanners use the throwing queue API', () {
      expect(read('lib/screens/scanner/receipt_scanner_sheet.dart'), isNot(contains('OfflineQueueManager().enqueue(')));
      expect(read('lib/widgets/scanner/batch_item_review_sheet.dart'), isNot(contains('OfflineQueueManager().enqueue(')));
      expect(read('lib/widgets/scanner/batch_item_review_sheet.dart'), isNot(contains('count as saved')));
    });
  });
}
