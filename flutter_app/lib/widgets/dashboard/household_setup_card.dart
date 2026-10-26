import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_localizations.dart';
import '../../models/household_membership.dart';
import '../../models/household_setup.dart';
import '../../models/money.dart';
import '../../services/api_service.dart';
import '../../services/household_setting_saver.dart';
import '../../services/salary_cycle_service.dart';
import '../../theme/app_themes.dart';
import '../app_snackbar.dart';
import '../settings/household_roles_card.dart';
import '../settings/income_settings_card.dart';
import '../settings/payday_settings_card.dart';
import '../settings/role_invite_dialog.dart';

/// Creates one category budget for the current cycle; true when the server
/// confirmed it (`POST /budgets/categories`).
typedef StarterBudgetCreator = Future<bool> Function(String categoryCode, String categoryName, double amount);

/// Device-local flags of the checklist (SharedPreferences).
class HouseholdSetupPrefs {
  static String paydayConfirmedKey(String householdId) => 'setup_payday_confirmed_$householdId';
  static String hiddenKey(String householdId) => 'setup_hidden_$householdId';

  static Future<void> setPaydayConfirmed(String householdId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(paydayConfirmedKey(householdId), true);
    } catch (_) {}
  }

  static Future<void> setHidden(String householdId, [bool hidden = true]) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(hiddenKey(householdId), hidden);
    } catch (_) {}
  }

  static Future<bool> isHidden(String householdId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(hiddenKey(householdId)) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Loads the checklist's data from the existing endpoints (payday, income,
  /// members). A value that cannot be read stays null.
  static Future<HouseholdSetupData> load(String householdId, {ApiService? api}) async {
    final service = api ?? ApiService.instance;
    Future<T?> attempt<T>(Future<T> Function() call) async {
      try {
        return await call();
      } catch (_) {
        return null;
      }
    }

    final results = await Future.wait<Object?>([
      attempt(() => service.getHouseholdPayday(householdId)),
      attempt(() => service.getHouseholdIncome(householdId)),
      attempt(() => service.getHouseholdMembers(householdId)),
    ]);
    var confirmed = false;
    var hidden = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      confirmed = prefs.getBool(paydayConfirmedKey(householdId)) ?? false;
      hidden = prefs.getBool(hiddenKey(householdId)) ?? false;
    } catch (_) {}
    final payday = results[0] as int?;
    return HouseholdSetupData(
      paydayDay: payday,
      // A payday other than the default was chosen on purpose.
      paydayConfirmed: confirmed || (payday != null && payday != SalaryCycleService.defaultPaydayDay),
      monthlyIncome: results[1] as double?,
      roster: results[2] as HouseholdRoster?,
      hidden: hidden,
    );
  }
}

/// "Set up your household in two minutes" (UX-02): the first-run checklist
/// for a household admin, each step opening the existing editor. A member who
/// is not an admin is told that the admin sets things up.
class HouseholdSetupCard extends StatelessWidget {
  final String householdId;
  final HouseholdSetupData data;

  /// The current cycle has budgets.
  final bool hasBudgets;

  /// A step changed something: reload [data].
  final VoidCallback onChanged;

  /// Hides the checklist (offered only once budgets exist).
  final VoidCallback? onHide;

  // Seams for tests; default to the API and SharedPreferences.
  final StarterBudgetCreator? createBudget;
  final Future<bool> Function(int day)? savePayday;
  final Future<bool> Function(double income)? saveIncome;
  final Future<void> Function()? confirmPayday;

  const HouseholdSetupCard({
    super.key,
    required this.householdId,
    required this.data,
    required this.hasBudgets,
    required this.onChanged,
    this.onHide,
    this.createBudget,
    this.savePayday,
    this.saveIncome,
    this.confirmPayday,
  });

