import 'package:flutter/material.dart';
import '../../theme/app_themes.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../l10n/app_localizations.dart';

class UserGuideWalkthroughDialog extends StatefulWidget {
  final VoidCallback? onDismiss;

  const UserGuideWalkthroughDialog({super.key, this.onDismiss});

  static const String prefKey = 'has_seen_user_guide_v1';

  /// Shows the dialog unconditionally (e.g. from Settings).
  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: UserGuideWalkthroughDialog(
          onDismiss: () => Navigator.of(ctx).pop(),
        ),
      ),
    );
  }

  /// Automatically shows the dialog if the user has not seen it yet.
  static Future<bool> showIfFirstTime(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeen = prefs.getBool(prefKey) ?? false;
    if (!hasSeen && context.mounted) {
      await show(context);
      await prefs.setBool(prefKey, true);
      return true;
    }
    return false;
  }

  @override
  State<UserGuideWalkthroughDialog> createState() =>
      _UserGuideWalkthroughDialogState();
}

class _UserGuideWalkthroughDialogState extends State<UserGuideWalkthroughDialog> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // Step texts are translation keys resolved at build time. UX-28: the core
  // promise (what is left until payday) first, then the household rules,
  // then the ways to record an expense.
  static const int _stepCount = 5;

  List<_WalkthroughStep> _getSteps(BuildContext context) => [
    _WalkthroughStep(
      icon: Icons.calendar_month_rounded,
      gradientColors: [context.warnText, context.warnText.withValues(alpha: 0.7)],
      title: 'wt3_title',
      subtitle: 'wt3_desc',
      tags: ['wt3_tag1', 'wt3_tag2', 'wt3_tag3'],
    ),
    _WalkthroughStep(
      icon: Icons.people_alt_rounded,
      gradientColors: [context.successText, context.successText.withValues(alpha: 0.7)],
      title: 'wt5_title',
      subtitle: 'wt5_desc',
      tags: ['wt5_tag1', 'wt5_tag2', 'wt5_tag3'],
    ),
    _WalkthroughStep(
      icon: Icons.mic_rounded,
      gradientColors: [context.accentText, context.primaryButtonBg],
      title: 'wt2_title',
      subtitle: 'wt2_desc',
      tags: ['wt2_tag1', 'wt2_tag2', 'wt2_tag3'],
    ),
    _WalkthroughStep(
      icon: Icons.qr_code_scanner_rounded,
      gradientColors: [context.successText, context.champagneGold],
      title: 'wt1_title',
      subtitle: 'wt1_desc',
      tags: ['wt1_tag1', 'wt1_tag2', 'wt1_tag3'],
    ),
    _WalkthroughStep(
      icon: Icons.receipt_long_rounded,
      gradientColors: [context.infoColor, context.infoColor.withValues(alpha: 0.7)],
      title: 'wt4_title',
      subtitle: 'wt4_desc',
      tags: ['wt4_tag1', 'wt4_tag2', 'wt4_tag3'],
    ),
  ];

  void _next() {
    if (_currentPage < _stepCount - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _finish();
    }
  }

  void _finish() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(UserGuideWalkthroughDialog.prefKey, true);
    } catch (_) {}
    if (mounted) {
      widget.onDismiss?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final steps = _getSteps(context);
    return Container(
      constraints: const BoxConstraints(maxWidth: 420, maxHeight: 600),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: context.borderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(
          children: [
            // Header with Step count and Close button
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 12, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: context.chipBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: context.borderColor),
                    ),
                    child: Text(
                      context.trArgs('wt_feature_x_of_y', {'current': _currentPage + 1, 'total': steps.length}),
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: context.textSecondary,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: context.tr('close'),
                    icon: Icon(Icons.close_rounded,
                        color: context.textSecondary, size: 20),
                    onPressed: _finish,
                  ),
                ],
              ),
            ),

            // Page View with the 5 steps
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: steps.length,
                onPageChanged: (idx) => setState(() => _currentPage = idx),
                itemBuilder: (ctx, index) {
                  final step = steps[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Center(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Animated Hero Icon
                            Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: step.gradientColors,
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(22),
                                boxShadow: [
                                  BoxShadow(
                                    color: step.gradientColors.first
                                        .withValues(alpha: 0.35),
                                    blurRadius: 20,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child:
                                  Icon(step.icon, size: 40, color: Colors.white),
                            ),
                            const SizedBox(height: 20),

                            // Title
                            Text(
                              context.tr(step.title),
                              textAlign: TextAlign.center,
                              style: GoogleFonts.outfit(
                                fontSize: 19,
                                fontWeight: FontWeight.w700,
                                color: context.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 10),

                            // Subtitle
                            Text(
                              context.tr(step.subtitle),
                              textAlign: TextAlign.center,
                              style: GoogleFonts.outfit(
                                fontSize: 13,
                                height: 1.4,
                                color: context.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Feature Chips
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              alignment: WrapAlignment.center,
                              children: step.tags.map((tag) {
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: context.subtleCardBg,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: context.borderColor),
                                  ),
                                  child: Text(
                                    context.tr(tag),
                                    style: GoogleFonts.outfit(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      color: context.textPrimary,
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            // Bottom Navigation and Dot Indicators
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                children: [
                  // Smooth Dots
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      steps.length,
                      (idx) => AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: _currentPage == idx ? 24 : 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: _currentPage == idx
                              ? AppThemes.success
                              : context.borderColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Actions
                  Row(
                    children: [
                      TextButton(
                        onPressed: _finish,
                        child: Text(
                          context.tr('wt_skip'),
                          style: GoogleFonts.outfit(
                            color: context.textSecondary,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const Spacer(),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppThemes.success,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        onPressed: _next,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _currentPage == steps.length - 1
                                  ? context.tr('wt_get_started')
                                  : context.tr('wt_next'),
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              _currentPage == steps.length - 1
                                  ? Icons.check_circle_rounded
                                  : Icons.arrow_forward_rounded,
                              size: 16,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WalkthroughStep {
  final IconData icon;
  final List<Color> gradientColors;
  final String title;
  final String subtitle;
  final List<String> tags;

  const _WalkthroughStep({
    required this.icon,
    required this.gradientColors,
    required this.title,
    required this.subtitle,
    required this.tags,
  });
}
