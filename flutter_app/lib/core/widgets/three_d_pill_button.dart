import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/velvet_burgundy_theme.dart';

/// Extruded 3D Velvet Burgundy pill button with top specular bevel,
/// bottom lip/thickness, and rich cast shadow.
class ThreeDPillButton extends StatefulWidget {
  final String? label;
  final Widget? child;
  final Widget? icon;
  final VoidCallback? onPressed;
  final bool isSecondary;
  final bool isFullWidth;
  final double height;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;
  final double fontSize;
  final Color? customBackgroundColor;

  const ThreeDPillButton({
    super.key,
    this.label,
    this.child,
    this.icon,
    required this.onPressed,
    this.isSecondary = false,
    this.isFullWidth = false,
    this.height = 44.0,
    this.padding,
    this.borderRadius = 16.0,
    this.fontSize = 13.0,
    this.customBackgroundColor,
  });

  @override
  State<ThreeDPillButton> createState() => _ThreeDPillButtonState();
}

class _ThreeDPillButtonState extends State<ThreeDPillButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isEnabled = widget.onPressed != null;

    // Gradient styling
    Gradient? gradient;
    Color? solidColor;

    if (!isEnabled) {
      solidColor = isDark ? const Color(0xFF2E1520) : const Color(0xFFE2D6DA);
    } else if (widget.customBackgroundColor != null) {
      solidColor = widget.customBackgroundColor;
    } else if (widget.isSecondary) {
      gradient = isDark
          ? const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF381423), Color(0xFF220914)],
            )
          : const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFFFF7F9), Color(0xFFF9ECF0)],
            );
    } else {
      gradient = isDark
          ? const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF7A1934),
                VelvetBurgundyColors.primaryDark,
                Color(0xFF380814),
              ],
            )
          : const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF6C162F),
                VelvetBurgundyColors.primaryLight,
                VelvetBurgundyColors.primaryDarkMaroon,
              ],
            );
    }

    // Shadow calculation
    final List<BoxShadow> shadows = !isEnabled
        ? []
        : (_isPressed
            ? [
                BoxShadow(
                  color: (isDark ? Colors.black : const Color(0xFF4A0E1E))
                      .withValues(alpha: 0.25),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ]
            : [
                BoxShadow(
                  color: (isDark ? Colors.black : const Color(0xFF4A0E1E))
                      .withValues(alpha: isDark ? 0.5 : 0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ]);

    // Border bevels
    final Border border = isEnabled
        ? (widget.isSecondary
            ? Border.all(
                color: isDark
                    ? VelvetBurgundyColors.roseBorderDark
                    : VelvetBurgundyColors.roseBorderLight,
                width: 1.2,
              )
            : Border(
                top: BorderSide(
                  color: (isDark ? Colors.white : Colors.white)
                      .withValues(alpha: isDark ? 0.35 : 0.45),
                  width: 1.2,
                ),
                bottom: BorderSide(
                  color: isDark
                      ? const Color(0xFF140207)
                      : const Color(0xFF1B0309),
                  width: _isPressed ? 1.0 : 2.5,
                ),
                left: BorderSide(
                  color: VelvetBurgundyColors.roseGold.withValues(alpha: 0.25),
                  width: 1.0,
                ),
                right: BorderSide(
                  color: VelvetBurgundyColors.roseGold.withValues(alpha: 0.25),
                  width: 1.0,
                ),
              ))
        : Border.all(color: Colors.transparent);

    final textColor = !isEnabled
        ? (isDark ? const Color(0xFF7A606A) : const Color(0xFF9E8E94))
        : (widget.isSecondary
            ? (isDark
                ? VelvetBurgundyColors.roseGoldGlow
                : VelvetBurgundyColors.primaryLight)
            : Colors.white);

    Widget content = widget.child ??
        Row(
          mainAxisSize: widget.isFullWidth ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (widget.icon != null) ...[
              widget.icon!,
              const SizedBox(width: 6),
            ],
            if (widget.label != null)
              Text(
                widget.label!,
                style: GoogleFonts.outfit(
                  fontSize: widget.fontSize,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                ).copyWith(fontFamilyFallback: VelvetBurgundyTheme.arabicFallback),
              ),
          ],
        );

    final buttonWidget = Container(
      height: widget.height,
      width: widget.isFullWidth ? double.infinity : null,
      padding: widget.padding ?? const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: solidColor,
        gradient: gradient,
        borderRadius: BorderRadius.circular(widget.borderRadius),
        boxShadow: shadows,
        border: border,
      ),
      alignment: Alignment.center,
      child: content,
    );

    if (!isEnabled) {
      return buttonWidget;
    }

    return GestureDetector(
      onTap: widget.onPressed,
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        transform: Matrix4.translationValues(0, _isPressed ? 1.5 : 0, 0),
        child: buttonWidget,
      ),
    );
  }
}
