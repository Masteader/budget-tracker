import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/app_localizations.dart';
import '../../models/nafaqah.dart';
import '../../theme/app_themes.dart';

/// Family-mode choice for an expense (Islamic Nafaqah, no spousal split), the
/// single "who paid, and for whom?" question of a family household (UX-03):
/// * `null` – the husband paid: ordinary household expense, no debt;
/// * [kWifeReimbursable] – the wife paid for something shared: the husband
///   owes it back to her;
/// * [kWifePersonal] – the wife's personal purchase: charged to her allowance.
///
/// Options are worded from the recorder's point of view with real names:
/// the husband sees "Sara paid for the home — I pay her back", the wife
/// "I paid for the home — he pays me back", an admin who is neither spouse
/// "Sara paid for the home — owed to her".
class NafaqahClassSelector extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;

  /// Labels speak to the wife ("my allowance") when she is the one recording.
  /// Ignored when [viewerRole] is given.
  final bool viewerIsWife;

  /// 'wife', 'husband' or 'admin' (an admin who is neither spouse). Defaults
  /// to 'wife' when [viewerIsWife], else 'husband'.
  final String? viewerRole;

  /// The wife the class refers to and the husband (provider), by name; generic
  /// words ("my wife", "my husband") are used when a name is unknown.
  final String? wifeName;
  final String? husbandName;

  /// Hide the husband option when the wife already said she paid.
  final bool showHusbandOption;

  const NafaqahClassSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.viewerIsWife = false,
    this.viewerRole,
    this.wifeName,
    this.husbandName,
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

  String get _role => viewerRole ?? (viewerIsWife ? 'wife' : 'husband');

  static String? _clean(String? name) {
    final n = (name ?? '').trim();
    return n.isEmpty ? null : n;
  }

  /// The label of option [nafaqahClass] for [role] ('wife' | 'husband' | 'admin').
  static String optionLabel(
    BuildContext context,
    String? nafaqahClass, {
    required String role,
    String? wifeName,
    String? husbandName,
  }) {
    final wife = _clean(wifeName) ??
        context.tr(role == 'husband' ? 'nafaqah_wife_generic_mine' : 'nafaqah_wife_generic');
    final husband = _clean(husbandName) ?? context.tr('nafaqah_husband_generic_mine');
    switch (role) {
      case 'wife':
        return switch (nafaqahClass) {
          kWifeReimbursable => context.tr('nafaqah_w_opt_shared'),
          kWifePersonal => context.tr('nafaqah_w_opt_personal'),
          _ => context.trArgs('nafaqah_w_opt_husband', {'husband': husband}),
        };
      case 'admin':
        return switch (nafaqahClass) {
          kWifeReimbursable => context.trArgs('nafaqah_a_opt_shared', {'wife': wife}),
          kWifePersonal => context.trArgs('nafaqah_h_opt_personal', {'wife': wife}),
          _ => context.tr('nafaqah_a_opt_household'),
        };
      default:
        return switch (nafaqahClass) {
          kWifeReimbursable => context.trArgs('nafaqah_h_opt_shared', {'wife': wife}),
          kWifePersonal => context.trArgs('nafaqah_h_opt_personal', {'wife': wife}),
          _ => context.tr('nafaqah_h_opt_me'),
        };
    }
  }

  @override
  Widget build(BuildContext context) {
    final options = <(String?, IconData)>[
      if (showHusbandOption) (null, Icons.shield_outlined),
      (kWifeReimbursable, Icons.currency_exchange_rounded),
      (kWifePersonal, Icons.shopping_bag_outlined),
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
          context.tr('nafaqah_q_title'),
          style: TextStyle(color: context.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        for (var i = 0; i < options.length; i++) ...[
          if (i > 0) const SizedBox(height: 6),
          _Option(
            key: ValueKey('nafaqah_option_${options[i].$1 ?? 'husband'}'),
            label: optionLabel(context, options[i].$1, role: _role, wifeName: wifeName, husbandName: husbandName),
            icon: options[i].$2,
            color: colorFor(options[i].$1),
            selected: value == options[i].$1,
            onTap: () => onChanged(options[i].$1),
          ),
        ],
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
                  style: GoogleFonts.outfit(color: context.textPrimary, fontSize: 12, fontWeight: FontWeight.w500),
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
      inMutuallyExclusiveGroup: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.16) : context.subtleCardBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? color : context.borderColor, width: selected ? 1.5 : 1.0),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                size: 18,
                color: selected ? color : context.textSecondary,
              ),
              const SizedBox(width: 10),
              Icon(icon, size: 18, color: selected ? color : context.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? context.textPrimary : context.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
