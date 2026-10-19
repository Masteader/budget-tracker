import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../models/recurring_bill.dart';
import '../../providers/budget_provider.dart';
import '../../providers/recurring_bills_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_themes.dart';
import '../../l10n/app_localizations.dart';
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
  bool _isExpanded = true;
  int _selectedFilter = 0; // 0: All, 1: Pending, 2: Paid
  TransactionProvider? _txProvider;
  BudgetProvider? _budgetProvider;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<RecurringBillsProvider>().init(widget.householdId);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newTx = Provider.of<TransactionProvider>(context, listen: false);
    if (_txProvider != newTx) {
      _txProvider?.removeListener(_onDependencyChanged);
      _txProvider = newTx;
      _txProvider?.addListener(_onDependencyChanged);
    }
    final newBudget = Provider.of<BudgetProvider>(context, listen: false);
    if (_budgetProvider != newBudget) {
      _budgetProvider?.removeListener(_onDependencyChanged);
      _budgetProvider = newBudget;
      _budgetProvider?.addListener(_onDependencyChanged);
    }
  }

  void _onDependencyChanged() {
    if (!mounted) return;
    context.read<RecurringBillsProvider>().fetchBills(silent: true);
  }

  @override
  void didUpdateWidget(RecurringBillsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.householdId != widget.householdId) {
      context.read<RecurringBillsProvider>().init(widget.householdId);
    }
  }

  @override
  void dispose() {
    _txProvider?.removeListener(_onDependencyChanged);
    _budgetProvider?.removeListener(_onDependencyChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {

    return Consumer<RecurringBillsProvider>(
      builder: (context, provider, child) {
        if (provider.isLoading && provider.summary == null) {
          return Container(
            height: 110,
            decoration: BoxDecoration(
              color: context.cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.borderColor),
            ),
            child: const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppThemes.success),
              ),
            ),
          );
        }

        final summary = provider.summary;
        if (summary == null || summary.bills.isEmpty) {
          return _buildEmptyOrActionCard();
        }
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
            color: context.cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: summary.reservedAmount > 0
                  ? const Color(0xFFF0883E).withValues(alpha: 0.3)
                  : context.borderColor,
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
                              : AppThemes.success.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.repeat_rounded,
                          color: summary.reservedAmount > 0
                              ? const Color(0xFFF0883E)
                              : AppThemes.success,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.tr('recurring_bills'),
                              style: GoogleFonts.outfit(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: context.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              summary.reservedAmount > 0
                                  ? '${context.sar(summary.reservedAmount)} ${context.tr('reserved')} • $upcomingCount ${context.tr('pending')}'
                                  : '${context.tr('all_cleared')} ✓',
                              style: TextStyle(
                                fontSize: 12,
                                color: summary.reservedAmount > 0
                                    ? const Color(0xFFF0883E)
                                    : AppThemes.success,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Manage Config Button
                      IconButton(
                        tooltip: context.tr('configure_bills'),
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.tune_rounded, color: Color(0xFF58A6FF), size: 20),
                        onPressed: () => _showManageRecurringBillsSheet(context),
                      ),
                      Icon(
                        _isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                        color: context.textSecondary,
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
                                child: Container(color: AppThemes.success),
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
                    // Wrap instead of Row: the three totals overflow on
                    // narrow phones / large text, especially in Arabic.
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      runSpacing: 4,
                      children: [
                        Text(
                          '${context.tr('total')}: ${context.sar(summary.totalRecurringMonthly)}',
                          style: TextStyle(color: context.textSecondary, fontSize: 11),
                        ),
                        Row(
                          children: [
                            Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppThemes.success, shape: BoxShape.circle)),
                            const SizedBox(width: 4),
                            Text(
                              '${context.tr('paid')} ${context.sar(summary.paidThisCycle)}',
                              style: TextStyle(color: context.successText, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 12),
                            Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFFF0883E), shape: BoxShape.circle)),
                            const SizedBox(width: 4),
                            Text(
                              '${context.tr('reserved')} ${context.sar(summary.reservedAmount)}',
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
                Divider(height: 1, color: context.borderColor),

                // Filter Chips
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                  child: Row(
                    children: [
                      _buildFilterChip(0, '${context.tr('all')} (${summary.bills.length})'),
                      const SizedBox(width: 8),
                      _buildFilterChip(1, '${context.tr('pending')} ($upcomingCount)'),
                      const SizedBox(width: 8),
                      _buildFilterChip(2, '${context.tr('paid')} ($paidCount)'),
                    ],
                  ),
                ),

                if (filteredBills.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        _selectedFilter == 1
                            ? context.tr('rb_all_paid')
                            : context.tr('rb_none_in_filter'),
                        style: TextStyle(color: context.textSecondary, fontSize: 12),
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
                        onMarkPaid: () => _recordBillPayment(bill),
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
        color: context.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
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
                  context.tr('recurring_bills'),
                  style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w700, color: context.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  context.tr('recurring_bills_empty_desc'),
                  style: TextStyle(fontSize: 11, color: context.textSecondary),
                ),
              ],
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: context.chipBg,
              foregroundColor: const Color(0xFF58A6FF),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => _showManageRecurringBillsSheet(context),
            child: Text(context.tr('rb_configure'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
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
          color: selected ? AppThemes.success.withValues(alpha: 0.2) : context.chipBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppThemes.success : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppThemes.success : context.textSecondary,
            fontSize: 11,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Future<void> _recordBillPayment(RecurringBillItem bill) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(context.tr('rb_record_payment_title'), style: GoogleFonts.outfit(color: context.textPrimary, fontWeight: FontWeight.bold)),
        content: Text(
          context.trArgs('rb_confirm_payment_msg', {'amount': context.sar(bill.averageAmount), 'merchant': bill.merchant}),
          style: TextStyle(color: context.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('cancel'), style: TextStyle(color: context.textSecondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppThemes.success),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr('rb_confirm_paid'), style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    try {
      final success = await context.read<RecurringBillsProvider>().recordBillPayment(bill);
      if (!mounted) return;
      if (success) {
        context.read<TransactionProvider>().refresh();
        context.read<BudgetProvider>().refresh();
        AppSnackBar.showSuccess(
          context,
          context.trArgs('rb_recorded_payment', {'merchant': bill.merchant}),
          title: context.tr('rb_bill_paid'),
        );
      } else {
        AppSnackBar.showError(context, context.tr('rb_payment_failed'), title: context.tr('rb_payment_error'));
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.showError(context, context.trArgs('rb_payment_failed_msg', {'error': e}), title: context.tr('rb_payment_error'));
      }
    }
  }

  void _showManageRecurringBillsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _ManageRecurringBillsSheet(
        householdId: widget.householdId,
        onUpdated: () {
          context.read<RecurringBillsProvider>().fetchBills();
          context.read<BudgetProvider>().refresh();
        },
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

    Color badgeColor;
    String badgeText;
    IconData badgeIcon;

    if (bill.isPaid) {
      badgeColor = AppThemes.success;
      badgeText = context.tr('paid');
      badgeIcon = Icons.check_circle_rounded;
    } else if (bill.isOverdue) {
      badgeColor = const Color(0xFFFF7B72);
      badgeText = context.tr('overdue');
      badgeIcon = Icons.error_outline_rounded;
    } else {
      badgeColor = const Color(0xFF58A6FF);
      badgeText = '${context.tr('due_day')} ~${bill.expectedDayOfMonth}';
      badgeIcon = Icons.schedule_rounded;
    }

    final billIcon = _getBillIcon(bill.iconKey, bill.merchant, bill.categoryCode);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: context.subtleCardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: bill.isOverdue
              ? const Color(0xFFFF7B72).withValues(alpha: 0.3)
              : context.borderColor,
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
                        (bill.subCode != null && bill.subCode!.isNotEmpty)
                            ? context.trSub(bill.subCode!, nameAr: bill.nameAr, nameEn: bill.merchant)
                            : (context.isArabic && bill.nameAr != null && bill.nameAr!.isNotEmpty
                                ? bill.nameAr!
                                : bill.merchant),
                        style: TextStyle(color: context.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
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
                        child: Text(context.tr('budgeted'), style: const TextStyle(color: Color(0xFF58A6FF), fontSize: 9)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  context.trCat(bill.categoryCode),
                  style: TextStyle(color: context.textSecondary, fontSize: 10),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                context.sar(bill.averageAmount),
                style: TextStyle(color: context.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
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
                          color: AppThemes.success.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppThemes.success.withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          context.tr('rb_pay'),
                          style: TextStyle(color: context.successText, fontSize: 9, fontWeight: FontWeight.bold),
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
                decoration: BoxDecoration(color: context.borderColor, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  context.tr('rb_manage_title'),
                  style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: context.textPrimary),
                ),
                IconButton(
                  tooltip: context.tr('close'),
                  icon: Icon(Icons.close_rounded, color: context.textSecondary),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            Text(
              context.tr('rb_manage_desc'),
              style: TextStyle(fontSize: 12, color: context.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: FutureBuilder<List<RecurringBillCandidate>>(
                future: _futureCandidates,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: AppThemes.success));
                  }
                  if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
                    return Center(
                      child: Text(
                        context.tr('rb_manage_empty'),
                        style: TextStyle(color: context.textSecondary, fontSize: 13),
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
                          color: context.subtleCardBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: c.isRecurring
                                ? AppThemes.success.withValues(alpha: 0.3)
                                : context.borderColor,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(icon, color: c.isRecurring ? AppThemes.success : context.textSecondary, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    c.nameEn,
                                    style: TextStyle(
                                      color: c.isRecurring ? context.textPrimary : context.textSecondary,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    '${context.trCat(c.categoryCode)} • ${context.sar(c.allocatedAmount)}',
                                    style: TextStyle(color: context.textSecondary, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: c.isRecurring,
                              activeThumbColor: AppThemes.success,
                              activeTrackColor: AppThemes.success.withValues(alpha: 0.4),
                              onChanged: (val) async {
                                setState(() {
                                  c.isRecurring = val;
                                });
                                try {
                                  await ApiService.instance.toggleRecurringBill(
                                    householdId: widget.householdId,
                                    categoryCode: c.categoryCode,
                                    subCode: c.subCode,
                                    isRecurring: val,
                                  );
                                  widget.onUpdated();
                                } catch (_) {
                                  if (mounted) {
                                    setState(() => c.isRecurring = !val);
                                  }
                                }
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
