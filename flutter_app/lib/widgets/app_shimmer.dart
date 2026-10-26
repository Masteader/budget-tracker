import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../theme/app_themes.dart';

/// Reusable theme-adaptive skeleton shimmer widgets.
/// Uses curated dark tones (#161B22 to #262C36) in dark mode,
/// and light tones (#E2E8F0 to #F1F5F9) in light mode for a seamless loading experience.
class AppShimmer extends StatelessWidget {
  final Widget child;

  const AppShimmer({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: context.shimmerBase,
      highlightColor: context.shimmerHighlight,
      child: child,
    );
  }

  /// Single placeholder rectangle with rounded corners
  static Widget box({
    required double width,
    required double height,
    double borderRadius = 8,
    Color? color,
  }) {
    return Builder(
      builder: (ctx) {
        return Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: color ?? ctx.chipBg,
            borderRadius: BorderRadius.circular(borderRadius),
          ),
        );
      },
    );
  }

  /// Shimmer placeholder mimicking BudgetHeroCard
  static Widget heroCard() {
    return Builder(
      builder: (ctx) {
        return AppShimmer(
          child: Container(
            height: 180,
            decoration: BoxDecoration(
              color: ctx.cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: ctx.borderColor),
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
      },
    );
  }

  /// Shimmer placeholder mimicking a list of category or transaction cards
  static Widget listItems({int count = 4}) {
    return Builder(
      builder: (ctx) {
        return AppShimmer(
          child: Column(
            children: List.generate(
              count,
              (i) => Container(
                margin: const EdgeInsets.symmetric(vertical: 6),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: ctx.cardBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: ctx.borderColor),
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
      },
    );
  }
}
