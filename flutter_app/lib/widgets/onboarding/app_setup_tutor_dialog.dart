import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_localizations.dart';
import '../../models/household_membership.dart';
import '../../models/tutor_viewer.dart';
import '../../providers/household_role_provider.dart' show viewerIsAdminOf;
import '../../services/api_service.dart';
import '../../theme/app_themes.dart';
import 'tutor_navigator.dart';

export '../../models/tutor_viewer.dart' show TutorAction, TutorViewer, TutorRoleStep;
export 'tutor_navigator.dart' show TutorNavigator;

typedef TutorRosterLoader = Future<HouseholdRoster> Function(String householdId);

/// The Interactive Setup Tutor: payday and income, accounts, budgets, the
/// household's living model, a step for the person's role (a wife, the
/// husband, or a roommate) and the ways to record an expense. Admin-only
/// buttons are shown to admins only (display only; [TutorViewer]).
///
/// The dialog never navigates: a step's button closes it with a
/// [TutorAction], and [AppSetupTutorDialog.show] opens that screen from the
/// caller's context once the dialog has gone.
class AppSetupTutorDialog extends StatefulWidget {
  /// Called once the tutor is marked seen, with the chosen action (null when
  /// it was closed, skipped or finished).
  final ValueChanged<TutorAction?>? onClose;
  final String? householdId;

  /// Who is looking; without one, the member steps.
  final TutorViewer viewer;

  const AppSetupTutorDialog({
    super.key,
    this.onClose,
    this.householdId,
    this.viewer = const TutorViewer(isAdmin: false),
  });

  /// Set once the tutor has been shown on this phone. `v3` is the role-aware
  /// tutor: everyone who saw the earlier one (`has_seen_setup_tutor_v2`, left
  /// as it is) sees this one once (owner decision D1, 2026-11-07).
  static const String prefKey = 'has_seen_setup_tutor_v3';

  /// Shows the tutor (e.g. from Settings or Help), then opens what the chosen
  /// step's button asked for. Without a [roster], it loads the household's
  /// members ([loadRoster]) when [loadMissingRoster]; if that fails, the
  /// cached admin flag ([fallbackIsAdmin], else the role provider) decides.
  ///
  /// Returns the action that ran (null when none did), once its screen has
  /// closed; [onActionDone] is told the same, so the caller can refresh.
  static Future<TutorAction?> show(
    BuildContext context, {
    String? householdId,
    HouseholdRoster? roster,
    bool? fallbackIsAdmin,
    bool loadMissingRoster = true,
    ValueChanged<TutorAction>? onActionDone,
    @visibleForTesting TutorRosterLoader? loadRoster,
    @visibleForTesting TutorNavigator? navigator,
  }) async {
    final hasHousehold = householdId != null && householdId.isNotEmpty;
    final fallback = fallbackIsAdmin ?? viewerIsAdminOf(context, householdId);
    Future<TutorViewer> viewer() async {
      var r = roster;
      if (r == null && hasHousehold && loadMissingRoster) {
        try {
          r = await (loadRoster ?? ApiService.instance.getHouseholdMembers)(householdId)
              .timeout(const Duration(seconds: 8));
        } catch (_) {
          r = null;
        }
      }
      return TutorViewer.from(roster: r, fallbackIsAdmin: fallback);
    }

    final action = await showDialog<TutorAction>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: _TutorLoader(
          viewer: roster != null ? Future.value(TutorViewer.from(roster: roster, fallbackIsAdmin: fallback)) : viewer(),
          householdId: householdId,
          onClose: (action) => Navigator.of(ctx).pop(action),
        ),
      ),
    );
    if (action == null || !hasHousehold && TutorNavigator.needsHousehold(action)) return null;
    if (!context.mounted) return null;
    await (navigator ?? const TutorNavigator()).open(context, action, householdId ?? '');
    onActionDone?.call(action);
    return action;
  }

  /// Shows the tutor once per phone (the first time the dashboard opens).
  static Future<bool> showIfFirstTime(
    BuildContext context, {
    String? householdId,
    HouseholdRoster? roster,
    bool loadMissingRoster = true,
    ValueChanged<TutorAction>? onActionDone,
    @visibleForTesting TutorNavigator? navigator,
  }) async {
    final SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      return false;
    }
    final hasSeen = prefs.getBool(prefKey) ?? false;
    if (!hasSeen && context.mounted) {
      await prefs.setBool(prefKey, true);
      if (!context.mounted) return false;
      await show(
        context,
        householdId: householdId,
        roster: roster,
        loadMissingRoster: loadMissingRoster,
        onActionDone: onActionDone,
        navigator: navigator,
      );
      return true;
    }
    return false;
  }

  @override
  State<AppSetupTutorDialog> createState() => _AppSetupTutorDialogState();
}

/// Waits for the viewer (the member list may still be loading) before
/// showing the steps; closing works meanwhile.
class _TutorLoader extends StatelessWidget {
  final Future<TutorViewer> viewer;
  final String? householdId;
  final ValueChanged<TutorAction?> onClose;

