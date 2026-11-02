import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/account.dart';
import '../models/operating_cash.dart';
import '../services/account_service.dart';
import '../services/commitments_service.dart';
import '../services/salary_cycle_service.dart';

abstract interface class IncomeSource {
  Future<List<IncomeRecord>> getCycleIncome(String householdId, String cycleKey);
  Future<double> getHouseholdConfiguredIncome(String householdId);
}

class AccountServiceIncomeSource implements IncomeSource {
  final AccountService _service;
  AccountServiceIncomeSource([AccountService? service]) : _service = service ?? AccountService.instance;

  @override
  Future<List<IncomeRecord>> getCycleIncome(String householdId, String cycleKey) =>
      _service.getCycleIncome(householdId, cycleKey);

  @override
  Future<double> getHouseholdConfiguredIncome(String householdId) =>
      _service.getHouseholdConfiguredIncome(householdId);
}

/// Central single source of truth provider for household accounts, liquidity,
/// commitments, operating cash, and cycle income.
class AccountProvider extends ChangeNotifier {
  final AccountService _accountsService;
  final CommitmentsService _commitmentsService;
  final IncomeSource _incomeSource;

  StreamSubscription<List<Account>>? _streamSub;

  String? _householdId;
  int _paydayDay = SalaryCycleService.defaultPaydayDay;
  String? _cycleKey;

  List<Account> _accounts = [];
  List<IncomeRecord> _cycleIncomeRecords = [];
  List<PendingCommitment> _lastCommitments = [];
  double? _configuredMonthlyIncome;

  OperatingCashSnapshot _snapshot = OperatingCashSnapshot.empty;

  bool _isLoading = false;
  bool _hasLoaded = false;
  String? _error;
  bool _disposed = false;

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  Future<void>? _inFlight;
  bool _pendingForce = false;
  int _generation = 0;
  int _bindEpoch = 0;

  AccountProvider({
    AccountService? accounts,
    AccountService? service, // legacy param alias
    CommitmentsService? commitments,
    IncomeSource? income,
  })  : _accountsService = accounts ?? service ?? AccountService.instance,
        _commitmentsService = commitments ?? CommitmentsService.instance,
        _incomeSource = income ?? AccountServiceIncomeSource(accounts ?? service ?? AccountService.instance);

  String? get householdId => _householdId;
  int get paydayDay => _paydayDay;
  String? get cycleKey => _cycleKey;

  List<Account> get accounts => List.unmodifiable(_accounts);
  List<IncomeRecord> get cycleIncomeRecords => List.unmodifiable(_cycleIncomeRecords);
  double? get configuredMonthlyIncome => _configuredMonthlyIncome;

  OperatingCashSnapshot get snapshot => _snapshot;

  bool get isLoading => _isLoading;
  bool get hasLoaded => _hasLoaded;
  String? get error => _error;

  /// Derived backwards-compatible getters driven by snapshot:
  double get operatingCash => _snapshot.operatingCash;
  double get cycleIncomeTotal => _snapshot.cycleIncome;
  double get effectiveCycleIncome => cycleIncomeTotal;
  int get accountsCount => _snapshot.accountsCount;

  /// Total net worth across all non-archived accounts.
  double get totalNetWorth => _accounts
      .where((a) => !a.isArchived)
      .fold<double>(0.0, (s, a) => s + a.balance);

  void _publishSnapshot({
    required String householdId,
    required String cycleKey,
    required List<Account> accounts,
    required List<PendingCommitment> commitments,
    required int cycleIncomeHalalas,
  }) {
    _snapshot = OperatingCashCalculator.compute(
      householdId: householdId,
      cycleKey: cycleKey,
      accounts: accounts,
      commitments: commitments,
      cycleIncomeHalalas: cycleIncomeHalalas,
    );
  }

  /// Binds provider to a household and resets any prior household state cleanly.
  void bindHousehold(String householdId, {required int paydayDay}) {
    if (_householdId != householdId) {
      _bindEpoch++;
      _householdId = householdId;
      _paydayDay = paydayDay;
      _cycleKey = SalaryCycleService.cycleKeyForInstant(DateTime.now(), paydayDay: paydayDay);
      _accounts = [];
      _cycleIncomeRecords = [];
      _lastCommitments = [];
      _snapshot = OperatingCashSnapshot.empty;
      _configuredMonthlyIncome = null;
      _hasLoaded = false;
      _isLoading = false;
      _error = null;
      _generation++;
      _inFlight = null;
      _pendingForce = false;
      notifyListeners();
      _listenToRealtime(householdId);
    } else if (_paydayDay != paydayDay) {
      onPaydayChanged(paydayDay);
    }
  }

  /// Sets active cycle key and triggers refresh if household is bound.
  Future<void> setCycleKey(String cycleKey) async {
    if (_cycleKey == cycleKey) return;
    _cycleKey = cycleKey;
    if (_householdId != null && _householdId!.isNotEmpty) {
      await refresh(force: true);
    }
  }

