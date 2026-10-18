import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/app_localizations.dart';
import '../../main.dart';
import '../../theme/app_themes.dart';
import '../salary/payday_income_sheet.dart';

/// Dismissible banner shown around payday (e.g. 25th-31st or 1st-3rd)
/// if no salary has been logged yet for the current cycle.
class PaydayCheckinBanner extends StatefulWidget {
  final String householdId;

  const PaydayCheckinBanner({super.key, required this.householdId});

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
    final now = DateTime.now();
    // Typical Saudi payday window is 25th to 31st or 1st to 3rd
    final isPaydayWindow = now.day >= 25 || now.day <= 3;
    if (!isPaydayWindow) {
      if (mounted) setState(() => _checked = true);
      return;
    }

    try {
      final since = now.subtract(const Duration(days: 20)).toIso8601String();
      final records = await supabase
          .from('income_records')
          .select('id')
          .eq('household_id', widget.householdId)
          .eq('income_type', 'salary')
          .gte('received_at', since)
          .limit(1);

      if (mounted) {
        setState(() {
          _shouldShow = records.isEmpty;
          _checked = true;
        });
      }
    } catch (_) {
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
              ? [const Color(0xFF0F3B2E), const Color(0xFF092822)]
              : [const Color(0xFFE6FAF5), const Color(0xFFD4F8ED)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: context.electricTeal.withValues(alpha: 0.4),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: context.electricTeal.withValues(alpha: 0.1),
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
              color: context.electricTeal.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.celebration_rounded,
              color: context.electricTeal,
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
                onCompleted: () => setState(() => _shouldShow = false),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: context.electricTeal,
              foregroundColor: context.scaffoldBg,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
            icon: Icon(Icons.close, size: 16, color: context.textSecondary),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => setState(() => _shouldShow = false),
          ),
        ],
      ),
    );
  }
}
