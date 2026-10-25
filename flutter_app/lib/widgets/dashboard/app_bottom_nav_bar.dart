import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/velvet_burgundy_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_themes.dart';

/// Floating Glassmorphic Bottom Navigation Dock:
/// Features a frosted glass capsule (30px radius, blur 24px, 1.5px specular rim),
/// active dot indicators, and an elevated 3D Velvet Burgundy center orb.
/// Above [hideLabelsAboveTextScale] the labels give way to icons so large
/// system text cannot overflow the bar (UX-14).
class AppBottomNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const double hideLabelsAboveTextScale = 1.3;

  const AppBottomNavBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final showLabels = MediaQuery.textScalerOf(context).scale(10) / 10 <= hideLabelsAboveTextScale;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      height: 72,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          // Frosted Glass Capsule
          ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                height: 66,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1E0B12).withValues(alpha: 0.82)
                      : Colors.white.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.18)
                        : Colors.white.withValues(alpha: 0.95),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isDark
                          ? Colors.black.withValues(alpha: 0.65)
                          : const Color(0xFF4A0E1E).withValues(alpha: 0.14),
                      blurRadius: 36,
                      offset: const Offset(0, 18),
                      spreadRadius: -4,
                    ),
                    BoxShadow(
                      color: const Color(0xFF4A0E1E).withValues(alpha: 0.06),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    _item(context, 0, Icons.home_outlined, Icons.home_rounded, context.tr('nav_dashboard'), showLabels),
                    _item(context, 1, Icons.receipt_long_outlined, Icons.receipt_long_rounded, context.tr('nav_transactions'), showLabels),
                    _centerOrb(context, showLabels),
                    _item(context, 3, Icons.pie_chart_outline_rounded, Icons.pie_chart_rounded, context.tr('nav_budgets'), showLabels),
                    _item(context, 4, Icons.person_outline_rounded, Icons.person_rounded, context.tr('nav_settings'), showLabels),
                  ],
                ),
              ),
            ),
          ),

          // Elevated Center 3D Burgundy Orb
          Positioned(
            top: -10,
            child: _ElevatedCenterOrb(
              isDark: isDark,
              isSelected: selectedIndex == 2,
              onPressed: () => onSelected(2),
            ),
          ),
        ],
      ),
    );
  }

  Color _activeColor(BuildContext context) {
    return context.isDark
        ? VelvetBurgundyColors.roseGoldGlow
        : VelvetBurgundyColors.primaryLight;
  }

  Color _inactiveColor(BuildContext context) {
    return context.isDark
        ? const Color(0xFF8E757F)
        : const Color(0xFF9E8E94);
  }

  Widget _item(
    BuildContext context,
    int index,
    IconData outline,
    IconData filled,
    String label,
    bool showLabels,
  ) {
    final isSelected = selectedIndex == index;
    final active = _activeColor(context);
    final inactive = _inactiveColor(context);

    return Expanded(
      child: Tooltip(
        message: label,
        child: Semantics(
          label: label,
          selected: isSelected,
          button: true,
          child: InkWell(
            key: Key('nav_item_$index'),
            onTap: () => onSelected(index),
            borderRadius: BorderRadius.circular(24),
            splashColor: active.withValues(alpha: 0.1),
            highlightColor: Colors.transparent,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isSelected ? filled : outline,
                  color: isSelected ? active : inactive,
                  size: 22,
                ),
                if (showLabels) ...[
                  const SizedBox(height: 2),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                      fontSize: 10,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? active : inactive,
                    ).copyWith(fontFamilyFallback: VelvetBurgundyTheme.arabicFallback),
                  ),
                ],
                const SizedBox(height: 2),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: isSelected ? 4 : 0,
                  height: isSelected ? 4 : 0,
                  decoration: BoxDecoration(
                    color: isSelected ? active : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _centerOrb(BuildContext context, bool showLabels) {
    // Spacer in the row so the elevated orb has breathing room
    return const SizedBox(width: 58);
  }
}

class _ElevatedCenterOrb extends StatefulWidget {
  final bool isDark;
  final bool isSelected;
  final VoidCallback onPressed;

  const _ElevatedCenterOrb({
    required this.isDark,
    required this.isSelected,
    required this.onPressed,
  });

  @override
  State<_ElevatedCenterOrb> createState() => _ElevatedCenterOrbState();
}

class _ElevatedCenterOrbState extends State<_ElevatedCenterOrb> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const Key('nav_center_ai'),
      onTap: widget.onPressed,
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.90 : 1.0,
        duration: const Duration(milliseconds: 90),
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: widget.isDark
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF6E162F), Color(0xFF29040D)],
                  )
                : const RadialGradient(
                    center: Alignment(-0.35, -0.35),
                    radius: 0.85,
                    colors: [
                      Color(0xFF8A243D),
                      Color(0xFF571324),
                      Color(0xFF25030A),
                    ],
                  ),
            boxShadow: [
              BoxShadow(
                color: (widget.isDark ? Colors.black : const Color(0xFF4A0E1E))
                    .withValues(alpha: widget.isDark ? 0.75 : 0.55),
                blurRadius: 22,
                offset: const Offset(0, 10),
                spreadRadius: -2,
              ),
              BoxShadow(
                color: const Color(0xFF4A0E1E).withValues(alpha: 0.35),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(
              color: Colors.white.withValues(alpha: widget.isDark ? 0.35 : 0.5),
              width: 2.0,
            ),
          ),
          child: const Center(
            child: Icon(
              Icons.add_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
        ),
      ),
    );
  }
}
