import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../models/offline_queue_item.dart';
import 'api_service.dart';
import 'offline_queue_manager.dart';

typedef ItemDispatcher = Future<Map<String, dynamic>> Function(OfflineQueueItem item);

/// Background worker that drains the SQLite offline queue upon connectivity restoration.
class SyncWorker {
  final OfflineQueueManager queueManager;
  final ItemDispatcher? customDispatcher;

  final ValueNotifier<int> pendingCountNotifier = ValueNotifier<int>(0);
  final StreamController<int> _flushedController = StreamController<int>.broadcast();
  Stream<int> get onItemsFlushed => _flushedController.stream;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _isDraining = false;

  SyncWorker({
    OfflineQueueManager? queueManager,
    this.customDispatcher,
  }) : queueManager = queueManager ?? OfflineQueueManager();

  /// Starts listening to network state changes to trigger automatic synchronization.
  void initConnectivityListener() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      final isOnline = results.any((r) =>
          r == ConnectivityResult.mobile ||
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.ethernet ||
          r == ConnectivityResult.vpn);

      if (isOnline) {
        debugPrint('[SyncWorker] Network connected. Triggering queue drain...');
        drainQueue();
      }
    });
  }

  void dispose() {
    _connectivitySubscription?.cancel();
    _flushedController.close();
  }

  /// Refreshes the reactive counter of pending offline operations.
  Future<int> updatePendingCount() async {
    final count = await queueManager.getPendingCount();
    pendingCountNotifier.value = count;
    return count;
  }

  /// Sequentially executes all pending queue items against the backend with idempotency keys.
  Future<int> drainQueue() async {
    if (_isDraining) return 0;
    _isDraining = true;

    int successCount = 0;
    try {
      final items = await queueManager.getPendingItems();

      for (final item in items) {
        await queueManager.markSyncing(item.id);
        bool success = false;
        String? failureError;

        try {
          if (customDispatcher != null) {
            final res = await customDispatcher!(item);
            success = res['status'] != 'error';
            if (!success) failureError = res['message']?.toString();
          } else {
            success = await _dispatchItem(item);
          }
        } catch (e) {
          success = false;
          failureError = e.toString();
        }

        if (success) {
          await queueManager.markSuccess(item.id);
          successCount++;
        } else {
          await queueManager.markFailed(
            item.id,
            error: failureError ?? 'Unknown synchronization failure',
          );
        }

        // Brief delay between replays to prevent burst congestion
        await Future.delayed(const Duration(milliseconds: 100));
      }

      await updatePendingCount();
      if (successCount > 0) {
        _flushedController.add(successCount);
      }
    } catch (e) {
      debugPrint('[SyncWorker] Error during drainQueue: $e');
    } finally {
      _isDraining = false;
    }

    return successCount;
  }

  Future<bool> _dispatchItem(OfflineQueueItem item) async {
    final payload = item.payload;
    final hid = item.householdId;

    if (item.operationType == 'chat') {
      final res = await ApiService.instance.postChatTransaction(
        message: payload['message'] as String? ?? '',
        householdId: hid,
        userId: payload['user_id'] as String?,
        allowDuplicate: true,
      );
      return res['status'] == 'success' ||
          res['status'] == 'enriched' ||
          res['status'] == 'simulation' ||
          res['status'] == 'preview';
    } else if (item.operationType == 'sms') {
      final res = await ApiService.instance.postSms(
        rawSms: payload['raw_sms'] as String? ?? '',
        sender: payload['sender'] as String? ?? '',
        receivedAt: payload['received_at'] as String? ?? '',
        householdId: hid,
      );
      return res['status'] == 'success';
    } else if (item.operationType == 'receipt') {
      final res = await ApiService.instance.scanReceipt(
        imagesBase64: (payload['images_base64'] as List?)?.cast<String>(),
        qrCodeRaw: payload['qr_code_raw'] as String?,
        householdId: hid,
        userId: payload['user_id'] as String?,
        allowDuplicate: true,
      );
      return res['status'] == 'success' || res['status'] == 'enriched';
    }

    return false;
  }
}
