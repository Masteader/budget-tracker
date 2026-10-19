import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/offline_queue_item.dart';
import 'api_service.dart';
import 'offline_queue_manager.dart';

typedef ItemDispatcher = Future<Map<String, dynamic>> Function(OfflineQueueItem item);

/// Inserts one `transactions` row directly through Supabase (RLS enforced).
typedef TransactionInserter = Future<void> Function(Map<String, dynamic> row);

/// Operation type for a manual expense row that is replayed verbatim with a
/// client-generated primary key, making the replay naturally idempotent.
const String kTransactionInsertOperation = 'transaction_insert';

/// How a single replay attempt ended.
enum ReplayOutcome {
  /// The server committed the operation (or it had nothing to commit).
  committed,

  /// Network/timeout/gateway/auth trouble: retry later, keep queue order.
  transient,

  /// The server rejected this payload; consumes the item's retry budget.
  permanent,
}

class ReplayResult {
  final ReplayOutcome outcome;
  final String? error;
  const ReplayResult(this.outcome, [this.error]);
}

/// Background worker that drains the SQLite offline queue upon connectivity restoration.
///
/// Guarantees:
/// * Single drain at a time per process; concurrent callers await the
///   in-flight drain instead of getting a misleading `0`.
/// * Rows orphaned in `syncing` by an app kill are replayed on the next drain.
/// * FIFO: the drain stops at the first transient failure, so later items are
///   never committed ahead of an earlier one that is still waiting.
/// * Each replay carries the row's idempotency key (`Idempotency-Key` header,
///   or the row's own primary key for direct inserts) so a request that timed
///   out after the server committed it is not booked twice.
class SyncWorker {
  final OfflineQueueManager queueManager;
  final ItemDispatcher? customDispatcher;
  final TransactionInserter? _transactionInserter;
  final ApiService? _api;
  final int maxPermanentRetries;
  final Duration interItemDelay;

  final ValueNotifier<int> pendingCountNotifier = ValueNotifier<int>(0);
  final StreamController<int> _flushedController = StreamController<int>.broadcast();
  Stream<int> get onItemsFlushed => _flushedController.stream;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Future<int>? _inFlightDrain;

  SyncWorker({
    OfflineQueueManager? queueManager,
    this.customDispatcher,
    TransactionInserter? transactionInserter,
    ApiService? api,
    this.maxPermanentRetries = 5,
    this.interItemDelay = const Duration(milliseconds: 100),
  })  : queueManager = queueManager ?? OfflineQueueManager(),
        _transactionInserter = transactionInserter,
        _api = api;

