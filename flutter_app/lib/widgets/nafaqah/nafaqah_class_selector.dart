import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/app_localizations.dart';
import '../../models/nafaqah.dart';
import '../../theme/app_themes.dart';

/// Family-mode choice for an expense (Islamic Nafaqah, no spousal split):
/// * `null` – the husband paid: ordinary household expense, no debt;
/// * [kWifeReimbursable] – the wife paid for something shared: the husband
///   owes it back to her;
/// * [kWifePersonal] – the wife's personal purchase: charged to her allowance.
class NafaqahClassSelector extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;

  /// Labels speak to the wife ("my allowance") when she is the one recording.
  final bool viewerIsWife;

  /// Hide the husband option when the wife already said she paid (chat review).
  final bool showHusbandOption;

  const NafaqahClassSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.viewerIsWife = false,
    this.showHusbandOption = true,
  });

  static Color colorFor(String? nafaqahClass) {
    switch (nafaqahClass) {
      case kWifeReimbursable:
        return AppThemes.champagneGold;
      case kWifePersonal:
        return AppThemes.iceCyan;
      default:
        return AppThemes.success;
    }
  }

  @override
  Widget build(BuildContext context) {
    final options = <(String?, String, IconData)>[
      if (showHusbandOption) (null, 'nafaqah_opt_husband', Icons.shield_outlined),
      (kWifeReimbursable, 'nafaqah_opt_shared', Icons.currency_exchange_rounded),
      (kWifePersonal, viewerIsWife ? 'nafaqah_opt_personal_mine' : 'nafaqah_opt_personal_hers',
          Icons.shopping_bag_outlined),
    ];
    final hintKey = switch (value) {
      kWifeReimbursable => 'nafaqah_wife_reimbursable_hint',
      kWifePersonal => 'nafaqah_wife_personal_hint',
      _ => 'nafaqah_me_hint',
    };
    final activeColor = colorFor(value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.tr('nafaqah_choice_title'),
          style: TextStyle(color: context.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (var i = 0; i < options.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: _Option(
                  key: ValueKey('nafaqah_option_${options[i].$1 ?? 'husband'}'),
                  label: context.tr(options[i].$2),
                  icon: options[i].$3,
                  color: colorFor(options[i].$1),
                  selected: value == options[i].$1,
                  onTap: () => onChanged(options[i].$1),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: activeColor.withValues(alpha: context.isDark ? 0.12 : 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: activeColor.withValues(alpha: context.isDark ? 0.35 : 0.25)),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 15, color: activeColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.tr(hintKey),
                  style: GoogleFonts.outfit(color: context.textPrimary, fontSize: 11.5, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Option extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _Option({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.16) : context.subtleCardBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? color : context.borderColor, width: selected ? 1.5 : 1.0),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: selected ? color : context.textSecondary),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 10.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? context.textPrimary : context.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