  /// Opens a modal bottom sheet displaying the setup checklist.
  /// Allows reviewing progress and restoring the checklist to the dashboard.
  static Future<void> showChecklistSheet(
    BuildContext context, {
    required String householdId,
    VoidCallback? onRestored,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _HouseholdSetupSheet(
        householdId: householdId,
        onRestored: onRestored,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!data.isAdmin) return _waitingForAdmin(context);

    final steps = data.steps;
    final done = data.doneCount(hasBudgets: hasBudgets);
    return Container(
      key: const Key('household_setup_card'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: context.accentSubtleBorder,
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('setup_title'),
                      style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w800, color: context.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.trArgs('setup_progress', {'done': done, 'total': steps.length}),
                      style: TextStyle(color: context.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (hasBudgets && onHide != null)
                TextButton(
                  onPressed: onHide,
                  style: TextButton.styleFrom(
                    foregroundColor: context.accentText,
                  ),
                  child: Text(context.tr('setup_hide')),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: steps.isEmpty ? 0 : done / steps.length,
              minHeight: 5,
              backgroundColor: context.chipBg,
              valueColor: AlwaysStoppedAnimation(
                context.accentText,
              ),
            ),
          ),
          const SizedBox(height: 6),
          for (final step in steps) _stepRow(context, step),
        ],
      ),
    );
  }

  Widget _waitingForAdmin(BuildContext context) => Container(
        key: const Key('household_setup_waiting'),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.cardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: context.borderColor),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.hourglass_top_rounded, color: context.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('setup_waiting_admin_title'),
                    style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w700, color: context.textPrimary),
                  ),
                  const SizedBox(height: 4),
                  Text(context.tr('setup_waiting_admin_desc'), style: TextStyle(color: context.textSecondary, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      );

  String _stepLabel(BuildContext context, SetupStep step) {
    switch (step) {
      case SetupStep.payday:
        return context.trArgs('setup_step_payday', {'day': data.paydayDay ?? SalaryCycleService.paydayDay});
      case SetupStep.income:
        final income = data.monthlyIncome ?? 0;
        return income > 0
            ? context.trArgs('setup_step_income_done', {'amount': context.sar(income, decimals: 0)})
            : context.tr('setup_step_income');
      case SetupStep.budgets:
        return context.tr('setup_step_budgets');
      case SetupStep.invite:
        return context.tr(data.isFamily ? 'setup_step_invite_family' : 'setup_step_invite_roommates');
      case SetupStep.provider:
        return context.tr('setup_step_provider');
    }
  }

  IconData _stepIcon(SetupStep step) {
    switch (step) {
      case SetupStep.payday:
        return Icons.event_rounded;
      case SetupStep.income:
        return Icons.payments_outlined;
      case SetupStep.budgets:
        return Icons.pie_chart_outline_rounded;
      case SetupStep.invite:
        return Icons.person_add_alt_1_rounded;
      case SetupStep.provider:
        return Icons.family_restroom_rounded;
    }
  }

  Widget _stepRow(BuildContext context, SetupStep step) {
    final isDone = data.isDone(step, hasBudgets: hasBudgets);
    return InkWell(
      key: Key('setup_step_${step.name}'),
      borderRadius: BorderRadius.circular(12),
      onTap: () => _open(context, step),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            Icon(
              isDone ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              color: isDone
                  ? (context.accentText)
                  : context.textSecondary,
              size: 22,
            ),
            const SizedBox(width: 10),
            Icon(_stepIcon(step), size: 18, color: context.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _stepLabel(context, step),
                style: TextStyle(
                  color: context.textPrimary,
                  fontSize: 13.5,
                  fontWeight: isDone ? FontWeight.w500 : FontWeight.w700,
                ),
              ),
            ),
            if (step == SetupStep.payday && !isDone)
              TextButton(
                key: const Key('setup_confirm_payday'),
                style: TextButton.styleFrom(
                  foregroundColor: context.accentText,
                ),
                onPressed: () async {
                  await (confirmPayday ?? () => HouseholdSetupPrefs.setPaydayConfirmed(householdId))();
                  onChanged();
                },
                child: Text(context.tr('setup_confirm')),
              )
            else
              Icon(
                context.isRtl ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
                color: context.textSecondary,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, SetupStep step) async {
    switch (step) {
      case SetupStep.payday:
        await _sheet(
          context,
          PaydaySettingsCard(
            initialPayday: data.paydayDay ?? SalaryCycleService.paydayDay,
            onSavePayday: (day) async {
              final ok = await (savePayday ?? (d) => _defaultSavePayday(context, d))(day);
              if (ok) {
                await (confirmPayday ?? () => HouseholdSetupPrefs.setPaydayConfirmed(householdId))();
                onChanged();
              }
              return ok;
            },
          ),
        );
      case SetupStep.income:
        await _sheet(
          context,
          IncomeSettingsCard(
            initialIncome: data.monthlyIncome ?? 0,
            onSaveIncome: (income) async {
              final ok = await (saveIncome ?? (v) => _defaultSaveIncome(context, v))(income);
              if (ok) onChanged();
              return ok;
            },
          ),
        );
      case SetupStep.budgets:
        await _sheet(
          context,
          StarterBudgetSheet(
            monthlyIncome: data.monthlyIncome,
            createBudget: createBudget ?? _defaultCreateBudget,
            onCreated: onChanged,
          ),
        );
      case SetupStep.invite:
        await showDialog<void>(
          context: context,
          builder: (_) => RoleInviteDialog(
            householdId: householdId,
            initialRole: data.isFamily ? 'spouse' : 'peer',
          ),
        );
        onChanged();
      case SetupStep.provider:
        await _sheet(
          context,
          HouseholdRolesCard(
            householdId: householdId,
            onNafaqahProviderChanged: (_) => onChanged(),
          ),
        );
    }
  }

  Future<void> _sheet(BuildContext context, Widget child) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        // The settings editors reused here are laid out for a full-width card.
        constraints: const BoxConstraints(maxWidth: 720),
        backgroundColor: context.scaffoldBg,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (ctx) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
              child: child,
            ),
          ),
        ),
      );

  /// Server first (MOB-27): the local cycle arithmetic changes only once the
  /// API confirmed the payday.
  Future<bool> _defaultSavePayday(BuildContext context, int day) async {
    try {
      await saveHouseholdSetting<int>(
        householdId: householdId,
        value: day,
        saveRemote: (hid, d) => ApiService.instance.setHouseholdPayday(hid, d),
        applyLocal: (d) async {
          SalaryCycleService.paydayDay = d;
          await SalaryCycleService.cachePayday(d);
        },
      );
      return true;
    } catch (e) {
      if (context.mounted) {
        AppSnackBar.showError(
          context,
          context.trArgs('set_failed_save_payday', {'error': _saveError(context, e)}),
          title: context.tr('set_payday_error'),
        );
      }
      return false;
    }
  }

  Future<bool> _defaultSaveIncome(BuildContext context, double income) async {
    try {
      await saveHouseholdSetting<double>(
        householdId: householdId,
        value: income,
        saveRemote: (hid, v) => ApiService.instance.setHouseholdIncome(hid, v),
        applyLocal: (v) async {
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setDouble('household_monthly_income', v);
          } catch (_) {}
        },
      );
      return true;
    } catch (e) {
      if (context.mounted) {
        AppSnackBar.showError(
          context,
          context.trArgs('set_failed_save_income', {'error': _saveError(context, e)}),
          title: context.tr('set_income_error'),
        );
      }
      return false;
    }
  }

  String _saveError(BuildContext context, Object e) =>
      e is HouseholdSettingNotSavedException ? context.tr('setting_not_saved_server') : e.toString();

  Future<bool> _defaultCreateBudget(String code, String name, double amount) async {
    try {
      final res = await ApiService.instance.addBudgetCategory(
        householdId: householdId,
        code: code,
        category: name,
        allocatedAmount: amount,
      );
      return res['status'] == 'success';
    } catch (_) {
      return false;
    }
  }
}

