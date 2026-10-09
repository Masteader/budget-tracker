import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// Reusable dark-mode skeleton shimmer widgets.
/// Uses curated dark tones (#161B22 to #21262D) for a seamless loading experience.
class AppShimmer extends StatelessWidget {
  final Widget child;

  const AppShimmer({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: const Color(0xFF161B22),
      highlightColor: const Color(0xFF262C36),
      child: child,
    );
  }

  /// Single placeholder rectangle with rounded corners
  static Widget box({
    required double width,
    required double height,
    double borderRadius = 8,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }

  /// Shimmer placeholder mimicking BudgetHeroCard
  static Widget heroCard() {
    return AppShimmer(
      child: Container(
        height: 180,
        decoration: BoxDecoration(
          color: const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF30363D)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                AppShimmer.box(width: 120, height: 16, borderRadius: 6),
                AppShimmer.box(width: 80, height: 16, borderRadius: 6),
              ],
            ),
            const SizedBox(height: 20),
            AppShimmer.box(width: 160, height: 32, borderRadius: 8),
            const SizedBox(height: 14),
            AppShimmer.box(width: double.infinity, height: 10, borderRadius: 6),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                AppShimmer.box(width: 90, height: 14, borderRadius: 4),
                AppShimmer.box(width: 90, height: 14, borderRadius: 4),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Shimmer placeholder mimicking a list of category or transaction cards
  static Widget listItems({int count = 4}) {
    return AppShimmer(
      child: Column(
        children: List.generate(
          count,
          (i) => Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF161B22),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF30363D)),
            ),
            child: Row(
              children: [
                AppShimmer.box(width: 40, height: 40, borderRadius: 10),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppShimmer.box(width: 140, height: 14, borderRadius: 4),
                      const SizedBox(height: 8),
                      AppShimmer.box(width: 80, height: 11, borderRadius: 4),
                    ],
                  ),
                ),
                AppShimmer.box(width: 70, height: 18, borderRadius: 6),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
