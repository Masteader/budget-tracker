import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../l10n/app_localizations.dart';
import '../../services/notifications/reminder_planner.dart';
import '../../services/notifications/reminder_preferences.dart';
import '../../theme/app_themes.dart';
import '../app_snackbar.dart';

/// Asks for the notification permission; true when granted.
typedef NotificationPermissionRequest = Future<bool> Function();

Future<bool> _requestNotificationPermission() async {
  final status = await Permission.notification.status;
  if (status.isGranted) return true;
  return (await Permission.notification.request()).isGranted;
}

/// One switch per reminder type (payday, 3 days before payday, bills,
/// installments), stored on this device.
class ReminderSettingsCard extends StatelessWidget {
  final ReminderPreferences? preferences;
  final NotificationPermissionRequest requestPermission;

  const ReminderSettingsCard({
    super.key,
    this.preferences,
    this.requestPermission = _requestNotificationPermission,
  });

  static const _items = <(ReminderType, IconData, String, String)>[
    (ReminderType.payday, Icons.payments_outlined, 'reminder_payday', 'reminder_payday_desc'),
    (ReminderType.cycleEnd, Icons.hourglass_bottom_rounded, 'reminder_cycle_end', 'reminder_cycle_end_desc'),
    (ReminderType.bill, Icons.receipt_long_outlined, 'reminder_bills', 'reminder_bills_desc'),
    (ReminderType.installment, Icons.credit_score_rounded, 'reminder_installments', 'reminder_installments_desc'),
  ];

  Future<void> _toggle(BuildContext context, ReminderPreferences prefs, ReminderType type, bool value) async {
    await prefs.setEnabled(type, value);
    if (!value) return;
    bool granted;
    try {
      granted = await requestPermission();
    } catch (_) {
      granted = false;
    }
    if (!granted && context.mounted) {
      AppSnackBar.showInfo(context, context.tr('reminders_permission_denied'), title: context.tr('reminders_title'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefs = preferences ?? ReminderPreferences.instance;
    return ListenableBuilder(
      listenable: prefs,
      builder: (context, _) => Material(
        color: context.cardBg,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: context.borderColor),
        ),
        child: Column(
          children: [
            for (var i = 0; i < _items.length; i++) ...[
              if (i > 0) Divider(color: context.borderColor, height: 1),
              SwitchListTile(
                key: ValueKey('reminder_switch_${_items[i].$1.name}'),
                secondary: Icon(_items[i].$2, color: context.accentText),
                title: Text(
                  context.tr(_items[i].$3),
                  style: GoogleFonts.outfit(color: context.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
                ),
                subtitle: Text(context.tr(_items[i].$4), style: TextStyle(color: context.textSecondary, fontSize: 11.5)),
                value: prefs.isEnabled(_items[i].$1),
                activeThumbColor: context.accentText,
                activeTrackColor: context.accentText.withValues(alpha: 0.35),
                onChanged: (v) => _toggle(context, prefs, _items[i].$1, v),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
