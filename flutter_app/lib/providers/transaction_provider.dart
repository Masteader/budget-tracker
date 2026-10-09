import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';
import '../models/models.dart';
import '../services/receipt_storage_service.dart';

/// Centralized reactive state provider for all transactions in the household.
/// Manages list cache, Supabase Realtime synchronization, optimistic deletions, and filtering.
class TransactionProvider extends ChangeNotifier {
  String? _householdId;
  List<Transaction> _transactions = [];
  bool _isLoading = false;
  String? _error;
  RealtimeChannel? _realtimeChannel;

  // Filter state
  String _searchQuery = '';
  String? _categoryFilter;
  String? _spentByFilter; // 'all' | 'me' | 'partner' | 'both'

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
    _householdId = householdId;
    await fetchTransactions();
    _subscribeRealtime();
  }

  /// Refresh transactions alias for uniform provider API.
  Future<void> refresh() => fetchTransactions();

  /// Fetch latest transactions from Supabase.
  Future<void> fetchTransactions() async {
    if (_householdId == null) return;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final data = await supabase
          .from('transactions')
          .select()
          .eq('household_id', _householdId!)
          .order('timestamp', ascending: false);

      _transactions = (data as List)
          .map((row) => Transaction.fromMap(Map<String, dynamic>.from(row as Map)))
          .toList();
      _recomputeFiltered();
      _isLoading = false;
      notifyListeners();
    } catch (e) {
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
  Future<bool> deleteTransaction(String transactionId) async {
    final existingIdx = _transactions.indexWhere((t) => t.id == transactionId);
    if (existingIdx == -1) return false;

    final removedTx = _transactions.removeAt(existingIdx);
    _recomputeFiltered();
    notifyListeners();

    try {
      if (removedTx.receiptUrl != null && removedTx.receiptUrl!.trim().isNotEmpty) {
        ReceiptStorageService().deleteReceiptByUrl(removedTx.receiptUrl!);
      }
      await supabase.from('transactions').delete().eq('id', transactionId);
      return true;
    } catch (e) {
      debugPrint('[TransactionProvider] Delete failed, rolling back: $e');
      // Rollback
      _transactions.insert(existingIdx, removedTx);
      _recomputeFiltered();
      notifyListeners();
      return false;
    }
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
    );

    _transactions[existingIdx] = updated;
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
    super.dispose();
  }
}
