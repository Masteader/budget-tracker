/// Offline-First SQLite Queue (`OfflineSyncService`).
/// Stores offline chat transactions, manual expenses, and receipt scans in local SQLite.
/// Automatically drains and synchronizes with FastAPI / Supabase when connectivity returns.
library;

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'api_service.dart';

class OfflineSyncService {
  OfflineSyncService._();
  static final OfflineSyncService instance = OfflineSyncService._();

  Database? _db;
  final ValueNotifier<int> pendingCountNotifier = ValueNotifier<int>(0);
  final StreamController<int> _flushedController = StreamController<int>.broadcast();
  Stream<int> get onItemsFlushed => _flushedController.stream;

  bool _isFlushing = false;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'budget_tracker_offline.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS offline_tx_queue (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            endpoint TEXT NOT NULL,
            payload TEXT NOT NULL,
            household_id TEXT NOT NULL,
            created_at TEXT NOT NULL,
            status TEXT DEFAULT 'pending'
          );
        ''');
      },
    );
  }

  /// Add a failed or offline transaction payload to the local queue.
  Future<int> enqueue({
    required String endpoint,
    required Map<String, dynamic> payload,
    required String householdId,
  }) async {
    try {
      final db = await database;
      final id = await db.insert('offline_tx_queue', {
        'endpoint': endpoint,
        'payload': jsonEncode(payload),
        'household_id': householdId,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'status': 'pending',
      });
      await updatePendingCount();
      debugPrint('[OfflineSyncService] Enqueued item #$id for $endpoint');
      return id;
    } catch (e) {
      debugPrint('[OfflineSyncService] Error enqueuing item: $e');
      return -1;
    }
  }

  /// Update the reactive counter of pending offline items.
  Future<int> updatePendingCount() async {
    try {
      final db = await database;
      final count = Sqflite.firstIntValue(
        await db.rawQuery("SELECT COUNT(*) FROM offline_tx_queue WHERE status = 'pending'"),
      ) ?? 0;
      pendingCountNotifier.value = count;
      return count;
    } catch (_) {
      return 0;
    }
  }

  /// Flushes all pending transactions to the backend when connectivity is restored.
  Future<int> flushQueue() async {
    if (_isFlushing) return 0;
    _isFlushing = true;

    int successCount = 0;
    try {
      final db = await database;
      final items = await db.query(
        'offline_tx_queue',
        where: "status = 'pending'",
        orderBy: 'id ASC',
      );

      for (final row in items) {
        final id = row['id'] as int;
        final endpoint = row['endpoint'] as String;
        final householdId = row['household_id'] as String;
        final payload = jsonDecode(row['payload'] as String) as Map<String, dynamic>;

        bool sent = false;
        try {
          if (endpoint == 'chat') {
            final res = await ApiService.instance.postChatTransaction(
              message: payload['message'] as String? ?? '',
              householdId: householdId,
              userId: payload['user_id'] as String?,
              allowDuplicate: true,
            );
            sent = res['status'] == 'success' || res['status'] == 'enriched' || res['status'] == 'simulation';
          } else if (endpoint == 'sms') {
            final res = await ApiService.instance.postSms(
              rawSms: payload['raw_sms'] as String? ?? '',
              sender: payload['sender'] as String? ?? '',
              receivedAt: payload['received_at'] as String? ?? '',
              householdId: householdId,
            );
            sent = res['status'] == 'success';
          } else if (endpoint == 'receipt') {
            final res = await ApiService.instance.scanReceipt(
              imagesBase64: (payload['images_base64'] as List?)?.cast<String>(),
              qrCodeRaw: payload['qr_code_raw'] as String?,
              householdId: householdId,
              userId: payload['user_id'] as String?,
              allowDuplicate: true,
            );
            sent = res['status'] == 'success' || res['status'] == 'enriched';
          }
        } catch (_) {
          sent = false;
        }

        if (sent) {
          await db.delete('offline_tx_queue', where: 'id = ?', whereArgs: [id]);
          successCount++;
        }
      }

      await updatePendingCount();
      if (successCount > 0) {
        _flushedController.add(successCount);
      }
    } catch (e) {
      debugPrint('[OfflineSyncService] Flush error: $e');
    } finally {
      _isFlushing = false;
    }

    return successCount;
  }
}
