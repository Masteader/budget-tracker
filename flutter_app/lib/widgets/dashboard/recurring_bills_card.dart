import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../models/recurring_bill.dart';
import '../../services/api_service.dart';

/// Interactive dashboard card displaying predicted recurring monthly bills (telecom,
/// utilities, subscriptions), payment status in current cycle, and reserved funds.
class RecurringBillsCard extends StatefulWidget {
  final String householdId;

  const RecurringBillsCard({super.key, required this.householdId});

  @override
  State<RecurringBillsCard> createState() => _RecurringBillsCardState();
}

class _RecurringBillsCardState extends State<RecurringBillsCard> {
  late Future<RecurringBillsSummary> _futureBills;
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadBills();
  }

  void _loadBills() {
    _futureBills = ApiService.instance.getRecurringBills(widget.householdId);
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00', 'en_US');

    return FutureBuilder<RecurringBillsSummary>(
      future: _futureBills,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            height: 100,
            decoration: BoxDecoration(
              color: const Color(0xFF161B22),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF30363D)),
            ),
            child: const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00C896)),
              ),
            ),
          );
        }

        if (snapshot.hasError || !snapshot.hasData || snapshot.data!.bills.isEmpty) {
          return const SizedBox.shrink(); // Don't take up space if no recurring bills detected
        }

        final summary = snapshot.data!;
        final upcomingCount = summary.bills.where((b) => b.isUpcoming || b.isOverdue).length;

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF30363D)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => setState(() => _isExpanded = !_isExpanded),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0883E).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.repeat_rounded,
                          color: Color(0xFFF0883E),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Recurring Bills & Reserves',
                              style: GoogleFonts.outfit(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              summary.reservedAmount > 0
                                  ? 'SAR ${fmt.format(summary.reservedAmount)} reserved for $upcomingCount unpaid bill(s)'
                                  : 'All monthly bills cleared for this cycle',
                              style: TextStyle(
                                fontSize: 12,
                                color: summary.reservedAmount > 0
                                    ? const Color(0xFFF0883E)
                                    : const Color(0xFF00C896),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        _isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                        color: const Color(0xFF8B949E),
                      ),
                    ],
                  ),
                ),
              ),

              // Expanded Bill List
              if (_isExpanded) ...[
                const Divider(height: 1, color: Color(0xFF21262D)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total Monthly: SAR ${fmt.format(summary.totalRecurringMonthly)}',
                        style: const TextStyle(color: Color(0xFF8B949E), fontSize: 11),
                      ),
                      Text(
                        'Paid: SAR ${fmt.format(summary.paidThisCycle)}',
                        style: const TextStyle(color: Color(0xFF00C896), fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  itemCount: summary.bills.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final bill = summary.bills[index];
                    return _BillRowItem(bill: bill);
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _BillRowItem extends StatelessWidget {
  final RecurringBillItem bill;

  const _BillRowItem({required this.bill});

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00', 'en_US');

    Color badgeColor;
    String badgeText;
    IconData badgeIcon;

    if (bill.isPaid) {
      badgeColor = const Color(0xFF00C896);
      badgeText = 'Paid';
      badgeIcon = Icons.check_circle_outline_rounded;
    } else if (bill.isOverdue) {
      badgeColor = Colors.redAccent;
      badgeText = 'Overdue';
      badgeIcon = Icons.error_outline_rounded;
    } else {
      badgeColor = const Color(0xFF58A6FF);
      badgeText = 'Due ~Day ${bill.expectedDayOfMonth}';
      badgeIcon = Icons.schedule_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF21262D)),
      ),
      child: Row(
        children: [
          Icon(badgeIcon, color: badgeColor, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bill.normalizedMerchant,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                ),
                Text(
                  bill.categoryCode.replaceFirst(RegExp(r'^[A-Z]+-'), ''),
                  style: const TextStyle(color: Color(0xFF8B949E), fontSize: 10),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'SAR ${fmt.format(bill.averageAmount)}',
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(color: badgeColor, fontSize: 9, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
