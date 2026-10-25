import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_themes.dart';

/// "Today / Yesterday / Pick a date…" for an expense (UX-12), so yesterday's
/// cash purchase is not booked today. Today keeps the current time; another
/// day keeps the current time of day on that date.
class ExpenseDateChips extends StatelessWidget {
  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  /// How far back a date may be picked (the server accepts 90 days for chat).
  final int maxDaysBack;

  /// The clock (tests).
  final DateTime Function() now;

  const ExpenseDateChips({
    super.key,
    required this.value,
    required this.onChanged,
    this.maxDaysBack = 89,
    this.now = DateTime.now,
  });

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime _onDay(DateTime day, DateTime clock) =>
      DateTime(day.year, day.month, day.day, clock.hour, clock.minute, clock.second);

  @override
  Widget build(BuildContext context) {
    final clock = now();
    final today = _day(clock);
    final yesterday = today.subtract(const Duration(days: 1));
    final chosen = _day(value);
    final isToday = chosen == today;
    final isYesterday = chosen == yesterday;
    final isOther = !isToday && !isYesterday;

    Widget chip(String key, String label, bool selected, VoidCallback onTap, {IconData? icon}) => ChoiceChip(
          key: ValueKey(key),
          avatar: icon == null
              ? null
              : Icon(icon, size: 16, color: selected ? (context.isDark ? const Color(0xFFF0A3BC) : Colors.white) : context.textSecondary),
          label: Text(label),
          selected: selected,
          showCheckmark: false,
          selectedColor: context.isDark ? const Color(0xFF5E1327) : const Color(0xFF4A0E1E),
          labelStyle: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? (context.isDark ? const Color(0xFFF0A3BC) : Colors.white) : context.textPrimary,
          ),
          onSelected: (_) => onTap(),
        );

    return Semantics(
      label: context.tr('expense_date_label'),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Icon(Icons.event_rounded, size: 18, color: context.textSecondary),
          chip('expense_date_today', context.tr('feed_today'), isToday, () => onChanged(clock)),
          chip('expense_date_yesterday', context.tr('feed_yesterday'), isYesterday, () => onChanged(_onDay(yesterday, clock))),
          chip(
            'expense_date_pick',
            isOther ? context.fmtDate(chosen, 'd MMMM') : context.tr('expense_date_pick'),
            isOther,
            () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: chosen.isAfter(today) ? today : chosen,
                firstDate: today.subtract(Duration(days: maxDaysBack)),
                lastDate: today,
              );
              if (picked != null) onChanged(_day(picked) == today ? clock : _onDay(picked, clock));
            },
            icon: Icons.calendar_month_rounded,
          ),
        ],
      ),
    );
  }
}
