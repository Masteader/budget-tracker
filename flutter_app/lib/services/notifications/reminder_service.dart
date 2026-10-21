/// Rebuilds the scheduled reminders from the household's data (R11).
///
/// [reschedule] is cheap to call often: it plans the reminders and touches
/// the platform only when the plan differs from the last one scheduled
/// (cancel all, then schedule the new set). [cancelAll] runs on sign-out.
library;

import 'package:flutter/widgets.dart';

import '../../l10n/app_localizations.dart';
import '../../models/installment_plan.dart';
import '../../models/recurring_bill.dart';
import 'reminder_notification_backend.dart';
import 'reminder_planner.dart';

class ReminderService {
  ReminderService({
    ReminderNotificationBackend? backend,
    DateTime Function()? clock,
    ReminderPlanner planner = const ReminderPlanner(),
  })  : _backend = backend ?? LocalNotificationsBackend(),
        _clock = clock ?? DateTime.now,
        _planner = planner;

  static ReminderService instance = ReminderService();

  final ReminderNotificationBackend _backend;
  final DateTime Function() _clock;
  final ReminderPlanner _planner;

  String? _scheduledSignature;
  List<PlannedReminder> _scheduled = const [];

  /// The reminders currently scheduled (for diagnostics and tests).
  List<PlannedReminder> get scheduled => _scheduled;

  /// Plans and, when anything changed, replaces the scheduled reminders.
  /// Returns the number of reminders scheduled. Never throws.
  Future<int> reschedule({
    required String householdId,
    required int paydayDay,
    required List<RecurringBillItem> bills,
    required List<InstallmentPlan> plans,
    required Set<ReminderType> enabled,
    required Locale locale,
  }) async {
    final l = AppLocalizations(locale);
    final plan = _planner.plan(
      now: _clock(),
      paydayDay: paydayDay,
      bills: bills,
      plans: plans,
      enabled: enabled,
      l: l,
    );
    final signature = [
      householdId,
      locale.languageCode,
      for (final r in plan) '${r.id}|${r.fireAtUtc.toIso8601String()}|${r.title}|${r.body}',
    ].join('\n');
    if (signature == _scheduledSignature) return plan.length;
    try {
      await _backend.initialize();
      await _backend.cancelAll();
      final channelName = l.get('notif_channel_name');
      final channelDescription = l.get('notif_channel_desc');
      for (final r in plan) {
        await _backend.schedule(r, channelName: channelName, channelDescription: channelDescription);
      }
      _scheduledSignature = signature;
      _scheduled = plan;
      return plan.length;
    } catch (e) {
      debugPrint('[Reminders] scheduling failed: $e');
      _scheduledSignature = null;
      return 0;
    }
  }

  /// Removes every scheduled reminder (sign-out, or all types switched off).
  Future<void> cancelAll() async {
    _scheduledSignature = null;
    _scheduled = const [];
    try {
      await _backend.cancelAll();
    } catch (e) {
      debugPrint('[Reminders] cancel failed: $e');
    }
  }
}
