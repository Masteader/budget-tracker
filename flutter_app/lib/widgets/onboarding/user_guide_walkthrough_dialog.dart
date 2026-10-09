import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  final List<_WalkthroughStep> _steps = const [
    _WalkthroughStep(
      icon: Icons.qr_code_scanner_rounded,
      gradientColors: [Color(0xFF00C896), Color(0xFF007A5A)],
      title: 'AI Invoice & ZATCA Scanner',
      subtitle:
          'Snap paper receipts with multi-page camera or scan official Saudi ZATCA QR codes for instant itemized extraction and tax breakdown.',
      tags: ['ZATCA TLV Verified', 'Line-Item Breakdown', 'Duplicate Defense'],
    ),
    _WalkthroughStep(
      icon: Icons.mic_rounded,
      gradientColors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
      title: 'Voice & Dialect Chat',
      subtitle:
          'Log expenses effortlessly speaking or typing in Saudi colloquial dialect, or ask our AI simulator whether you can afford a new purchase.',
      tags: ['Saudi Dialect', 'Purchase Simulator', 'Instant Logging'],
    ),
    _WalkthroughStep(
      icon: Icons.calendar_month_rounded,
      gradientColors: [Color(0xFFF59E0B), Color(0xFFB45309)],
      title: 'Salary Cycles & Payday (27th)',
      subtitle:
          'Stay on top of your financial health with automated salary cycles aligned to the 27th payday, daily allowance pacing, and cycle rollovers.',
      tags: ['27th Payday Cycle', 'Burn-Rate Forecast', 'Cycle Rollover'],
    ),
    _WalkthroughStep(
      icon: Icons.receipt_long_rounded,
      gradientColors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
      title: 'Recurring Bills & Installments',
      subtitle:
          'Never miss a due date. Reserve funds for Rent, SEC electricity, and Iqama fees with 1-tap payments, plus track Tabby & Tamara installments.',
      tags: ['1-Tap Bill Pay', 'Iqama & Rent Reserves', 'BNPL Tracking'],
    ),
    _WalkthroughStep(
      icon: Icons.people_alt_rounded,
      gradientColors: [Color(0xFF10B981), Color(0xFF047857)],
      title: 'Household & 2D Partner Split',
      subtitle:
          'Share expenses transparently with your spouse or family. Track who paid vs who benefited with automatic zero-friction monthly settlements.',
      tags: ['2D Attribution', 'Net Settlements', 'Joint Household'],
    ),
  ];

  void _next() {
    if (_currentPage < _steps.length - 1) {
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
    return Container(
      constraints: const BoxConstraints(maxWidth: 420, maxHeight: 600),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF30363D), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.6),
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
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF21262D),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF30363D)),
                    ),
                    child: Text(
                      'Feature ${_currentPage + 1} of ${_steps.length}',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF8B949E),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: Color(0xFF8B949E), size: 20),
                    onPressed: _finish,
                  ),
                ],
              ),
            ),

            // Page View with the 5 steps
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _steps.length,
                onPageChanged: (idx) => setState(() => _currentPage = idx),
                itemBuilder: (ctx, index) {
                  final step = _steps[index];
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
                                        .withOpacity(0.35),
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
                              step.title,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.outfit(
                                fontSize: 19,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 10),

                            // Subtitle
                            Text(
                              step.subtitle,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.outfit(
                                fontSize: 13,
                                height: 1.4,
                                color: const Color(0xFF8B949E),
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
                                    color: const Color(0xFF0D1117),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: const Color(0xFF30363D)),
                                  ),
                                  child: Text(
                                    tag,
                                    style: GoogleFonts.outfit(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      color: const Color(0xFFC9D1D9),
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
                      _steps.length,
                      (idx) => AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: _currentPage == idx ? 24 : 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: _currentPage == idx
                              ? const Color(0xFF00C896)
                              : const Color(0xFF30363D),
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
                          'Skip',
                          style: GoogleFonts.outfit(
                            color: const Color(0xFF8B949E),
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const Spacer(),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00C896),
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
                              _currentPage == _steps.length - 1
                                  ? 'Get Started'
                                  : 'Next',
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              _currentPage == _steps.length - 1
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
