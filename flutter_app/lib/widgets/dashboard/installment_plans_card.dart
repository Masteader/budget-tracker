import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/installment_plan.dart';
import '../../services/api_service.dart';

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
      _futurePlans = ApiService.instance.getInstallments(widget.householdId!);
    } else {
      _futurePlans = Future.value([]);
    }
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

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<InstallmentPlan>>(
      future: _futurePlans,
      builder: (context, snapshot) {
        final plans = snapshot.data ?? widget.plans ?? [];
        if (plans.isEmpty && snapshot.connectionState == ConnectionState.done) {
          return const SizedBox.shrink();
        }

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
                                  : 'SAR ${totalMonthlyCommitment.toStringAsFixed(2)} / mo scheduled',
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

              if (_isExpanded && plans.isNotEmpty) ...[
                const Divider(color: Color(0xFF21262D), height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                    children: plans.map((plan) {
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
                                  'SAR ${plan.monthlyAmount.toStringAsFixed(2)} / mo',
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
                                  'Remaining: SAR ${plan.remainingAmount.toStringAsFixed(2)}',
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
                    }).toList(),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
