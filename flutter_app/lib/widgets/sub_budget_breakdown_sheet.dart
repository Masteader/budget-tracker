import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import 'sub_budget_allocation_dialog.dart';

class SubBudgetBreakdownSheet extends StatefulWidget {
  final String householdId;
  final String categoryCode;
  final String? cycleKey;
  final double allocatedAmount;
  final double previousCycleDelta;

  const SubBudgetBreakdownSheet({
    super.key,
    required this.householdId,
    required this.categoryCode,
    this.cycleKey,
    required this.allocatedAmount,
    this.previousCycleDelta = 0.0,
  });

  static void show(
    BuildContext context, {
    required String householdId,
    required String categoryCode,
    String? cycleKey,
    required double allocatedAmount,
    double previousCycleDelta = 0.0,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF161B22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SubBudgetBreakdownSheet(
        householdId: householdId,
        categoryCode: categoryCode,
        cycleKey: cycleKey,
        allocatedAmount: allocatedAmount,
        previousCycleDelta: previousCycleDelta,
      ),
    );
  }

  @override
  State<SubBudgetBreakdownSheet> createState() => _SubBudgetBreakdownSheetState();
}

class _SubBudgetBreakdownSheetState extends State<SubBudgetBreakdownSheet> {
  bool _isLoading = true;
  String? _errorMessage;
  CategoryBreakdownItem? _categoryData;
  SalaryCycleInfo? _cycleInfo;

  @override
  void initState() {
    super.initState();
    _loadBreakdown();
  }

  Future<void> _loadBreakdown() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await ApiService.instance.getBudgetBreakdown(
        widget.householdId,
        cycleKey: widget.cycleKey,
      );

