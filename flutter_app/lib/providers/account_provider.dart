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
  double? _configuredMonthlyIncome;
  bool _isLoading = false;
  bool _hasLoaded = false;
  String? _error;

  AccountProvider({AccountService? service}) : _service = service ?? AccountService.instance;

  String? get householdId => _householdId;
  String? get cycleKey => _cycleKey;
  List<Account> get accounts => List.unmodifiable(_accounts);
  List<IncomeRecord> get cycleIncomeRecords => List.unmodifiable(_cycleIncomeRecords);
  double? get configuredMonthlyIncome => _configuredMonthlyIncome;
  bool get isLoading => _isLoading;
  bool get hasLoaded => _hasLoaded;
  String? get error => _error;

  /// Liquid operating cash: accounts in the active operating pool with positive balances.
  double get operatingCash => _accounts
      .where((a) => !a.isArchived && a.accountType.isOperatingPool)
      .fold<double>(0.0, (s, a) => s + (a.balance > 0 ? a.balance : 0.0));

  /// Total net worth across all non-archived accounts.
  double get totalNetWorth => _accounts
      .where((a) => !a.isArchived)
      .fold<double>(0.0, (s, a) => s + a.balance);

  /// Verified cycle income total from income records (falls back to configured income if no records exist).
  double get cycleIncomeTotal {
    final sum = _cycleIncomeRecords.fold<double>(0.0, (s, r) => s + r.netAmount);
    if (sum > 0) return sum;
    return _configuredMonthlyIncome ?? 0.0;
  }

  /// Effective cycle income for funding benchmark calculations.
  double get effectiveCycleIncome => cycleIncomeTotal;

  /// Initializes accounts and cycle income for the active household and salary cycle.
  /// Enforces Guardrail 1: cancels any prior stream before listening anew.
  Future<void> init(String householdId, String cycleKey) async {
    final isSameScope = _householdId == householdId && _cycleKey == cycleKey;
    if (isSameScope && _accounts.isNotEmpty) return;
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
        _hasLoaded = true;
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

  /// Deduct an expense from the given account (or default operating pool account).
  /// Updates local state optimistically and optionally persists to remote database
  /// via [AccountService.updateBalance] when [persistToRemote] is true.
  Future<void> deductExpense({
    String? accountId,
    required double amount,
    String? nafaqahClass,
    bool persistToRemote = false,
  }) async {
    // Both wife_personal (charged to allowance) and wife_reimbursable (paid from wife's own funds)
    // are isolated from the household/husband's operating cash pool (Rule 02.3).
    if (nafaqahClass == 'wife_personal' ||
        nafaqahClass == 'wife_reimbursable' ||
        amount <= 0 ||
        _accounts.isEmpty) {
      return;
    }

    Account? target;
    if (accountId != null && accountId.isNotEmpty) {
      target = _accounts.where((a) => a.id == accountId).firstOrNull;
    }
    target ??= _accounts.where((a) => !a.isArchived && a.accountType.isOperatingPool).firstOrNull ??
        _accounts.where((a) => !a.isArchived).firstOrNull;

    if (target != null) {
      final newBal = (target.balance - amount) >= 0 ? (target.balance - amount) : 0.0;
      optimisticUpdateBalance(target.id, newBal);
      if (persistToRemote) {
        try {
          await _service.updateBalance(target.id, newBal);
        } catch (e) {
          debugPrint('[AccountProvider] deductExpense updateBalance error: $e');
        }
      }
    }
  }

  /// Full refresh of accounts and cycle income from database.
  Future<void> refresh() async {
    final hid = _householdId;
    if (hid == null || hid.isEmpty) return;

    _isLoading = true;
    notifyListeners();

    try {
      try {
        await _service.reconcileUnlinkedTransactions(hid);
      } catch (_) {}

      final accFuture = _service.getAccounts(hid);
      final incFuture = _cycleKey != null && _cycleKey!.isNotEmpty
          ? _service.getCycleIncome(hid, _cycleKey!)
          : Future.value(<IncomeRecord>[]);
      final cfgIncFuture = _service.getHouseholdConfiguredIncome(hid);

      final results = await Future.wait([accFuture, incFuture, cfgIncFuture]);
      _accounts = results[0] as List<Account>;
      _cycleIncomeRecords = results[1] as List<IncomeRecord>;
      _configuredMonthlyIncome = results[2] as double;
      _hasLoaded = true;
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
    _configuredMonthlyIncome = null;
    _isLoading = false;
    _hasLoaded = false;
    _error = null;
    notifyListeners();
  }

  @visibleForTesting
  void setAccountsForTesting(List<Account> accounts, {String? householdId, String? cycleKey}) {
    _accounts = List.from(accounts);
    _householdId = householdId;
    if (cycleKey != null) _cycleKey = cycleKey;
    _hasLoaded = true;
    notifyListeners();
  }

  @visibleForTesting
  void setCycleIncomeForTesting(List<IncomeRecord> records, {String? cycleKey}) {
    _cycleIncomeRecords = List.from(records);
    _cycleKey = cycleKey;
    notifyListeners();
  }

  @visibleForTesting
  void setConfiguredMonthlyIncomeForTesting(double income) {
    _configuredMonthlyIncome = income;
    notifyListeners();
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    _streamSub = null;
    super.dispose();
  }
}
