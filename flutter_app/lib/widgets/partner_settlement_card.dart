import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/api_service.dart';
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
          color: const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF30363D)),
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
    final stcNote = _data!['stc_pay_note'] as String? ?? 'Household Settlement';
    final recText = _data!['recommendation_en'] as String? ?? '';

    Color badgeColor = const Color(0xFF00C896);
    IconData badgeIcon = Icons.check_circle_outline_rounded;
    String statusTitle = "Expenses Balanced";

    if (whoOwes == 'partner_owes_me') {
      badgeColor = const Color(0xFF00C896);
      badgeIcon = Icons.arrow_downward_rounded;
      statusTitle = "Partner Owes You";
    } else if (whoOwes == 'me_owes_partner') {
      badgeColor = const Color(0xFFFF9E79);
      badgeIcon = Icons.arrow_upward_rounded;
      statusTitle = "You Owe Partner";
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF30363D)),
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
                        'Partner Settlement',
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          color: Colors.white,
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
                'SAR ${settleAmt.toStringAsFixed(2)}',
                style: GoogleFonts.outfit(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: settleAmt > 0 ? badgeColor : Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                whoOwes == 'settled'
                    ? 'All square'
                    : (whoOwes == 'partner_owes_me' ? 'incoming balance' : 'outgoing balance'),
                style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            recText,
            style: const TextStyle(color: Color(0xFFC9D1D9), fontSize: 13, height: 1.3),
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
                  color: const Color(0xFF0D1117),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF30363D)),
                ),
                child: Text(
                  'Shared 50/50: SAR ${totalShared.toStringAsFixed(2)}',
                  style: const TextStyle(color: Color(0xFF8B949E), fontSize: 11),
                ),
              ),
              if (iPaidForPartner > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFBC8CFF).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFBC8CFF).withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    'Paid for partner: SAR ${iPaidForPartner.toStringAsFixed(2)}',
                    style: const TextStyle(color: Color(0xFFBC8CFF), fontSize: 11),
                  ),
                ),
              if (partnerPaidForMe > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF9E79).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFF9E79).withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    'Partner paid for me: SAR ${partnerPaidForMe.toStringAsFixed(2)}',
                    style: const TextStyle(color: Color(0xFFFF9E79), fontSize: 11),
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
                  backgroundColor: const Color(0xFF21262D),
                  foregroundColor: const Color(0xFF00C896),
                  side: const BorderSide(color: Color(0xFF00C896)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
                label: Text(
                  'Settle SAR ${settleAmt.toStringAsFixed(2)} via STC Pay / IBAN',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                onPressed: () async {
                  HapticFeedback.lightImpact();
                  await Clipboard.setData(ClipboardData(text: '$stcNote - SAR ${settleAmt.toStringAsFixed(2)}'));
                  if (context.mounted) {
                    AppSnackBar.showSuccess(
                      context,
                      'Payment note copied: "$stcNote - SAR ${settleAmt.toStringAsFixed(2)}"',
                      title: 'Note Copied',
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