  /// Backwards-compatible init method.
  Future<void> init(String householdId, String cycleKey, {int? paydayDay}) async {
    final targetPayday = paydayDay ?? _paydayDay;
    if (_householdId != householdId || _paydayDay != targetPayday) {
      bindHousehold(householdId, paydayDay: targetPayday);
    }
    _cycleKey = cycleKey;
    await ensureLoaded();
  }

  /// Ensures data is loaded for the bound household; returns immediately if already cached.
  Future<void> ensureLoaded([String? householdId]) async {
    if (householdId != null && householdId != _householdId) {
      bindHousehold(householdId, paydayDay: _paydayDay);
    }
    if (_hasLoaded) return;
    return refresh();
  }

  /// Refreshes accounts, commitments, and income from remote sources.
  /// Deduplicates in-flight calls and queues forced refreshes sequentially.
  Future<void> refresh({bool force = false}) {
    final hid = _householdId;
    if (hid == null || hid.isEmpty) return Future.value();

    if (_inFlight != null) {
      if (force) {
        _pendingForce = true;
      }
      return _inFlight!;
    }

    final completer = Completer<void>();
    final myFuture = completer.future;
    _inFlight = myFuture;
    final myEpoch = _bindEpoch;

    () async {
      try {
        await _executeLoad();
        while (_pendingForce && myEpoch == _bindEpoch && hid == _householdId) {
          _pendingForce = false;
          await _executeLoad();
        }
      } catch (_) {
        // Errors are stored in _error property; never rethrow from refresh
      } finally {
        if (identical(_inFlight, myFuture)) {
          _inFlight = null;
        }
        if (!completer.isCompleted) completer.complete();
      }
    }();

    return _inFlight!;
  }

