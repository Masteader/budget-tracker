import 'package:flutter/material.dart';
import '../theme/app_themes.dart';
import 'package:google_fonts/google_fonts.dart';
import '../l10n/app_localizations.dart';

/// Reusable store name input & 'Spent by who?' selector card.
/// Ensures consistent UX across receipt scanner, chat confirmation, and manual entry.
class StoreAttributionCard extends StatelessWidget {
  final TextEditingController merchantController;
  final String selectedSpentBy;
  final ValueChanged<String> onSpentByChanged;
  final ValueChanged<String>? onMerchantChanged;
  /// Card title; defaults to the localized "Store & Attribution Details".
  final String? title;
  final bool compact;

  /// Asks "spent by whom?". A family household hides it: the Nafaqah
  /// question next to the card already says who paid (UX-03).
  final bool showSpentBy;

  const StoreAttributionCard({
    super.key,
    required this.merchantController,
    required this.selectedSpentBy,
    required this.onSpentByChanged,
    this.onMerchantChanged,
    this.title,
    this.compact = false,
    this.showSpentBy = true,
  });

  Widget _buildSpentByOption(
    BuildContext context, {
    required String key,
    required String label,
    required IconData icon,
    required Color activeColor,
  }) {
    final isSelected = selectedSpentBy.toLowerCase() == key;
    return Expanded(
      child: GestureDetector(
        onTap: () => onSpentByChanged(key),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: compact ? 8 : 10),
          decoration: BoxDecoration(
            color: isSelected ? activeColor.withValues(alpha: 0.18) : context.subtleCardBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? activeColor : context.borderColor,
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: compact ? 16 : 18, color: isSelected ? activeColor : context.textSecondary),
              const SizedBox(height: 3),
              Text(
                label,
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? (context.isDark ? Colors.white : const Color(0xFF0F172A)) : context.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: compact ? 8 : 14),
      padding: EdgeInsets.all(compact ? 12 : 14),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.storefront_outlined, color: AppThemes.success, size: 18),
              const SizedBox(width: 8),
              Text(
                title ?? context.tr('sac_title'),
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w700,
                  fontSize: compact ? 12 : 13,
                  color: context.textPrimary,
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 8 : 12),
          TextField(
            controller: merchantController,
            style: TextStyle(color: context.textPrimary, fontSize: 13),
            onChanged: onMerchantChanged,
            decoration: InputDecoration(
              labelText: context.tr('sac_store_label'),
              labelStyle: TextStyle(color: context.textSecondary, fontSize: 11),
              prefixIcon: const Icon(Icons.store_outlined, color: AppThemes.success, size: 18),
              filled: true,
              fillColor: context.inputBg,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: compact ? 10 : 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: context.borderColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: context.borderColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppThemes.success),
              ),
            ),
          ),
          if (showSpentBy) ...[
          SizedBox(height: compact ? 10 : 14),
          Text(
            context.tr('sac_spent_by_caps'),
            style: GoogleFonts.outfit(
              fontSize: 10,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w600,
              color: context.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _buildSpentByOption(context,
                key: 'me',
                label: context.tr('me'),
                icon: Icons.person_outline,
                activeColor: const Color(0xFF58A6FF),
              ),
              const SizedBox(width: 6),
              _buildSpentByOption(context,
                key: 'partner',
                label: context.tr('partner'),
                icon: Icons.favorite_outline,
                activeColor: const Color(0xFFBC8CFF),
              ),
              const SizedBox(width: 6),
              _buildSpentByOption(context,
                key: 'both',
                label: context.tr('both_shared'),
                icon: Icons.group_outlined,
                activeColor: AppThemes.success,
              ),
            ],
          ),
          ],
        ],
      ),
    );
  }
}
