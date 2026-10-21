/// The device side of reminders: flutter_local_notifications with inexact
/// scheduling (no exact-alarm permission) on the Asia/Riyadh time zone.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_10y.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'reminder_planner.dart';

/// What the reminder service needs from the platform (faked in tests).
abstract class ReminderNotificationBackend {
  Future<void> initialize();
  Future<void> cancelAll();
  Future<void> schedule(PlannedReminder reminder, {required String channelName, required String channelDescription});
}

class LocalNotificationsBackend implements ReminderNotificationBackend {
  LocalNotificationsBackend({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const String channelId = 'budget_reminders';

  /// res/drawable/ic_stat_reminder.xml (monochrome small icon).
  static const String smallIcon = 'ic_stat_reminder';

  final FlutterLocalNotificationsPlugin _plugin;
  tz.Location? _riyadh;
  bool _initialized = false;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    tzdata.initializeTimeZones();
    _riyadh = tz.getLocation('Asia/Riyadh');
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings(smallIcon),
        // Permission is asked from the settings screen, never at launch.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _initialized = true;
  }

  @override
  Future<void> cancelAll() async {
    if (!_initialized) await initialize();
    await _plugin.cancelAll();
  }

  @override
  Future<void> schedule(PlannedReminder reminder, {required String channelName, required String channelDescription}) async {
    if (!_initialized) await initialize();
    final when = tz.TZDateTime.from(reminder.fireAtUtc, _riyadh!);
    await _plugin.zonedSchedule(
      reminder.id,
      reminder.title,
      reminder.body,
      when,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          channelDescription: channelDescription,
          icon: smallIcon,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          styleInformation: BigTextStyleInformation(reminder.body),
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      // Inexact: no SCHEDULE_EXACT_ALARM permission; a few minutes late is fine.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      payload: reminder.type.name,
    );
    debugPrint('[Reminders] scheduled ${reminder.type.name} #${reminder.id} at $when');
  }
}
