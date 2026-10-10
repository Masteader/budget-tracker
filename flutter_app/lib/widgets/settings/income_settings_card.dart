import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../app_snackbar.dart';

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
    final parsed = double.tryParse(_incomeCtrl.text.trim()) ?? 0.0;
    if (parsed < 0) {
      AppSnackBar.showError(context, 'Income cannot be negative');
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
        final formatted = NumberFormat('#,##0.00').format(parsed);
        AppSnackBar.showSuccess(
          context,
          'Monthly income updated to $formatted SAR',
          title: 'Income Saved',
          icon: Icons.payments_rounded,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF161B22) : Colors.white;
    final borderColor = isDark ? const Color(0xFF30363D) : const Color(0xFFE2E8F0);
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subtextColor = isDark ? const Color(0xFF8B949E) : const Color(0xFF64748B);

    final currentIncome = double.tryParse(_incomeCtrl.text) ?? widget.initialIncome;
    final formattedIncome = NumberFormat('#,##0.00').format(currentIncome);

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
                  color: const Color(0xFF00C896).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.payments_rounded,
                  color: Color(0xFF00C896),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Monthly Salary / Income',
                      style: GoogleFonts.outfit(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Base for budget allocations & savings reserve',
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
                  icon: const Icon(Icons.edit_rounded, size: 18, color: Color(0xFF00C896)),
                  tooltip: 'Edit Income',
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
                color: isDark ? const Color(0xFF0D1117) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Configured Income:',
                    style: TextStyle(color: subtextColor, fontSize: 13),
                  ),
                  Text(
                    currentIncome > 0 ? '$formattedIncome SAR' : 'Not configured (0 SAR)',
                    style: GoogleFonts.outfit(
                      color: currentIncome > 0 ? const Color(0xFF00C896) : subtextColor,
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
                labelText: 'Monthly Income (SAR)',
                labelStyle: TextStyle(color: subtextColor),
                prefixIcon: const Icon(Icons.attach_money_rounded, color: Color(0xFF00C896)),
                suffixText: 'SAR',
                suffixStyle: TextStyle(color: subtextColor, fontWeight: FontWeight.bold),
                filled: true,
                fillColor: isDark ? const Color(0xFF0D1117) : const Color(0xFFF1F5F9),
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
                      color: isDark ? const Color(0xFF21262D) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: borderColor),
                    ),
                    child: Text(
                      '${NumberFormat('#,###').format(preset)} SAR',
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
                  child: Text('Cancel', style: TextStyle(color: subtextColor)),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00C896),
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
                      : const Text('Save Income', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
