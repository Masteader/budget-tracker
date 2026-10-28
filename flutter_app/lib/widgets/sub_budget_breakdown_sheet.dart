import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_themes.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../main.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import 'sub_budget_allocation_dialog.dart';

class SubBudgetBreakdownSheet extends StatefulWidget {
  final String householdId;
  final String categoryCode;
  final String? cycleKey;
  final double allocatedAmount;
  final double spentAmount;
  final double previousCycleDelta;

  const SubBudgetBreakdownSheet({
    super.key,
    required this.householdId,
    required this.categoryCode,
    this.cycleKey,
    required this.allocatedAmount,
    this.spentAmount = 0.0,
    this.previousCycleDelta = 0.0,
  });

  static void show(
    BuildContext context, {
    required String householdId,
    required String categoryCode,
    String? cycleKey,
    required double allocatedAmount,
    double spentAmount = 0.0,
    double previousCycleDelta = 0.0,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SubBudgetBreakdownSheet(
        householdId: householdId,
        categoryCode: categoryCode,
        cycleKey: cycleKey,
        allocatedAmount: allocatedAmount,
        spentAmount: spentAmount,
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
            _errorMessage = res['message'] as String? ?? context.tr('sbb_load_failed');
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

      // Fetch the latest budget row for this household & cycle to get any saved subAllocations
      Map<String, double> dbSubAllocs = {};
      try {
        var query = supabase
            .from('budgets')
            .select('sub_allocations, allocated_amount, spent_amount, remaining_amount, previous_cycle_delta')
            .eq('household_id', widget.householdId)
            .eq('category_code', widget.categoryCode);
        if (widget.cycleKey != null && widget.cycleKey!.isNotEmpty) {
          query = query.eq('cycle_key', widget.cycleKey!);
        }
        final bData = await query.maybeSingle();
        if (bData != null && bData['sub_allocations'] is Map) {
          final rawMap = bData['sub_allocations'] as Map<String, dynamic>;
          final Map<String, double> dbSubAllocsMap = {};
          for (final entry in rawMap.entries) {
            if (!entry.key.startsWith('_') && entry.value is num) {
              dbSubAllocsMap[entry.key] = (entry.value as num).toDouble();
            }
          }
          dbSubAllocs = dbSubAllocsMap;
        }
      } catch (_) {}

      // Fallback CategoryBreakdownItem if API returned no matching item
      matched ??= CategoryBreakdownItem(
        categoryCode: widget.categoryCode,
        categoryName: widget.categoryCode,
        allocatedAmount: widget.allocatedAmount,
        spentAmount: widget.spentAmount,
        remainingAmount: widget.allocatedAmount - widget.spentAmount,
        previousCycleDelta: widget.previousCycleDelta,
        subCategories: const [],
      );

      // Merge any configured sub-allocations from the database into matched.subCategories
      if (dbSubAllocs.isNotEmpty) {
        final existingCodes = matched.subCategories.map((s) => s.subCode).whereType<String>().toSet();
        final updatedSubs = List<SubCategoryBreakdownItem>.from(matched.subCategories);

        for (final entry in dbSubAllocs.entries) {
          if (entry.key != 'other' && !existingCodes.contains(entry.key)) {
            String name = entry.key.replaceAll('_', ' ');
            name = name.isNotEmpty ? name[0].toUpperCase() + name.substring(1) : entry.key;
            final catalog = SubBudgetAllocationDialog.kDefaultSubCategoriesCatalog[widget.categoryCode];
            if (catalog != null) {
              final found = catalog.where((c) => c['sub_code'] == entry.key).firstOrNull;
              if (found != null && found['name_en'] != null) {
                name = found['name_en']!;
              }
            }
            updatedSubs.add(SubCategoryBreakdownItem(
              subCode: entry.key,
              name: name,
              allocatedAmount: entry.value,
              spentAmount: 0.0,
              transactionCount: 0,
            ));
          }
        }

        // If we now have specific sub-categories, filter out empty "other" (0 spent, 0 allocated)
        final hasSpecific = updatedSubs.any((s) => s.subCode != null && s.subCode != 'other');
        final filteredSubs = hasSpecific
            ? updatedSubs.where((s) => !(s.subCode == 'other' && s.spentAmount == 0 && s.allocatedAmount == 0)).toList()
            : updatedSubs;

        matched = CategoryBreakdownItem(
          categoryCode: matched.categoryCode,
          categoryName: matched.categoryName,
          allocatedAmount: matched.allocatedAmount,
          spentAmount: matched.spentAmount,
          remainingAmount: matched.remainingAmount,
          previousCycleDelta: matched.previousCycleDelta,
          subCategories: filteredSubs,
        );
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
    if (code.contains('cloth') || code.contains('fashion') || code.contains('shoe')) return Icons.checkroom_outlined;
    if (code.contains('electronic') || code.contains('gadget')) return Icons.devices_outlined;
    if (code.contains('furnitur') || code.contains('home')) return Icons.chair_outlined;
    if (code.contains('cinema') || code.contains('game') || code.contains('entertain')) return Icons.sports_esports_outlined;
    if (code.contains('tuition') || code.contains('book') || code.contains('school') || code.contains('educat')) return Icons.school_outlined;
    if (code.contains('gov') || code.contains('visa') || code.contains('iqama')) return Icons.account_balance_outlined;
    return Icons.category_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00', 'en_US');
    final spent = _categoryData != null ? _categoryData!.spentAmount : widget.spentAmount;
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
                  color: context.borderColor,
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
                    color: context.accentSubtleBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.pie_chart_outline_rounded,
                    color: context.accentText,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.trCat(widget.categoryCode),
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: context.textPrimary,
                        ),
                      ),
                      if (_cycleInfo != null)
                        Text(
                          _cycleInfo!.label,
                          style: TextStyle(
                            color: context.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.edit_outlined,
                    color: context.accentText,
                    size: 20,
                  ),
                  tooltip: context.tr('edit_allocations'),
                  onPressed: () async {
                    Budget? existing;
                    if (_categoryData != null) {
                      final allocMap = <String, double>{};
                      for (final s in _categoryData!.subCategories) {
                        if (s.subCode != null && s.allocatedAmount > 0) {
                          allocMap[s.subCode!] = s.allocatedAmount;
                        }
                      }
                      existing = Budget(
                        id: '',
                        householdId: widget.householdId,
                        month: '${widget.cycleKey ?? "2026-10"}-01',
                        categoryCode: widget.categoryCode,
                        allocatedAmount: _categoryData!.allocatedAmount,
                        spentAmount: _categoryData!.spentAmount,
                        remainingAmount: _categoryData!.remainingAmount,
                        cycleKey: widget.cycleKey,
                        subAllocations: allocMap,
                      );
                    }

                    final updated = await SubBudgetAllocationDialog.show(
                      context,
                      householdId: widget.householdId,
                      categoryCode: widget.categoryCode,
                      categoryName: _categoryData?.categoryName ?? widget.categoryCode,
                      existingBudget: existing,
                      cycleKey: widget.cycleKey,
                    );
                    if (updated == true) {
                      _loadBreakdown();
                    }
                  },

                ),
                IconButton(
                  tooltip: context.tr('close'),
                  icon: Icon(Icons.close, color: context.textSecondary),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Overview summary card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.subtleCardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.borderColor),
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
                          Text(context.tr('spent'),
                              style: TextStyle(color: context.textSecondary, fontSize: 12)),
                          const SizedBox(height: 2),
                          Text(
                            context.sar(spent),
                            style: GoogleFonts.outfit(
                              color: context.textPrimary,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(context.tr('base_allocation'),
                              style: TextStyle(color: context.textSecondary, fontSize: 12)),
                          const SizedBox(height: 2),
                          Text(
                            context.sar(allocated),
                            style: GoogleFonts.outfit(
                              color: context.accentText,
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
                            ? (context.accentSubtleBg)
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
                                ? (context.accentText)
                                : Colors.redAccent,
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            prevDelta > 0
                                ? '+${context.sar(prevDelta)} ${context.tr('rolled_over_surplus')}'
                                : '-${context.sar(prevDelta.abs())} ${context.tr('rolled_over_overspend')}',
                            style: TextStyle(
                              color: prevDelta > 0
                                  ? (context.accentText)
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
                  context.tr('itemized_sub_budgets'),
                  style: GoogleFonts.outfit(
                    color: context.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${context.tr('allocated')} & ${context.tr('spent')}',
                  style: GoogleFonts.inter(
                    color: context.textSecondary,
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
            Text(
              context.tr('no_sub_budget_records'),
              style: TextStyle(color: context.textSecondary, fontSize: 13),
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
          progressColor = context.infoColor;
        } else if (item.spentAmount > item.allocatedAmount) {
          progressColor = Colors.redAccent;
        } else if (item.spentAmount > item.allocatedAmount * 0.85) {
          progressColor = Colors.orangeAccent;
        } else {
          progressColor = context.accentText;
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: context.subtleCardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: context.chipBg,
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
                          context.trSub(item.subCode ?? item.name, nameEn: item.name),
                          style: TextStyle(
                            color: context.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (item.transactionCount > 0)
                          Text(
                            context.trPlural('transactions_count', item.transactionCount),
                            style: TextStyle(
                              color: context.textSecondary,
                              fontSize: 11,
                            ),
                          )
                        else if (hasAllocation)
                          Text(
                            context.tr('no_expenses_yet'),
                            style: TextStyle(
                              color: context.textSecondary,
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
                        context.sar(item.spentAmount),
                        style: GoogleFonts.outfit(
                          color: item.spentAmount > 0 ? context.textPrimary : context.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (hasAllocation)
                        Text(
                          context.trArgs('of_amount', {'amount': context.sar(item.allocatedAmount)}),
                          style: TextStyle(
                            color: item.spentAmount > item.allocatedAmount
                                ? Colors.redAccent
                                : context.textSecondary,
                            fontSize: 11,
                            fontWeight: item.spentAmount > item.allocatedAmount
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        )
                      else if (totalCatSpent > 0 && item.spentAmount > 0)
                        Text(
                          context.trArgs('sbb_pct_of_category', {'percent': ((item.spentAmount / totalCatSpent) * 100).toStringAsFixed(0)}),
                          style: TextStyle(
                            color: context.textSecondary,
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
                    backgroundColor: context.chipBg,
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