  Future<void> _executeLoad() async {
    final hid = _householdId;
    if (hid == null || hid.isEmpty) return;

    final gen = ++_generation;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final curCycleKey = _cycleKey ??
          SalaryCycleService.cycleKeyForInstant(DateTime.now(), paydayDay: _paydayDay);

      Object? commitmentsError;
      Future<List<PendingCommitment>> fetchCommitmentsSafe() async {
        try {
          return await _commitmentsService.getPendingCommitments(
            householdId: hid,
            paydayDay: _paydayDay,
            cycleKey: curCycleKey,
          );
        } catch (err) {
          commitmentsError = err;
          return _lastCommitments;
        }
      }

      final results = await Future.wait([
        _accountsService.getAccounts(hid),
        fetchCommitmentsSafe(),
        _fetchIncome(hid, curCycleKey),
      ]);

      if (gen != _generation || hid != _householdId) {
        return; // Stale response discarded
      }

      final fetchedAccounts = results[0] as List<Account>;
      final fetchedCommitments = results[1] as List<PendingCommitment>;
      final incomeData = results[2] as ({List<IncomeRecord> records, double totalIncome, double? configured});

      if (gen != _generation || hid != _householdId) {
        return; // Stale response discarded
      }

      _configuredMonthlyIncome = incomeData.configured ?? _configuredMonthlyIncome;
      _accounts = fetchedAccounts;
      _lastCommitments = fetchedCommitments;
      _cycleIncomeRecords = incomeData.records;

      _publishSnapshot(
        householdId: hid,
        cycleKey: curCycleKey,
        accounts: fetchedAccounts,
        commitments: fetchedCommitments,
        cycleIncomeHalalas: OperatingCashCalculator.toHalalas(incomeData.totalIncome),
      );

      _hasLoaded = true;
      _error = commitmentsError?.toString();
    } catch (e) {
      if (gen == _generation && hid == _householdId) {
        _error = e.toString();
      }
    } finally {
      if (gen == _generation && hid == _householdId) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<({List<IncomeRecord> records, double totalIncome, double? configured})> _fetchIncome(
      String hid, String curCycleKey) async {
    List<IncomeRecord> records = [];
    try {
      records = await _incomeSource.getCycleIncome(hid, curCycleKey);
    } catch (_) {}

    double sum = records.fold<double>(0.0, (s, r) => s + r.netAmount);
    double? configured;
    if (sum <= 0) {
      try {
        configured = await _incomeSource.getHouseholdConfiguredIncome(hid);
        sum = configured;
      } catch (_) {
        sum = 0.0;
      }
    }
    return (records: records, totalIncome: sum, configured: configured);
  }

  /// Handles household payday changes by recomputing the active cycle key and refreshing.
  Future<void> onPaydayChanged(int paydayDay) async {
    _paydayDay = paydayDay;
    _cycleKey = SalaryCycleService.cycleKeyForInstant(DateTime.now(), paydayDay: paydayDay);
    if (_householdId != null && _householdId!.isNotEmpty) {
      await refresh(force: true);
    }
  }

  void _listenToRealtime(String householdId) {
    _streamSub?.cancel();
    _streamSub = _accountsService.streamAccounts(householdId).listen(
      (list) {
        if (_householdId != householdId) return;
        _accounts = list;
        _publishSnapshot(
          householdId: householdId,
          cycleKey: _cycleKey ?? '',
          accounts: list,
          commitments: _lastCommitments,
          cycleIncomeHalalas: _snapshot.cycleIncomeHalalas,
        );
        notifyListeners();
      },
      onError: (err) {
        if (_householdId != householdId) return;
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

      _publishSnapshot(
        householdId: _householdId ?? '',
        cycleKey: _cycleKey ?? '',
        accounts: _accounts,
        commitments: _lastCommitments,
        cycleIncomeHalalas: _snapshot.cycleIncomeHalalas,
      );
      notifyListeners();
    }
  }

  /// Deduct an expense from the given account optimistically.
  /// Realtime CDC reconciles server-side balance changes.
  Future<void> deductExpense({
    String? accountId,
    required double amount,
    String? nafaqahClass,
    String? spouseId,
  }) async {
    if (amount <= 0 || _accounts.isEmpty) return;
    if (accountId == null || accountId.isEmpty) return;

    final target = _accounts.where((a) => a.id == accountId).firstOrNull;
    if (target == null) return;
    if (target.isArchived || !target.accountType.isOperatingPool) return;

    if (nafaqahClass == 'wife_personal' || nafaqahClass == 'wife_reimbursable') {
      final isSpousePersonal = !target.isSharedPool && target.ownerUserId == spouseId;
      if (!isSpousePersonal) return;
    }

    final newBal = target.balance - amount;
    optimisticUpdateBalance(target.id, newBal);
  }

  /// Voids an income record, reverses the credited account balance, and forces a refresh of snapshot and accounts.
  Future<void> voidIncomeRecord(String incomeId, [String? householdId]) async {
    if (householdId != null && householdId.isNotEmpty && householdId != _householdId) {
      bindHousehold(householdId, paydayDay: _paydayDay);
    }
    await _accountsService.voidIncomeRecord(incomeId);
    await refresh(force: true);
  }

  /// Clean teardown on sign-out or household switch.
  void reset() {
    _bindEpoch++;
    _streamSub?.cancel();
    _streamSub = null;
    _householdId = null;
    _cycleKey = null;
    _accounts = [];
    _cycleIncomeRecords = [];
    _lastCommitments = [];
    _snapshot = OperatingCashSnapshot.empty;
    _configuredMonthlyIncome = null;
    _isLoading = false;
    _hasLoaded = false;
    _error = null;
    _generation++;
    _inFlight = null;
    _pendingForce = false;
    notifyListeners();
  }

  @visibleForTesting
  void setAccountsForTesting(
    List<Account> accounts, {
    String? householdId,
    String? cycleKey,
    List<PendingCommitment>? commitments,
    int? cycleIncomeHalalas,
  }) {
    _accounts = List.from(accounts);
    if (householdId != null) _householdId = householdId;
    if (cycleKey != null) _cycleKey = cycleKey;
    _lastCommitments = commitments ?? _lastCommitments;
    _hasLoaded = true;

    final hid = _householdId ?? 'test-hh';
    final cKey = _cycleKey ?? '2026-11';
    final income = cycleIncomeHalalas ??
        OperatingCashCalculator.toHalalas(_calculateTestingIncome());

    _publishSnapshot(
      householdId: hid,
      cycleKey: cKey,
      accounts: _accounts,
      commitments: _lastCommitments,
      cycleIncomeHalalas: income,
    );
    notifyListeners();
  }

  @visibleForTesting
  void setCycleIncomeForTesting(List<IncomeRecord> records, {String? cycleKey}) {
    _cycleIncomeRecords = List.from(records);
    if (cycleKey != null) _cycleKey = cycleKey;
    _recomputeTestingSnapshot();
    notifyListeners();
  }

  @visibleForTesting
  void setConfiguredMonthlyIncomeForTesting(double income) {
    _configuredMonthlyIncome = income;
    _recomputeTestingSnapshot();
    notifyListeners();
  }

  double _calculateTestingIncome() {
    final sum = _cycleIncomeRecords.fold<double>(0.0, (s, r) => s + r.netAmount);
    if (sum > 0) return sum;
    return _configuredMonthlyIncome ?? 0.0;
  }

  void _recomputeTestingSnapshot() {
    final hid = _householdId ?? 'test-hh';
    final cKey = _cycleKey ?? '2026-11';
    _publishSnapshot(
      householdId: hid,
      cycleKey: cKey,
      accounts: _accounts,
      commitments: _lastCommitments,
      cycleIncomeHalalas: OperatingCashCalculator.toHalalas(_calculateTestingIncome()),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _streamSub?.cancel();
    _streamSub = null;
    super.dispose();
  }
}
