import 'dart:async';
import 'package:flutter/foundation.dart';

import 'offline_queue_manager.dart';
import 'sync_worker.dart';

export 'offline_queue_manager.dart' show OfflineQueueWriteException;

/// Offline-First SQLite Synchronization Service.
/// Acts as a unified facade coordinating the OfflineQueueManager and SyncWorker.
class OfflineSyncService {
  OfflineSyncService._() : queueManager = OfflineQueueManager();
  static final OfflineSyncService instance = OfflineSyncService._();

  @visibleForTesting
  OfflineSyncService.withQueue(this.queueManager);

  final OfflineQueueManager queueManager;
  late final SyncWorker syncWorker = SyncWorker(queueManager: queueManager);

  ValueNotifier<int> get pendingCountNotifier => syncWorker.pendingCountNotifier;
  Stream<int> get onItemsFlushed => syncWorker.onItemsFlushed;

  /// Initializes connectivity listeners and updates the pending queue counter.
  void initialize() {
    syncWorker.initConnectivityListener();
    updatePendingCount();
  }

  /// Adds a failed or offline operation to the local SQLite queue.
  ///
  /// Returns the queue item id. Throws [OfflineQueueWriteException] when the
  /// item could not be stored, so callers never show "saved offline" for
  /// data that was lost (MOB-28).
  Future<String> enqueue({
    required String endpoint,
    required Map<String, dynamic> payload,
    required String householdId,
    String? customId,
    String? idempotencyKey,
  }) async {
    final id = await queueManager.enqueueOrThrow(
      operationType: endpoint,
      payload: payload,
      householdId: householdId,
      customId: customId,
      idempotencyKey: idempotencyKey,
    );
    await updatePendingCount();
    return id;
  }

  /// Refreshes the reactive counter of pending items.
  Future<int> updatePendingCount() => syncWorker.updatePendingCount();

  /// Manually triggers an immediate background drain of all queued items.
  Future<int> flushQueue() => syncWorker.drainQueue();

  /// Number of poison items the server rejected repeatedly.
  Future<int> failedCount() => queueManager.getFailedCount();

  /// Gives parked `failed` items a fresh retry budget and drains again.
  Future<int> retryFailed() async {
    await queueManager.requeueFailed();
    await updatePendingCount();
    return syncWorker.drainQueue();
  }
}
