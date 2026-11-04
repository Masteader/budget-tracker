import 'package:flutter/material.dart';

/// The app's brand mark, on a transparent background for light and dark surfaces.
///
/// Decoded at display size for the device pixel ratio, so a small mark does not
/// hold the full image in memory. Excluded from semantics because it always sits
/// beside text that names the app.
class BrandLogo extends StatelessWidget {
  static const assetPath = 'assets/images/brand_logo.png';

  final double size;

  const BrandLogo({super.key, required this.size});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      assetPath,
      width: size,
      height: size,
      fit: BoxFit.contain,
      cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).ceil(),
      filterQuality: FilterQuality.medium,
      excludeFromSemantics: true,
    );
  }
}
