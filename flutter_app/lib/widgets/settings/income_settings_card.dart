import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../app_snackbar.dart';
import '../../theme/app_themes.dart';
import '../../l10n/app_localizations.dart';
import '../../models/money.dart';

/// Card for setting and updating household monthly salary/income (SAR).
class IncomeSettingsCard extends StatefulWidget {
  final double initialIncome;
  final Future<bool> Function(double newIncome) onSaveIncome;

  const IncomeSettingsCard({
    super.key,
    this.initialIncome = 0.0,
    required this.onSaveIncome,
  });

  @override
  State<IncomeSettingsCard> createState() => _IncomeSettingsCardState();
}

class _IncomeSettingsCardState extends State<IncomeSettingsCard> {
  late final TextEditingController _incomeCtrl;
  bool _saving = false;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _incomeCtrl = TextEditingController(
      text: widget.initialIncome > 0 ? widget.initialIncome.toStringAsFixed(0) : '',
    );
  }

  @override
  void didUpdateWidget(covariant IncomeSettingsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialIncome != widget.initialIncome && !_isEditing) {
      _incomeCtrl.text = widget.initialIncome > 0 ? widget.initialIncome.toStringAsFixed(0) : '';
    }
  }

  @override
  void dispose() {
    _incomeCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    final parsed = parseMoneyInput(_incomeCtrl.text.trim()) ?? 0.0;
    if (parsed < 0) {
      AppSnackBar.showError(context, context.tr('isc_negative'));
      return;
    }

    setState(() => _saving = true);
    final success = await widget.onSaveIncome(parsed);
    if (mounted) {
      setState(() {
        _saving = false;
        if (success) _isEditing = false;
      });
      if (success) {
        AppSnackBar.showSuccess(
          context,
          context.trArgs('isc_updated', {'amount': context.sar(parsed)}),
          title: context.tr('isc_saved_title'),
          icon: Icons.payments_rounded,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardColor = context.cardBg;
    final borderColor = context.borderColor;
    final textColor = context.textPrimary;
    final subtextColor = context.textSecondary;

    final currentIncome = parseMoneyInput(_incomeCtrl.text) ?? widget.initialIncome;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Icon + Title + Current Income Badge
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppThemes.success.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.payments_rounded,
                  color: AppThemes.success,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('isc_title'),
                      style: GoogleFonts.outfit(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.tr('isc_subtitle'),
                      style: TextStyle(
                        color: subtextColor,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (!_isEditing)
                IconButton(
                  icon: const Icon(Icons.edit_rounded, size: 18, color: AppThemes.success),
                  tooltip: context.tr('isc_edit'),
                  onPressed: () => setState(() => _isEditing = true),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // Display or Edit Mode
          if (!_isEditing) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: context.subtleCardBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    context.tr('isc_configured'),
                    style: TextStyle(color: subtextColor, fontSize: 13),
                  ),
                  Text(
                    currentIncome > 0 ? context.sar(currentIncome) : context.tr('isc_not_configured'),
                    style: GoogleFonts.outfit(
                      color: currentIncome > 0 ? AppThemes.success : subtextColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            // Input TextField
            TextField(
              controller: _incomeCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16),
              decoration: InputDecoration(
                labelText: context.tr('isc_monthly_income_sar'),
                labelStyle: TextStyle(color: subtextColor),
                prefixIcon: const Icon(Icons.attach_money_rounded, color: AppThemes.success),
                suffixText: context.tr('sar'),
                suffixStyle: TextStyle(color: subtextColor, fontWeight: FontWeight.bold),
                filled: true,
                fillColor: context.inputBg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: borderColor),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Quick Preset Buttons
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [5000, 10000, 15000, 20000, 25000].map((preset) {
                return InkWell(
                  onTap: () {
                    setState(() => _incomeCtrl.text = preset.toString());
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: context.chipBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: borderColor),
                    ),
                    child: Text(
                      context.sar(preset, decimals: 0),
                      style: TextStyle(
                        fontSize: 11,
                        color: textColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),

            // Action Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => setState(() => _isEditing = false),
                  child: Text(context.tr('cancel'), style: TextStyle(color: subtextColor)),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppThemes.success,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _saving ? null : _handleSave,
                  child: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                        )
                      : Text(context.tr('save_income'), style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
