import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/offline_queue_item.dart';

/// Resolves the directory used to store large offline payload blobs
/// (receipt images) outside of the SQLite row.
typedef BlobDirectoryProvider = Future<Directory> Function();

/// SQLite Database manager for queued offline transactions.
///
/// Invariants:
/// * Every enqueue creates a new row unless the caller passes an explicit
///   [idempotencyKey] that is already queued (double-submit protection).
/// * Receipt images are written to files under the blob directory and only
///   their file names are stored in the row, so a multi-page receipt can never
///   exceed Android's ~2 MB CursorWindow and wedge the whole queue.
/// * Rows are read one at a time, so a single unreadable legacy row is
///   quarantined as `failed` instead of blocking every other queued expense.
class OfflineQueueManager {
  static const String tableName = 'offline_sync_queue';
  static const int databaseVersion = 2;

  /// Payload key holding inline base64 images supplied by callers.
  static const String inlineImagesKey = 'images_base64';

  /// Payload key holding the blob file names that replaced [inlineImagesKey].
  static const String imageBlobsKey = 'image_blob_files';

  Database? _db;
  final Database? customDb;
  final BlobDirectoryProvider? _blobDirectoryProvider;

  OfflineQueueManager({this.customDb, BlobDirectoryProvider? blobDirectoryProvider})
      : _db = customDb,
        _blobDirectoryProvider = blobDirectoryProvider;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  Future<Directory> _blobDirectory() async {
    final dir = _blobDirectoryProvider != null
        ? await _blobDirectoryProvider()
        : Directory(p.join(await getDatabasesPath(), 'offline_blobs'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'budget_tracker_offline.db');

    return await openDatabase(
      path,
      version: databaseVersion,
      onCreate: (db, version) async {
        await createSchema(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await createSchema(db);
          // Migrate legacy v1 table if exists
          try {
            final oldRows = await db.query('offline_tx_queue');
            for (final r in oldRows) {
              final payloadStr = r['payload'] as String? ?? '{}';
              final hid = r['household_id'] as String? ?? '';
              final endpoint = r['endpoint'] as String? ?? 'receipt';
              final id = const Uuid().v4();
              final idempotencyKey = OfflineQueueItem.generateIdempotencyKey(
                operationType: endpoint,
                householdId: hid,
                payload: {'raw': payloadStr},
                nonce: id,
              );
              await db.insert(tableName, {
                'id': id,
                'operation_type': endpoint,
                'payload': payloadStr,
                'household_id': hid,
                'idempotency_key': idempotencyKey,
                'status': 'pending',
                'retry_count': 0,
                'created_at': r['created_at'] ?? DateTime.now().toUtc().toIso8601String(),
                'last_error': null,
              });
            }
            await db.execute('DROP TABLE IF EXISTS offline_tx_queue');
          } catch (e) {
            debugPrint('[OfflineQueueManager] Migration notice: $e');
          }
        }
      },
    );
  }

  static Future<void> createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableName (
        id TEXT PRIMARY KEY,
        operation_type TEXT NOT NULL,
        payload TEXT NOT NULL,
        household_id TEXT NOT NULL,
        idempotency_key TEXT UNIQUE,
        status TEXT NOT NULL,
        retry_count INTEGER DEFAULT 0,
        created_at TEXT NOT NULL,
        last_error TEXT
      );
    ''');
  }

  /// Enqueues an operation.
  ///
  /// Each call creates a new queue row, because two identical offline expenses
  /// are two real purchases. Pass a stable [idempotencyKey] (e.g. a UUID minted
  /// when the user opened the form) to make repeated submissions of the same
  /// user action collapse into one row; in that case the existing row's ID is
  /// returned whatever its status.
  Future<String?> enqueue({
    required String operationType,
    required Map<String, dynamic> payload,
    required String householdId,
    String? customId,
    String? idempotencyKey,
  }) async {
    try {
      final db = await database;
      final itemId = customId ?? const Uuid().v4();
      final key = idempotencyKey ??
          OfflineQueueItem.generateIdempotencyKey(
            operationType: operationType,
            householdId: householdId,
            payload: payload,
            nonce: itemId,
          );

      final existing = await db.query(
        tableName,
        columns: ['id'],
        where: 'idempotency_key = ?',
        whereArgs: [key],
      );
      if (existing.isNotEmpty) {
        debugPrint('[OfflineQueueManager] Deduplicated repeated submission of one user action.');
        return existing.first['id'] as String;
      }

      final storedPayload = await _offloadImages(itemId, payload);

      final item = OfflineQueueItem(
        id: itemId,
        operationType: operationType,
        payload: storedPayload,
        householdId: householdId,
        idempotencyKey: key,
        status: 'pending',
        retryCount: 0,
        createdAt: DateTime.now().toUtc(),
      );

      await db.insert(
        tableName,
        item.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      return itemId;
    } catch (e) {
      debugPrint('[OfflineQueueManager] Error enqueuing: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>> _offloadImages(String itemId, Map<String, dynamic> payload) async {
    final images = payload[inlineImagesKey];
    if (images is! List || images.isEmpty) return payload;

    final dir = await _blobDirectory();
    final names = <String>[];
    for (var i = 0; i < images.length; i++) {
      final name = '${itemId}_$i.b64';
      await File(p.join(dir.path, name)).writeAsString(images[i].toString(), flush: true);
      names.add(name);
    }
    final stored = Map<String, dynamic>.from(payload)..remove(inlineImagesKey);
    stored[imageBlobsKey] = names;
    return stored;
  }

  /// Returns the base64 images attached to [item], reading offloaded blob
  /// files and falling back to images stored inline by older app versions.
  Future<List<String>> loadImages(OfflineQueueItem item) async {
    final names = item.payload[imageBlobsKey];
    if (names is List && names.isNotEmpty) {
      final dir = await _blobDirectory();
      final result = <String>[];
      for (final name in names) {
        final file = File(p.join(dir.path, p.basename(name.toString())));
        if (await file.exists()) {
          result.add(await file.readAsString());
        }
      }
      return result;
    }
    final inline = item.payload[inlineImagesKey];
    if (inline is List) {
      return inline.map((e) => e.toString()).toList();
    }
    return const [];
  }

  Future<void> _deleteBlobs(String id) async {
    try {
      final dir = await _blobDirectory();
      await for (final entity in dir.list()) {
        if (entity is File && p.basename(entity.path).startsWith('${id}_')) {
          await entity.delete();
        }
      }
    } catch (e) {
      debugPrint('[OfflineQueueManager] Blob cleanup notice: $e');
    }
  }

  /// Returns operations pending sync, oldest first.
  ///
  /// IDs are listed first and each row is then loaded on its own, so one
  /// oversized or corrupt row is quarantined (`failed`) instead of throwing
  /// for the whole batch. Rows whose IDs are in [excludeIds] are skipped.
  Future<List<OfflineQueueItem>> getPendingItems({
    int limit = 50,
    Set<String> excludeIds = const {},
  }) async {
    final db = await database;
    final idRows = await db.query(
      tableName,
      columns: ['id'],
      where: 'status = ?',
      whereArgs: ['pending'],
      orderBy: 'created_at ASC, rowid ASC',
    );

    final items = <OfflineQueueItem>[];
    for (final row in idRows) {
      if (items.length >= limit) break;
      final id = row['id'] as String;
      if (excludeIds.contains(id)) continue;
      try {
        final rows = await db.query(tableName, where: 'id = ?', whereArgs: [id]);
        if (rows.isNotEmpty) items.add(OfflineQueueItem.fromMap(rows.first));
      } catch (e) {
        debugPrint('[OfflineQueueManager] Quarantining unreadable queue row: $e');
        await db.update(
          tableName,
          {'status': 'failed', 'last_error': 'Unreadable queue row: $e'},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    }
    return items;
  }

  /// Marks an item as currently transmitting over the network.
  Future<void> markSyncing(String id) async {
    final db = await database;
    await db.update(
      tableName,
      {'status': 'syncing'},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Returns rows left in `syncing` by a drain that never finished (the app
  /// was killed mid-request) to `pending` so they are replayed. Must only be
  /// called while no drain is running in this process.
  Future<int> recoverInterruptedItems() async {
    final db = await database;
    return db.update(
      tableName,
      {'status': 'pending'},
      where: 'status = ?',
      whereArgs: ['syncing'],
    );
  }

  /// Removes an item (and its image blobs) from the queue after successful upload.
  Future<void> markSuccess(String id) async {
    final db = await database;
    await db.delete(tableName, where: 'id = ?', whereArgs: [id]);
    await _deleteBlobs(id);
  }

  /// Records a failure.
  ///
  /// A [transient] failure (no network, timeout, 5xx gateway, auth refresh
  /// pending) returns the item to `pending` without consuming its retry
  /// budget. A permanent failure increments `retry_count`; once it reaches
  /// [maxRetries] the item is parked as `failed` (poison message).
  Future<void> markFailed(
    String id, {
    required String error,
    int maxRetries = 5,
    bool transient = false,
  }) async {
    final db = await database;
    final rows = await db.query(
      tableName,
      columns: ['retry_count'],
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isEmpty) return;

    final currentRetries = (rows.first['retry_count'] as num?)?.toInt() ?? 0;
    final newRetries = transient ? currentRetries : currentRetries + 1;
    final newStatus = !transient && newRetries >= maxRetries ? 'failed' : 'pending';

    await db.update(
      tableName,
      {
        'status': newStatus,
        'retry_count': newRetries,
        'last_error': error,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Returns the count of items waiting or syncing.
  Future<int> getPendingCount() async {
    final db = await database;
    final count = Sqflite.firstIntValue(
      await db.rawQuery(
        "SELECT COUNT(*) FROM $tableName WHERE status IN ('pending', 'syncing')",
      ),
    );
    return count ?? 0;
  }

  /// Returns the count of poison items parked as `failed`.
  Future<int> getFailedCount() async {
    final db = await database;
    final count = Sqflite.firstIntValue(
      await db.rawQuery("SELECT COUNT(*) FROM $tableName WHERE status = 'failed'"),
    );
    return count ?? 0;
  }

  /// Moves every parked `failed` item back to `pending` with a fresh retry
  /// budget (explicit user-initiated retry).
  Future<int> requeueFailed() async {
    final db = await database;
    return db.update(
      tableName,
      {'status': 'pending', 'retry_count': 0},
      where: 'status = ?',
      whereArgs: ['failed'],
    );
  }

  /// Clears all entries (and image blobs) from the queue.
  Future<void> clearQueue() async {
    final db = await database;
    final ids = await db.query(tableName, columns: ['id']);
    await db.delete(tableName);
    for (final row in ids) {
      await _deleteBlobs(row['id'] as String);
    }
  }
}
