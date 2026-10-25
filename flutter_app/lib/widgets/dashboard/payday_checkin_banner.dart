import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/app_localizations.dart';
import '../../main.dart';
import '../../models/account.dart';
import '../../theme/app_themes.dart';
import '../salary/payday_income_sheet.dart';

/// Looks up whether a salary income record was received for [householdId]
/// on or after [since].
typedef RecentSalaryLookup = Future<bool> Function(String householdId, DateTime since);

/// Dismissible banner shown around payday (e.g. 25th-31st or 1st-3rd)
/// if no salary has been logged yet for the current cycle.
class PaydayCheckinBanner extends StatefulWidget {
  final String householdId;

  /// Overrides the Supabase lookup (used by tests).
  final RecentSalaryLookup? salaryLookup;

  /// Overrides the clock (used by tests).
  final DateTime Function()? clock;

  const PaydayCheckinBanner({
    super.key,
    required this.householdId,
    this.salaryLookup,
    this.clock,
  });

  /// Column of `income_records` holding the income kind ('salary', 'bonus', ...).
  /// It is `source_type` (see IncomeRecord.toMap); an earlier version queried a
  /// non-existent `income_type` column, so the query always failed and the
  /// banner never appeared.
  static const String sourceTypeColumn = 'source_type';

  /// Whether [now] falls in the typical Saudi payday window (27th to 3rd).
  /// Saudi public/private salary deposits occur on the 27th of the month.
  static bool isPaydayWindow(DateTime now) => now.day >= 27 || now.day <= 3;

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

  @override
  void initState() {
    super.initState();
    _checkPaydayStatus();
  }

  Future<void> _checkPaydayStatus() async {
    final now = (widget.clock ?? DateTime.now)();
    if (!PaydayCheckinBanner.isPaydayWindow(now)) {
      if (mounted) setState(() => _checked = true);
      return;
    }

    try {
      final since = now.subtract(const Duration(days: 20));
      final lookup = widget.salaryLookup ?? PaydayCheckinBanner.supabaseSalaryLookup;
      final hasSalary = await lookup(widget.householdId, since);

      if (mounted) {
        setState(() {
          _shouldShow = !hasSalary;
          _checked = true;
        });
      }
    } catch (e, st) {
      // Do not fail silently: a broken query hides the banner for everyone.
      debugPrint('[PaydayCheckinBanner] salary lookup failed: $e');
      debugPrintStack(stackTrace: st, maxFrames: 5);
      if (mounted) setState(() => _checked = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked || !_shouldShow) return const SizedBox.shrink();

    final isDark = context.isDark;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF4A0E1E), const Color(0xFF2A050E)]
              : [const Color(0xFFFFF1F4), const Color(0xFFFCEEF2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0x40F0A3BC) : const Color(0xFFF2DCE2),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4A0E1E).withValues(alpha: isDark ? 0.35 : 0.08),
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
              color: isDark ? const Color(0xFF5E1327) : const Color(0xFFFCEEF2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.celebration_rounded,
              color: isDark ? const Color(0xFFF0A3BC) : const Color(0xFF4A0E1E),
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
                  if (mounted) setState(() => _shouldShow = false);
                },
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: isDark ? const Color(0xFFF0A3BC) : const Color(0xFF4A0E1E),
              foregroundColor: isDark ? const Color(0xFF1E040B) : Colors.white,
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
            onPressed: () => setState(() => _shouldShow = false),
          ),
        ],
      ),
    );
  }
}
