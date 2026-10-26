import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_localizations.dart';
import '../../screens/accounts/accounts_overview_screen.dart';
import '../../screens/home/budget_management_screen.dart';
import '../../screens/settings/settings_screen.dart';
import '../../theme/app_themes.dart';

/// 5-Stage Interactive Setup Tutor Wizard for Saudi Households.
/// Walks users through Payday Cycle, Accounts vs. Vaults, Budget Envelopes,
/// Living Model (Islamic Nafaqah vs. Roommates), and Three Recording Modes.
class AppSetupTutorDialog extends StatefulWidget {
  final VoidCallback? onDismiss;
  final ValueChanged<String>? onActionTriggered;
  final String? householdId;

  const AppSetupTutorDialog({
    super.key,
    this.onDismiss,
    this.onActionTriggered,
    this.householdId,
  });

  static const String prefKey = 'has_seen_setup_tutor_v2';

  /// Shows the tutor dialog unconditionally (e.g. from Settings or Help).
  static Future<void> show(
    BuildContext context, {
    String? householdId,
    ValueChanged<String>? onActionTriggered,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: AppSetupTutorDialog(
          householdId: householdId,
          onActionTriggered: onActionTriggered,
          onDismiss: () => Navigator.of(ctx).pop(),
        ),
      ),
    );
  }

  /// Automatically shows the dialog forcefully on first launch if not yet seen.
  static Future<bool> showIfFirstTime(
    BuildContext context, {
    String? householdId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeen = prefs.getBool(prefKey) ?? false;
    if (!hasSeen && context.mounted) {
      await show(context, householdId: householdId);
      await prefs.setBool(prefKey, true);
      return true;
    }
    return false;
  }

  @override
  State<AppSetupTutorDialog> createState() => _AppSetupTutorDialogState();
}

