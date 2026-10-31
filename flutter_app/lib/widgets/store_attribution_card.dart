import 'package:flutter/material.dart';
import '../models/account.dart';
import '../theme/app_themes.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/widgets/three_d_surface_card.dart';
import '../l10n/app_localizations.dart';

/// Reusable store name input, 'Paid by', 'For whom?', and Nafaqah preview selector card.
/// Ensures consistent UX across receipt scanner, chat confirmation, and manual entry.
class StoreAttributionCard extends StatelessWidget {
  final TextEditingController merchantController;
  final String selectedSpentBy;
  final ValueChanged<String> onSpentByChanged;
  final ValueChanged<String>? onMerchantChanged;

  /// Card title; defaults to the localized "Store & Attribution Details".
  final String? title;
  final bool compact;

  /// Whether to show the payer selection section.
  final bool showSpentBy;

  /// Whether this household is in Family mode (Islamic Nafaqah).
  /// In Family mode, payer is strictly Me or Partner (no Both/Shared cashier split).
  final bool isFamily;

  /// The beneficiary: 'both' (household), 'me', 'partner', 'children', or specific name.
  final String? selectedBeneficiary;
  final ValueChanged<String>? onBeneficiaryChanged;

  /// List of dependent names if any.
  final List<String> dependents;

  /// Live Nafaqah Preview badge properties.
  final String? nafaqahBadgeText;
  final IconData? nafaqahBadgeIcon;
  final Color? nafaqahBadgeColor;

  /// Account selection.
  final List<Account> accounts;
  final String? selectedAccountId;
  final ValueChanged<String?>? onAccountChanged;

  const StoreAttributionCard({
    super.key,
    required this.merchantController,
    required this.selectedSpentBy,
    required this.onSpentByChanged,
    this.onMerchantChanged,
    this.title,
    this.compact = false,
    this.showSpentBy = true,
    this.isFamily = false,
    this.selectedBeneficiary,
    this.onBeneficiaryChanged,
    this.dependents = const [],
    this.nafaqahBadgeText,
    this.nafaqahBadgeIcon,
    this.nafaqahBadgeColor,
    this.accounts = const [],
    this.selectedAccountId,
    this.onAccountChanged,
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
        key: ValueKey('spent_by_$key'),
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
                  color: isSelected ? (context.textPrimary) : context.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChoiceChip(
    BuildContext context, {
    required String chipKey,
    required String label,
    required bool isSelected,
    required VoidCallback onSelected,
    IconData? icon,
  }) {
    final activeColor = context.accentText;
    return GestureDetector(
      key: ValueKey('beneficiary_$chipKey'),
      onTap: onSelected,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withValues(alpha: 0.18) : context.subtleCardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? activeColor : context.borderColor,
            width: isSelected ? 1.4 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: isSelected ? activeColor : context.textSecondary),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? context.textPrimary : context.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ben = selectedBeneficiary?.toLowerCase() ?? 'both';

    return ThreeDSurfaceCard(
      margin: EdgeInsets.only(bottom: compact ? 8 : 14),
      padding: EdgeInsets.all(compact ? 12 : 16),
      borderRadius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.storefront_outlined, color: context.accentText, size: 18),
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
              prefixIcon: Icon(Icons.store_outlined, color: context.accentText, size: 18),
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
                borderSide: BorderSide(color: context.accentText),
              ),
            ),
          ),

