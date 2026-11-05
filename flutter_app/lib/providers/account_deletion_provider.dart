import 'package:flutter/foundation.dart';

import '../models/account_deletion.dart';
import '../services/account_deletion_service.dart';
import '../services/local_account_data_cleaner.dart';
import '../utils/failure_log.dart';

/// The signed-in user's account deletion: the status the Settings section shows
/// at all times, the deletion marks the dashboard banner shows, and the device
/// flag that decides when local data is wiped.
///
/// `households` is not in the realtime publication, so marks change on the next
/// load or app resume, or right after this user's own request or cancel.
class AccountDeletionProvider extends ChangeNotifier {
  AccountDeletionProvider({
    AccountDeletionService? service,
    LocalAccountDataCleaner? cleaner,
    String? Function()? currentUserId,
    DateTime Function()? clock,
    Future<void> Function()? signOut,
  })  : _service = service ?? AccountDeletionService(),
        _cleaner = cleaner ?? LocalAccountDataCleaner(),
        _clock = clock ?? DateTime.now {
    _currentUserId = currentUserId ?? () => _service.currentUserId;
    _signOut = signOut ?? _service.signOut;
  }

  final AccountDeletionService _service;
  final LocalAccountDataCleaner _cleaner;
  final DateTime Function() _clock;
  late final String? Function() _currentUserId;
  late final Future<void> Function() _signOut;

  AccountDeletionStatus _status = AccountDeletionStatus.none;
  bool _isLoaded = false;
  bool _isFromDevice = false;
  String? _loadedUserId;
  String? _trackedHouseholdId;
  final Map<String, DateTime> _marks = {};

  /// Bumped by [reset]: an answer that started before it belongs to a session
  /// that has ended.
  int _generation = 0;

  /// The flow's re-authentication calls.
  AccountDeletionService get service => _service;

  AccountDeletionStatus get status => _status;

  /// The server answered at least once, or this device remembers a request.
  bool get isLoaded => _isLoaded;

  /// The status comes from this device because the server could not be reached.
  bool get isFromDevice => _isFromDevice;

  bool get isPending => _status.isPending;

  /// The date [householdId] is marked for deletion, or null when it is not.
  DateTime? householdDeletionDate(String householdId) => _marks[householdId];

  /// Reads the status. Offline, a user this device knows is pending still sees
  /// the date and Cancel; the server decides when they press it.
  Future<void> load() async {
    final userId = _currentUserId();
    if (userId == null) return;
    final generation = _generation;
    if (_loadedUserId != null && _loadedUserId != userId) {
      _status = AccountDeletionStatus.none;
      _isLoaded = false;
      _isFromDevice = false;
      _marks.clear();
      _trackedHouseholdId = null;
    }
    _loadedUserId = userId;
    try {
      final status = await _service.getStatus();
      if (generation != _generation) return;
      await _applyServerStatus(userId, status);
      if (generation != _generation) return;
      _status = status;
      _isLoaded = true;
      _isFromDevice = false;
    } catch (e) {
      logFailure('AccountDeletion.load', e);
      if (generation != _generation) return;
      final flag = await _readFlagSafely(userId);
      if (generation != _generation) return;
      if (flag != null) {
        _status = AccountDeletionStatus.fromDeviceFlag(flag.scheduledFor);
        _isLoaded = true;
        _isFromDevice = true;
      }
    }
    notifyListeners();
  }

  Future<AccountDeletionFlag?> _readFlagSafely(String userId) async {
    try {
      return await _cleaner.readFlag(userId);
    } catch (e) {
      logFailure('AccountDeletion.readFlag', e);
      return null;
    }
  }

  /// Keeps the device flag in step with what the server says.
  Future<void> _applyServerStatus(String userId, AccountDeletionStatus status) async {
    final flag = await _readFlagSafely(userId);
    if (status.isPending) {
      final scheduledFor = status.scheduledFor;
      if (scheduledFor == null) return;
      var householdIds = flag?.householdIds ?? const <String>[];
      if (householdIds.isEmpty) householdIds = await _knownHouseholdIds();
      await _cleaner.setFlag(userId, scheduledFor, householdIds: householdIds);
      return;
    }
    if (flag == null) return;
    if (flag.scheduledFor.isAfter(_clock())) {
      await _cleaner.clearFlag(userId);
      return;
    }
    // Past the date and nothing pending: purged (the JWT outlives the account) or
    // cancelled at the last moment. Only a purge may cost unsynced items.
    final bool accountExists;
    try {
      accountExists = await _service.accountRowExists();
    } catch (e) {
      logFailure('AccountDeletion.accountRowExists', e);
      return;
    }
    if (accountExists) {
      await _cleaner.clearFlag(userId);
      return;
    }
    // Purged. Their own data goes now; the flag stays so that the sign-out below
    // makes [handleSignedOut] clear what the device shares too, once nobody is
    // signed in. If the sign-out fails, the next launch comes back here.
    await _cleaner.wipeUserData(userId, keepFlag: true);
    try {
      await _signOut();
    } catch (e) {
      logFailure('AccountDeletion.signOutPurged', e);
    }
  }

