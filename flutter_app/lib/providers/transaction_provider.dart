import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';
import '../models/models.dart';
import '../services/household_permissions.dart';
import '../services/nafaqah_write_errors.dart';
import '../services/receipt_storage_service.dart';

/// Centralized reactive state provider for all transactions in the household.
/// Manages list cache, Supabase Realtime synchronization, optimistic deletions, and filtering.
typedef TransactionRowDeleter = Future<List<Map<String, dynamic>>> Function(String transactionId);
typedef TransactionRowInserter = Future<void> Function(Map<String, dynamic> row);
typedef ReceiptDeleter = Future<void> Function(String receiptUrl);

class TransactionProvider extends ChangeNotifier {
  TransactionProvider({
    TransactionRowDeleter? deleteRow,
    TransactionRowInserter? insertRow,
    ReceiptDeleter? deleteReceipt,
    this.undoWindow = const Duration(seconds: 10),
  })  : _deleteRow = deleteRow ?? _supabaseDeleteRow,
        _insertRow = insertRow ?? _supabaseInsertRow,
        _deleteReceipt = deleteReceipt ?? _storageDeleteReceipt;

  final TransactionRowDeleter _deleteRow;
  final TransactionRowInserter _insertRow;
  final ReceiptDeleter _deleteReceipt;

  /// How long a deleted transaction's receipt image is kept so the delete can
  /// still be undone. Longer than the undo snackbar (4 s).
  final Duration undoWindow;

  /// Full database rows of deleted transactions, kept for undo (UI-25).
  final Map<String, Map<String, dynamic>> _deletedRows = {};
  final Map<String, Timer> _pendingReceiptCleanups = {};
  final Map<String, String> _pendingReceiptUrls = {};

  String? _householdId;
  List<Transaction> _transactions = [];
  bool _isLoading = false;
  String? _error;
  RealtimeChannel? _realtimeChannel;
  int _fetchGeneration = 0;

  // Filter state
  String _searchQuery = '';
  String? _categoryFilter;
  String? _spentByFilter; // 'all' | 'me' | 'partner' | 'both'

  /// True when the last failed delete/update was refused by the server for lack
  /// of rights (another member's transaction and the user is no admin, DB-18).
  bool _lastWriteDenied = false;
  bool get lastWriteDenied => _lastWriteDenied;

  /// The Nafaqah rule that refused the last failed delete/update, if any (e.g.
  /// the ledger guard refusing to delete a wife advance already repaid).
  NafaqahWriteRefusal? _lastNafaqahRefusal;
  NafaqahWriteRefusal? get lastNafaqahRefusal => _lastNafaqahRefusal;

  // Getters
  bool get isLoading => _isLoading;
  String? get error => _error;
  List<Transaction> get transactions => _transactions;
  List<Transaction> _filteredTransactions = [];

  String get searchQuery => _searchQuery;
  String? get categoryFilter => _categoryFilter;
  String? get spentByFilter => _spentByFilter;

  List<Transaction> get filteredTransactions => _filteredTransactions;

  void _recomputeFiltered() {
    final hasSearch = _searchQuery.isNotEmpty;
    final q = hasSearch ? _searchQuery.toLowerCase() : '';
    final hasCategory = _categoryFilter != null && _categoryFilter!.isNotEmpty;
    final hasSpentBy = _spentByFilter != null && _spentByFilter != 'all';
    final targetSpentBy = hasSpentBy ? _spentByFilter!.toLowerCase() : '';

    if (!hasSearch && !hasCategory && !hasSpentBy) {
      _filteredTransactions = List.unmodifiable(_transactions);
      return;
    }

    _filteredTransactions = _transactions.where((tx) {
      if (hasSearch) {
        final merchantMatch = (tx.merchant ?? '').toLowerCase().contains(q);
        final rawMatch = (tx.rawSms ?? '').toLowerCase().contains(q);
        final itemMatch = tx.items.any((it) => (it['name']?.toString() ?? '').toLowerCase().contains(q));
        if (!merchantMatch && !rawMatch && !itemMatch) return false;
      }

      if (hasCategory) {
        if (tx.categoryCode != _categoryFilter) return false;
      }

      if (hasSpentBy) {
        if (tx.spentBy.toLowerCase() != targetSpentBy) return false;
      }

      return true;
    }).toList(growable: false);
  }

  void setSearchQuery(String query) {
    _searchQuery = query.trim();
    _recomputeFiltered();
    notifyListeners();
  }

  void setCategoryFilter(String? categoryCode) {
    _categoryFilter = categoryCode;
    _recomputeFiltered();
    notifyListeners();
  }

  void setSpentByFilter(String? spentBy) {
    _spentByFilter = spentBy;
    _recomputeFiltered();
    notifyListeners();
  }

  void clearFilters() {
    _searchQuery = '';
    _categoryFilter = null;
    _spentByFilter = 'all';
    _recomputeFiltered();
    notifyListeners();
  }

