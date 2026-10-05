import 'dart:async';
import 'package:flutter/foundation.dart';

import 'offline_queue_manager.dart';
import 'sync_worker.dart';

/// Offline-First SQLite Synchronization Service.
/// Acts as a unified facade coordinating the OfflineQueueManager and SyncWorker.
class OfflineSyncService {
  OfflineSyncService._();
  static final OfflineSyncService instance = OfflineSyncService._();

  final OfflineQueueManager queueManager = OfflineQueueManager();
  late final SyncWorker syncWorker = SyncWorker(queueManager: queueManager);

  ValueNotifier<int> get pendingCountNotifier => syncWorker.pendingCountNotifier;
  Stream<int> get onItemsFlushed => syncWorker.onItemsFlushed;

  /// Initializes connectivity listeners and updates the pending queue counter.
  void initialize() {
    syncWorker.initConnectivityListener();
    updatePendingCount();
  }

  /// Adds a failed or offline operation to the local SQLite queue.
  Future<String?> enqueue({
    required String endpoint,
    required Map<String, dynamic> payload,
    required String householdId,
    String? customId,
  }) async {
    final id = await queueManager.enqueue(
      operationType: endpoint,
      payload: payload,
      householdId: householdId,
      customId: customId,
    );
    await updatePendingCount();
    return id;
  }

  /// Refreshes the reactive counter of pending items.
  Future<int> updatePendingCount() => syncWorker.updatePendingCount();

  /// Manually triggers an immediate background drain of all queued items.
  Future<int> flushQueue() => syncWorker.drainQueue();
}
