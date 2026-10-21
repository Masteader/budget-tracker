import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/app_localizations.dart';
import '../../models/household_membership.dart';
import '../../theme/app_themes.dart';

/// Family (Islamic Nafaqah) or Roommates, chosen when a household is created
/// and changed later by an admin. Two selectable cards; RTL-safe.
class HouseholdTypeChooser extends StatelessWidget {
  /// 'family' | 'roommates', or null while nothing is chosen.
  final String? value;
  final ValueChanged<String> onChanged;

  /// Highlights the choice after an attempt to continue without one.
  final bool showRequired;

  const HouseholdTypeChooser({
    super.key,
    required this.value,
    required this.onChanged,
    this.showRequired = false,
  });

  static String labelKey(String householdType) =>
      householdType == kHouseholdTypeRoommates ? 'household_model_roommates' : 'household_model_family';

  Widget _option(
    BuildContext context, {
    required String type,
    required IconData icon,
    required String descKey,
    required Color color,
  }) {
    final selected = value == type;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        key: ValueKey('household_type_$type'),
        borderRadius: BorderRadius.circular(14),
        onTap: () => onChanged(type),
        child: Container(
          padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 12, 12),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.12) : context.subtleCardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? color : context.borderColor, width: selected ? 1.5 : 1),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: selected ? color : context.textSecondary, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr(labelKey(type)),
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(context.tr(descKey), style: TextStyle(fontSize: 11.5, color: context.textSecondary)),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                color: selected ? color : context.textSecondary,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          context.tr('hh_type_question'),
          style: TextStyle(color: context.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        _option(
          context,
          type: kHouseholdTypeFamily,
          icon: Icons.family_restroom_rounded,
          descKey: 'hh_type_family_desc',
          color: context.champagneGold,
        ),
        const SizedBox(height: 8),
        _option(
          context,
          type: kHouseholdTypeRoommates,
          icon: Icons.group_outlined,
          descKey: 'hh_type_roommates_desc',
          color: AppThemes.success,
        ),
        if (showRequired && value == null) ...[
          const SizedBox(height: 6),
          Text(
            context.tr('hh_type_required'),
            style: TextStyle(color: context.dangerColor, fontSize: 11.5, fontWeight: FontWeight.w600),
          ),
        ],
      ],
    );
  }
}