/// The suggested starter budget: one amount per category, pre-filled from the
/// income (editable, 0 skips), created for the current cycle.
class StarterBudgetSheet extends StatefulWidget {
  final double? monthlyIncome;
  final StarterBudgetCreator createBudget;
  final VoidCallback onCreated;

  const StarterBudgetSheet({
    super.key,
    required this.monthlyIncome,
    required this.createBudget,
    required this.onCreated,
  });

  @override
  State<StarterBudgetSheet> createState() => _StarterBudgetSheetState();
}

class _StarterBudgetSheetState extends State<StarterBudgetSheet> {
  late final List<StarterBudgetRow> _rows = starterBudgetTemplate(widget.monthlyIncome);
  late final Map<String, TextEditingController> _controllers = {
    for (final r in _rows) r.categoryCode: TextEditingController(text: r.amount > 0 ? r.amount.toStringAsFixed(0) : ''),
  };
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _create() async {
    final amounts = <String, double>{};
    for (final r in _rows) {
      final text = _controllers[r.categoryCode]!.text.trim();
      if (text.isEmpty) continue;
      final value = parseMoneyInput(text, allowNegative: false);
      if (value == null) {
        setState(() => _error = context.tr('starter_budgets_invalid'));
        return;
      }
      if (value > 0) amounts[r.categoryCode] = value;
    }
    if (amounts.isEmpty) {
      setState(() => _error = context.tr('starter_budgets_none'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final failed = <String>[];
    var created = 0;
    for (final entry in amounts.entries) {
      final ok = await widget.createBudget(entry.key, context.trCat(entry.key), entry.value);
      if (!mounted) return;
      if (ok) {
        created++;
      } else {
        failed.add(context.trCat(entry.key));
      }
    }
    if (!mounted) return;
    if (created > 0) widget.onCreated();
    if (failed.isEmpty) {
      AppSnackBar.showSuccess(context, context.tr('starter_budgets_created'));
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _saving = false;
      _error = context.trArgs('starter_budgets_partial', {'categories': failed.join(context.isArabic ? '، ' : ', ')});
    });
  }

  @override
  Widget build(BuildContext context) {
    final income = widget.monthlyIncome ?? 0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.tr('starter_budgets_title'),
          style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800, color: context.textPrimary),
        ),
        const SizedBox(height: 4),
        Text(
          income > 0
              ? context.trArgs('starter_budgets_desc_income', {'amount': context.sar(income, decimals: 0)})
              : context.tr('starter_budgets_desc_no_income'),
          style: TextStyle(color: context.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 12),
        for (final r in _rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: TextField(
              key: Key('starter_amount_${r.categoryCode}'),
              controller: _controllers[r.categoryCode],
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: context.trCat(r.categoryCode),
                suffixText: context.tr('sar'),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
            ),
          ),
        if (_error != null) ...[
          Text(_error!, style: TextStyle(color: context.dangerColor, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
        ],
        ElevatedButton(
          onPressed: _saving ? null : _create,
          style: ElevatedButton.styleFrom(
            backgroundColor: context.primaryButtonBg,
            foregroundColor: context.primaryButtonFg,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(context.tr('starter_budgets_create'), style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}

class _HouseholdSetupSheet extends StatefulWidget {
  final String householdId;
  final VoidCallback? onRestored;

  const _HouseholdSetupSheet({
    required this.householdId,
    this.onRestored,
  });

  @override
  State<_HouseholdSetupSheet> createState() => _HouseholdSetupSheetState();
}

class _HouseholdSetupSheetState extends State<_HouseholdSetupSheet> {
  late Future<HouseholdSetupData> _future;
  bool _restoring = false;

  @override
  void initState() {
    super.initState();
    _future = HouseholdSetupPrefs.load(widget.householdId);
  }

  void _reload() {
    setState(() {
      _future = HouseholdSetupPrefs.load(widget.householdId);
    });
  }

  Future<void> _restoreChecklist() async {
    setState(() => _restoring = true);
    await HouseholdSetupPrefs.setHidden(widget.householdId, false);
    if (!mounted) return;
    AppSnackBar.showSuccess(
      context,
      context.tr('setup_card_restored'),
    );
    widget.onRestored?.call();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.scaffoldBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: context.borderColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr('household_setup_checklist'),
                          style: GoogleFonts.outfit(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: context.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          context.tr('household_setup_checklist_desc'),
                          style: TextStyle(
                            fontSize: 12,
                            color: context.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    color: context.textSecondary,
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FutureBuilder<HouseholdSetupData>(
                future: _future,
                builder: (ctx, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }
                  if (snap.hasError || !snap.hasData) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        context.tr('load_error_generic'),
                        style: TextStyle(color: context.dangerColor),
                        textAlign: TextAlign.center,
                      ),
                    );
                  }
                  final data = snap.data!;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      HouseholdSetupCard(
                        householdId: widget.householdId,
                        data: data,
                        hasBudgets: true,
                        onChanged: _reload,
                        onHide: null,
                      ),
                      const SizedBox(height: 16),
                      if (data.hidden)
                        ElevatedButton.icon(
                          key: const Key('restore_setup_checklist_button'),
                          onPressed: _restoring ? null : _restoreChecklist,
                          icon: const Icon(Icons.dashboard_customize_rounded, size: 18),
                          label: Text(
                            context.tr('restore_to_dashboard'),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: context.primaryButtonBg,
                            foregroundColor: context.primaryButtonFg,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