class _AppSetupTutorDialogState extends State<AppSetupTutorDialog> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  static const List<_TutorStep> _steps = [
    _TutorStep(
      id: 'stage_1',
      icon: Icons.calendar_month_rounded,
      gradient: [Color(0xFF800020), Color(0xFFB76E79)],
      titleKey: 'tutor_stage_1_title',
      descKey: 'tutor_stage_1_desc',
      actionBtnKey: 'tutor_stage_1_btn',
      actionIcon: Icons.calendar_today_rounded,
      routeAction: 'open_payday',
    ),
    _TutorStep(
      id: 'stage_2',
      icon: Icons.account_balance_wallet_rounded,
      gradient: [Color(0xFF1E3A8A), Color(0xFF3B82F6)],
      titleKey: 'tutor_stage_2_title',
      descKey: 'tutor_stage_2_desc',
      actionBtnKey: 'tutor_stage_2_btn',
      actionIcon: Icons.account_balance_rounded,
      routeAction: 'open_accounts',
    ),
    _TutorStep(
      id: 'stage_3',
      icon: Icons.pie_chart_rounded,
      gradient: [Color(0xFF065F46), Color(0xFF10B981)],
      titleKey: 'tutor_stage_3_title',
      descKey: 'tutor_stage_3_desc',
      actionBtnKey: 'tutor_stage_3_btn',
      actionIcon: Icons.tune_rounded,
      routeAction: 'open_budgets',
    ),
    _TutorStep(
      id: 'stage_4',
      icon: Icons.family_restroom_rounded,
      gradient: [Color(0xFF581C87), Color(0xFF9333EA)],
      titleKey: 'tutor_stage_4_title',
      descKey: 'tutor_stage_4_desc',
      actionBtnKey: 'tutor_stage_4_btn',
      actionIcon: Icons.shield_outlined,
      routeAction: 'open_roles',
    ),
    _TutorStep(
      id: 'stage_5',
      icon: Icons.rocket_launch_rounded,
      gradient: [Color(0xFF9A3412), Color(0xFFF97316)],
      titleKey: 'tutor_stage_5_title',
      descKey: 'tutor_stage_5_desc',
      actionBtnKey: 'tutor_stage_5_btn',
      actionIcon: Icons.check_circle_rounded,
      routeAction: 'finish',
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

  void _prev() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _finish() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(AppSetupTutorDialog.prefKey, true);
    } catch (_) {}
    if (mounted) {
      widget.onDismiss?.call();
    }
  }

  void _handleStepAction(_TutorStep step) {
    widget.onActionTriggered?.call(step.routeAction);
    if (step.routeAction == 'finish') {
      _finish();
      return;
    }
    if (widget.onActionTriggered == null) {
      _finish();
      switch (step.routeAction) {
        case 'open_payday':
        case 'open_roles':
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SettingsScreen()),
          );
          break;
        case 'open_accounts':
          if (widget.householdId != null) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AccountsOverviewScreen(householdId: widget.householdId!),
              ),
            );
          } else {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            );
          }
          break;
        case 'open_budgets':
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const BudgetManagementScreen()),
          );
          break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 420, maxHeight: 620),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: context.isDark ? VelvetBurgundyColors.roseBorderDark : VelvetBurgundyColors.roseBorderLight,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: context.isDark ? 0.6 : 0.15),
            blurRadius: 32,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(
          children: [
            // Top Header: Step Badge & Close button
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 12, 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: context.icedHeroGradient.colors,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: context.primaryButtonBg.withValues(alpha: 0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      context.trArgs('tutor_step_badge', {
                        'current': '${_currentPage + 1}',
                        'total': '${_steps.length}',
                      }),
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: context.tr('close'),
                    icon: Icon(Icons.close_rounded, color: context.textSecondary, size: 20),
                    onPressed: _finish,
                  ),
                ],
              ),
            ),

            // Page View with the 5 interactive stages
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
                            // 3D Hero Icon Badge
                            Container(
                              width: 82,
                              height: 82,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: step.gradient,
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(22),
                                boxShadow: [
                                  BoxShadow(
                                    color: step.gradient.first.withValues(alpha: 0.35),
                                    blurRadius: 20,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: Icon(step.icon, size: 42, color: Colors.white),
                            ),
                            const SizedBox(height: 18),

                            // Stage Title
                            Text(
                              context.tr(step.titleKey),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: context.textPrimary,
                                fontFamilyFallback: VelvetBurgundyTheme.arabicFallback,
                              ),
                            ),
                            const SizedBox(height: 10),

                            // Stage Description
                            Text(
                              context.tr(step.descKey),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.5,
                                color: context.textSecondary,
                                fontFamilyFallback: VelvetBurgundyTheme.arabicFallback,
                              ),
                            ),
                            const SizedBox(height: 20),

                            // Direct Action Button
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: context.primaryButtonBg,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                elevation: 3,
                              ),
                              icon: Icon(step.actionIcon, size: 18),
                              label: Text(
                                context.tr(step.actionBtnKey),
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  fontFamilyFallback: VelvetBurgundyTheme.arabicFallback,
                                ),
                              ),
                              onPressed: () => _handleStepAction(step),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            // Bottom Navigation, Progress Dots & Prev/Next Controls
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
              child: Column(
                children: [
                  // Smooth Progress Dots
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
                              ? context.primaryButtonBg
                              : context.borderColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Bottom Action Buttons
                  Row(
                    children: [
                      if (_currentPage > 0)
                        Flexible(
                          child: TextButton(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: _prev,
                            child: Text(
                              context.tr('tutor_btn_prev'),
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: context.textSecondary,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                                fontFamilyFallback: VelvetBurgundyTheme.arabicFallback,
                              ),
                            ),
                          ),
                        )
                      else
                        Flexible(
                          child: TextButton(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: _finish,
                            child: Text(
                              context.tr('tutor_btn_skip'),
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: context.textSecondary,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                                fontFamilyFallback: VelvetBurgundyTheme.arabicFallback,
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppThemes.success,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              elevation: 0,
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: _next,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    _currentPage == _steps.length - 1
                                        ? context.tr('tutor_btn_finish')
                                        : context.tr('tutor_btn_next'),
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      fontFamilyFallback: VelvetBurgundyTheme.arabicFallback,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  _currentPage == _steps.length - 1
                                      ? Icons.check_circle_rounded
                                      : Icons.arrow_forward_rounded,
                                  size: 14,
                                ),
                              ],
                            ),
                          ),
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

class _TutorStep {
  final String id;
  final IconData icon;
  final List<Color> gradient;
  final String titleKey;
  final String descKey;
  final String actionBtnKey;
  final IconData actionIcon;
  final String routeAction;

  const _TutorStep({
    required this.id,
    required this.icon,
    required this.gradient,
    required this.titleKey,
    required this.descKey,
    required this.actionBtnKey,
    required this.actionIcon,
    required this.routeAction,
  });
}
