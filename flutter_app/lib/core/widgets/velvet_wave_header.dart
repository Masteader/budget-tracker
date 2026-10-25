import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/velvet_burgundy_theme.dart';

/// Curved Velvet Burgundy Top Wave Header.
/// Features a smooth organic S-curve transitioning into the canvas background,
/// status bar padding, ambient glow circles, and slots for 3D circular action buttons.
class VelvetWaveHeader extends StatelessWidget {
  final String? title;
  final Widget? titleWidget;
  final String? subtitle;
  final Widget? leading;
  final List<Widget>? actions;
  final double height;
  final Widget? bottom;
  final bool showWave;

  const VelvetWaveHeader({
    super.key,
    this.title,
    this.titleWidget,
    this.subtitle,
    this.leading,
    this.actions,
    this.height = 200.0,
    this.bottom,
    this.showWave = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final topPadding = MediaQuery.paddingOf(context).top;

    final headerContent = Container(
      width: double.infinity,
      height: height + topPadding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [
                  Color(0xFF5E1327),
                  Color(0xFF3A0916),
                  Color(0xFF2A050E),
                ]
              : const [
                  VelvetBurgundyColors.primaryLight,
                  Color(0xFF3A0916),
                  VelvetBurgundyColors.primaryDarkMaroon,
                ],
        ),
      ),
      child: Stack(
        children: [
          // Ambient Glow Circles
          Positioned(
            top: -40,
            right: -30,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: VelvetBurgundyColors.roseGold.withValues(alpha: 0.15),
              ),
            ),
          ),
          Positioned(
            bottom: 20,
            left: -20,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: VelvetBurgundyColors.accentRose.withValues(alpha: 0.18),
              ),
            ),
          ),

          // Header Bar & Navigation Elements
          Padding(
            padding: EdgeInsets.fromLTRB(16, topPadding + 10, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Leading Action
                    if (leading != null)
                      leading!
                    else
                      const SizedBox(width: 44),

                    // Center Title / Emblem
                    Expanded(
                      child: titleWidget ??
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (title != null)
                                Text(
                                  title!,
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.outfit(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    letterSpacing: -0.2,
                                  ).copyWith(fontFamilyFallback: VelvetBurgundyTheme.arabicFallback),
                                ),
                              if (subtitle != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  subtitle!,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white.withValues(alpha: 0.75),
                                    fontFamilyFallback: VelvetBurgundyTheme.arabicFallback,
                                  ),
                                ),
                              ],
                            ],
                          ),
                    ),

                    // Trailing Actions
                    if (actions != null && actions!.isNotEmpty)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: actions!,
                      )
                    else
                      const SizedBox(width: 44),
                  ],
                ),

                if (bottom != null) ...[
                  const Spacer(),
                  bottom!,
                  const SizedBox(height: 24),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    if (!showWave) {
      return headerContent;
    }

    return ClipPath(
      clipper: const _VelvetWaveClipper(),
      child: headerContent,
    );
  }
}

/// Precise S-curve clipper matching Stitch Screen 1 wave geometry.
class _VelvetWaveClipper extends CustomClipper<Path> {
  const _VelvetWaveClipper();

  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height - 28);

    // Smooth organic S-wave curve
    final firstControlPoint = Offset(size.width * 0.35, size.height + 4);
    final firstEndPoint = Offset(size.width * 0.65, size.height - 14);
    path.quadraticBezierTo(
      firstControlPoint.dx,
      firstControlPoint.dy,
      firstEndPoint.dx,
      firstEndPoint.dy,
    );

    final secondControlPoint = Offset(size.width * 0.88, size.height - 28);
    final secondEndPoint = Offset(size.width, size.height - 20);
    path.quadraticBezierTo(
      secondControlPoint.dx,
      secondControlPoint.dy,
      secondEndPoint.dx,
      secondEndPoint.dy,
    );

    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