  Future<List<String>> _knownHouseholdIds() async {
    try {
      final preflight = await _service.getPreflight();
      return preflight.households.map((h) => h.id).toList();
    } catch (e) {
      logFailure('AccountDeletion.knownHouseholds', e);
      return const [];
    }
  }

  /// Reads the deletion mark of the household on screen. Returns true when the
  /// server answered with no row: it is gone, or no longer the active one. A
  /// failed read is not that, and keeps the last answer.
  Future<bool> loadHouseholdMark(String householdId) async {
    _trackedHouseholdId = householdId;
    final generation = _generation;
    final HouseholdDeletionMark mark;
    try {
      mark = await _service.readHouseholdMark(householdId);
    } catch (e) {
      logFailure('AccountDeletion.householdMark', e);
      return false;
    }
    if (generation != _generation) return false;
    final before = _marks[householdId];
    final date = mark.scheduledFor;
    if (date == null) {
      _marks.remove(householdId);
    } else {
      _marks[householdId] = date;
    }
    if (before != date) notifyListeners();
    return !mark.readable;
  }

  /// Rereads everything when the app comes back. Returns true when the household
  /// on screen has vanished and the app must resolve the active one again.
  Future<bool> refreshOnResume() async {
    await load();
    final householdId = _trackedHouseholdId;
    if (householdId == null) return false;
    return loadHouseholdMark(householdId);
  }

  /// What the flow's first step shows.
  Future<AccountDeletionPreflight> loadPreflight() => _service.getPreflight();

  /// Schedules the deletion. Throws [AccountDeletionException] when refused, and
  /// nothing has changed then.
  Future<AccountDeletionStatus> requestDeletion({
    required String confirmation,
    required List<HouseholdDeletionChoice> choices,
    required String locale,
  }) async {
    final status = await _service.request(confirmation: confirmation, choices: choices, locale: locale);
    final userId = _currentUserId();
    if (userId != null) {
      try {
        await _applyServerStatus(userId, status);
      } catch (e) {
        // The request stands; the next load writes the flag.
        logFailure('AccountDeletion.setFlag', e);
      }
    }
    _status = status;
    _isLoaded = true;
    _isFromDevice = false;
    notifyListeners();
    await _refreshTrackedHousehold();
    return status;
  }

  /// Cancels the deletion: signing in never does. Throws
  /// [AccountDeletionException] when refused (`deletion_in_progress`), and the
  /// status then says so.
  Future<void> cancelDeletion() async {
    final marked = _status.markedHouseholds.map((h) => h.id).toList();
    try {
      await _service.cancel();
    } on AccountDeletionException catch (e) {
      if (e.code == 'deletion_in_progress') await load();
      rethrow;
    }
    final userId = _currentUserId();
    if (userId != null) {
      try {
        await _cleaner.clearFlag(userId);
      } catch (e) {
        // The next load sees nothing pending and removes it.
        logFailure('AccountDeletion.clearFlag', e);
      }
    }
    _status = AccountDeletionStatus.none;
    _isLoaded = true;
    _isFromDevice = false;
    // This user's own marks ended with the request, whatever the read below does.
    marked.forEach(_marks.remove);
    notifyListeners();
    await _refreshTrackedHousehold();
  }

  Future<void> _refreshTrackedHousehold() async {
    final householdId = _trackedHouseholdId;
    if (householdId != null) await loadHouseholdMark(householdId);
  }

  /// [userId] has signed out, so nobody is signed in. If they were pending (or
  /// purged: [load] signs them out), this device forgets them, including what it
  /// shares between accounts; otherwise their data stays, because unsynced
  /// items wait for them.
  Future<void> handleSignedOut(String userId) async {
    reset();
    try {
      final flag = await _cleaner.readFlag(userId);
      if (flag != null) await _cleaner.wipeForUser(userId, householdIds: flag.householdIds);
    } catch (e) {
      logFailure('AccountDeletion.handleSignedOut', e);
    }
  }

  /// Launch check for accounts that signed out or were purged while away. Only
  /// their own data goes: the signed-in user's payday and reminders stay.
  Future<void> wipeDueUsers() async {
    try {
      await _cleaner.wipeDueUsers(now: _clock(), exceptUserId: _currentUserId());
    } catch (e) {
      logFailure('AccountDeletion.wipeDueUsers', e);
    }
  }

  void reset() {
    _generation++;
    _status = AccountDeletionStatus.none;
    _isLoaded = false;
    _isFromDevice = false;
    _loadedUserId = null;
    _trackedHouseholdId = null;
    _marks.clear();
    notifyListeners();
  }
}
