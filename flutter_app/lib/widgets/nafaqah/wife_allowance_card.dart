import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/app_localizations.dart';
import '../../models/money.dart';
import '../../models/nafaqah.dart';
import '../../services/api_service.dart';
import '../../theme/app_themes.dart';
import '../app_snackbar.dart';

/// Saves the wife's allowance for a cycle. Defaults to the API; injectable for tests.
typedef AllowanceSetter = Future<AllowanceStatus> Function({
  required double amount,
  required String wifeUserId,
  String? cycleKey,
});

/// The wife's personal allowance ("مصروفها") for the salary cycle: allocated,
/// spent on her personal purchases and remaining. Overspend is shown as a
/// negative remainder, never blocked. Only the husband or a household admin
/// (never the wife herself) can set it.
class WifeAllowanceCard extends StatelessWidget {
  final String householdId;
  final NafaqahWife wife;
  final String? cycleKey;
  final bool viewerIsWife;
  final bool canSet;
  final bool showWifeName;
  final AllowanceSetter? setAllowance;
  final VoidCallback? onChanged;

  const WifeAllowanceCard({
    super.key,
    required this.householdId,
    required this.wife,
    this.cycleKey,
    this.viewerIsWife = false,
    this.canSet = false,
    this.showWifeName = false,
    this.setAllowance,
    this.onChanged,
  });

  Future<void> _openEditor(BuildContext context) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AllowanceEditorSheet(
        householdId: householdId,
        wifeUserId: wife.id,
        cycleKey: cycleKey ?? wife.allowance.cycleKey,
        initialAmount: wife.allowance.isSet ? wife.allowance.allocated : null,
        setAllowance: setAllowance,
      ),
    );
    if (saved == true) onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final st = wife.allowance;
    final key = cycleKey ?? st.cycleKey;
    final cycle = AppLocalizations.of(context).cycleLabel(key, fallback: key);
    final remainingColor = st.isOverspent ? context.dangerColor : context.successText;
    final barColor = st.isOverspent ? context.dangerColor : AppThemes.iceCyan;
    final title = viewerIsWife ? context.tr('allowance_title_mine') : context.tr('allowance_title');

    return Container(
      key: ValueKey('wife_allowance_${wife.id}'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: st.isOverspent ? context.dangerColor.withValues(alpha: 0.4) : context.borderColor,
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppThemes.iceCyan.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.account_balance_wallet_outlined, color: AppThemes.iceCyan, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      showWifeName && (wife.displayName ?? '').isNotEmpty ? '$title · ${wife.displayName}' : title,
                      style: GoogleFonts.outfit(color: context.textPrimary, fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      context.trArgs('allowance_subtitle', {'cycle': cycle}),
                      style: TextStyle(color: context.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (!st.hasAllowance) ...[
            Text(
              context.trArgs(
                viewerIsWife ? 'allowance_personal_spending_mine' : 'allowance_personal_spending_her',
                {'amount': context.sar(st.spent)},
              ),
              key: const ValueKey('allowance_personal_spending'),
              style: GoogleFonts.outfit(color: context.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ] else ...[
            Row(
              children: [
                _Stat(label: context.tr('allowance_allocated'), value: context.sar(st.allocated), color: context.textPrimary),
                _Stat(label: context.tr('allowance_spent'), value: context.sar(st.spent), color: context.textPrimary),
                _Stat(
                  key: const ValueKey('allowance_remaining_value'),
                  label: context.tr('allowance_remaining'),
                  value: context.sar(st.remaining),
                  color: remainingColor,
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: st.usedFraction,
                minHeight: 6,
                backgroundColor: context.subtleCardBg,
                valueColor: AlwaysStoppedAnimation<Color>(barColor),
              ),
            ),
          ],
          if (st.isOverspent) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 14, color: context.dangerColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    context.trArgs('allowance_overspent', {'amount': context.sar(-st.remaining)}),
                    style: TextStyle(color: context.dangerColor, fontSize: 11.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
          if (!st.hasAllowance) ...[
            const SizedBox(height: 8),
            Text(context.tr('allowance_not_set'), style: TextStyle(color: context.textSecondary, fontSize: 11.5)),
          ],
          if (canSet) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppThemes.iceCyan,
                  side: BorderSide(color: AppThemes.iceCyan.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.tune_rounded, size: 18),
                label: Text(st.isSet ? context.tr('allowance_edit') : context.tr('allowance_set')),
                onPressed: () => _openEditor(context),
              ),
            ),
          ] else if (viewerIsWife) ...[
            const SizedBox(height: 8),
            Text(context.tr('allowance_set_by_husband'), style: TextStyle(color: context.textSecondary, fontSize: 11)),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _Stat({super.key, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: context.textSecondary, fontSize: 11)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              value,
              style: GoogleFonts.outfit(color: color, fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _AllowanceEditorSheet extends StatefulWidget {
  final String householdId;
  final String wifeUserId;
  final String cycleKey;
  final double? initialAmount;
  final AllowanceSetter? setAllowance;

  const _AllowanceEditorSheet({
    required this.householdId,
    required this.wifeUserId,
    required this.cycleKey,
    this.initialAmount,
    this.setAllowance,
  });

  @override
  State<_AllowanceEditorSheet> createState() => _AllowanceEditorSheetState();
}

class _AllowanceEditorSheetState extends State<_AllowanceEditorSheet> {
  late final TextEditingController _ctrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialAmount?.toStringAsFixed(2) ?? '');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = parseMoneyInput(_ctrl.text.trim());
    if (amount == null || amount < 0) {
      AppSnackBar.showError(context, context.tr('settle_invalid_amount'));
      return;
    }
    setState(() => _saving = true);
    try {
      final setter = widget.setAllowance ??
          ({required double amount, required String wifeUserId, String? cycleKey}) => ApiService.instance
              .setWifeAllowance(widget.householdId, amount: amount, wifeUserId: wifeUserId, cycleKey: cycleKey);
      await setter(
        amount: amount,
        wifeUserId: widget.wifeUserId,
        cycleKey: widget.cycleKey.isEmpty ? null : widget.cycleKey,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      final forbidden = e is NafaqahApiException && e.code == 'forbidden';
      AppSnackBar.showError(
        context,
        forbidden ? context.tr('nafaqah_err_forbidden') : e.toString(),
        title: context.tr('allowance_save_failed'),
      );
      return;
    }
    if (!mounted) return;
    AppSnackBar.showSuccess(context, context.sar(amount), title: context.tr('allowance_saved'));
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.trArgs('allowance_set_title', {
              'cycle': AppLocalizations.of(context).cycleLabel(widget.cycleKey, fallback: widget.cycleKey),
            }),
            style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: context.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(context.tr('allowance_set_by_husband'), style: TextStyle(color: context.textSecondary, fontSize: 12)),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('allowance_amount_field'),
            controller: _ctrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: context.tr('allowance_amount_label'),
              prefixIcon: const Icon(Icons.account_balance_wallet_outlined),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppThemes.iceCyan,
              foregroundColor: AppThemes.deepGlacial,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppThemes.deepGlacial),
                  )
                : const Icon(Icons.check_rounded, size: 18),
            label: Text(context.tr('allowance_save'), style: const TextStyle(fontWeight: FontWeight.bold)),
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
    );
  }
}
