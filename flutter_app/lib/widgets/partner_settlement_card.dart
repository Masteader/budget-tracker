import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/api_service.dart';
import '../theme/app_themes.dart';
import '../l10n/app_localizations.dart';
import 'app_snackbar.dart';

class PartnerSettlementCard extends StatefulWidget {
  final String householdId;
  final Map<String, dynamic>? initialData;

  const PartnerSettlementCard({
    super.key,
    required this.householdId,
    this.initialData,
  });

  @override
  State<PartnerSettlementCard> createState() => _PartnerSettlementCardState();
}

class _PartnerSettlementCardState extends State<PartnerSettlementCard> {
  Map<String, dynamic>? _data;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null) {
      _data = widget.initialData;
      _isLoading = false;
    } else {
      _loadSettlement();
    }
  }

  Future<void> _loadSettlement() async {
    final res = await ApiService.instance.getPartnerSettlement(widget.householdId);
    if (mounted) {
      setState(() {
        _data = res;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        height: 100,
        decoration: BoxDecoration(
          color: context.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.borderColor),
        ),
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00C896)),
          ),
        ),
      );
    }

    if (_data == null || _data!['total_shared_expenses'] == null) {
      return const SizedBox.shrink();
    }

    final whoOwes = _data!['who_owes'] as String? ?? 'settled';
    final settleAmt = (_data!['settlement_amount'] as num?)?.toDouble() ?? 0.0;
    final totalShared = (_data!['total_shared_expenses'] as num?)?.toDouble() ?? 0.0;
    final iPaidForPartner = (_data!['i_paid_for_partner_100'] as num?)?.toDouble() ?? 0.0;
    final partnerPaidForMe = (_data!['partner_paid_for_me_100'] as num?)?.toDouble() ?? 0.0;
    final stcNote = _data!['stc_pay_note'] as String? ?? context.tr('psc_household_settlement');
    final recEn = _data!['recommendation_en'] as String? ?? '';

    Color badgeColor = const Color(0xFF00C896);
    IconData badgeIcon = Icons.check_circle_outline_rounded;
    String statusTitle = context.tr('psc_balanced');

    if (whoOwes == 'partner_owes_me') {
      badgeColor = const Color(0xFF00C896);
      badgeIcon = Icons.arrow_downward_rounded;
      statusTitle = context.tr('psc_partner_owes_you');
    } else if (whoOwes == 'me_owes_partner') {
      badgeColor = const Color(0xFFFF9E79);
      badgeIcon = Icons.arrow_upward_rounded;
      statusTitle = context.tr('psc_you_owe_partner');
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF58A6FF).withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.people_alt_outlined, color: Color(0xFF58A6FF), size: 18),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        context.tr('partner_settlement'),
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          color: context.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(badgeIcon, size: 12, color: badgeColor),
                    const SizedBox(width: 4),
                    Text(
                      statusTitle,
                      style: TextStyle(
                        color: badgeColor,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Prominent Net Balance
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                context.sar(settleAmt),
                style: GoogleFonts.outfit(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: settleAmt > 0 ? badgeColor : context.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                whoOwes == 'settled'
                    ? context.tr('psc_all_square')
                    : (whoOwes == 'partner_owes_me' ? context.tr('psc_incoming') : context.tr('psc_outgoing')),
                style: TextStyle(color: context.textSecondary, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            context.isRtl
                ? (whoOwes == 'partner_owes_me'
                    ? context.trArgs('psc_rec_partner_owes', {'amount': context.sar(settleAmt)})
                    : (whoOwes == 'me_owes_partner'
                        ? context.trArgs('psc_rec_you_owe', {'amount': context.sar(settleAmt)})
                        : context.tr('psc_rec_balanced')))
                : recEn,
            style: TextStyle(color: context.textPrimary, fontSize: 13, height: 1.3),
          ),
          const SizedBox(height: 12),

          // 2D Breakdown Pills
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: context.chipBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: context.borderColor),
                ),
                child: Text(
                  context.trArgs('psc_shared', {'amount': context.sar(totalShared)}),
                  style: TextStyle(color: context.textSecondary, fontSize: 11),
                ),
              ),
              if (iPaidForPartner > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B5CF6).withValues(alpha: context.isDarkMode ? 0.1 : 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFF8B5CF6).withValues(alpha: context.isDarkMode ? 0.3 : 0.4),
                    ),
                  ),
                  child: Text(
                    context.trArgs('psc_paid_for_partner', {'amount': context.sar(iPaidForPartner)}),
                    style: TextStyle(
                      color: context.isDarkMode ? const Color(0xFFBC8CFF) : const Color(0xFF6D28D9),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              if (partnerPaidForMe > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF97316).withValues(alpha: context.isDarkMode ? 0.1 : 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFFF97316).withValues(alpha: context.isDarkMode ? 0.3 : 0.4),
                    ),
                  ),
                  child: Text(
                    context.trArgs('psc_partner_paid_for_me', {'amount': context.sar(partnerPaidForMe)}),
                    style: TextStyle(
                      color: context.isDarkMode ? const Color(0xFFFF9E79) : const Color(0xFFC2410C),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),

          if (settleAmt > 0) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.chipBg,
                  foregroundColor: const Color(0xFF00C896),
                  side: const BorderSide(color: Color(0xFF00C896)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
                label: Text(
                  context.trArgs('psc_settle_via', {'amount': context.sar(settleAmt)}),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                onPressed: () async {
                  HapticFeedback.lightImpact();
                  await Clipboard.setData(ClipboardData(text: '$stcNote - SAR ${settleAmt.toStringAsFixed(2)}'));
                  if (context.mounted) {
                    AppSnackBar.showSuccess(
                      context,
                      context.trArgs('psc_note_copied', {'note': '$stcNote - SAR ${settleAmt.toStringAsFixed(2)}'}),
                      title: context.tr('settle_copied_note'),
                      icon: Icons.account_balance_wallet_outlined,
                    );
                  }
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
