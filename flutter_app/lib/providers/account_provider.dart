import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/account.dart';
import '../services/account_service.dart';

/// Central reactive provider for household accounts, liquidity, operating cash,
/// and cycle income records. Eliminates stale local-state across screens.
class AccountProvider extends ChangeNotifier {
  final AccountService _service;
  StreamSubscription<List<Account>>? _streamSub;

  String? _householdId;
  String? _cycleKey;
  List<Account> _accounts = [];
  List<IncomeRecord> _cycleIncomeRecords = [];
  bool _isLoading = false;
  String? _error;

  AccountProvider({AccountService? service}) : _service = service ?? AccountService.instance;

  String? get householdId => _householdId;
  String? get cycleKey => _cycleKey;
  List<Account> get accounts => List.unmodifiable(_accounts);
  List<IncomeRecord> get cycleIncomeRecords => List.unmodifiable(_cycleIncomeRecords);
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Liquid operating cash: accounts in the active operating pool with positive balances.
  double get operatingCash => _accounts
      .where((a) => !a.isArchived && a.accountType.isOperatingPool)
      .fold<double>(0.0, (s, a) => s + (a.balance > 0 ? a.balance : 0.0));

  /// Total net worth across all non-archived accounts.
  double get totalNetWorth => _accounts
      .where((a) => !a.isArchived)
      .fold<double>(0.0, (s, a) => s + a.balance);

  /// Verified cycle income total from income records.
  double get cycleIncomeTotal =>
      _cycleIncomeRecords.fold<double>(0.0, (s, r) => s + r.netAmount);

  /// Initializes accounts and cycle income for the active household and salary cycle.
  /// Enforces Guardrail 1: cancels any prior stream before listening anew.
  Future<void> init(String householdId, String cycleKey) async {
    final isSameScope = _householdId == householdId && _cycleKey == cycleKey;
    _householdId = householdId;
    _cycleKey = cycleKey;

    if (!isSameScope || _streamSub == null) {
      _listenToRealtime(householdId);
    }
    await refresh();
  }

  void _listenToRealtime(String householdId) {
    _streamSub?.cancel();
    _streamSub = _service.streamAccounts(householdId).listen(
      (list) {
        _accounts = list;
        _error = null;
        notifyListeners();
      },
      onError: (err) {
        _error = err.toString();
        notifyListeners();
      },
    );
  }

  /// Instantaneous optimistic balance update before Realtime CDC arrives.
  void optimisticUpdateBalance(String accountId, double newBalance) {
    final idx = _accounts.indexWhere((a) => a.id == accountId);
    if (idx != -1) {
      final updated = _accounts[idx].copyWith(balance: newBalance);
      _accounts = List<Account>.from(_accounts)..[idx] = updated;
      notifyListeners();
    }
  }

  /// Full refresh of accounts and cycle income from database.
  Future<void> refresh() async {
    final hid = _householdId;
    if (hid == null || hid.isEmpty) return;

    _isLoading = true;
    notifyListeners();

    try {
      final accFuture = _service.getAccounts(hid);
      final incFuture = _cycleKey != null && _cycleKey!.isNotEmpty
          ? _service.getCycleIncome(hid, _cycleKey!)
          : Future.value(<IncomeRecord>[]);

      final results = await Future.wait([accFuture, incFuture]);
      _accounts = results[0] as List<Account>;
      _cycleIncomeRecords = results[1] as List<IncomeRecord>;
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Clean teardown on sign-out or household switch.
  void reset() {
    _streamSub?.cancel();
    _streamSub = null;
    _householdId = null;
    _cycleKey = null;
    _accounts = [];
    _cycleIncomeRecords = [];
    _isLoading = false;
    _error = null;
    notifyListeners();
  }

  @visibleForTesting
  void setAccountsForTesting(List<Account> accounts, {String? householdId}) {
    _accounts = List.from(accounts);
    _householdId = householdId;
    notifyListeners();
  }

  @visibleForTesting
  void setCycleIncomeForTesting(List<IncomeRecord> records, {String? cycleKey}) {
    _cycleIncomeRecords = List.from(records);
    _cycleKey = cycleKey;
    notifyListeners();
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    _streamSub = null;
    super.dispose();
  }
}
