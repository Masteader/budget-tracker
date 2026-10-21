import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_themes.dart';

/// The floating bottom navigation of the home screen: dashboard, feed, the
/// AI assistant in the middle, budgets and settings. Above
/// [hideLabelsAboveTextScale] the labels give way to icons (with tooltips and
/// semantic labels) so large system text cannot overflow the bar (UX-14).
class AppBottomNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const double hideLabelsAboveTextScale = 1.3;

  const AppBottomNavBar({super.key, required this.selectedIndex, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final showLabels = MediaQuery.textScalerOf(context).scale(10) / 10 <= hideLabelsAboveTextScale;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      height: 68,
      decoration: BoxDecoration(
        color: isDark ? AppThemes.deepGlacial.withValues(alpha: 0.94) : Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isDark
              ? AppThemes.iceCyan.withValues(alpha: 0.22)
              : AppThemes.electricTeal.withValues(alpha: 0.35),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black.withValues(alpha: 0.45) : AppThemes.electricTeal.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
          if (!isDark)
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: Row(
        children: [
          _item(context, 0, Icons.home_outlined, Icons.home_rounded, context.tr('nav_dashboard'), showLabels),
          _item(context, 1, Icons.receipt_long_outlined, Icons.receipt_long_rounded, context.tr('nav_transactions'), showLabels),
          _centerAi(context, showLabels),
          _item(context, 3, Icons.pie_chart_outline_rounded, Icons.pie_chart_rounded, context.tr('nav_budgets'), showLabels),
          _item(context, 4, Icons.person_outline_rounded, Icons.person_rounded, context.tr('nav_settings'), showLabels),
        ],
      ),
    );
  }

  // UX-27: contrast-safe tokens (the hard-coded #008F7A was 4.0:1 in light mode).
  Color _active(BuildContext context) => context.accentText;
  Color _inactive(BuildContext context) => context.textMuted;

  Widget _label(BuildContext context, String label, bool isSelected, double size, {bool bold = false}) => Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.outfit(
          fontSize: size,
          fontWeight: isSelected || bold ? FontWeight.w700 : FontWeight.w500,
          color: isSelected ? _active(context) : _inactive(context),
        ),
      );

  Widget _item(BuildContext context, int index, IconData icon, IconData selectedIcon, String label, bool showLabels) {
    final isSelected = selectedIndex == index;
    final isDark = context.isDark;
    return Expanded(
      child: Semantics(
        label: label,
        selected: isSelected,
        button: true,
        excludeSemantics: true,
        child: Tooltip(
          message: label,
          child: InkWell(
            key: Key('nav_item_$index'),
            onTap: () => onSelected(index),
            borderRadius: BorderRadius.circular(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding: EdgeInsets.symmetric(horizontal: isSelected ? 12 : 6, vertical: 4),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppThemes.electricTeal.withValues(alpha: isDark ? 0.16 : 0.18)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    isSelected ? selectedIcon : icon,
                    color: isSelected ? _active(context) : _inactive(context),
                    size: 22,
                  ),
                ),
                if (showLabels) ...[
                  const SizedBox(height: 2),
                  _label(context, label, isSelected, 10),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _centerAi(BuildContext context, bool showLabels) {
    final isSelected = selectedIndex == 2;
    final label = context.tr('nav_ai');
    return Expanded(
      child: Semantics(
        label: label,
        selected: isSelected,
        button: true,
        excludeSemantics: true,
        child: Tooltip(
          message: label,
          child: GestureDetector(
            key: const Key('nav_item_2'),
            onTap: () => onSelected(2),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppThemes.electricTeal, AppThemes.iceCyan],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppThemes.electricTeal.withValues(alpha: isSelected ? 0.65 : 0.4),
                        blurRadius: isSelected ? 16 : 10,
                        spreadRadius: isSelected ? 2 : 0,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.auto_awesome, color: AppThemes.brandDarkBg, size: 22),
                ),
                if (showLabels) ...[
                  const SizedBox(height: 2),
                  _label(context, label, isSelected, 9.5, bold: true),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