          // ── WHO PAID? ──────────────────────────────────────────────
          if (showSpentBy) ...[
            SizedBox(height: compact ? 10 : 14),
            Text(
              isFamily ? context.tr('scan_paid_by') : context.tr('sac_spent_by_caps'),
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
                _buildSpentByOption(
                  context,
                  key: 'me',
                  label: context.tr('me'),
                  icon: Icons.person_outline,
                  activeColor: context.infoColor,
                ),
                const SizedBox(width: 6),
                _buildSpentByOption(
                  context,
                  key: 'partner',
                  label: context.tr('partner'),
                  icon: Icons.favorite_outline,
                  activeColor: context.accentText,
                ),
                // Rule 02.3: In Family mode, never offer 'Both (Shared)' as the payer
                if (!isFamily) ...[
                  const SizedBox(width: 6),
                  _buildSpentByOption(
                    context,
                    key: 'both',
                    label: context.tr('both_shared'),
                    icon: Icons.group_outlined,
                    activeColor: context.accentText,
                  ),
                ],
              ],
            ),
          ],

          // ── FOR WHOM? ──────────────────────────────────────────────
          if (isFamily || onBeneficiaryChanged != null) ...[
            SizedBox(height: compact ? 10 : 14),
            Text(
              context.tr('scan_for_whom'),
              style: GoogleFonts.outfit(
                fontSize: 10,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w600,
                color: context.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _buildChoiceChip(
                  context,
                  chipKey: 'both',
                  label: context.tr('beneficiary_household'),
                  isSelected: ben == 'both' || ben == 'household',
                  onSelected: () => onBeneficiaryChanged?.call('both'),
                ),
                _buildChoiceChip(
                  context,
                  chipKey: 'me',
                  label: context.tr('beneficiary_me'),
                  isSelected: ben == 'me',
                  onSelected: () => onBeneficiaryChanged?.call('me'),
                ),
                _buildChoiceChip(
                  context,
                  chipKey: 'partner',
                  label: context.tr('beneficiary_partner'),
                  isSelected: ben == 'partner' || ben == 'wife',
                  onSelected: () => onBeneficiaryChanged?.call('partner'),
                ),
                _buildChoiceChip(
                  context,
                  chipKey: 'children',
                  label: context.tr('beneficiary_children'),
                  icon: Icons.child_care_rounded,
                  isSelected: ben == 'children',
                  onSelected: () => onBeneficiaryChanged?.call('children'),
                ),
                ...dependents.map((depName) {
                  return _buildChoiceChip(
                    context,
                    chipKey: depName.toLowerCase(),
                    label: depName,
                    icon: Icons.child_care_rounded,
                    isSelected: ben == depName.toLowerCase(),
                    onSelected: () => onBeneficiaryChanged?.call(depName.toLowerCase()),
                  );
                }),
              ],
            ),
          ],

          // ── LIVE NAFAQAH CLASSIFICATION BADGE ──────────────────────
          if (nafaqahBadgeText != null && nafaqahBadgeText!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: (nafaqahBadgeColor ?? context.accentText).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: (nafaqahBadgeColor ?? context.accentText).withValues(alpha: 0.35),
                  width: 1.0,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    nafaqahBadgeIcon ?? Icons.shield_outlined,
                    size: 16,
                    color: nafaqahBadgeColor ?? context.accentText,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      nafaqahBadgeText!,
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: nafaqahBadgeColor ?? context.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ── PAYMENT ACCOUNT ────────────────────────────────────────
          if (accounts.isNotEmpty) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: selectedAccountId,
              dropdownColor: context.cardBg,
              style: TextStyle(color: context.textPrimary, fontSize: 12),
              decoration: InputDecoration(
                labelText: context.tr('payment_account'),
                labelStyle: TextStyle(color: context.textSecondary, fontSize: 11),
                prefixIcon: Icon(Icons.account_balance_wallet_outlined, color: context.accentText, size: 18),
                filled: true,
                fillColor: context.inputBg,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: context.borderColor),
                ),
              ),
              items: accounts.map((acc) {
                return DropdownMenuItem<String>(
                  value: acc.id,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(acc.accountType.defaultIcon, size: 14, color: context.accentText),
                      const SizedBox(width: 6),
                      Text(
                        '${acc.name} (${context.sar(acc.balance)})',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: context.textPrimary, fontSize: 12),
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: onAccountChanged,
            ),
          ],
        ],
      ),
    );
  }
}
