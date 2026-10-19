import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../main.dart';
import '../../models/installment_plan.dart';
import '../../providers/installment_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../providers/budget_provider.dart';
import '../../providers/recurring_bills_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_themes.dart';
import '../../l10n/app_localizations.dart';
import '../app_snackbar.dart';
import '../../models/money.dart';

/// Card displayed on the dashboard for tracking BNPL installment plans (Tamara, Tabby, etc.).
class InstallmentPlansCard extends StatefulWidget {
  final List<InstallmentPlan>? plans;
  final String? householdId;
  final ValueChanged<String>? onPayInstallment;

  const InstallmentPlansCard({
    super.key,
    this.plans,
    this.householdId,
    this.onPayInstallment,
  });

  @override
  State<InstallmentPlansCard> createState() => _InstallmentPlansCardState();
}

class _InstallmentPlansCardState extends State<InstallmentPlansCard> {
  late Future<List<InstallmentPlan>> _futurePlans;
  bool _isExpanded = true;
  TransactionProvider? _txProvider;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.householdId != null && widget.householdId!.isNotEmpty) {
        try {
          context.read<InstallmentProvider>().init(widget.householdId!);
        } catch (_) {}
      }
    });
    _loadPlans();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    try {
      final newTx = Provider.of<TransactionProvider>(context, listen: false);
      if (_txProvider != newTx) {
        _txProvider?.removeListener(_onDependencyChanged);
        _txProvider = newTx;
        _txProvider?.addListener(_onDependencyChanged);
      }
    } catch (_) {}
  }

  void _onDependencyChanged() {
    if (!mounted) return;
    try {
      context.read<InstallmentProvider>().fetchPlans(silent: true);
    } catch (_) {
      setState(() => _loadPlans());
    }
  }

  @override
  void dispose() {
    _txProvider?.removeListener(_onDependencyChanged);
    super.dispose();
  }

  void _loadPlans() {
    if (widget.plans != null) {
      _futurePlans = Future.value(widget.plans);
    } else if (widget.householdId != null && widget.householdId!.isNotEmpty) {
      _futurePlans = _fetchPlans(widget.householdId!);
    } else {
      _futurePlans = Future.value([]);
    }
  }

  Future<List<InstallmentPlan>> _fetchPlans(String hid) async {
    try {
      final apiPlans = await ApiService.instance.getInstallments(hid);
      if (apiPlans.isNotEmpty) return apiPlans;
    } catch (_) {}

    // Fallback: Check Supabase transactions for financed purchases
    try {
      final rows = await supabase
          .from('transactions')
          .select('id, amount, merchant, timestamp, raw_sms, category_code')
          .eq('household_id', hid)
          .like('raw_sms', '%Financed via%');

      final result = <InstallmentPlan>[];
      for (final r in (rows as List)) {
        final raw = (r['raw_sms'] as String? ?? '');
        final regex = RegExp(
          r'Financed via\s+([^:]+):\s*Installment\s*(\d+)\s*of\s*(\d+)\.?\s*(?:Full price:\s*(?:SAR\s*)?([0-9,.]+))?',
          caseSensitive: false,
        );
        final match = regex.firstMatch(raw);
        final provider = match?.group(1)?.trim() ??
            (raw.toLowerCase().contains('tamara') ? 'Tamara' : 'Tabby');
        final paid = int.tryParse(match?.group(2) ?? '1') ?? 1;
        final count = int.tryParse(match?.group(3) ?? '4') ?? 4;
        final monthly = (r['amount'] as num?)?.toDouble() ?? 0.0;
        final totalParsed = match?.group(4) != null
            ? double.tryParse(match!.group(4)!.replaceAll(',', ''))
            : null;
        final total = totalParsed ?? (monthly * count);

        result.add(InstallmentPlan(
          id: 'plan-${(r['id'] as String).substring(0, 8)}',
          householdId: hid,
          merchant: r['merchant'] as String? ?? 'Installment Purchase',
          provider: provider,
          totalAmount: total,
          installmentCount: count,
          monthlyAmount: monthly > 0 ? monthly : (total / count),
          paidInstallments: paid,
          dayOfMonth: 27,
          startDate: (r['timestamp'] as String? ??
                  DateTime.now().toIso8601String())
              .substring(0, 10),
          status: paid >= count ? 'COMPLETED' : 'ACTIVE',
          categoryCode: r['category_code'] as String? ?? 'OPEX-SHOPPING',
          originalTransactionId: r['id'] as String?,
          notes: raw,
        ));
      }
      if (result.isNotEmpty) return result;
    } catch (_) {}

    return [];
  }

  @override
  void didUpdateWidget(InstallmentPlansCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.plans != widget.plans || oldWidget.householdId != widget.householdId) {
      if (widget.householdId != null && widget.householdId!.isNotEmpty) {
        try {
          context.read<InstallmentProvider>().init(widget.householdId!);
        } catch (_) {}
      }
      _loadPlans();
    }
  }

  Color _getProviderColor(String provider) {
    switch (provider.toLowerCase()) {
      case 'tamara':
        return const Color(0xFFFF6B6B);
      case 'tabby':
        return const Color(0xFF00E676);
      default:
        return const Color(0xFF58A6FF);
    }
  }

  void _showAddPlanDialog(BuildContext context) {
    final merchantCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    String selectedProvider = 'Tamara';
    int selectedCount = 4;
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (dCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: context.cardBg,
          title: Text(
            context.tr('new_installment_plan'),
            style: GoogleFonts.outfit(color: context.textPrimary, fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: merchantCtrl,
                  style: TextStyle(color: context.textPrimary),
                  decoration: InputDecoration(
                    labelText: context.tr('merchant_item'),
                    labelStyle: TextStyle(color: context.textSecondary),
                    hintText: context.tr('merchant_placeholder'),
                    hintStyle: TextStyle(color: context.textSecondary),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(color: context.textPrimary),
                  decoration: InputDecoration(
                    labelText: context.tr('total_price'),
                    labelStyle: TextStyle(color: context.textSecondary),
                    hintText: '${context.tr('example_prefix')} 4000',
                    hintStyle: TextStyle(color: context.textSecondary),
                  ),
                ),
                const SizedBox(height: 16),
                Text(context.tr('provider'), style: TextStyle(color: context.textSecondary, fontSize: 11)),
                const SizedBox(height: 6),
                Row(
                  children: ['Tamara', 'Tabby', 'Bank'].map((p) {
                    final isSel = selectedProvider == p;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: InkWell(
                          onTap: () => setDialogState(() => selectedProvider = p),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: isSel ? AppThemes.success.withValues(alpha: 0.2) : context.inputBg,
                              border: Border.all(color: isSel ? AppThemes.success : context.borderColor),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              p == 'Bank' ? context.tr('bnpl_provider_bank_other') : p,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: isSel ? AppThemes.success : context.textPrimary,
                                fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                Text(context.tr('duration'), style: TextStyle(color: context.textSecondary, fontSize: 11)),
                const SizedBox(height: 6),
                Row(
                  children: [3, 4, 6].map((cnt) {
                    final isSel = selectedCount == cnt;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: InkWell(
                          onTap: () => setDialogState(() => selectedCount = cnt),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: isSel ? AppThemes.success.withValues(alpha: 0.2) : context.inputBg,
                              border: Border.all(color: isSel ? AppThemes.success : context.borderColor),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$cnt ${context.tr('months_short')}',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: isSel ? AppThemes.success : context.textPrimary,
                                fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dCtx),
              child: Text(context.tr('cancel'), style: TextStyle(color: context.textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppThemes.success,
                foregroundColor: Colors.black,
              ),
              onPressed: isSubmitting
                  ? null
                  : () async {
                      final merchant = merchantCtrl.text.trim();
                      final total = parseMoneyInput(amountCtrl.text);
                      if (merchant.isEmpty || total == null || total <= 0) {
                        AppSnackBar.showError(dCtx, context.tr('inst_invalid_input'));
                        return;
                      }
                      setDialogState(() => isSubmitting = true);
                      try {
                        final planData = {
                          'household_id': widget.householdId ?? '',
                          'merchant': merchant,
                          'provider': selectedProvider,
                          'total_amount': total,
                          'installment_count': selectedCount,
                          'paid_installments': 1,
                          'category_code': 'OPEX-SHOPPING',
                          'adjust_original_transaction': false,
                          'notes': 'Manually registered BNPL plan',
                        };
                        try {
                          await context.read<InstallmentProvider>().createPlan(planData);
                        } catch (_) {
                          await ApiService.instance.createInstallmentPlan(planData);
                        }
                        if (dCtx.mounted) Navigator.pop(dCtx);
                        if (mounted) setState(() => _loadPlans());
                        if (context.mounted) {
                          try {
                            context.read<TransactionProvider>().fetchTransactions();
                            context.read<BudgetProvider>().refresh();
                            context.read<RecurringBillsProvider>().fetchBills(silent: true);
                          } catch (_) {}
                          AppSnackBar.showSuccess(
                            context,
                            context.trArgs('inst_created_msg', {'provider': selectedProvider == 'Bank' ? context.tr('bnpl_provider_bank_other') : selectedProvider, 'merchant': merchant}),
                            title: context.tr('plan_active'),
                          );
                        }
                      } catch (e) {
                        setDialogState(() => isSubmitting = false);
                        if (dCtx.mounted) {
                          AppSnackBar.showError(dCtx, dCtx.trArgs('inst_create_failed', {'error': e}));
                        }
                      }
                    },
              child: isSubmitting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : Text(context.tr('confirm_plan'), style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00', 'en_US');
    InstallmentProvider? installmentProv;
    try {
      installmentProv = Provider.of<InstallmentProvider>(context);
    } catch (_) {}

    if (widget.plans != null) {
      return _buildCardContent(context, widget.plans!, fmt);
    }

    if (installmentProv != null) {
      return _buildCardContent(context, installmentProv.plans, fmt);
    }

    return FutureBuilder<List<InstallmentPlan>>(
      future: _futurePlans,
      builder: (context, snapshot) {
        final plans = snapshot.data ?? [];
        return _buildCardContent(context, plans, fmt);
      },
    );
  }

  Widget _buildCardContent(
    BuildContext context,
    List<InstallmentPlan> plans,
    NumberFormat fmt,
  ) {
    final activePlans = plans.where((p) => !p.isCompleted).toList();
    final totalMonthlyCommitment = activePlans.fold<double>(
      0.0,
      (sum, p) => sum + p.monthlyAmount,
    );

    return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: context.cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF6B6B).withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.credit_score_rounded,
                          color: Color(0xFFFF6B6B),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.tr('installments_bnpl'),
                              style: GoogleFonts.outfit(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: context.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              activePlans.isEmpty
                                  ? context.tr('all_installments_cleared')
                                  : '${context.sar(totalMonthlyCommitment)} / ${context.tr('month')} ${context.tr('scheduled_monthly')}',
                              style: TextStyle(
                                fontSize: 12,
                                color: activePlans.isEmpty
                                    ? AppThemes.success
                                    : context.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        _isExpanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: context.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),

              if (_isExpanded) ...[
                Divider(color: context.borderColor, height: 1),
                if (plans.isEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: context.subtleCardBg,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.credit_score_outlined,
                            color: context.textSecondary,
                            size: 28,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          context.tr('no_active_installments'),
                          style: GoogleFonts.outfit(
                            color: context.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          context.tr('bnpl_empty_desc'),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: context.textSecondary, fontSize: 12),
                        ),
                        const SizedBox(height: 14),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppThemes.success,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          ),
                          icon: const Icon(Icons.add, size: 16),
                          label: Text(
                            '+ ${context.tr('add_installment_plan')}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          onPressed: () => _showAddPlanDialog(context),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Column(
                      children: [
                        ...plans.map((plan) {
                          final providerColor = _getProviderColor(plan.provider);

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: context.subtleCardBg,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: context.borderColor),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: providerColor.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: providerColor.withValues(alpha: 0.5),
                                          width: 0.8,
                                        ),
                                      ),
                                      child: Text(
                                        plan.provider,
                                        style: TextStyle(
                                          color: providerColor,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        plan.merchant,
                                        style: GoogleFonts.outfit(
                                          fontWeight: FontWeight.w600,
                                          color: context.textPrimary,
                                          fontSize: 14,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Text(
                                      '${context.sar(plan.monthlyAmount)} / ${context.tr('month')}',
                                      style: GoogleFonts.outfit(
                                        fontWeight: FontWeight.bold,
                                        color: context.successText,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: plan.progressPercentage,
                                    backgroundColor: context.chipBg,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      plan.isCompleted
                                          ? AppThemes.success
                                          : providerColor,
                                    ),
                                    minHeight: 6,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      context.trArgs('inst_x_of_y_paid', {'paid': plan.paidInstallments, 'count': plan.installmentCount}),
                                      style: TextStyle(
                                        color: context.textSecondary,
                                        fontSize: 11,
                                      ),
                                    ),
                                    Text(
                                      '${context.tr('remaining')}: ${context.sar(plan.remainingAmount)}',
                                      style: TextStyle(
                                        color: context.textPrimary,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                                if (!plan.isCompleted) ...[
                                  const SizedBox(height: 8),
                                  Align(
                                    alignment: AlignmentDirectional.centerEnd,
                                    child: OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: context.textPrimary,
                                        side: BorderSide(color: context.borderColor),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 4),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      icon: const Icon(Icons.check_circle_outline, size: 14),
                                      label: Text(context.tr('record_payment'), style: const TextStyle(fontSize: 11)),
                                      onPressed: () async {
                                        if (widget.onPayInstallment != null) {
                                          widget.onPayInstallment!(plan.id);
                                        } else {
                                          try {
                                            await context.read<InstallmentProvider>().recordPayment(plan.id);
                                          } catch (_) {
                                            await ApiService.instance.payInstallment(plan.id);
                                          }
                                          setState(() => _loadPlans());
                                          if (context.mounted) {
                                            try {
                                              context.read<TransactionProvider>().fetchTransactions();
                                              context.read<BudgetProvider>().refresh();
                                              context.read<RecurringBillsProvider>().fetchBills(silent: true);
                                            } catch (_) {}
                                          }
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        }),
                        const SizedBox(height: 4),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppThemes.success,
                            side: BorderSide(color: context.borderColor),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          ),
                          icon: const Icon(Icons.add, size: 14),
                          label: Text('+ ${context.tr('add_installment_plan')}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          onPressed: () => _showAddPlanDialog(context),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ],
          ),
        );
  }
}
