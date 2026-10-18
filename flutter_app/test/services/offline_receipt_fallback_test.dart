import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:budget_tracker/services/offline_queue_manager.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  late OfflineQueueManager queueManager;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    queueManager = OfflineQueueManager(customDb: db);
    await OfflineQueueManager.createSchema(db);
  });

  tearDown(() async => await db.close());

  test('enqueues offline receipt draft with pending cloud enrichment tag', () async {
    final item = await queueManager.enqueue(
      operationType: 'receipt_offline_draft',
      householdId: 'hh-123',
      payload: {
        'merchant': 'Al Othaim Supermarket',
        'amount': 150.0,
        'vat_amount': 22.5,
        'image_path': '/mock/receipt.jpg',
        'needs_cloud_enrichment': true,
      },
    );

    expect(item, isNotNull);
    final pending = await queueManager.getPendingItems();
    expect(pending.length, 1);
    expect(pending.first.operationType, 'receipt_offline_draft');
    expect(pending.first.payload['needs_cloud_enrichment'], true);
    expect(pending.first.payload['merchant'], 'Al Othaim Supermarket');
  });
}