  /// Initialize provider with active household ID and start Realtime sync.
  Future<void> init(String householdId) async {
    if (_householdId == householdId && _transactions.isNotEmpty) return;
    if (_householdId != householdId) {
      // Never show (or keep streaming) another household's transactions
      // while the new household loads.
      _clearState();
    }
    _householdId = householdId;
    await fetchTransactions();
    _subscribeRealtime();
  }

  /// Drops all cached data and the Realtime channel (sign-out / account switch).
  void reset() {
    _householdId = null;
    _clearState();
    notifyListeners();
  }

  void _clearState() {
    // Never offer an undo across a sign-out or household switch.
    _flushPendingDeletes();
    _fetchGeneration++;
    _realtimeChannel?.unsubscribe();
    _realtimeChannel = null;
    _transactions = [];
    _filteredTransactions = [];
    _error = null;
    _isLoading = false;
  }

  /// Refresh transactions alias for uniform provider API.
  Future<void> refresh() => fetchTransactions();

  /// Fetch latest transactions from Supabase.
  Future<void> fetchTransactions() async {
    final householdId = _householdId;
    if (householdId == null) return;
    final generation = ++_fetchGeneration;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final data = await supabase
          .from('transactions')
          .select()
          .eq('household_id', householdId)
          .order('timestamp', ascending: false);

      // A reset or household switch happened while this request was in flight.
      if (generation != _fetchGeneration) return;
      _transactions = (data as List)
          .map((row) => Transaction.fromMap(Map<String, dynamic>.from(row as Map)))
          .toList();
      _recomputeFiltered();
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      if (generation != _fetchGeneration) return;
      _isLoading = false;
      _error = e.toString();
      debugPrint('[TransactionProvider] Error fetching transactions: $e');
      notifyListeners();
    }
  }

  /// Subscribes to Supabase Realtime channel for instant multi-device syncing.
  void _subscribeRealtime() {
    _realtimeChannel?.unsubscribe();
    if (_householdId == null) return;

    _realtimeChannel = supabase
        .channel('public:transactions:$_householdId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'transactions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'household_id',
            value: _householdId!,
          ),
          callback: (payload) {
            _handleRealtimePayload(payload);
          },
        )
        .subscribe();
  }

  void _handleRealtimePayload(PostgresChangePayload payload) {
    final eventType = payload.eventType;

    if (eventType == PostgresChangeEvent.insert) {
      final newRecord = payload.newRecord;
      if (newRecord.isNotEmpty) {
        final tx = Transaction.fromMap(Map<String, dynamic>.from(newRecord));
        // Prevent duplicate insertion if already in list
        final idx = _transactions.indexWhere((t) => t.id == tx.id);
        if (idx == -1) {
          _transactions.insert(0, tx);
          _recomputeFiltered();
          notifyListeners();
        }
      }
    } else if (eventType == PostgresChangeEvent.update) {
      final updatedRecord = payload.newRecord;
      if (updatedRecord.isNotEmpty) {
        final tx = Transaction.fromMap(Map<String, dynamic>.from(updatedRecord));
        final idx = _transactions.indexWhere((t) => t.id == tx.id);
        if (idx != -1) {
          _transactions[idx] = tx;
          _recomputeFiltered();
          notifyListeners();
        }
      }
    } else if (eventType == PostgresChangeEvent.delete) {
      final oldRecord = payload.oldRecord;
      final deletedId = oldRecord['id'] as String?;
      if (deletedId != null) {
        _transactions.removeWhere((t) => t.id == deletedId);
        _recomputeFiltered();
        notifyListeners();
      }
    }
  }

  /// Optimistically deletes a transaction, updating UI immediately.
  /// If the remote delete fails, rolls back the deletion and restores list state.
  ///
  /// UI-25: the deleted row is captured exactly as the database returned it
  /// (every column, including payer, beneficiary, account and sub-category
  /// attribution), so [restoreDeletedTransaction] can undo the delete with the
  /// same id and values. The receipt image is removed from storage only after
  /// [undoWindow] passes without an undo; before, it was deleted up front and
  /// an undone transaction pointed at a missing receipt.
  Future<bool> deleteTransaction(String transactionId) async {
    final existingIdx = _transactions.indexWhere((t) => t.id == transactionId);
    if (existingIdx == -1) return false;

    final removedTx = _transactions.removeAt(existingIdx);
    _lastWriteDenied = false;
    _lastNafaqahRefusal = null;
    _recomputeFiltered();
    notifyListeners();

    try {
      final deletedRows = await _deleteRow(transactionId);
      _deletedRows[transactionId] =
          deletedRows.isNotEmpty ? Map<String, dynamic>.from(deletedRows.first) : removedTx.toMap();
      final receiptUrl = removedTx.receiptUrl;
      if (receiptUrl != null && receiptUrl.trim().isNotEmpty) {
        _pendingReceiptCleanups[transactionId]?.cancel();
        _pendingReceiptUrls[transactionId] = receiptUrl;
        _pendingReceiptCleanups[transactionId] = Timer(undoWindow, () => _runReceiptCleanup(transactionId));
      }
      return true;
    } catch (e) {
      debugPrint('[TransactionProvider] Delete failed, rolling back: $e');
      _lastWriteDenied = HouseholdPermissions.isPermissionDenied(e);
      _lastNafaqahRefusal = nafaqahWriteRefusalOf(e);
      // Rollback
      _transactions.insert(existingIdx, removedTx);
      _recomputeFiltered();
      notifyListeners();
      return false;
    }
  }

  /// Re-inserts a transaction removed by [deleteTransaction] with its original
  /// id and every original column (UI-25). Returns false when there is nothing
  /// to restore or the insert fails; the receipt image is then cleaned up.
  Future<bool> restoreDeletedTransaction(String transactionId) async {
    final row = _deletedRows[transactionId];
    if (row == null) return false;
    _pendingReceiptCleanups.remove(transactionId)?.cancel();

    try {
      await _insertRow(Map<String, dynamic>.from(row));
    } catch (e) {
      debugPrint('[TransactionProvider] Undo failed: $e');
      _deletedRows.remove(transactionId);
      _runReceiptCleanup(transactionId);
      return false;
    }

    _deletedRows.remove(transactionId);
    _pendingReceiptUrls.remove(transactionId);
    try {
      addTransaction(Transaction.fromMap(row));
    } catch (e) {
      // Row shape the model cannot parse: the next fetch shows it.
      debugPrint('[TransactionProvider] Restored row not parsed locally: $e');
    }
    return true;
  }

  void _runReceiptCleanup(String transactionId) {
    _pendingReceiptCleanups.remove(transactionId)?.cancel();
    final url = _pendingReceiptUrls.remove(transactionId);
    if (url == null) return;
    _deleteReceipt(url).catchError((Object e) {
      debugPrint('[TransactionProvider] Receipt cleanup failed: $e');
    });
  }

  /// Runs the deferred receipt deletions now and forgets undo snapshots.
  void _flushPendingDeletes() {
    for (final id in _pendingReceiptCleanups.keys.toList()) {
      _runReceiptCleanup(id);
    }
    _deletedRows.clear();
  }

  static Future<List<Map<String, dynamic>>> _supabaseDeleteRow(String id) async {
    final res = await supabase.from('transactions').delete().eq('id', id).select();
    return (res as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();
  }

  static Future<void> _supabaseInsertRow(Map<String, dynamic> row) async {
    await supabase.from('transactions').insert(row);
  }

  static Future<void> _storageDeleteReceipt(String url) async {
    await ReceiptStorageService().deleteReceiptByUrl(url);
  }

  /// Optimistically updates a transaction in local state and persists to database.
  Future<bool> updateTransaction({
    required String transactionId,
    required double amount,
    required String merchant,
    required String categoryCode,
    required String spentBy,
    String? paidBy,
    String? beneficiary,
    String? subCategory,
    List<Map<String, dynamic>>? items,
  }) async {
    final existingIdx = _transactions.indexWhere((t) => t.id == transactionId);
    if (existingIdx == -1) return false;

    final original = _transactions[existingIdx];
    final updated = Transaction(
      id: original.id,
      householdId: original.householdId,
      amount: amount,
      currency: original.currency,
      merchant: merchant,
      categoryCode: categoryCode,
      timestamp: original.timestamp,
      isReallocated: original.isReallocated,
      reallocatedFromBudgetId: original.reallocatedFromBudgetId,
      createdAt: original.createdAt,
      source: original.source,
      spentBy: spentBy,
      paidBy: paidBy ?? original.paidBy,
      beneficiary: beneficiary ?? original.beneficiary,
      items: items ?? original.items,
      receiptUrl: original.receiptUrl,
      dedupFingerprint: original.dedupFingerprint,
      rawSms: original.rawSms,
      userId: original.userId,
    );

    _transactions[existingIdx] = updated;
    _lastWriteDenied = false;
    _lastNafaqahRefusal = null;
    _recomputeFiltered();
    notifyListeners();

    try {
      final updateData = <String, dynamic>{
        'amount': amount,
        'merchant': merchant,
        'category_code': categoryCode,
        'spent_by': spentBy,
        if (paidBy != null) 'paid_by': paidBy,
        if (beneficiary != null) 'beneficiary': beneficiary,
        if (subCategory != null) 'sub_category': subCategory,
        if (items != null) 'items': items,
      };
      await supabase.from('transactions').update(updateData).eq('id', transactionId);
      return true;
    } catch (e) {
      debugPrint('[TransactionProvider] Update failed, rolling back: $e');
      _lastWriteDenied = HouseholdPermissions.isPermissionDenied(e);
      _lastNafaqahRefusal = nafaqahWriteRefusalOf(e);
      _transactions[existingIdx] = original;
      _recomputeFiltered();
      notifyListeners();
      return false;
    }
  }

  /// Add a newly scanned/logged transaction immediately to local state.
  void addTransaction(Transaction tx) {
    final idx = _transactions.indexWhere((t) => t.id == tx.id);
    if (idx == -1) {
      _transactions.insert(0, tx);
      _recomputeFiltered();
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _realtimeChannel?.unsubscribe();
    _flushPendingDeletes();
    super.dispose();
  }
}
