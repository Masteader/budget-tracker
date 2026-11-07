import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_themes.dart';
import 'tutor_navigator.dart';

export 'tutor_navigator.dart' show TutorAction, TutorNavigator;

/// The Interactive Setup Tutor: payday, accounts, budgets, the household's
/// living model and the ways to record an expense.
///
/// The dialog never navigates: a step's button closes it with a
/// [TutorAction], and [AppSetupTutorDialog.show] opens that screen from the
/// caller's context once the dialog has gone.
class AppSetupTutorDialog extends StatefulWidget {
  /// Called once the tutor is marked seen, with the chosen action (null when
  /// it was closed, skipped or finished).
  final ValueChanged<TutorAction?>? onClose;
  final String? householdId;

  const AppSetupTutorDialog({
    super.key,
    this.onClose,
    this.householdId,
  });

  static const String prefKey = 'has_seen_setup_tutor_v2';

  /// Shows the tutor (e.g. from Settings or Help), then opens what the chosen
  /// step's button asked for.
  static Future<void> show(
    BuildContext context, {
    String? householdId,
    bool? fallbackIsAdmin,
    @visibleForTesting TutorNavigator? navigator,
  }) async {
    final action = await showDialog<TutorAction>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: AppSetupTutorDialog(
          householdId: householdId,
          onClose: (action) => Navigator.of(ctx).pop(action),
        ),
      ),
    );
    if (action == null || householdId == null && TutorNavigator.needsHousehold(action)) return;
    if (!context.mounted) return;
    await (navigator ?? const TutorNavigator()).open(context, action, householdId ?? '');
  }

  /// Shows the tutor once per phone (the first time the dashboard opens).
  static Future<bool> showIfFirstTime(
    BuildContext context, {
    String? householdId,
    @visibleForTesting TutorNavigator? navigator,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeen = prefs.getBool(prefKey) ?? false;
    if (!hasSeen && context.mounted) {
      await prefs.setBool(prefKey, true);
      if (!context.mounted) return false;
      await show(context, householdId: householdId, navigator: navigator);
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
  bool _closing = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  bool get _hasHousehold => widget.householdId != null && widget.householdId!.isNotEmpty;

  /// A button is offered only when its screen can open.
  TutorAction? _offer(TutorAction action) =>
      _hasHousehold || !TutorNavigator.needsHousehold(action) ? action : null;

  List<_TutorStep> get _steps => [
        _TutorStep(
          icon: Icons.calendar_month_rounded,
          titleKey: 'tutor_stage_1_title',
          descKey: 'tutor_stage_1_desc',
          actionBtnKey: 'tutor_stage_1_btn',
          actionIcon: Icons.calendar_today_rounded,
          action: _offer(TutorAction.payday),
          secondaryBtnKey: 'record_income',
          secondaryAction: _offer(TutorAction.income),
        ),
        _TutorStep(
          icon: Icons.account_balance_wallet_rounded,
          titleKey: 'tutor_stage_2_title',
          descKey: 'tutor_stage_2_desc',
          actionBtnKey: 'tutor_stage_2_btn',
          actionIcon: Icons.account_balance_rounded,
          action: _offer(TutorAction.accounts),
        ),
        _TutorStep(
          icon: Icons.pie_chart_rounded,
          titleKey: 'tutor_stage_3_title',
          descKey: 'tutor_stage_3_desc',
          actionBtnKey: 'tutor_stage_3_btn',
          actionIcon: Icons.tune_rounded,
          action: _offer(TutorAction.budgets),
        ),
        _TutorStep(
          icon: Icons.family_restroom_rounded,
          titleKey: 'tutor_stage_4_title',
          descKey: 'tutor_stage_4_desc',
          actionBtnKey: 'tutor_stage_4_btn',
          actionIcon: Icons.shield_outlined,
          action: _offer(TutorAction.roles),
        ),
        const _TutorStep(
          icon: Icons.rocket_launch_rounded,
          titleKey: 'tutor_stage_5_title',
          descKey: 'tutor_stage_5_desc',
          actionBtnKey: 'tutor_stage_5_btn',
          actionIcon: Icons.check_circle_rounded,
          finishes: true,
        ),
      ];

  void _next(int count) {
    if (_currentPage < count - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _close(null);
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

  /// Marks the tutor seen, then closes it with [action].
  Future<void> _close(TutorAction? action) async {
    if (_closing) return;
    _closing = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(AppSetupTutorDialog.prefKey, true);
    } catch (_) {}
    if (mounted) {
      widget.onClose?.call(action);
    }
  }

  @override
  Widget build(BuildContext context) {
    final steps = _steps;
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
                        'total': '${steps.length}',
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
                    onPressed: () => _close(null),
                  ),
                ],
              ),
            ),

            // Page View with the 5 interactive stages
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
                            // 3D Hero Icon Badge
                            Container(
                              width: 82,
                              height: 82,
                              decoration: BoxDecoration(
                                gradient: context.icedAccentGradient,
                                borderRadius: BorderRadius.circular(22),
                                boxShadow: [
                                  BoxShadow(
                                    color: context.primaryButtonBg.withValues(alpha: 0.35),
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

                            if (step.finishes || step.action != null)
                              ElevatedButton.icon(
                                key: ValueKey('tutor_action_${step.finishes ? 'finish' : step.action!.name}'),
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
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    fontFamilyFallback: VelvetBurgundyTheme.arabicFallback,
                                  ),
                                ),
                                onPressed: () => _close(step.action),
                              ),
                            if (step.secondaryAction != null) ...[
                              const SizedBox(height: 10),
                              OutlinedButton(
                                key: ValueKey('tutor_action_${step.secondaryAction!.name}'),
                                onPressed: () => _close(step.secondaryAction),
                                child: Text(
                                  context.tr(step.secondaryBtnKey!),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    fontFamilyFallback: VelvetBurgundyTheme.arabicFallback,
                                  ),
                                ),
                              ),
                            ],
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
                      steps.length,
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
                            key: const ValueKey('tutor_skip'),
                            onPressed: () => _close(null),
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
                            key: const ValueKey('tutor_next'),
                            onPressed: () => _next(steps.length),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    _currentPage == steps.length - 1
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
                                  _currentPage == steps.length - 1
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
  final IconData icon;
  final String titleKey;
  final String descKey;
  final String actionBtnKey;
  final IconData actionIcon;

  /// What the main button opens; null for no button (unless [finishes]).
  final TutorAction? action;

  /// The last step: its button closes the tutor.
  final bool finishes;
  final String? secondaryBtnKey;
  final TutorAction? secondaryAction;

  const _TutorStep({
    required this.icon,
    required this.titleKey,
    required this.descKey,
    required this.actionBtnKey,
    required this.actionIcon,
    this.action,
    this.finishes = false,
    this.secondaryBtnKey,
    this.secondaryAction,
  });
}