      if (res['status'] == 'error') {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = res['message'] as String? ?? 'Failed to load breakdown';
          });
        }
        return;
      }

      if (res['cycle_info'] != null) {
        _cycleInfo = SalaryCycleInfo.fromMap(
          Map<String, dynamic>.from(res['cycle_info'] as Map),
        );
      }

      final categoriesRaw = res['categories'] as List? ?? [];
      CategoryBreakdownItem? matched;
      for (final c in categoriesRaw) {
        final item = CategoryBreakdownItem.fromMap(
          Map<String, dynamic>.from(c as Map),
        );
        if (item.categoryCode == widget.categoryCode) {
          matched = item;
          break;
        }
      }

      if (mounted) {
        setState(() {
          _categoryData = matched;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  IconData _getSubCategoryIcon(String? subCode) {
    final code = (subCode ?? '').toLowerCase();
    if (code.contains('meat') || code.contains('chicken')) return Icons.restaurant;
    if (code.contains('vegetable') || code.contains('produce') || code.contains('fruit')) return Icons.eco_outlined;
    if (code.contains('dairy') || code.contains('egg')) return Icons.egg_alt_outlined;
    if (code.contains('snack') || code.contains('chip')) return Icons.cookie_outlined;
    if (code.contains('beverage') || code.contains('water')) return Icons.local_drink_outlined;
    if (code.contains('rent') || code.contains('housing')) return Icons.home_outlined;
    if (code.contains('electric') || code.contains('sec')) return Icons.electric_bolt_outlined;
    if (code.contains('internet') || code.contains('fiber')) return Icons.wifi_outlined;
    if (code.contains('sim') || code.contains('mobile')) return Icons.sim_card_outlined;
    if (code.contains('fuel') || code.contains('gas')) return Icons.local_gas_station_outlined;
    if (code.contains('car') || code.contains('mechanic')) return Icons.car_repair_outlined;
    if (code.contains('dine') || code.contains('burger')) return Icons.lunch_dining_outlined;
    if (code.contains('coffee') || code.contains('cafe')) return Icons.coffee_outlined;
    if (code.contains('pharmacy') || code.contains('med')) return Icons.medication_outlined;
    return Icons.category_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00', 'en_US');
    final catName = _categoryData?.categoryName ??
        widget.categoryCode.replaceFirst(RegExp(r'^[A-Z]+-'), '');
    final spent = _categoryData?.spentAmount ?? 0.0;
    final allocated = widget.allocatedAmount > 0 ? widget.allocatedAmount : (_categoryData?.allocatedAmount ?? 0.0);
    final prevDelta = widget.previousCycleDelta != 0.0
        ? widget.previousCycleDelta
        : (_categoryData?.previousCycleDelta ?? 0.0);

    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF30363D),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00C896).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.pie_chart_outline_rounded,
                      color: Color(0xFF00C896), size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        catName,
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      if (_cycleInfo != null)
                        Text(
                          _cycleInfo!.label,
                          style: const TextStyle(
                            color: Color(0xFF8B949E),
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, color: Color(0xFF00C896), size: 20),
                  tooltip: 'Edit Sub-Allocations',
                  onPressed: () async {
                    final updated = await SubBudgetAllocationDialog.show(
                      context,
                      householdId: widget.householdId,
                      categoryCode: widget.categoryCode,
                      categoryName: _categoryData?.categoryName ?? widget.categoryCode,
                      cycleKey: widget.cycleKey,
                    );
                    if (updated == true) {
                      _loadBreakdown();
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Color(0xFF8B949E)),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Overview summary card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0D1117),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF30363D)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Total Spent',
                              style: TextStyle(color: Color(0xFF8B949E), fontSize: 12)),
                          const SizedBox(height: 2),
                          Text(
                            'SAR ${fmt.format(spent)}',
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text('Base Allocation',
                              style: TextStyle(color: Color(0xFF8B949E), fontSize: 12)),
                          const SizedBox(height: 2),
                          Text(
                            'SAR ${fmt.format(allocated)}',
                            style: GoogleFonts.outfit(
                              color: const Color(0xFF00C896),
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (prevDelta != 0.0) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: prevDelta > 0
                            ? const Color(0xFF00C896).withValues(alpha: 0.12)
                            : Colors.redAccent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            prevDelta > 0
                                ? Icons.arrow_downward_rounded
                                : Icons.arrow_upward_rounded,
                            color: prevDelta > 0
                                ? const Color(0xFF00C896)
                                : Colors.redAccent,
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            prevDelta > 0
                                ? '+SAR ${fmt.format(prevDelta)} unspent surplus rolled over'
                                : '-SAR ${fmt.format(prevDelta.abs())} overspend carried over',
                            style: TextStyle(
                              color: prevDelta > 0
                                  ? const Color(0xFF00C896)
                                  : Colors.redAccent,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Sub-Category Budgets',
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Allocated & Spent',
                  style: GoogleFonts.inter(
                    color: const Color(0xFF00C896),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Content
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _errorMessage != null
                      ? Center(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(color: Colors.redAccent),
                          ),
                        )
                      : _buildSubCategoryList(fmt, spent),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubCategoryList(NumberFormat fmt, double totalCatSpent) {
    final subList = _categoryData?.subCategories ?? [];
    if (subList.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_outlined,
                color: Colors.grey.withValues(alpha: 0.4), size: 40),
            const SizedBox(height: 10),
            const Text(
              'No itemized sub-budget records yet',
              style: TextStyle(color: Color(0xFF8B949E), fontSize: 13),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: subList.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (ctx, index) {
        final item = subList[index];
        final hasAllocation = item.allocatedAmount > 0;
        final usageRatio = hasAllocation
            ? (item.spentAmount / item.allocatedAmount)
            : (totalCatSpent > 0 ? (item.spentAmount / totalCatSpent) : 0.0);
        final clampedProgress = usageRatio.clamp(0.0, 1.0);

        Color progressColor;
        if (!hasAllocation) {
          progressColor = const Color(0xFF58A6FF);
        } else if (item.spentAmount > item.allocatedAmount) {
          progressColor = Colors.redAccent;
        } else if (item.spentAmount > item.allocatedAmount * 0.85) {
          progressColor = Colors.orangeAccent;
        } else {
          progressColor = const Color(0xFF00C896);
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF0D1117),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF21262D)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF21262D),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      _getSubCategoryIcon(item.subCode),
                      color: progressColor,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (item.transactionCount > 0)
                          Text(
                            '${item.transactionCount} transaction${item.transactionCount > 1 ? 's' : ''}',
                            style: const TextStyle(
                              color: Color(0xFF8B949E),
                              fontSize: 11,
                            ),
                          )
                        else if (hasAllocation)
                          const Text(
                            'No expenses yet',
                            style: TextStyle(
                              color: Color(0xFF8B949E),
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'SAR ${fmt.format(item.spentAmount)}',
                        style: GoogleFonts.outfit(
                          color: item.spentAmount > 0 ? Colors.white : const Color(0xFF8B949E),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (hasAllocation)
                        Text(
                          'of SAR ${fmt.format(item.allocatedAmount)}',
                          style: TextStyle(
                            color: item.spentAmount > item.allocatedAmount
                                ? Colors.redAccent
                                : const Color(0xFF8B949E),
                            fontSize: 11,
                            fontWeight: item.spentAmount > item.allocatedAmount
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        )
                      else if (totalCatSpent > 0 && item.spentAmount > 0)
                        Text(
                          '${((item.spentAmount / totalCatSpent) * 100).toStringAsFixed(0)}% of cat',
                          style: const TextStyle(
                            color: Color(0xFF8B949E),
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              if (hasAllocation || item.spentAmount > 0) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: clampedProgress,
                    backgroundColor: const Color(0xFF21262D),
                    valueColor: AlwaysStoppedAnimation(progressColor),
                    minHeight: 4,
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
