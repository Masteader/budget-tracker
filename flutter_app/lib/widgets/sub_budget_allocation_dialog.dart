import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../main.dart';
import '../models/models.dart';
import '../services/api_service.dart';

class SubBudgetAllocationDialog extends StatefulWidget {
  final String householdId;
  final String categoryCode;
  final String categoryName;
  final Budget? existingBudget;
  final String? cycleKey;
  final VoidCallback? onSaved;

  const SubBudgetAllocationDialog({
    super.key,
    required this.householdId,
    required this.categoryCode,
    required this.categoryName,
    this.existingBudget,
    this.cycleKey,
    this.onSaved,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String householdId,
    required String categoryCode,
    required String categoryName,
    Budget? existingBudget,
    String? cycleKey,
    VoidCallback? onSaved,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SubBudgetAllocationDialog(
        householdId: householdId,
        categoryCode: categoryCode,
        categoryName: categoryName,
        existingBudget: existingBudget,
        cycleKey: cycleKey,
        onSaved: onSaved,
      ),
    );
  }

  @override
  State<SubBudgetAllocationDialog> createState() =>
      _SubBudgetAllocationDialogState();
}

class _SubCategoryItemDef {
  final String subCode;
  final String nameEn;
  final String nameAr;
  final TextEditingController controller;

  _SubCategoryItemDef({
    required this.subCode,
    required this.nameEn,
    required this.nameAr,
    required this.controller,
  });
}

class _SubBudgetAllocationDialogState extends State<SubBudgetAllocationDialog> {
  final NumberFormat _currencyFmt = NumberFormat('#,##0.00', 'en_US');
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;
  final List<_SubCategoryItemDef> _subItems = [];
  late TextEditingController _fallbackParentController;
  double _totalSum = 0.0;

  @override
  void initState() {
    super.initState();
    _fallbackParentController = TextEditingController(
      text: widget.existingBudget != null && widget.existingBudget!.allocatedAmount > 0
          ? widget.existingBudget!.allocatedAmount.toStringAsFixed(2)
          : '',
    );
    _fallbackParentController.addListener(_recomputeTotal);
    _loadSubCategories();
  }

  @override
  void dispose() {
    _fallbackParentController.removeListener(_recomputeTotal);
    _fallbackParentController.dispose();
    for (final item in _subItems) {
      item.controller.removeListener(_recomputeTotal);
      item.controller.dispose();
    }
    super.dispose();
  }

  void _recomputeTotal() {
    if (!mounted) return;
    double sum = 0.0;
    if (_subItems.isNotEmpty) {
      for (final item in _subItems) {
        final val = double.tryParse(item.controller.text.trim()) ?? 0.0;
        sum += val;
      }
    } else {
      sum = double.tryParse(_fallbackParentController.text.trim()) ?? 0.0;
    }
    setState(() {
      _totalSum = sum;
    });
  }

