import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/offline_queue_item.dart';

/// SQLite Database manager for queued offline transactions.
class OfflineQueueManager {
  static const String tableName = 'offline_sync_queue';
  static const int databaseVersion = 2;

  Database? _db;
  final Database? customDb;

  OfflineQueueManager({this.customDb}) : _db = customDb;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDatabase();
    return _db!;
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

  /// Enqueues an operation idempotently. If an operation with identical idempotencyKey
  /// is already pending or syncing, returns the existing ID without creating a duplicate.
  Future<String?> enqueue({
    required String operationType,
    required Map<String, dynamic> payload,
    required String householdId,
    String? customId,
  }) async {
    try {
      final db = await database;
      final idempotencyKey = OfflineQueueItem.generateIdempotencyKey(
        operationType: operationType,
        householdId: householdId,
        payload: payload,
      );

      // Check for existing pending or syncing item with the same idempotency key
      final existing = await db.query(
        tableName,
        columns: ['id'],
        where: 'idempotency_key = ? AND status IN (?, ?)',
        whereArgs: [idempotencyKey, 'pending', 'syncing'],
      );

      if (existing.isNotEmpty) {
        debugPrint('[OfflineQueueManager] Deduplicated operation $idempotencyKey');
        return existing.first['id'] as String;
      }

      final itemId = customId ?? const Uuid().v4();
      final item = OfflineQueueItem(
        id: itemId,
        operationType: operationType,
        payload: payload,
        householdId: householdId,
        idempotencyKey: idempotencyKey,
        status: 'pending',
        retryCount: 0,
        createdAt: DateTime.now().toUtc(),
      );

      await db.insert(
        tableName,
        item.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      return itemId;
    } catch (e) {
      debugPrint('[OfflineQueueManager] Error enqueuing: $e');
      return null;
    }
  }

  /// Returns all operations pending sync, ordered chronologically.
  Future<List<OfflineQueueItem>> getPendingItems({int limit = 50}) async {
    final db = await database;
    final rows = await db.query(
      tableName,
      where: 'status = ?',
      whereArgs: ['pending'],
      orderBy: 'created_at ASC',
      limit: limit,
    );

    return rows.map(OfflineQueueItem.fromMap).toList();
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

  /// Removes an item from the queue after successful upload.
  Future<void> markSuccess(String id) async {
    final db = await database;
    await db.delete(tableName, where: 'id = ?', whereArgs: [id]);
  }

  /// Records a failure. If retry_count reaches maxRetries, status becomes 'failed'.
  /// Otherwise resets status to 'pending' for subsequent retry attempts.
  Future<void> markFailed(String id, {required String error, int maxRetries = 5}) async {
    final db = await database;
    final rows = await db.query(tableName, where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return;

    final currentRetries = (rows.first['retry_count'] as num?)?.toInt() ?? 0;
    final newRetries = currentRetries + 1;
    final newStatus = newRetries >= maxRetries ? 'failed' : 'pending';

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

  /// Clears all entries from the queue (useful in tests).
  Future<void> clearQueue() async {
    final db = await database;
    await db.delete(tableName);
  }
}