  const _TutorLoader({required this.viewer, required this.householdId, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<TutorViewer>(
      future: viewer,
      builder: (context, snap) {
        if (!snap.hasData) {
          return Container(
            constraints: const BoxConstraints(maxWidth: 420, minHeight: 160),
            decoration: BoxDecoration(
              color: context.cardBg,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: context.borderColor, width: 1.5),
            ),
            child: Stack(
              children: [
                Center(child: CircularProgressIndicator(color: context.accentText)),
                PositionedDirectional(
                  top: 8,
                  end: 8,
                  child: IconButton(
                    tooltip: context.tr('close'),
                    icon: Icon(Icons.close_rounded, color: context.textSecondary, size: 20),
                    onPressed: () => onClose(null),
                  ),
                ),
              ],
            ),
          );
        }
        return AppSetupTutorDialog(householdId: householdId, viewer: snap.data!, onClose: onClose);
      },
    );
  }
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

  /// The exact UI names each text inserts, so they match the buttons in
  /// every language.
  static const Map<String, Map<String, String>> _labels = {
    'tutor_stage_1_desc': {'payday': 'pds_title', 'income': 'record_income', 'tools': 'tools_title'},
    'tutor_stage_1_desc_member': {'income': 'record_income', 'tools': 'tools_title'},
    'tutor_stage_3_desc': {'prior': 'apply_prior_spend_adjustment', 'budgets': 'nav_budgets'},
    'tutor_stage_3_desc_member': {'budgets': 'nav_budgets'},
    'tutor_stage_5_desc': {'add': 'add_expense', 'voice': 'voice_chat', 'scan': 'scan_receipt', 'manual': 'manual_log'},
    'tutor_role_wife_desc': {
      'whoPaid': 'nafaqah_q_title',
      'shared': 'nafaqah_w_opt_shared',
      'personal': 'nafaqah_w_opt_personal',
      'received': 'nafaqah_mark_received',
    },
    'tutor_role_husband_desc': {
      'addWife': 'wife_acc_add_title',
      'accounts': 'accounts_balances',
      'reimburse': 'reimburse_wife',
      'received': 'nafaqah_mark_received',
      'approve': 'req_approve',
      'decline': 'req_decline',
      'reverse': 'rev_action',
    },
    'tutor_role_roommate_desc': {
      'splitAll': 'roommate_split_all',
      'personal': 'roommate_split_personal',
      'fewest': 'simplify_debts',
      'settle': 'settle_now',
    },
  };

  String _text(String key) {
    final labels = _labels[key];
    if (labels == null) return context.tr(key);
    return context.trArgs(key, {for (final e in labels.entries) e.key: context.tr(e.value)});
  }

  List<_TutorStep> get _steps => [
        for (final spec in widget.viewer.steps(hasHousehold: _hasHousehold)) _stepFor(spec),
      ];

  _TutorStep _stepFor(TutorStepSpec spec) {
    final admin = widget.viewer.isAdmin;
    switch (spec.id) {
      case TutorStepId.payday:
        return _TutorStep(
          spec: spec,
          icon: Icons.calendar_month_rounded,
          titleKey: 'tutor_stage_1_title',
          descKey: admin ? 'tutor_stage_1_desc' : 'tutor_stage_1_desc_member',
          actionBtnKey: admin ? 'tutor_stage_1_btn' : 'record_income',
          actionIcon: admin ? Icons.calendar_today_rounded : Icons.add_card_rounded,
          secondaryBtnKey: 'record_income',
        );
      case TutorStepId.accounts:
        return _TutorStep(
          spec: spec,
          icon: Icons.account_balance_wallet_rounded,
          titleKey: 'tutor_stage_2_title',
          descKey: 'tutor_stage_2_desc',
          actionBtnKey: 'tutor_stage_2_btn',
          actionIcon: Icons.account_balance_rounded,
        );
      case TutorStepId.budgets:
        return _TutorStep(
          spec: spec,
          icon: Icons.pie_chart_rounded,
          titleKey: 'tutor_stage_3_title',
          descKey: admin ? 'tutor_stage_3_desc' : 'tutor_stage_3_desc_member',
          actionBtnKey: 'tutor_stage_3_btn',
          actionIcon: Icons.tune_rounded,
        );
      case TutorStepId.living:
        return _TutorStep(
          spec: spec,
          icon: Icons.family_restroom_rounded,
          titleKey: 'tutor_stage_4_title',
          descKey: 'tutor_stage_4_desc',
          actionBtnKey: 'roles_title',
          actionIcon: Icons.shield_outlined,
        );
      case TutorStepId.wife:
        return _TutorStep(
          spec: spec,
          icon: Icons.favorite_rounded,
          titleKey: 'tutor_role_wife_title',
          descKey: 'tutor_role_wife_desc',
          actionBtnKey: '',
          actionIcon: Icons.favorite_rounded,
        );
      case TutorStepId.husband:
        return _TutorStep(
          spec: spec,
          icon: Icons.volunteer_activism_rounded,
          titleKey: 'tutor_role_husband_title',
          descKey: 'tutor_role_husband_desc',
          actionBtnKey: 'accounts_balances',
          actionIcon: Icons.account_balance_rounded,
        );
      case TutorStepId.roommate:
        return _TutorStep(
          spec: spec,
          icon: Icons.groups_rounded,
          titleKey: 'tutor_role_roommate_title',
          descKey: 'tutor_role_roommate_desc',
          actionBtnKey: '',
          actionIcon: Icons.groups_rounded,
        );
      case TutorStepId.record:
        return _TutorStep(
          spec: spec,
          icon: Icons.rocket_launch_rounded,
          titleKey: 'tutor_stage_5_title',
          descKey: 'tutor_stage_5_desc',
          actionBtnKey: 'tutor_stage_5_btn',
          actionIcon: Icons.check_circle_rounded,
          finishes: true,
        );
    }
  }

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