  ApiService get _apiService => _api ?? ApiService.instance;

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
    pendingCountNotifier.dispose();
  }

  /// Refreshes the reactive counter of pending offline operations.
  Future<int> updatePendingCount() async {
    final count = await queueManager.getPendingCount();
    pendingCountNotifier.value = count;
    return count;
  }

  /// Replays every pending queue item. Returns the number committed by this
  /// drain (or by the drain already in flight when called concurrently).
  Future<int> drainQueue() {
    return _inFlightDrain ??= _drain().whenComplete(() => _inFlightDrain = null);
  }

  Future<int> _drain() async {
    int successCount = 0;
    try {
      await queueManager.recoverInterruptedItems();

      final attempted = <String>{};
      var halted = false;
      while (!halted) {
        final batch = await queueManager.getPendingItems(excludeIds: attempted);
        if (batch.isEmpty) break;

        for (final item in batch) {
          attempted.add(item.id);
          await queueManager.markSyncing(item.id);

          final result = await _replay(item);
          switch (result.outcome) {
            case ReplayOutcome.committed:
              await queueManager.markSuccess(item.id);
              successCount++;
            case ReplayOutcome.permanent:
              await queueManager.markFailed(
                item.id,
                error: result.error ?? 'Rejected by server',
                maxRetries: maxPermanentRetries,
              );
            case ReplayOutcome.transient:
              await queueManager.markFailed(
                item.id,
                error: result.error ?? 'Temporarily unavailable',
                transient: true,
              );
              halted = true;
          }
          if (halted) break;

          if (interItemDelay > Duration.zero) {
            // Brief delay between replays to prevent burst congestion
            await Future.delayed(interItemDelay);
          }
        }
      }
    } catch (e) {
      debugPrint('[SyncWorker] Error during drainQueue: $e');
    }

    try {
      await updatePendingCount();
    } catch (e) {
      debugPrint('[SyncWorker] Error refreshing pending count: $e');
    }
    if (successCount > 0 && !_flushedController.isClosed) {
      _flushedController.add(successCount);
    }
    return successCount;
  }

  Future<ReplayResult> _replay(OfflineQueueItem item) async {
    try {
      if (customDispatcher != null) {
        return classifyResponse(await customDispatcher!(item), item.operationType);
      }
      return await _dispatchItem(item);
    } on Exception catch (e) {
      return ReplayResult(_classifyException(e), e.toString());
    } catch (e) {
      // Programming/data errors (TypeError, etc.) never heal by retrying the
      // same payload; count them against the poison budget.
      return ReplayResult(ReplayOutcome.permanent, e.toString());
    }
  }

  static ReplayOutcome _classifyException(Exception e) {
    if (e is PostgrestException) {
      // 23505 unique_violation: the row with this client-generated id is
      // already stored, i.e. a previous attempt committed before timing out.
      if (e.code == '23505') return ReplayOutcome.committed;
      if (e.code == 'PGRST301' || e.code == '401' || e.code == '403') {
        return ReplayOutcome.transient;
      }
      return ReplayOutcome.permanent;
    }
    if (e is AuthException) return ReplayOutcome.transient;
    if (e is SocketException ||
        e is TimeoutException ||
        e is http.ClientException ||
        e is HttpException) {
      return ReplayOutcome.transient;
    }
    // Unknown exceptions are most likely I/O; do not burn the retry budget.
    return ReplayOutcome.transient;
  }

  /// Maps a backend response map to a replay outcome.
  @visibleForTesting
  static ReplayResult classifyResponse(Map<String, dynamic> res, String operationType) {
    final status = res['status']?.toString();
    final message = res['message']?.toString() ?? res['detail']?.toString();

    switch (status) {
      case 'success':
      case 'enriched':
        return const ReplayResult(ReplayOutcome.committed);
      case 'simulation':
        // A queued "can I afford ...?" question: answered, nothing to store.
        return const ReplayResult(ReplayOutcome.committed);
      case 'preview':
        // The chat client returns a local `preview` parse when the backend
        // is unreachable; nothing was stored on the server.
        if (operationType == 'chat' || operationType == 'receipt_offline_draft') {
          return ReplayResult(ReplayOutcome.transient, message ?? 'Backend unreachable');
        }
        return ReplayResult(ReplayOutcome.permanent, message ?? 'Server returned an uncommitted preview');
      case 'error':
        return ReplayResult(_classifyStatusCode(res['status_code']), message);
      default:
        // pending_confirmation, duplicate_candidate, non_transactional, or a
        // body without a status: the operation was not committed.
        return ReplayResult(
          ReplayOutcome.permanent,
          'Not committed (status: ${status ?? 'missing'})${message == null ? '' : ': $message'}',
        );
    }
  }

  static ReplayOutcome _classifyStatusCode(Object? rawCode) {
    final code = rawCode is num ? rawCode.toInt() : int.tryParse('$rawCode');
    // No HTTP status means the request never completed (offline, DNS, timeout).
    if (code == null) return ReplayOutcome.transient;
    if (code == 401 || code == 403) return ReplayOutcome.transient;
    if (code == 408 || code == 425 || code == 429) return ReplayOutcome.transient;
    if (code == 502 || code == 503 || code == 504) return ReplayOutcome.transient;
    return ReplayOutcome.permanent;
  }

  Future<void> _insertTransaction(Map<String, dynamic> row) async {
    final inserter = _transactionInserter;
    if (inserter != null) {
      await inserter(row);
      return;
    }
    await Supabase.instance.client.from('transactions').insert(row);
  }

  static String? _nonEmpty(Object? value) {
    final s = value?.toString().trim();
    return (s == null || s.isEmpty) ? null : s;
  }

  /// Legacy queued manual expenses stored the family payer as `wife`; the
  /// chat endpoint only understands `me` / `partner`.
  static String? _chatPaidBy(Object? paidBy) {
    final v = _nonEmpty(paidBy)?.toLowerCase();
    if (v == null) return null;
    if (v == 'me' || v == 'partner') return v;
    if (v == 'wife' || v == 'husband') return 'partner';
    return null;
  }

  Future<ReplayResult> _dispatchItem(OfflineQueueItem item) async {
    final payload = item.payload;
    final hid = item.householdId;
    final key = item.idempotencyKey.isEmpty ? item.id : item.idempotencyKey;

    switch (item.operationType) {
      case kTransactionInsertOperation:
        final row = Map<String, dynamic>.from(payload);
        row['household_id'] = hid;
        row['id'] ??= item.id;
        row['timestamp'] ??= item.createdAt.toUtc().toIso8601String();
        await _insertTransaction(row);
        return const ReplayResult(ReplayOutcome.committed);

      case 'chat':
        final res = await _apiService.postChatTransaction(
          message: payload['message'] as String? ?? '',
          householdId: hid,
          userId: payload['user_id'] as String?,
          allowDuplicate: true,
          previewOnly: false,
          merchant: _nonEmpty(payload['merchant']),
          spentBy: _nonEmpty(payload['spent_by']),
          categoryCode: _nonEmpty(payload['category_code']),
          subCategory: _nonEmpty(payload['sub_category']),
          paidBy: _chatPaidBy(payload['paid_by']),
          beneficiary: _nonEmpty(payload['beneficiary']),
          idempotencyKey: key,
          occurredAt: item.createdAt,
        );
        return classifyResponse(res, item.operationType);

      case 'receipt':
      case 'receipt_offline_draft':
        final images = await queueManager.loadImages(item);
        final qr = payload['qr_code_raw'] as String?;
        if (images.isNotEmpty || (item.operationType == 'receipt' && qr != null)) {
          final res = await _apiService.scanReceipt(
            imagesBase64: images,
            qrCodeRaw: qr,
            householdId: hid,
            userId: payload['user_id'] as String?,
            allowDuplicate: true,
            merchant: _nonEmpty(payload['merchant']),
            spentBy: _nonEmpty(payload['spent_by']),
            idempotencyKey: key,
            occurredAt: item.createdAt,
          );
          return classifyResponse(res, item.operationType);
        }
        final amount = (payload['amount'] as num?)?.toDouble() ?? 0.0;
        final merchant = _nonEmpty(payload['merchant']) ?? 'Merchant';
        if (amount > 0) {
          final res = await _apiService.postChatTransaction(
            message: '$merchant ${amount.toStringAsFixed(2)} SAR',
            householdId: hid,
            userId: payload['user_id'] as String?,
            allowDuplicate: true,
            previewOnly: false,
            merchant: merchant,
            spentBy: _nonEmpty(payload['spent_by']),
            categoryCode: _nonEmpty(payload['category_code']),
            idempotencyKey: key,
            occurredAt: item.createdAt,
          );
          return classifyResponse(res, item.operationType);
        }
        return const ReplayResult(
          ReplayOutcome.permanent,
          'Draft has neither images nor an amount to record',
        );

      default:
        return ReplayResult(
          ReplayOutcome.permanent,
          'Unsupported offline operation: ${item.operationType}',
        );
    }
  }
}
