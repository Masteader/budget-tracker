import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/installment_plan.dart';
import '../../providers/installment_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../providers/budget_provider.dart';
import '../../providers/recurring_bills_provider.dart';
import '../../services/api_service.dart';
import '../../services/nafaqah_write_errors.dart';
import '../../theme/app_themes.dart';
import '../../l10n/app_localizations.dart';
import '../app_snackbar.dart';
import '../card_error_state.dart';
import '../dispose_on_unmount.dart';
import '../../models/money.dart';
import '../../services/salary_cycle_service.dart';

/// Card displayed on the dashboard for tracking BNPL installment plans (Tamara, Tabby, etc.).
class InstallmentPlansCard extends StatefulWidget {
  final List<InstallmentPlan>? plans;
  final String? householdId;
  final ValueChanged<String>? onPayInstallment;

  /// Clock for the due dates (tests); defaults to now.
  final DateTime? now;

  const InstallmentPlansCard({
    super.key,
    this.plans,
    this.householdId,
    this.onPayInstallment,
    this.now,
  });

  @override
  State<InstallmentPlansCard> createState() => _InstallmentPlansCardState();
}

class _InstallmentPlansCardState extends State<InstallmentPlansCard> {
  /// Used only without an [InstallmentProvider]; created on first build.
  Future<List<InstallmentPlan>>? _futurePlans;
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

  /// Forgets the loaded plans; the next build without a provider loads them again.
  void _loadPlans() => _futurePlans = null;

  /// Rows from the API only; a failure reaches the FutureBuilder as an error.
  Future<List<InstallmentPlan>> _fetchPlans() {
    final hid = widget.householdId;
    if (hid == null || hid.isEmpty) return Future.value(const []);
    return ApiService.instance.getInstallments(hid);
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
    // null: the default for the provider (Tabby/Tamara "pay in 4" is every
    // two weeks, the server applies the same rule); set when the user picks.
    String? chosenFrequency;
    String frequencyFor() =>
        chosenFrequency ?? ((selectedProvider == 'Tabby' || selectedProvider == 'Tamara') && selectedCount == 4 ? 'biweekly' : 'monthly');
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (dCtx) => DisposeOnUnmount(
        disposables: [merchantCtrl, amountCtrl],
        child: StatefulBuilder(
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
                Text(context.tr('inst_installment_count'), style: TextStyle(color: context.textSecondary, fontSize: 11)),
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
                              '$cnt',
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
                Text(context.tr('inst_frequency'), style: TextStyle(color: context.textSecondary, fontSize: 11)),
                const SizedBox(height: 6),
                Row(
                  children: ['biweekly', 'monthly'].map((f) {
                    final isSel = frequencyFor() == f;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: InkWell(
                          key: ValueKey('inst_frequency_$f'),
                          onTap: () => setDialogState(() => chosenFrequency = f),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: isSel ? AppThemes.success.withValues(alpha: 0.2) : context.inputBg,
                              border: Border.all(color: isSel ? AppThemes.success : context.borderColor),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              context.tr(f == 'biweekly' ? 'inst_every_two_weeks' : 'inst_every_month'),
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
                          'frequency': frequencyFor(),
                          'paid_installments': 1,
                          'category_code': 'OPEX-SHOPPING',
                          'adjust_original_transaction': false,
                          'notes': 'Manually registered BNPL plan',
                        };
                        try {
                          await context.read<InstallmentProvider>().createPlan(planData);
                        } on ProviderNotFoundException {
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
                          AppSnackBar.showError(
                            dCtx,
                            nafaqahWriteErrorText(dCtx, e) ?? dCtx.trArgs('inst_create_failed', {'error': e}),
                          );
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

    final prov = installmentProv;
    if (prov != null) {
      // Loading, error and empty are distinct (UX-01): an empty list is shown
      // only after a successful load.
      if (prov.error != null && !prov.hasLoaded) return _buildError(context, prov.fetchPlans);
      if (!prov.hasLoaded) return _buildLoading(context);
      return _buildCardContent(
        context,
        prov.plans,
        fmt,
        staleBanner: prov.error == null
            ? null
            : CardErrorBanner(lastUpdated: prov.lastUpdated, onRetry: prov.fetchPlans),
      );
    }

    return FutureBuilder<List<InstallmentPlan>>(
      future: _futurePlans ??= _fetchPlans(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return _buildError(context, () => setState(_loadPlans));
        if (snapshot.connectionState != ConnectionState.done) return _buildLoading(context);
        return _buildCardContent(context, snapshot.data ?? const [], fmt);
      },
    );
  }

  Widget _buildLoading(BuildContext context) => Container(
        key: const Key('installments_loading'),
        height: 88,
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: context.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.borderColor),
        ),
        child: const Center(
          child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );

  Widget _buildError(BuildContext context, VoidCallback onRetry) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: CardErrorState(
          title: context.tr('installments_bnpl'),
          message: context.tr('load_error_installments'),
          icon: Icons.credit_score_rounded,
          onRetry: onRetry,
        ),
      );

  /// "Installment 2 of 4 paid · next 29 Oct" for an active plan.
  String? _nextDueText(BuildContext context, InstallmentPlan plan, DateTime today) {
    final next = plan.nextDueDate(today: today);
    if (next == null) return null;
    return context.trArgs('inst_paid_next_due', {
      'paid': plan.paidInstallments,
      'count': plan.installmentCount,
      'date': context.fmtDate(next, 'd MMM'),
    });
  }

  Widget _buildCardContent(
    BuildContext context,
    List<InstallmentPlan> plans,
    NumberFormat fmt, {
    Widget? staleBanner,
  }) {
    final activePlans = plans.where((p) => !p.isCompleted).toList();
    // What the installments take before the next payday (both frequencies),
    // instead of a "/month" total that is wrong for bi-weekly plans.
    final today = SalaryCycleService.riyadhToday(now: widget.now);
    final cycleEnd = SalaryCycleService.currentCycle(now: widget.now).end;
    final dueBeforePayday = activePlans.fold<double>(0.0, (sum, p) {
      final due = p.dueDates(today: today, max: 12).where((d) => !d.isBefore(today) && !d.isAfter(cycleEnd));
      return sum + p.installmentAmount * due.length;
    });

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
                              // UX-25: "all cleared" only when plans exist and all are paid.
                              plans.isEmpty
                                  ? context.tr('no_installments')
                                  : activePlans.isEmpty
                                  ? context.tr('all_installments_cleared')
                                  : dueBeforePayday > 0
                                      ? context.trArgs('inst_due_before_payday', {'amount': context.sar(dueBeforePayday)})
                                      : context.tr('inst_nothing_due_before_payday'),
                              style: TextStyle(
                                fontSize: 12,
                                color: activePlans.isEmpty && plans.isNotEmpty
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

              if (staleBanner != null)
                Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 8), child: staleBanner),
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
                                      '${context.sar(plan.installmentAmount)} / ${context.tr(plan.isBiweekly ? 'inst_two_weeks_short' : 'month')}',
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
                                      _nextDueText(context, plan, today) ??
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
                                          bool recorded;
                                          try {
                                            recorded = await context.read<InstallmentProvider>().recordPayment(plan.id);
                                          } catch (_) {
                                            recorded = await ApiService.instance.payInstallment(plan.id) != null;
                                          }
                                          if (!mounted) return;
                                          setState(() => _loadPlans());
                                          if (!recorded && context.mounted) {
                                            // FR-A-03: never imply a payment the server did not record.
                                            AppSnackBar.showError(context, context.tr('rb_payment_failed'));
                                          }
                                          if (recorded && context.mounted) {
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
