import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../utils/failure_log.dart';
import '../widgets/dashboard/household_setup_card.dart' show HouseholdSetupPrefs;
import 'household_resolver.dart';
import 'notifications/reminder_service.dart';
import 'offline_queue_manager.dart';
import 'offline_sync_service.dart';
import 'receipt_storage_service.dart';
import 'salary_cycle_service.dart';
import 'statement_pdf_service.dart';

/// What this device remembers about a pending deletion of one account.
class AccountDeletionFlag {
  final DateTime scheduledFor;
  final List<String> householdIds;

  const AccountDeletionFlag({required this.scheduledFor, this.householdIds = const []});
}

/// Removes one account's data from this device: its offline queue rows and
/// blobs, cached household id, household checklist flags, cached payday, signed
/// receipt URLs, reminders and temporary statement PDFs. Theme and language are
/// the device's, not the account's, and stay. So does what another account queued.
///
/// When, per the plan's device rules: a flag is set per user when the deletion is
/// requested and removed on cancel. Signing out while flagged wipes everything
/// ([wipeForUser]), and so does the sign-out that follows a purge. At launch any
/// flagged user whose date has passed loses their own data ([wipeUserData]),
/// except the signed-in one, for whom the server decides
/// ([AccountDeletionProvider.load]); what the device shares between accounts is
/// left to the next sign-out, because another account may be signed in.
class LocalAccountDataCleaner {
  LocalAccountDataCleaner({
    OfflineQueueManager? queue,
    Future<void> Function()? cancelReminders,
    Future<void> Function()? deleteStatements,
    void Function()? clearSignedUrls,
  })  : _queue = queue,
        _cancelReminders = cancelReminders ?? ReminderService.instance.cancelAll,
        _deleteStatements = deleteStatements ?? StatementPdfService.deleteTemporaryStatements,
        _clearSignedUrls = clearSignedUrls ?? ReceiptStorageService.clearSignedUrlCache;

  final OfflineQueueManager? _queue;
  final Future<void> Function() _cancelReminders;
  final Future<void> Function() _deleteStatements;
  final void Function() _clearSignedUrls;

  static const String _flagPrefix = 'account_deletion_pending_';

  static String flagKey(String userId) => '$_flagPrefix$userId';

  Future<void> setFlag(String userId, DateTime scheduledFor, {Iterable<String> householdIds = const []}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      flagKey(userId),
      jsonEncode({
        'scheduled_for': scheduledFor.toUtc().toIso8601String(),
        'household_ids': householdIds.toList(),
      }),
    );
  }

  Future<AccountDeletionFlag?> readFlag(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return _parseFlag(prefs.getString(flagKey(userId)));
  }

  Future<void> clearFlag(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(flagKey(userId));
  }

  static AccountDeletionFlag? _parseFlag(String? raw) {
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final scheduledFor = DateTime.parse(map['scheduled_for'] as String);
      final ids = map['household_ids'];
      return AccountDeletionFlag(
        scheduledFor: scheduledFor,
        householdIds: ids is List ? ids.map((e) => e.toString()).toList() : const [],
      );
    } catch (_) {
      return null;
    }
  }

  /// Runs [action] as one step of a wipe: a failure is logged and reported as
  /// false, and never stops the steps after it.
  static Future<bool> _step(String name, Future<void> Function() action) async {
    try {
      await action();
      return true;
    } catch (e) {
      logFailure('LocalAccountDataCleaner.$name', e);
      return false;
    }
  }

  /// What only [userId] owns, so it is safe while another account is signed in:
  /// their offline queue items and blobs and their cached active household. The
  /// flag goes when both worked, unless [keepFlag]: then [wipeForUser] still has
  /// to run once nobody is signed in. Returns whether both worked.
  Future<bool> wipeUserData(String userId, {bool keepFlag = false}) async {
    var complete = await _step('queue', () async {
      final queue = _queue;
      if (queue != null) {
        await queue.clearForUser(userId);
      } else {
        final sync = OfflineSyncService.instance;
        await sync.queueManager.clearForUser(userId);
        await sync.updatePendingCount();
      }
    });
    complete &= await _step('activeHousehold', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(HouseholdResolver.cacheKeyFor(userId));
    });
    if (complete && !keepFlag) await clearFlag(userId);
    return complete;
  }

  /// Removes everything this device kept for [userId]. Only when nobody is
  /// signed in ([AccountDeletionProvider.handleSignedOut]): besides the user's
  /// own data it clears what the device shares between accounts, namely the
  /// checklist flags of the user's households, the cached payday, every
  /// scheduled reminder, temporary statements and signed receipt URLs.
  ///
  /// Each step runs on its own so one failure cannot leave the rest behind. The
  /// flag goes only when every step worked, so the launch check can try again.
  /// Returns whether everything was removed.
  Future<bool> wipeForUser(String userId, {Iterable<String> householdIds = const []}) async {
    // Read before [wipeUserData] drops the cached active household.
    final households = await _householdsOf(userId, householdIds);
    var complete = await wipeUserData(userId, keepFlag: true);
    complete &= await _step('householdPrefs', () async {
      final prefs = await SharedPreferences.getInstance();
      for (final household in households) {
        await prefs.remove(HouseholdSetupPrefs.paydayConfirmedKey(household));
        await prefs.remove(HouseholdSetupPrefs.hiddenKey(household));
      }
    });
    complete &= await _step('payday', () async {
      // The next account on this device must not inherit this household's payday.
      SalaryCycleService.paydayDay = SalaryCycleService.defaultPaydayDay;
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(SalaryCycleService.paydayPrefKey);
    });
    complete &= await _step('reminders', _cancelReminders);
    complete &= await _step('statements', _deleteStatements);
    complete &= await _step('signedUrls', () async => _clearSignedUrls());

    if (complete) await clearFlag(userId);
    return complete;
  }

  /// [householdIds], the households in the flag and the cached active one.
  Future<Set<String>> _householdsOf(String userId, Iterable<String> householdIds) async {
    final households = <String>{...householdIds};
    try {
      final prefs = await SharedPreferences.getInstance();
      households.addAll(_parseFlag(prefs.getString(flagKey(userId)))?.householdIds ?? const []);
      final active = prefs.getString(HouseholdResolver.cacheKeyFor(userId));
      if (active != null) households.add(active);
    } catch (e) {
      logFailure('LocalAccountDataCleaner.households', e);
    }
    return households;
  }

  /// Wipes the own data ([wipeUserData]) of every flagged user whose date has
  /// passed, except [exceptUserId]. Nothing the device shares between accounts:
  /// someone else may be signed in, with their own payday and reminders, in a
  /// household the flagged user also belonged to. Returns who was wiped.
  Future<List<String>> wipeDueUsers({required DateTime now, String? exceptUserId}) async {
    final prefs = await SharedPreferences.getInstance();
    final wiped = <String>[];
    for (final key in prefs.getKeys().where((k) => k.startsWith(_flagPrefix)).toList()) {
      final userId = key.substring(_flagPrefix.length);
      if (userId == exceptUserId) continue;
      final flag = _parseFlag(prefs.getString(key));
      if (flag == null || flag.scheduledFor.isAfter(now)) continue;
      await wipeUserData(userId);
      wiped.add(userId);
    }
    return wiped;
  }
}
