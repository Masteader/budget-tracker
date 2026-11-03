import 'package:flutter/material.dart';

/// The app's brand mark.
///
/// Decoded at display size for the device pixel ratio, so a small mark does not
/// hold the full image in memory. Excluded from semantics because it always sits
/// beside text that names the app.
class BrandLogo extends StatelessWidget {
  static const assetPath = 'assets/images/brand_logo.png';

  final double size;
  final double radius;

  const BrandLogo({super.key, required this.size, required this.radius});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.asset(
        assetPath,
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).ceil(),
        filterQuality: FilterQuality.medium,
        excludeFromSemantics: true,
      ),
    );
  }
}
