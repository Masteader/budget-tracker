import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/account_deletion_provider.dart';
import '../../services/salary_cycle_service.dart';
import '../../theme/app_themes.dart';

/// Tells everyone in a household that it is scheduled for deletion, with the date
/// and an export hint. The household stays usable until then, and this cannot be
/// dismissed. `households` has no realtime feed, so it follows the mark on the next
/// load or app resume, or at once for the user who cancels.
class HouseholdDeletionBanner extends StatefulWidget {
  final String householdId;

  const HouseholdDeletionBanner({super.key, required this.householdId});

  @override
  State<HouseholdDeletionBanner> createState() => _HouseholdDeletionBannerState();
}

class _HouseholdDeletionBannerState extends State<HouseholdDeletionBanner> {
  @override
  void initState() {
    super.initState();
    _scheduleLoad();
  }

  @override
  void didUpdateWidget(covariant HouseholdDeletionBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.householdId != widget.householdId) _scheduleLoad();
  }

  void _scheduleLoad() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AccountDeletionProvider?>()?.loadHouseholdMark(widget.householdId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final date = context.watch<AccountDeletionProvider?>()?.householdDeletionDate(widget.householdId);
    if (date == null) return const SizedBox.shrink();
    return Container(
      key: const ValueKey('household_deletion_banner'),
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.dangerColor, width: 1.2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: context.dangerColor, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('del_banner_title'),
                  style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: context.textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  context.trArgs('del_banner_date', {'date': context.fmtDate(SalaryCycleService.riyadhDate(date), 'd MMMM yyyy')}),
                  style: TextStyle(fontSize: 12.5, color: context.textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  // The feed's All Records export covers the whole household;
                  // the one in Settings is the current cycle only.
                  context.trArgs('del_banner_export', {
                    'transactions': context.tr('nav_transactions'),
                    'export': context.tr('export_csv'),
                    'all': context.tr('csv_export_all_records'),
                  }),
                  style: TextStyle(fontSize: 12, color: context.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
