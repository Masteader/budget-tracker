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
import '../../services/nafaqah_write_errors.dart';
import '../../theme/app_themes.dart';
import '../../l10n/app_localizations.dart';
import '../app_snackbar.dart';
import '../card_error_state.dart';
import '../dispose_on_unmount.dart';
import '../transactions/manual_expense_sheet.dart';
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
        return context.dangerColor;
      case 'tabby':
        return context.successText;
      default:
        return context.infoColor;
    }
  }

  void _showEditPlanDialog(BuildContext context, InstallmentPlan plan) {
    final merchantCtrl = TextEditingController(text: plan.merchant);
    final totalAmountCtrl = TextEditingController(text: plan.totalAmount.toStringAsFixed(2));
    final monthlyAmountCtrl = TextEditingController(text: plan.monthlyAmount.toStringAsFixed(2));
    final countCtrl = TextEditingController(text: plan.installmentCount.toString());
    final paidCtrl = TextEditingController(text: plan.paidInstallments.toString());
    final dayCtrl = TextEditingController(text: plan.dayOfMonth.toString());

    String selectedProvider = plan.provider;
    String selectedFrequency = plan.frequency;
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (dCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: context.cardBg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(
              context.tr('edit_installment_title'),
              style: GoogleFonts.outfit(
                color: context.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: SingleChildScrollView(
              child: SizedBox(
                width: MediaQuery.of(context).size.width * 0.85,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: merchantCtrl,
                      decoration: InputDecoration(
                        labelText: context.tr('merchant'),
                        labelStyle: TextStyle(color: context.textSecondary),
                      ),
                      style: TextStyle(color: context.textPrimary),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: totalAmountCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: context.tr('total_amount'),
                        labelStyle: TextStyle(color: context.textSecondary),
                        suffixText: 'SAR',
                      ),
                      style: TextStyle(color: context.textPrimary),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: monthlyAmountCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: context.tr('monthly_amount'),
                        labelStyle: TextStyle(color: context.textSecondary),
                        suffixText: 'SAR',
                      ),
                      style: TextStyle(color: context.textPrimary),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: countCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: context.tr('installment_count'),
                              labelStyle: TextStyle(color: context.textSecondary, fontSize: 12),
                            ),
                            style: TextStyle(color: context.textPrimary),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: paidCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: context.tr('paid_installments'),
                              labelStyle: TextStyle(color: context.textSecondary, fontSize: 12),
                            ),
                            style: TextStyle(color: context.textPrimary),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: dayCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: context.tr('day_of_month'),
                              labelStyle: TextStyle(color: context.textSecondary, fontSize: 12),
                            ),
                            style: TextStyle(color: context.textPrimary),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      context.tr('provider'),
                      style: TextStyle(color: context.textSecondary, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: ['Tamara', 'Tabby', 'Bank', 'Other'].map((p) {
                        final isSel = selectedProvider.toLowerCase() == p.toLowerCase();
                        return Expanded(
                          child: GestureDetector(
                            onTap: () => setDialogState(() => selectedProvider = p),
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              decoration: BoxDecoration(
                                color: isSel ? context.primaryButtonBg : context.inputBg,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isSel ? context.accentText : context.borderColor,
                                ),
                              ),
                              child: Text(
                                p,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: isSel ? context.primaryButtonFg : context.textPrimary,
                                  fontSize: 11,
                                  fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
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
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dCtx),
                child: Text(context.tr('cancel'), style: TextStyle(color: context.textSecondary)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.primaryButtonBg,
                  foregroundColor: context.primaryButtonFg,
                ),
                onPressed: isSubmitting
                    ? null
                    : () async {
                        final merchant = merchantCtrl.text.trim();
                        final total = parseMoneyInput(totalAmountCtrl.text) ?? plan.totalAmount;
                        final monthly = parseMoneyInput(monthlyAmountCtrl.text) ?? plan.monthlyAmount;
                        final count = int.tryParse(countCtrl.text.trim()) ?? plan.installmentCount;
                        final paid = int.tryParse(paidCtrl.text.trim()) ?? plan.paidInstallments;
                        final day = int.tryParse(dayCtrl.text.trim()) ?? plan.dayOfMonth;

                        if (merchant.isEmpty) {
                          AppSnackBar.showError(context, 'Merchant is required');
                          return;
                        }
                        if (paid > count) {
                          AppSnackBar.showError(context, 'Paid installments cannot exceed total count');
                          return;
                        }

                        setDialogState(() => isSubmitting = true);
                        try {
                          final prov = Provider.of<InstallmentProvider>(context, listen: false);
                          await prov.updatePlan(plan.id, {
                            'merchant': merchant,
                            'provider': selectedProvider,
                            'total_amount': total,
                            'monthly_amount': monthly,
                            'installment_count': count,
                            'paid_installments': paid,
                            'day_of_month': day,
                            'frequency': selectedFrequency,
                          });
                          if (dCtx.mounted) Navigator.pop(dCtx);
                          if (context.mounted) {
                            AppSnackBar.showSuccess(context, context.tr('installment_updated'));
                            if (mounted) setState(() => _loadPlans());
                          }
                        } catch (e) {
                          setDialogState(() => isSubmitting = false);
                          if (context.mounted) {
                            AppSnackBar.showError(context, e.toString());
                          }
                        }
                      },
                child: isSubmitting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(context.tr('save'), style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showAddPlanDialog(BuildContext context) {
    final merchantCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final monthlyCtrl = TextEditingController();
    final customCountCtrl = TextEditingController();
    bool isOngoing = false;
    String selectedProvider = 'Tamara';
    int selectedCount = 4;
    bool isCustomCount = false;
    bool firstPaidAtCheckout = true;
    String? chosenFrequency;
    String frequencyFor() =>
        chosenFrequency ?? ((selectedProvider == 'Tabby' || selectedProvider == 'Tamara') && selectedCount == 4 ? 'biweekly' : 'monthly');
    bool isSubmitting = false;
    bool isUpdatingInternally = false;

    void onRemainingAmountChanged(String val, StateSetter setDialogState) {
      if (isUpdatingInternally) return;
      final remaining = parseMoneyInput(val);
      if (remaining != null && remaining > 0 && selectedCount > 0) {
        isUpdatingInternally = true;
        final monthly = remaining / selectedCount;
        monthlyCtrl.text = monthly.toStringAsFixed(2);
        isUpdatingInternally = false;
        setDialogState(() {});
      }
    }

    void onMonthlyPaymentChanged(String val, StateSetter setDialogState) {
      if (isUpdatingInternally) return;
      final monthly = parseMoneyInput(val);
      if (monthly != null && monthly > 0 && selectedCount > 0) {
        isUpdatingInternally = true;
        final totalRemaining = monthly * selectedCount;
        amountCtrl.text = totalRemaining.toStringAsFixed(2);
        isUpdatingInternally = false;
        setDialogState(() {});
      }
    }

    void onCountChanged(int count, StateSetter setDialogState) {
      selectedCount = count;
      isCustomCount = false;
      final amt = parseMoneyInput(amountCtrl.text);
      if (amt != null && amt > 0 && selectedCount > 0) {
        isUpdatingInternally = true;
        monthlyCtrl.text = (amt / selectedCount).toStringAsFixed(2);
        isUpdatingInternally = false;
      }
      setDialogState(() {});
    }

    showDialog(
      context: context,
      builder: (dCtx) => DisposeOnUnmount(
        disposables: [merchantCtrl, amountCtrl, monthlyCtrl, customCountCtrl],
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
                  // Mode Selector: New Purchase vs Ongoing Plan
                  Container(
                    decoration: BoxDecoration(
                      color: context.inputBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: context.borderColor),
                    ),
                    padding: const EdgeInsets.all(3),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              if (isOngoing) {
                                setDialogState(() {
                                  isOngoing = false;
                                  if (selectedCount == 1) selectedCount = 4;
                                });
                              }
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: !isOngoing ? context.primaryButtonBg : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                context.tr('plan_type_new'),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: !isOngoing ? context.primaryButtonFg : context.textSecondary,
                                  fontWeight: !isOngoing ? FontWeight.bold : FontWeight.normal,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              if (!isOngoing) {
                                setDialogState(() {
                                  isOngoing = true;
                                  final amt = parseMoneyInput(amountCtrl.text);
                                  if (amt != null && amt > 0) {
                                    isUpdatingInternally = true;
                                    monthlyCtrl.text = (amt / selectedCount).toStringAsFixed(2);
                                    isUpdatingInternally = false;
                                  }
                                });
                              }
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: isOngoing ? context.primaryButtonBg : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                context.tr('plan_type_ongoing'),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: isOngoing ? context.primaryButtonFg : context.textSecondary,
                                  fontWeight: isOngoing ? FontWeight.bold : FontWeight.normal,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

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

                  if (!isOngoing) ...[
                    TextField(
                      controller: amountCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: TextStyle(color: context.textPrimary),
                      onChanged: (_) => setDialogState(() {}),
                      decoration: InputDecoration(
                        labelText: context.tr('total_price'),
                        labelStyle: TextStyle(color: context.textSecondary),
                        hintText: '${context.tr('example_prefix')} 4000',
                        hintStyle: TextStyle(color: context.textSecondary),
                      ),
                    ),
                    if (parseMoneyInput(amountCtrl.text) != null && parseMoneyInput(amountCtrl.text)! > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          '≈ ${context.sar(parseMoneyInput(amountCtrl.text)! / selectedCount)} / ${context.tr(frequencyFor() == 'biweekly' ? 'inst_two_weeks_short' : 'month')}',
                          style: TextStyle(color: context.accentText, fontSize: 11.5, fontWeight: FontWeight.bold),
                        ),
                      ),
                  ] else ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: amountCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            style: TextStyle(color: context.textPrimary),
                            onChanged: (v) => onRemainingAmountChanged(v, setDialogState),
                            decoration: InputDecoration(
                              labelText: context.tr('remaining_amount_sar'),
                              labelStyle: TextStyle(color: context.textSecondary, fontSize: 11),
                              hintText: '${context.tr('example_prefix')} 1000',
                              hintStyle: TextStyle(color: context.textSecondary),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: monthlyCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            style: TextStyle(color: context.textPrimary),
                            onChanged: (v) => onMonthlyPaymentChanged(v, setDialogState),
                            decoration: InputDecoration(
                              labelText: context.tr('monthly_payment_sar'),
                              labelStyle: TextStyle(color: context.textSecondary, fontSize: 11),
                              hintText: '${context.tr('example_prefix')} 500',
                              hintStyle: TextStyle(color: context.textSecondary),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),

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
                                color: isSel ? (context.primaryButtonBg) : context.inputBg,
                                border: Border.all(
                                  color: isSel ? (context.accentText) : context.borderColor,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                p == 'Bank' ? context.tr('bnpl_provider_bank_other') : p,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: isSel ? (context.primaryButtonFg) : context.textPrimary,
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
                  const SizedBox(height: 14),

                  Text(
                    context.tr(isOngoing ? 'remaining_installments' : 'inst_installment_count'),
                    style: TextStyle(color: context.textSecondary, fontSize: 11),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      ...[1, 2, 3, 4, 6, 12].map((cnt) {
                        final isSel = !isCustomCount && selectedCount == cnt;
                        return InkWell(
                          onTap: () => onCountChanged(cnt, setDialogState),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                            decoration: BoxDecoration(
                              color: isSel ? context.primaryButtonBg : context.inputBg,
                              border: Border.all(
                                color: isSel ? context.accentText : context.borderColor,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$cnt',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: isSel ? context.primaryButtonFg : context.textPrimary,
                                fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        );
                      }),
                      InkWell(
                        onTap: () => setDialogState(() => isCustomCount = true),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: isCustomCount ? context.primaryButtonBg : context.inputBg,
                            border: Border.all(
                              color: isCustomCount ? context.accentText : context.borderColor,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            isCustomCount && selectedCount > 0 ? '$selectedCount' : context.tr('custom_installments'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: isCustomCount ? context.primaryButtonFg : context.textPrimary,
                              fontWeight: isCustomCount ? FontWeight.bold : FontWeight.normal,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (isCustomCount) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: customCountCtrl,
                      keyboardType: TextInputType.number,
                      style: TextStyle(color: context.textPrimary),
                      onChanged: (v) {
                        final n = int.tryParse(v);
                        if (n != null && n >= 1 && n <= 60) {
                          selectedCount = n;
                          final amt = parseMoneyInput(amountCtrl.text);
                          if (amt != null && amt > 0) {
                            isUpdatingInternally = true;
                            monthlyCtrl.text = (amt / n).toStringAsFixed(2);
                            isUpdatingInternally = false;
                          }
                          setDialogState(() {});
                        }
                      },
                      decoration: InputDecoration(
                        labelText: context.tr('custom_count_label'),
                        labelStyle: TextStyle(color: context.textSecondary, fontSize: 11),
                        hintText: 'e.g. 5, 8, 9, 18, 24, 36',
                        hintStyle: TextStyle(color: context.textSecondary),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),

                  if (!isOngoing && selectedCount > 1) ...[
                    InkWell(
                      onTap: () => setDialogState(() => firstPaidAtCheckout = !firstPaidAtCheckout),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 24,
                              height: 24,
                              child: Checkbox(
                                value: firstPaidAtCheckout,
                                onChanged: (v) => setDialogState(() => firstPaidAtCheckout = v ?? true),
                                activeColor: context.accentText,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                context.tr('first_paid_at_checkout'),
                                style: TextStyle(color: context.textSecondary, fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],

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
                                color: isSel ? (context.primaryButtonBg) : context.inputBg,
                                border: Border.all(
                                  color: isSel ? (context.accentText) : context.borderColor,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                context.tr(f == 'biweekly' ? 'inst_every_two_weeks' : 'inst_every_month'),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: isSel ? (context.primaryButtonFg) : context.textPrimary,
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
                  backgroundColor: context.primaryButtonBg,
                  foregroundColor: context.primaryButtonFg,
                ),
                onPressed: isSubmitting
                    ? null
                    : () async {
                        final merchant = merchantCtrl.text.trim();
                        final totalInput = parseMoneyInput(amountCtrl.text);
                        if (merchant.isEmpty || totalInput == null || totalInput <= 0 || selectedCount <= 0) {
                          AppSnackBar.showError(dCtx, context.tr('inst_invalid_input'));
                          return;
                        }
                        setDialogState(() => isSubmitting = true);
                        try {
                          final double totalAmount;
                          final double monthlyAmount;
                          final int totalCount = selectedCount;
                          final int paidCount;

                          if (isOngoing) {
                            totalAmount = totalInput;
                            final parsedMonthly = parseMoneyInput(monthlyCtrl.text);
                            monthlyAmount = (parsedMonthly != null && parsedMonthly > 0)
                                ? parsedMonthly
                                : totalInput / selectedCount;
                            paidCount = 0;
                          } else {
                            totalAmount = totalInput;
                            monthlyAmount = totalInput / selectedCount;
                            paidCount = (selectedCount > 1 && firstPaidAtCheckout) ? 1 : 0;
                          }

                          final planData = {
                            'household_id': widget.householdId ?? '',
                            'merchant': merchant,
                            'provider': selectedProvider,
                            'total_amount': totalAmount,
                            'monthly_amount': monthlyAmount,
                            'installment_count': totalCount,
                            'frequency': frequencyFor(),
                            'paid_installments': paidCount,
                            'category_code': 'OPEX-SHOPPING',
                            'adjust_original_transaction': false,
                            'notes': isOngoing
                                ? 'Manually registered ongoing plan ($selectedCount remaining)'
                                : 'Manually registered BNPL plan',
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

  /// "Installment 2 of 4 paid · next 29 Oct" for an active plan, or
  /// "First of 2 due 29 Oct" when 0 paid.
  String? _nextDueText(BuildContext context, InstallmentPlan plan, DateTime today) {
    final next = plan.nextDueDate(today: today);
    if (next == null) return null;
    if (plan.paidInstallments == 0) {
      return context.trArgs('inst_first_due', {
        'count': plan.installmentCount,
        'date': context.fmtDate(next, 'd MMM'),
      });
    }
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
                          color: context.alertDangerBg,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.credit_score_rounded,
                          color: context.dangerColor,
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
                                    ? (context.successText)
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
                            backgroundColor: context.primaryButtonBg,
                            foregroundColor: context.primaryButtonFg,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          ),
                          icon: const Icon(Icons.add, size: 16),
                          label: Text(
                            context.tr('add_installment_plan'),
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
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Wrap(
                                        spacing: 8,
                                        runSpacing: 4,
                                        crossAxisAlignment: WrapCrossAlignment.center,
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
                                          Text(
                                            plan.merchant,
                                            style: GoogleFonts.outfit(
                                              fontWeight: FontWeight.w600,
                                              color: context.textPrimary,
                                              fontSize: 14,
                                            ),
                                          ),
                                          Text(
                                            '${context.sar(plan.installmentAmount)} / ${context.tr(plan.isBiweekly ? 'inst_two_weeks_short' : 'month')}',
                                            style: GoogleFonts.outfit(
                                              fontWeight: FontWeight.bold,
                                              color: context.accentText,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    PopupMenuButton<String>(
                                      icon: Icon(Icons.more_vert, size: 18, color: context.textSecondary),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      color: context.cardBg,
                                      onSelected: (val) async {
                                        if (val == 'edit') {
                                          _showEditPlanDialog(context, plan);
                                        } else if (val == 'delete') {
                                          final confirmed = await showDialog<bool>(
                                            context: context,
                                            builder: (dCtx) => AlertDialog(
                                              backgroundColor: dCtx.cardBg,
                                              title: Text(dCtx.tr('delete_installment_title'),
                                                  style: GoogleFonts.outfit(color: dCtx.textPrimary, fontWeight: FontWeight.bold)),
                                              content: Text(dCtx.tr('delete_installment_confirm'),
                                                  style: TextStyle(color: dCtx.textSecondary)),
                                              actions: [
                                                TextButton(
                                                  onPressed: () => Navigator.pop(dCtx, false),
                                                  child: Text(dCtx.tr('cancel'), style: TextStyle(color: dCtx.textSecondary)),
                                                ),
                                                ElevatedButton(
                                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                                                  onPressed: () => Navigator.pop(dCtx, true),
                                                  child: Text(dCtx.tr('delete'),
                                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                                ),
                                              ],
                                            ),
                                          );
                                          if (confirmed == true && context.mounted) {
                                            try {
                                              await context.read<InstallmentProvider>().deletePlan(plan.id);
                                            } catch (_) {
                                              try {
                                                await supabase.from('installment_plans').delete().eq('id', plan.id);
                                              } catch (_) {}
                                            }
                                            if (!context.mounted) return;
                                            if (mounted) setState(() => _loadPlans());
                                            AppSnackBar.showSuccess(context, context.tr('installment_deleted'));
                                          }
                                        }
                                      },
                                      itemBuilder: (ctx) => [
                                          PopupMenuItem(
                                            value: 'edit',
                                            child: Row(
                                              children: [
                                                Icon(Icons.edit_outlined, size: 18, color: ctx.textPrimary),
                                                const SizedBox(width: 8),
                                                Text(ctx.tr('edit'), style: TextStyle(color: ctx.textPrimary, fontSize: 13)),
                                              ],
                                            ),
                                          ),
                                        PopupMenuItem(
                                          value: 'delete',
                                          child: Row(
                                            children: [
                                              const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                                              const SizedBox(width: 8),
                                              Text(ctx.tr('delete'), style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                                            ],
                                          ),
                                        ),
                                      ],
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
                                          ? (context.successText)
                                          : providerColor,
                                    ),
                                    minHeight: 6,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  alignment: WrapAlignment.spaceBetween,
                                  spacing: 8,
                                  runSpacing: 2,
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
                                          final recorded = await ManualExpenseSheet.show(
                                            context,
                                            householdId: plan.householdId.isNotEmpty
                                                ? plan.householdId
                                                : widget.householdId,
                                            initialMerchant: plan.merchant,
                                            initialAmount: plan.monthlyAmount,
                                            initialCategory: (plan.categoryCode != null && plan.categoryCode!.isNotEmpty)
                                                ? plan.categoryCode!
                                                : 'OPEX-SHOPPING',
                                            installmentPlan: plan,
                                          );
                                          if (recorded == true && mounted) {
                                            setState(() => _loadPlans());
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
                            foregroundColor: context.accentText,
                            side: BorderSide(color: context.borderColor),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          ),
                          icon: const Icon(Icons.add, size: 14),
                          label: Text(context.tr('add_installment_plan'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
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