  ButtonStyle get _primaryStyle => ElevatedButton.styleFrom(
        backgroundColor: context.primaryButtonBg,
        foregroundColor: context.primaryButtonFg,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 2,
      );

  static const TextStyle _buttonText = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.bold,
    fontFamilyFallback: VelvetBurgundyTheme.arabicFallback,
  );

  Widget _page(_TutorStep step) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Center(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Hero badge
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
              Text(
                _text(step.descKey),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: context.textSecondary,
                  fontFamilyFallback: VelvetBurgundyTheme.arabicFallback,
                ),
              ),
              if (step.spec.adminSetsNote) ...[
                const SizedBox(height: 14),
                Container(
                  key: const ValueKey('tutor_admin_note'),
                  padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 8),
                  decoration: BoxDecoration(
                    color: context.accentSubtleBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: context.accentSubtleBorder),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.info_outline_rounded, size: 16, color: context.accentText),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          context.tr('tutor_admin_sets_note'),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: context.accentText,
                            fontFamilyFallback: VelvetBurgundyTheme.arabicFallback,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (step.finishes || step.spec.action != null) ...[
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  key: ValueKey('tutor_action_${step.finishes ? 'finish' : step.spec.action!.name}'),
                  style: _primaryStyle,
                  icon: Icon(step.actionIcon, size: 18),
                  label: Text(context.tr(step.actionBtnKey), textAlign: TextAlign.center, style: _buttonText),
                  onPressed: () => _close(step.finishes ? null : step.spec.action),
                ),
              ],
              if (step.spec.secondaryAction != null) ...[
                const SizedBox(height: 10),
                OutlinedButton(
                  key: ValueKey('tutor_action_${step.spec.secondaryAction!.name}'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.accentText,
                    side: BorderSide(color: context.accentSubtleBorder),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () => _close(step.spec.secondaryAction),
                  child: Text(context.tr(step.secondaryBtnKey!), textAlign: TextAlign.center, style: _buttonText),
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final steps = _steps;
    final isLast = _currentPage >= steps.length - 1;
    return Container(
      constraints: const BoxConstraints(maxWidth: 420, maxHeight: 620),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: context.borderColor, width: 1.5),
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
            // Step badge and close button
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 12, 4),
              child: Row(
                children: [
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        gradient: context.icedHeroGradient,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        context.trArgs('tutor_step_badge', {
                          'current': '${_currentPage + 1}',
                          'total': '${steps.length}',
                        }),
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: context.heroText,
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: context.tr('close'),
                    icon: Icon(Icons.close_rounded, color: context.textSecondary, size: 20),
                    onPressed: () => _close(null),
                  ),
                ],
              ),
            ),

            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: steps.length,
                onPageChanged: (idx) => setState(() => _currentPage = idx),
                itemBuilder: (ctx, index) => _page(steps[index]),
              ),
            ),

            // Progress dots and the back / next buttons
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 20, 18),
              child: Column(
                children: [
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
                          color: _currentPage == idx ? context.primaryAccent : context.borderColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Flexible(
                        child: TextButton(
                          key: ValueKey(_currentPage > 0 ? 'tutor_prev' : 'tutor_skip'),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: _currentPage > 0 ? _prev : () => _close(null),
                          child: Text(
                            context.tr(_currentPage > 0 ? 'tutor_btn_prev' : 'tutor_btn_skip'),
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
                            key: const ValueKey('tutor_next'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: context.primaryButtonBg,
                              foregroundColor: context.primaryButtonFg,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              elevation: 0,
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () => _next(steps.length),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    context.tr(isLast ? 'tutor_btn_finish' : 'tutor_btn_next'),
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      fontFamilyFallback: VelvetBurgundyTheme.arabicFallback,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(isLast ? Icons.check_circle_rounded : Icons.arrow_forward_rounded, size: 14),
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
  final TutorStepSpec spec;
  final IconData icon;
  final String titleKey;
  final String descKey;
  final String actionBtnKey;
  final IconData actionIcon;

  /// The last step: its button closes the tutor.
  final bool finishes;
  final String? secondaryBtnKey;

  const _TutorStep({
    required this.spec,
    required this.icon,
    required this.titleKey,
    required this.descKey,
    required this.actionBtnKey,
    required this.actionIcon,
    this.finishes = false,
    this.secondaryBtnKey,
  });
}
