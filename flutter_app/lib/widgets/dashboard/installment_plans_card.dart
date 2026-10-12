import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../main.dart';
import '../../models/installment_plan.dart';
import '../../services/api_service.dart';
import '../app_snackbar.dart';

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

  @override
  void initState() {
    super.initState();
    _loadPlans();
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
          backgroundColor: const Color(0xFF161B22),
          title: Text(
            'New Installment Plan',
            style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: merchantCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Merchant / Item',
                    labelStyle: TextStyle(color: Color(0xFF8B949E)),
                    hintText: 'e.g. eXtra Electronics, Jarir',
                    hintStyle: TextStyle(color: Color(0xFF484F58)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Total Price (SAR)',
                    labelStyle: TextStyle(color: Color(0xFF8B949E)),
                    hintText: 'e.g. 4000',
                    hintStyle: TextStyle(color: Color(0xFF484F58)),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('PROVIDER', style: TextStyle(color: Color(0xFF8B949E), fontSize: 11)),
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
                              color: isSel ? const Color(0xFF00C896).withValues(alpha: 0.2) : const Color(0xFF0D1117),
                              border: Border.all(color: isSel ? const Color(0xFF00C896) : const Color(0xFF30363D)),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              p,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: isSel ? const Color(0xFF00C896) : Colors.white,
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
                const Text('DURATION', style: TextStyle(color: Color(0xFF8B949E), fontSize: 11)),
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
                              color: isSel ? const Color(0xFF00C896).withValues(alpha: 0.2) : const Color(0xFF0D1117),
                              border: Border.all(color: isSel ? const Color(0xFF00C896) : const Color(0xFF30363D)),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$cnt mo',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: isSel ? const Color(0xFF00C896) : Colors.white,
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
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF8B949E))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00C896),
                foregroundColor: Colors.black,
              ),
              onPressed: isSubmitting
                  ? null
                  : () async {
                      final merchant = merchantCtrl.text.trim();
                      final total = double.tryParse(amountCtrl.text);
                      if (merchant.isEmpty || total == null || total <= 0) {
                        AppSnackBar.showError(dCtx, 'Please provide valid merchant and total amount.');
                        return;
                      }
                      setDialogState(() => isSubmitting = true);
                      try {
                        await ApiService.instance.createInstallmentPlan({
                          'household_id': widget.householdId ?? '',
                          'merchant': merchant,
                          'provider': selectedProvider,
                          'total_amount': total,
                          'installment_count': selectedCount,
                          'paid_installments': 1,
                          'category_code': 'OPEX-SHOPPING',
                          'adjust_original_transaction': false,
                          'notes': 'Manually registered BNPL plan',
                        });
                        if (dCtx.mounted) Navigator.pop(dCtx);
                        setState(() => _loadPlans());
                        if (context.mounted) {
                          AppSnackBar.showSuccess(
                            context,
                            'Created $selectedProvider installment plan for $merchant',
                            title: 'Plan Active',
                          );
                        }
                      } catch (e) {
                        setDialogState(() => isSubmitting = false);
                        if (dCtx.mounted) {
                          AppSnackBar.showError(dCtx, 'Failed to create plan: $e');
                        }
                      }
                    },
              child: isSubmitting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : const Text('Confirm Plan', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00', 'en_US');
    return FutureBuilder<List<InstallmentPlan>>(
      future: _futurePlans,
      builder: (context, snapshot) {
        final plans = snapshot.data ?? widget.plans ?? [];
        final activePlans = plans.where((p) => !p.isCompleted).toList();
        final totalMonthlyCommitment = activePlans.fold<double>(
          0.0,
          (sum, p) => sum + p.monthlyAmount,
        );

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF30363D)),
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
                              'Installments & BNPL',
                              style: GoogleFonts.outfit(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              activePlans.isEmpty
                                  ? 'All installments cleared'
                                  : 'SAR ${fmt.format(totalMonthlyCommitment)} / mo scheduled',
                              style: TextStyle(
                                fontSize: 12,
                                color: activePlans.isEmpty
                                    ? const Color(0xFF00C896)
                                    : const Color(0xFF8B949E),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        _isExpanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: const Color(0xFF8B949E),
                      ),
                    ],
                  ),
                ),
              ),

              if (_isExpanded) ...[
                const Divider(color: Color(0xFF21262D), height: 1),
                if (plans.isEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: const BoxDecoration(
                            color: Color(0xFF0D1117),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.credit_score_outlined,
                            color: Color(0xFF8B949E),
                            size: 28,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'No Active BNPL Installments',
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Convert large purchases into 3 or 4 monthly payments (Tamara / Tabby) in the transaction edit sheet, or log a commitment directly.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFF8B949E), fontSize: 12),
                        ),
                        const SizedBox(height: 14),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00C896),
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          ),
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text(
                            '+ Add Installment Plan',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
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
                              color: const Color(0xFF0D1117),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFF21262D)),
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
                                          color: Colors.white,
                                          fontSize: 14,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Text(
                                      'SAR ${fmt.format(plan.monthlyAmount)} / mo',
                                      style: GoogleFonts.outfit(
                                        fontWeight: FontWeight.bold,
                                        color: const Color(0xFF00C896),
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
                                    backgroundColor: const Color(0xFF21262D),
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      plan.isCompleted
                                          ? const Color(0xFF00C896)
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
                                      'Installment ${plan.paidInstallments} of ${plan.installmentCount} paid',
                                      style: const TextStyle(
                                        color: Color(0xFF8B949E),
                                        fontSize: 11,
                                      ),
                                    ),
                                    Text(
                                      'Remaining: SAR ${fmt.format(plan.remainingAmount)}',
                                      style: const TextStyle(
                                        color: Color(0xFFC9D1D9),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                                if (!plan.isCompleted) ...[
                                  const SizedBox(height: 8),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.white,
                                        side: const BorderSide(color: Color(0xFF30363D)),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 4),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      icon: const Icon(Icons.check_circle_outline, size: 14),
                                      label: const Text('Record Payment', style: TextStyle(fontSize: 11)),
                                      onPressed: () {
                                        if (widget.onPayInstallment != null) {
                                          widget.onPayInstallment!(plan.id);
                                        } else {
                                          ApiService.instance.payInstallment(plan.id).then((_) {
                                            setState(() => _loadPlans());
                                          });
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
                            foregroundColor: const Color(0xFF00C896),
                            side: const BorderSide(color: Color(0xFF30363D)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          ),
                          icon: const Icon(Icons.add, size: 14),
                          label: const Text('+ Add Installment Plan', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
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
      },
    );
  }
}