  Future<void> _loadSubCategories() async {
    try {
      final res = await supabase
          .from('cost_control_sub_categories')
          .select('sub_code, name_en, name_ar')
          .eq('parent_code', widget.categoryCode)
          .order('id');

      final existingAllocs = widget.existingBudget?.subAllocations ?? {};
      final list = (res as List).map((row) {
        final code = row['sub_code'] as String;
        final nameEn = row['name_en'] as String? ?? code;
        final nameAr = row['name_ar'] as String? ?? '';
        final existingVal = existingAllocs[code];
        final ctrl = TextEditingController(
          text: (existingVal != null && existingVal > 0)
              ? existingVal.toStringAsFixed(2)
              : '',
        );
        ctrl.addListener(_recomputeTotal);
        return _SubCategoryItemDef(
          subCode: code,
          nameEn: nameEn,
          nameAr: nameAr,
          controller: ctrl,
        );
      }).toList();

      if (mounted) {
        setState(() {
          _subItems.addAll(list);
          _isLoading = false;
        });
        _recomputeTotal();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Could not load sub-categories catalog: $e';
        });
        _recomputeTotal();
      }
    }
  }

  Future<void> _handleSave() async {
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      if (_subItems.isNotEmpty) {
        final allocMap = <String, double>{};
        for (final item in _subItems) {
          final val = double.tryParse(item.controller.text.trim()) ?? 0.0;
          allocMap[item.subCode] = val;
        }

        final res = await ApiService.instance.saveSubAllocations(
          householdId: widget.householdId,
          categoryCode: widget.categoryCode,
          subAllocations: allocMap,
          cycleKey: widget.cycleKey,
        );

        if (res['status'] != 'success') {
          throw Exception(res['message'] ?? 'Failed to save sub-allocations');
        }
      } else {
        // Fallback for single category without sub-categories
        final amount = double.tryParse(_fallbackParentController.text.trim()) ?? 0.0;
        final cycleKey = widget.cycleKey ?? DateFormat('yyyy-MM').format(DateTime.now());
        final monthStr = '$cycleKey-01';

        if (widget.existingBudget != null) {
          await supabase.from('budgets').update({
            'allocated_amount': amount,
            'cycle_key': cycleKey,
            'is_active': true,
          }).eq('id', widget.existingBudget!.id);
        } else {
          await supabase.from('budgets').insert({
            'household_id': widget.householdId,
            'category_code': widget.categoryCode,
            'allocated_amount': amount,
            'spent_amount': 0.0,
            'month': monthStr,
            'cycle_key': cycleKey,
            'is_active': true,
          });
        }
      }

      if (mounted) {
        widget.onSaved?.call();
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${widget.categoryName} budget saved (SAR ${_currencyFmt.format(_totalSum)})',
            ),
            backgroundColor: const Color(0xFF00C896),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      margin: EdgeInsets.only(bottom: bottomInset),
      decoration: const BoxDecoration(
        color: Color(0xFF161B22),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF30363D),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),

            // Header Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.categoryName,
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${widget.categoryCode} • Cycle ${widget.cycleKey ?? "Current"}',
                          style: GoogleFonts.inter(
                            color: const Color(0xFF8B949E),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: Color(0xFF8B949E)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Prominent Total Sum Card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0F2D24), Color(0xFF161B22)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFF00C896).withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TOTAL MAIN CATEGORY BUDGET',
                          style: GoogleFonts.inter(
                            color: const Color(0xFF00C896),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Auto-sums all sub-categories',
                          style: GoogleFonts.inter(
                            color: const Color(0xFF8B949E),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      'SAR ${_currencyFmt.format(_totalSum)}',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Scrollable Content
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: Color(0xFF00C896)),
                    )
                  : _subItems.isEmpty
                      ? SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Allocate Budget for ${widget.categoryName}:',
                                style: const TextStyle(color: Colors.white70, fontSize: 14),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _fallbackParentController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                style: const TextStyle(color: Colors.white, fontSize: 16),
                                decoration: InputDecoration(
                                  hintText: '0.00',
                                  prefixText: 'SAR ',
                                  prefixStyle: const TextStyle(
                                    color: Color(0xFF00C896),
                                    fontWeight: FontWeight.bold,
                                  ),
                                  filled: true,
                                  fillColor: const Color(0xFF0D1117),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(color: Color(0xFF30363D)),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(color: Color(0xFF00C896)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                          itemCount: _subItems.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (ctx, i) {
                            final item = _subItems[i];
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0D1117),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0xFF30363D)),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.nameEn,
                                          style: GoogleFonts.inter(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
                                          ),
                                        ),
                                        if (item.nameAr.isNotEmpty) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            item.nameAr,
                                            style: GoogleFonts.inter(
                                              color: const Color(0xFF8B949E),
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  SizedBox(
                                    width: 125,
                                    height: 44,
                                    child: TextField(
                                      controller: item.controller,
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      style: GoogleFonts.inter(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      textAlign: TextAlign.end,
                                      decoration: InputDecoration(
                                        hintText: '0.00',
                                        hintStyle: const TextStyle(color: Color(0xFF484F58), fontSize: 13),
                                        prefixText: 'SAR ',
                                        prefixStyle: const TextStyle(
                                          color: Color(0xFF00C896),
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        filled: true,
                                        fillColor: const Color(0xFF161B22),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(10),
                                          borderSide: const BorderSide(color: Color(0xFF30363D)),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(10),
                                          borderSide: const BorderSide(color: Color(0xFF30363D)),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(10),
                                          borderSide: const BorderSide(color: Color(0xFF00C896)),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
            ),

            // Action Buttons
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: const BoxDecoration(
                color: Color(0xFF161B22),
                border: Border(top: BorderSide(color: Color(0xFF30363D))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSaving ? null : () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: Color(0xFF30363D)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        'Cancel',
                        style: GoogleFonts.inter(color: Colors.white70, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _handleSave,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00C896),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                            )
                          : Text(
                              'Save SAR ${_currencyFmt.format(_totalSum)}',
                              style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
