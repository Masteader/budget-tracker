import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../main.dart';
import '../../models/recurring_bill.dart';
import '../../providers/budget_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../services/api_service.dart';
import '../app_snackbar.dart';

/// Interactive dashboard card displaying recurring monthly bills, payment status
/// in the active salary cycle, reserved fund allowance, and category inclusion settings.
class RecurringBillsCard extends StatefulWidget {
  final String householdId;

  const RecurringBillsCard({super.key, required this.householdId});

  @override
  State<RecurringBillsCard> createState() => _RecurringBillsCardState();
}

class _RecurringBillsCardState extends State<RecurringBillsCard> {
  late Future<RecurringBillsSummary> _futureBills;
  bool _isExpanded = true;
  int _selectedFilter = 0; // 0: All, 1: Pending, 2: Paid

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
            height: 110,
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
          return _buildEmptyOrActionCard();
        }

        final summary = snapshot.data!;
        final upcomingCount = summary.bills.where((b) => b.isUpcoming || b.isOverdue).length;
        final paidCount = summary.bills.where((b) => b.isPaid).length;

        final double total = summary.totalRecurringMonthly > 0 ? summary.totalRecurringMonthly : 1.0;
        final double paidRatio = (summary.paidThisCycle / total).clamp(0.0, 1.0);

        List<RecurringBillItem> filteredBills = summary.bills;
        if (_selectedFilter == 1) {
          filteredBills = summary.bills.where((b) => !b.isPaid).toList();
        } else if (_selectedFilter == 2) {
          filteredBills = summary.bills.where((b) => b.isPaid).toList();
        }

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: summary.reservedAmount > 0
                  ? const Color(0xFFF0883E).withValues(alpha: 0.3)
                  : const Color(0xFF30363D),
            ),
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
                          color: summary.reservedAmount > 0
                              ? const Color(0xFFF0883E).withValues(alpha: 0.15)
                              : const Color(0xFF00C896).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.repeat_rounded,
                          color: summary.reservedAmount > 0
                              ? const Color(0xFFF0883E)
                              : const Color(0xFF00C896),
                          size: 22,
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
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              summary.reservedAmount > 0
                                  ? 'SAR ${fmt.format(summary.reservedAmount)} reserved • $upcomingCount unpaid bill(s)'
                                  : 'All monthly bills cleared for this cycle ✓',
                              style: TextStyle(
                                fontSize: 12,
                                color: summary.reservedAmount > 0
                                    ? const Color(0xFFF0883E)
                                    : const Color(0xFF00C896),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Manage Config Button
                      IconButton(
                        tooltip: 'Configure Bills',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.tune_rounded, color: Color(0xFF58A6FF), size: 20),
                        onPressed: () => _showManageRecurringBillsSheet(context),
                      ),
                      Icon(
                        _isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                        color: const Color(0xFF8B949E),
                      ),
                    ],
                  ),
                ),
              ),

              // Visual Progress Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        height: 6,
                        child: Row(
                          children: [
                            if (paidRatio > 0)
                              Expanded(
                                flex: (paidRatio * 1000).toInt(),
                                child: Container(color: const Color(0xFF00C896)),
                              ),
                            if (1.0 - paidRatio > 0)
                              Expanded(
                                flex: ((1.0 - paidRatio) * 1000).toInt(),
                                child: Container(color: const Color(0xFFF0883E)),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Total: SAR ${fmt.format(summary.totalRecurringMonthly)}',
                          style: const TextStyle(color: Color(0xFF8B949E), fontSize: 11),
                        ),
                        Row(
                          children: [
                            Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF00C896), shape: BoxShape.circle)),
                            const SizedBox(width: 4),
                            Text(
                              'Paid SAR ${fmt.format(summary.paidThisCycle)}',
                              style: const TextStyle(color: Color(0xFF00C896), fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 12),
                            Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFFF0883E), shape: BoxShape.circle)),
                            const SizedBox(width: 4),
                            Text(
                              'Reserved SAR ${fmt.format(summary.reservedAmount)}',
                              style: const TextStyle(color: Color(0xFFF0883E), fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Expanded Bill List
              if (_isExpanded) ...[
                const SizedBox(height: 12),
                const Divider(height: 1, color: Color(0xFF21262D)),

                // Filter Chips
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                  child: Row(
                    children: [
                      _buildFilterChip(0, 'All (${summary.bills.length})'),
                      const SizedBox(width: 8),
                      _buildFilterChip(1, 'Pending ($upcomingCount)'),
                      const SizedBox(width: 8),
                      _buildFilterChip(2, 'Paid ($paidCount)'),
                    ],
                  ),
                ),

                if (filteredBills.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        _selectedFilter == 1
                            ? 'All recurring bills are paid for this cycle!'
                            : 'No bills found in this filter.',
                        style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12),
                      ),
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                    itemCount: filteredBills.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final bill = filteredBills[index];
                      return _BillRowItem(
                        bill: bill,
                        onMarkPaid: () => _recordBillPayment(context, bill),
                      );
                    },
                  ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyOrActionCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF58A6FF).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.repeat_rounded, color: Color(0xFF58A6FF), size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Recurring Bills & Reserves',
                  style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Set up monthly bills (utilities, iqama fees, rent) to reserve funds.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF8B949E)),
                ),
              ],
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF21262D),
              foregroundColor: const Color(0xFF58A6FF),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => _showManageRecurringBillsSheet(context),
            child: const Text('Configure', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(int index, String label) {
    final selected = _selectedFilter == index;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => setState(() => _selectedFilter = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF00C896).withValues(alpha: 0.2) : const Color(0xFF21262D),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? const Color(0xFF00C896) : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? const Color(0xFF00C896) : const Color(0xFF8B949E),
            fontSize: 11,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Future<void> _recordBillPayment(BuildContext context, RecurringBillItem bill) async {
    final fmt = NumberFormat('#,##0.00', 'en_US');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Record Bill Payment', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'Confirm payment of SAR ${fmt.format(bill.averageAmount)} for "${bill.merchant}" in this cycle?',
          style: const TextStyle(color: Color(0xFFC9D1D9), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF8B949E))),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF00C896)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm Paid', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await supabase.from('transactions').insert({
        'household_id': widget.householdId,
        'merchant': bill.merchant,
        'amount': bill.averageAmount,
        'category_code': bill.categoryCode,
        'sub_category': bill.subCode,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });

      if (mounted) {
        context.read<TransactionProvider>().init(widget.householdId);
        context.read<BudgetProvider>().init(widget.householdId);
        setState(() => _loadBills());
        AppSnackBar.showSuccess(
          context,
          'Recorded payment for ${bill.merchant}!',
          title: 'Bill Paid',
        );
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.showError(context, 'Failed to record payment: $e', title: 'Payment Error');
      }
    }
  }

  void _showManageRecurringBillsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF161B22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _ManageRecurringBillsSheet(
        householdId: widget.householdId,
        onUpdated: () => setState(() => _loadBills()),
      ),
    );
  }
}

