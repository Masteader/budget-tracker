import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_themes.dart';
import '../app_snackbar.dart';

/// Card for customizing budget surplus rollover behavior at payday.
/// Provides user options:
/// 1. 'send_to_savings' (Default): Sweeps positive unspent cycle surplus to Savings Reserve.
/// 2. 'rollover_to_categories': Inherits delta into same categories in next cycle.
/// 3. 'fresh_start': Discards surplus and resets categories cleanly to base allocations.
class RolloverSettingsCard extends StatefulWidget {
  final String initialRule;
  final double accumulatedSavings;
  final Future<bool> Function(String newRule) onSaveRule;

  const RolloverSettingsCard({
    super.key,
    this.initialRule = 'send_to_savings',
    this.accumulatedSavings = 0.0,
    required this.onSaveRule,
  });

  @override
  State<RolloverSettingsCard> createState() => _RolloverSettingsCardState();
}

class _RolloverSettingsCardState extends State<RolloverSettingsCard> {
  late String _selectedRule;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selectedRule = widget.initialRule;
  }

  @override
  void didUpdateWidget(covariant RolloverSettingsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialRule != widget.initialRule) {
      setState(() => _selectedRule = widget.initialRule);
    }
  }

  Future<void> _handleSave() async {
    setState(() => _saving = true);
    final success = await widget.onSaveRule(_selectedRule);
    if (mounted) {
      setState(() => _saving = false);
      if (success) {
        AppSnackBar.showSuccess(
          context,
          context.tr('rollover_policy_saved'),
          title: context.tr('budget_rollover_rules'),
          icon: Icons.savings_rounded,
          duration: const Duration(seconds: 3),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasChanges = _selectedRule != widget.initialRule;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF00C896).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.savings_rounded,
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
                      context.tr('budget_rollover_rules'),
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.tr('budget_rollover_rules_subtitle'),
                      style: TextStyle(
                        color: context.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              // Current Rule Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF00C896).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF00C896),
                    width: 0.8,
                  ),
                ),
                child: Text(
                  _selectedRule == 'send_to_savings'
                      ? context.tr('rsc_badge_savings')
                      : _selectedRule == 'rollover_to_categories'
                          ? context.tr('rsc_badge_carryover')
                          : context.tr('rsc_badge_fresh'),
                  style: const TextStyle(
                    color: Color(0xFF00C896),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),

          // Accumulated Savings Banner if available
          if (widget.accumulatedSavings > 0) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF00C896).withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF00C896).withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFF00C896), size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      context.tr('accumulated_savings_pool'),
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        color: context.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Text(
                    context.sar(widget.accumulatedSavings),
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF00C896),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),
          Divider(color: context.borderColor, height: 1),
          const SizedBox(height: 16),

          // Option 1: Send All to Savings (Default)
          _buildOptionCard(
            rule: 'send_to_savings',
            title: context.tr('rollover_send_to_savings_title'),
            description: context.tr('rollover_send_to_savings_desc'),
            icon: Icons.savings_rounded,
            iconColor: const Color(0xFF00C896),
            isRecommended: true,
          ),
          const SizedBox(height: 10),

          // Option 2: Rollover to Same Categories
          _buildOptionCard(
            rule: 'rollover_to_categories',
            title: context.tr('rollover_to_categories_title'),
            description: context.tr('rollover_to_categories_desc'),
            icon: Icons.swap_horiz_rounded,
            iconColor: const Color(0xFF58A6FF),
            isRecommended: false,
          ),
          const SizedBox(height: 10),

          // Option 3: Fresh Start
          _buildOptionCard(
            rule: 'fresh_start',
            title: context.tr('rollover_fresh_start_title'),
            description: context.tr('rollover_fresh_start_desc'),
            icon: Icons.restart_alt_rounded,
            iconColor: const Color(0xFFF0883E),
            isRecommended: false,
          ),

          const SizedBox(height: 18),

          // Action Save Button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: hasChanges
                    ? const Color(0xFF00C896)
                    : context.cardBg,
                foregroundColor: hasChanges ? Colors.black : context.textPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: hasChanges
                        ? const Color(0xFF00C896)
                        : context.borderColor,
                  ),
                ),
                elevation: hasChanges ? 2 : 0,
              ),
              onPressed: _saving ? null : _handleSave,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.check_circle_outline_rounded,
                          size: 18,
                          color: hasChanges ? Colors.black : context.textSecondary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          context.tr('save_rollover_policy'),
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionCard({
    required String rule,
    required String title,
    required String description,
    required IconData icon,
    required Color iconColor,
    required bool isRecommended,
  }) {
    final isSelected = _selectedRule == rule;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => setState(() => _selectedRule = rule),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? iconColor.withValues(alpha: 0.10)
              : context.cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? iconColor : context.borderColor,
            width: isSelected ? 1.6 : 1.0,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: GoogleFonts.outfit(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: context.textPrimary,
                          ),
                        ),
                      ),
                      if (isRecommended) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00C896).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            context.tr('rollover_recommended'),
                            style: const TextStyle(
                              color: Color(0xFF00C896),
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.textSecondary,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? iconColor : context.borderColor,
                  width: 2,
                ),
                color: isSelected ? iconColor : Colors.transparent,
              ),
              child: isSelected
                  ? const Icon(
                      Icons.check,
                      size: 14,
                      color: Colors.black,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
