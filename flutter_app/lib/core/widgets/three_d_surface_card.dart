import 'package:flutter/material.dart';
import '../theme/velvet_burgundy_theme.dart';

/// Uniform 3D squircle ceramic card.
/// In Light Mode: Pure White (#FFFFFF) surface on Soft Blush-Alabaster with
/// top specular bevel highlight and deep velvet burgundy drop shadow.
/// In Dark Mode: Dark Plum-Charcoal (#1E0B12) surface on Obsidian Wine with
/// rose-gold specular border.
class ThreeDSurfaceCard extends StatefulWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;
  final VoidCallback? onTap;
  final bool isVelvetBurgundy;
  final BoxBorder? customBorder;
  final Gradient? customGradient;

  const ThreeDSurfaceCard({
    super.key,
    required this.child,
    this.borderRadius = 22.0,
    this.padding = const EdgeInsets.all(16.0),
    this.margin,
    this.width,
    this.height,
    this.onTap,
    this.isVelvetBurgundy = false,
    this.customBorder,
    this.customGradient,
  });

  @override
  State<ThreeDSurfaceCard> createState() => _ThreeDSurfaceCardState();
}

class _ThreeDSurfaceCardState extends State<ThreeDSurfaceCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Background gradient/color
    final decorationGradient = widget.customGradient ??
        (widget.isVelvetBurgundy
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? const [Color(0xFF5E1327), Color(0xFF2A050E)]
                    : const [
                        VelvetBurgundyColors.primaryLightGradient,
                        VelvetBurgundyColors.primaryLight,
                        VelvetBurgundyColors.primaryDarkMaroon,
                      ],
              )
            : (isDark
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      VelvetBurgundyColors.surfaceDarkGradientStart,
                      VelvetBurgundyColors.surfaceDarkGradientEnd,
                    ],
                  )
                : null));

    final backgroundColor = (widget.isVelvetBurgundy || isDark || widget.customGradient != null)
        ? null
        : VelvetBurgundyColors.surfaceLight;

    // Multi-layer physical 3D drop shadows
    final List<BoxShadow> shadows = isDark
        ? [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.65),
              blurRadius: 28,
              offset: const Offset(0, 14),
              spreadRadius: -4,
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 12,
              offset: const Offset(0, 6),
              spreadRadius: -2,
            ),
          ]
        : [
            BoxShadow(
              color: const Color(0xFF4A0E1E).withValues(alpha: 0.11),
              blurRadius: 28,
              offset: const Offset(0, 14),
              spreadRadius: -4,
            ),
            BoxShadow(
              color: const Color(0xFF4A0E1E).withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 6),
              spreadRadius: -2,
            ),
          ];

    final border = widget.customBorder ??
        Border.all(
          color: isDark
              ? VelvetBurgundyColors.roseBorderDark
              : VelvetBurgundyColors.roseBorderLight.withValues(alpha: 0.8),
          width: 1.0,
        );

    final cardContent = Container(
      width: widget.width,
      height: widget.height,
      margin: widget.margin,
      padding: widget.padding,
      decoration: BoxDecoration(
        color: backgroundColor,
        gradient: decorationGradient,
        borderRadius: BorderRadius.circular(widget.borderRadius),
        border: border,
        boxShadow: shadows,
      ),
      child: widget.child,
    );

    if (widget.onTap == null) {
      return cardContent;
    }

    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: cardContent,
      ),
    );
  }
}
