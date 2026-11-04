import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/app_localizations.dart';
import '../../main.dart';
import '../../models/account.dart';
import '../../services/salary_cycle_service.dart';
import '../../theme/app_themes.dart';
import '../salary/payday_income_sheet.dart';

/// Looks up whether a salary income record was received for [householdId]
/// on or after [since].
typedef RecentSalaryLookup = Future<bool> Function(String householdId, DateTime since);

/// Dismissible banner shown from the household's payday and the days after it
/// if no salary has been logged yet for the current cycle.
class PaydayCheckinBanner extends StatefulWidget {
  final String householdId;

  /// The household's `payday_day`; null (not loaded yet, or unreadable) means
  /// the default payday.
  final int? paydayDay;

  /// Overrides the Supabase lookup (used by tests).
  final RecentSalaryLookup? salaryLookup;

  /// Overrides the clock (used by tests).
  final DateTime Function()? clock;

  const PaydayCheckinBanner({
    super.key,
    required this.householdId,
    this.paydayDay,
    this.salaryLookup,
    this.clock,
  });

  /// Column of `income_records` holding the income kind ('salary', 'bonus', ...).
  /// It is `source_type` (see IncomeRecord.toMap); an earlier version queried a
  /// non-existent `income_type` column, so the query always failed and the
  /// banner never appeared.
  static const String sourceTypeColumn = 'source_type';

  /// Days the window stays open after payday: the 27th to the 3rd at most.
  static const int windowFollowingDays = 7;

  /// Whether [now] falls in the payday window of a household paid on
  /// [paydayDay], by the Asia/Riyadh calendar date like the salary cycle.
  ///
  /// It opens on payday, clamped to the month's last day like the salary cycle,
  /// and closes on a fixed day of the month: [windowFollowingDays] after payday
  /// counted on a 31-day month (27 closes on the 3rd, 15 on the 22nd, 31 on the
  /// 7th). That is 8 days, and fewer when a shorter month's end falls inside it,
  /// exactly as the 27th to the 3rd is 5 days across a 28-day February.
  static bool isPaydayWindow(DateTime now, {int? paydayDay}) {
    final today = SalaryCycleService.riyadhDate(now);
    final payday = SalaryCycleService.normalizePayday(paydayDay);
    final lastDay = SalaryCycleService.daysInMonth(today.year, today.month);
    final opens = payday < lastDay ? payday : lastDay;
    final closes = payday + windowFollowingDays;
    return closes <= 31
        ? today.day >= opens && today.day <= closes
        : today.day >= opens || today.day <= closes - 31;
  }

  /// Default lookup against Supabase.
  static Future<bool> supabaseSalaryLookup(String householdId, DateTime since) async {
    final records = await supabase
        .from('income_records')
        .select('id')
        .eq('household_id', householdId)
        .eq(sourceTypeColumn, IncomeSourceType.salary.value)
        .gte('received_at', since.toIso8601String())
        .limit(1);
    return records.isNotEmpty;
  }

  @override
  State<PaydayCheckinBanner> createState() => _PaydayCheckinBannerState();
}

class _PaydayCheckinBannerState extends State<PaydayCheckinBanner> {
  bool _shouldShow = false;
  bool _checked = false;

  /// Dismissed or completed: stays closed if the payday reloads.
  bool _closed = false;

  /// Only the latest check may decide; an older lookup can finish after it.
  int _latestCheck = 0;

  @override
  void initState() {
    super.initState();
    _checkPaydayStatus();
  }

  @override
  void didUpdateWidget(PaydayCheckinBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The dashboard loads the household's payday after this banner can mount.
    if (SalaryCycleService.normalizePayday(oldWidget.paydayDay) !=
        SalaryCycleService.normalizePayday(widget.paydayDay)) {
      _checkPaydayStatus();
    }
  }

  Future<void> _checkPaydayStatus() async {
    final check = ++_latestCheck;
    final now = (widget.clock ?? DateTime.now)();
    if (!PaydayCheckinBanner.isPaydayWindow(now, paydayDay: widget.paydayDay)) {
      if (mounted) {
        setState(() {
          _shouldShow = false;
          _checked = true;
        });
      }
      return;
    }

    try {
      final since = now.subtract(const Duration(days: 20));
      final lookup = widget.salaryLookup ?? PaydayCheckinBanner.supabaseSalaryLookup;
      final hasSalary = await lookup(widget.householdId, since);

      if (mounted && check == _latestCheck) {
        setState(() {
          _shouldShow = !hasSalary;
          _checked = true;
        });
      }
    } catch (e, st) {
      // Do not fail silently: a broken query hides the banner for everyone.
      debugPrint('[PaydayCheckinBanner] salary lookup failed: $e');
      debugPrintStack(stackTrace: st, maxFrames: 5);
      if (mounted && check == _latestCheck) {
        setState(() {
          _shouldShow = false;
          _checked = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked || !_shouldShow || _closed) return const SizedBox.shrink();

    final isDark = context.isDark;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: context.icedHeroGradient.colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: context.borderColor,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: context.primaryButtonBg.withValues(alpha: isDark ? 0.35 : 0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: context.pillBg,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.celebration_rounded,
              color: context.accentText,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('payday_banner_title'),
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: context.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  context.tr('payday_banner_desc'),
                  style: TextStyle(
                    fontSize: 11,
                    color: context.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () {
              PaydayIncomeSheet.show(
                context,
                householdId: widget.householdId,
                onCompleted: () {
                  if (mounted) setState(() => _closed = true);
                },
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: context.accentText,
              foregroundColor: context.primaryButtonFg,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              minimumSize: const Size(48, 40),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: Text(
              context.tr('log_salary'),
              style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: context.tr('dismiss'),
            icon: Icon(Icons.close, size: 16, color: context.textSecondary),
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            padding: EdgeInsets.zero,
            onPressed: () => setState(() => _closed = true),
          ),
        ],
      ),
    );
  }
}
