import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/velvet_burgundy_theme.dart';

/// Raised 3D circular/squircle burgundy or rose-gold icon puck
/// casting a 45° diagonal drop shadow.
class ThreeDIconPuck extends StatefulWidget {
  final IconData? icon;
  final Widget? child;
  final double size;
  final bool isRoseGold;
  final bool isWhiteSurface;
  final bool isSquircle;
  final double? borderRadius;
  final String? badge;
  final Color? iconColor;
  final double? iconSize;
  final VoidCallback? onTap;

  const ThreeDIconPuck({
    super.key,
    this.icon,
    this.child,
    this.size = 44.0,
    this.isRoseGold = false,
    this.isWhiteSurface = false,
    this.isSquircle = false,
    this.borderRadius,
    this.badge,
    this.iconColor,
    this.iconSize,
    this.onTap,
  });

  @override
  State<ThreeDIconPuck> createState() => _ThreeDIconPuckState();
}

class _ThreeDIconPuckState extends State<ThreeDIconPuck> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Gradient calculation
    final Gradient gradient = widget.isWhiteSurface
        ? (isDark
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF2A101A), Color(0xFF15060C)],
              )
            : const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFFFFFFF), Color(0xFFFBF6F7)],
              ))
        : (widget.isRoseGold
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFF2A6BD),
                  VelvetBurgundyColors.roseGold,
                  Color(0xFFB86B84),
                ],
              )
            : (isDark
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF6E162F),
                      VelvetBurgundyColors.primaryDark,
                      Color(0xFF29040D),
                    ],
                  )
                : const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF65172C),
                      VelvetBurgundyColors.primaryLight,
                      VelvetBurgundyColors.primaryDarkMaroon,
                    ],
                  )));

    // 45-degree diagonal shadow
    final List<BoxShadow> shadows = [
      BoxShadow(
        color: (widget.isWhiteSurface
                ? (isDark ? Colors.black : const Color(0xFF4A0E1E))
                : const Color(0xFF4A0E1E))
            .withValues(alpha: isDark ? 0.6 : 0.35),
        blurRadius: 14,
        offset: const Offset(3, 6),
        spreadRadius: -2,
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.15),
        blurRadius: 4,
        offset: const Offset(0, 2),
      ),
    ];

    final effectiveRadius = widget.borderRadius ??
        (widget.isSquircle ? widget.size * 0.28 : widget.size / 2);

    final border = Border.all(
      color: widget.isWhiteSurface
          ? (isDark
              ? VelvetBurgundyColors.roseBorderDark
              : Colors.white.withValues(alpha: 0.95))
          : (widget.isRoseGold
              ? Colors.white.withValues(alpha: 0.5)
              : (isDark
                  ? Colors.white.withValues(alpha: 0.22)
                  : Colors.white.withValues(alpha: 0.3))),
      width: 1.2,
    );

    final effectiveIconColor = widget.iconColor ??
        (widget.isWhiteSurface
            ? (isDark
                ? VelvetBurgundyColors.roseGoldGlow
                : VelvetBurgundyColors.primaryLight)
            : (widget.isRoseGold
                ? const Color(0xFF4A0E1E)
                : VelvetBurgundyColors.roseGold));

    Widget content = widget.child ??
        (widget.icon != null
            ? Icon(
                widget.icon,
                color: effectiveIconColor,
                size: widget.iconSize ?? (widget.size * 0.48),
              )
            : const SizedBox.shrink());

    Widget puck = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(effectiveRadius),
        boxShadow: shadows,
        border: border,
      ),
      alignment: Alignment.center,
      child: content,
    );

    if (widget.badge != null && widget.badge!.isNotEmpty) {
      puck = Stack(
        clipBehavior: Clip.none,
        children: [
          puck,
          Positioned(
            top: -2,
            left: -2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFE5395B), Color(0xFFB31435)],
                ),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                widget.badge!,
                style: GoogleFonts.outfit(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (widget.onTap == null) {
      return puck;
    }

    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 90),
        child: puck,
      ),
    );
  }
}