class _BillRowItem extends StatelessWidget {
  final RecurringBillItem bill;
  final VoidCallback onMarkPaid;

  const _BillRowItem({required this.bill, required this.onMarkPaid});

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00', 'en_US');

    Color badgeColor;
    String badgeText;
    IconData badgeIcon;

    if (bill.isPaid) {
      badgeColor = const Color(0xFF00C896);
      badgeText = 'Paid';
      badgeIcon = Icons.check_circle_rounded;
    } else if (bill.isOverdue) {
      badgeColor = const Color(0xFFFF7B72);
      badgeText = 'Overdue';
      badgeIcon = Icons.error_outline_rounded;
    } else {
      badgeColor = const Color(0xFF58A6FF);
      badgeText = 'Due ~Day ${bill.expectedDayOfMonth}';
      badgeIcon = Icons.schedule_rounded;
    }

    final billIcon = _getBillIcon(bill.iconKey, bill.merchant, bill.categoryCode);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: bill.isOverdue
              ? const Color(0xFFFF7B72).withValues(alpha: 0.3)
              : const Color(0xFF21262D),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(billIcon, color: badgeColor, size: 18),
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
                        bill.merchant,
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (bill.isBudgeted) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFF58A6FF).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('Budgeted', style: TextStyle(color: Color(0xFF58A6FF), fontSize: 9)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _formatCategory(bill.categoryCode),
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
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 3),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(badgeIcon, color: badgeColor, size: 10),
                        const SizedBox(width: 3),
                        Text(
                          badgeText,
                          style: TextStyle(color: badgeColor, fontSize: 9, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  if (!bill.isPaid) ...[
                    const SizedBox(width: 6),
                    InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: onMarkPaid,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00C896).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF00C896).withValues(alpha: 0.4)),
                        ),
                        child: const Text(
                          'Pay',
                          style: TextStyle(color: Color(0xFF00C896), fontSize: 9, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ManageRecurringBillsSheet extends StatefulWidget {
  final String householdId;
  final VoidCallback onUpdated;

  const _ManageRecurringBillsSheet({required this.householdId, required this.onUpdated});

  @override
  State<_ManageRecurringBillsSheet> createState() => _ManageRecurringBillsSheetState();
}

class _ManageRecurringBillsSheetState extends State<_ManageRecurringBillsSheet> {
  late Future<List<RecurringBillCandidate>> _futureCandidates;

  @override
  void initState() {
    super.initState();
    _loadCandidates();
  }

  void _loadCandidates() {
    _futureCandidates = ApiService.instance.getRecurringBillCandidates(widget.householdId);
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00', 'en_US');

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollCtrl) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: const Color(0xFF30363D), borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Manage Recurring Bills',
                  style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Color(0xFF8B949E)),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Text(
              'Toggle which budgeted sub-items (utilities, iqama fees, rent, subscriptions) should be tracked as monthly recurring obligations and reserved from salary.',
              style: TextStyle(fontSize: 12, color: Color(0xFF8B949E), height: 1.4),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: FutureBuilder<List<RecurringBillCandidate>>(
                future: _futureCandidates,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: Color(0xFF00C896)));
                  }
                  if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
                    return const Center(
                      child: Text(
                        'No budgeted sub-categories found. Allocate amounts in Budget Management first.',
                        style: TextStyle(color: Color(0xFF8B949E), fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    );
                  }

                  final candidates = snapshot.data!;

                  return ListView.separated(
                    controller: scrollCtrl,
                    itemCount: candidates.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final c = candidates[index];
                      final icon = _getBillIcon(c.iconKey, c.nameEn, c.categoryCode);

                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0D1117),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: c.isRecurring
                                ? const Color(0xFF00C896).withValues(alpha: 0.3)
                                : const Color(0xFF21262D),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(icon, color: c.isRecurring ? const Color(0xFF00C896) : const Color(0xFF8B949E), size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    c.nameEn,
                                    style: TextStyle(
                                      color: c.isRecurring ? Colors.white : const Color(0xFF8B949E),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    '${_formatCategory(c.categoryCode)} • SAR ${fmt.format(c.allocatedAmount)}',
                                    style: const TextStyle(color: Color(0xFF8B949E), fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: c.isRecurring,
                              activeColor: const Color(0xFF00C896),
                              onChanged: (val) async {
                                await ApiService.instance.toggleRecurringBill(
                                  householdId: widget.householdId,
                                  categoryCode: c.categoryCode,
                                  subCode: c.subCode,
                                  isRecurring: val,
                                );
                                widget.onUpdated();
                                setState(() => _loadCandidates());
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

IconData _getBillIcon(String? iconKey, String merchant, String catCode) {
  final m = merchant.toLowerCase();
  final k = iconKey?.toLowerCase() ?? '';
  if (k == 'bolt' || m.contains('electric') || m.contains('sec') || m.contains('kahraba') || m.contains('كهرباء')) {
    return Icons.bolt_rounded;
  }
  if (k == 'wifi' || m.contains('fiber') || m.contains('internet') || m.contains('نت') || m.contains('ألياف')) {
    return Icons.wifi_rounded;
  }
  if (k == 'phone_android' || m.contains('mobile') || m.contains('sim') || m.contains('stc') || m.contains('mobily') || m.contains('zain') || m.contains('جوال')) {
    return Icons.phone_android_rounded;
  }
  if (k == 'water_drop' || m.contains('water') || m.contains('nwc') || m.contains('مياه')) {
    return Icons.water_drop_rounded;
  }
  if (k == 'home' || m.contains('rent') || m.contains('housing') || m.contains('إيجار')) {
    return Icons.home_rounded;
  }
  if (k == 'badge' || m.contains('iqama') || m.contains('visa') || m.contains('إقامة') || m.contains('اقامة') || m.contains('جوازات')) {
    return Icons.badge_rounded;
  }
  if (k == 'ac_unit' || m.contains('cooling') || m.contains('تبريد')) {
    return Icons.ac_unit_rounded;
  }
  if (k == 'sports_esports' || m.contains('gaming') || m.contains('netflix') || m.contains('spotify') || m.contains('اشتراك')) {
    return Icons.sports_esports_rounded;
  }
  if (k == 'school' || m.contains('tuition') || m.contains('school') || m.contains('مدرسة')) {
    return Icons.school_rounded;
  }
  return Icons.receipt_long_rounded;
}

String _formatCategory(String code) {
  final clean = code.replaceFirst(RegExp(r'^[A-Z]+-'), '');
  switch (clean) {
    case 'UTILITIES':
      return 'Utilities & Bills';
    case 'GOV':
      return 'Government & Fees';
    case 'ENTERTAINMENT':
      return 'Entertainment';
    case 'EDUCATION':
      return 'Education';
    case 'HEALTH':
      return 'Health';
    case 'FUEL':
      return 'Fuel & Transport';
    default:
      return clean;
  }
}
