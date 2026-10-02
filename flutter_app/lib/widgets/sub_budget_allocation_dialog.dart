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

  static const Map<String, List<Map<String, String>>> kDefaultSubCategoriesCatalog = {
  'OPEX-UTILITIES': [
    {'sub_code': 'housing_rent', 'name_en': 'Housing Rent', 'name_ar': 'إيجار السكن'},
    {'sub_code': 'electricity_sec', 'name_en': 'Electricity (SEC)', 'name_ar': 'فاتورة الكهرباء'},
    {'sub_code': 'fiber_internet', 'name_en': 'Home Fiber Internet', 'name_ar': 'الإنترنت المنزلي'},
    {'sub_code': 'mobile_sims', 'name_en': 'Mobile SIMs & Data', 'name_ar': 'باقات الجوال والاتصالات'},
    {'sub_code': 'water_municipal', 'name_en': 'Water & Municipal Bills', 'name_ar': 'المياه والخدمات البلدية'},
  ],
  'OPEX-DINING': [
    {'sub_code': 'restaurants_dinners', 'name_en': 'Restaurants & Meals', 'name_ar': 'المطاعم والوجبات'},
    {'sub_code': 'coffee_bakeries', 'name_en': 'Coffee & Bakeries', 'name_ar': 'القهوة والمخابز'},
    {'sub_code': 'delivery_apps', 'name_en': 'Delivery Apps', 'name_ar': 'تطبيقات التوصيل'},
  ],
  'OPEX-GROCERY': [
    {'sub_code': 'meat', 'name_en': 'Meat & Poultry', 'name_ar': 'اللحوم والدواجن'},
    {'sub_code': 'vegetables_fruit', 'name_en': 'Fresh Produce & Fruits', 'name_ar': 'الخضار والفواكه'},
    {'sub_code': 'dairy_eggs', 'name_en': 'Dairy & Eggs', 'name_ar': 'الألبان والبيض'},
    {'sub_code': 'snacks_chips', 'name_en': 'Snacks, Chips & Sweets', 'name_ar': 'الشيبس والسناكات والحلويات'},
    {'sub_code': 'beverages', 'name_en': 'Beverages & Water', 'name_ar': 'المشروبات والمياه'},
    {'sub_code': 'pantry_staples', 'name_en': 'Pantry & Staples', 'name_ar': 'التموين والمؤن'},
    {'sub_code': 'cleaning_household', 'name_en': 'Cleaning Supplies', 'name_ar': 'المنظفات ومستلزمات المنزل'},
  ],
  'OPEX-FUEL': [
    {'sub_code': 'gas_fuel', 'name_en': 'Gasoline & Fuel', 'name_ar': 'بنزين ووقود'},
    {'sub_code': 'car_maintenance', 'name_en': 'Car Maintenance & Oil', 'name_ar': 'صيانة وتغيير الزيت'},
    {'sub_code': 'ride_hailing', 'name_en': 'Ride Hailing (Uber/Bolt)', 'name_ar': 'تطبيقات النقل والتوصيل'},
  ],
  'OPEX-HEALTH': [
    {'sub_code': 'prescriptions_meds', 'name_en': 'Prescriptions & Medicines', 'name_ar': 'الأدوية والوصفات'},
    {'sub_code': 'clinics_dental', 'name_en': 'Clinics & Dental', 'name_ar': 'العيادات والأسنان'},
  ],
  'OPEX-SHOPPING': [
    {'sub_code': 'clothing_fashion', 'name_en': 'Clothing & Fashion', 'name_ar': 'الملابس والأزياء'},
    {'sub_code': 'electronics_gadgets', 'name_en': 'Electronics & Gadgets', 'name_ar': 'الإلكترونيات والتقنية'},
    {'sub_code': 'home_furniture', 'name_en': 'Home Goods & Furniture', 'name_ar': 'الأثاث والمفروشات'},
  ],
  'OPEX-ENTERTAINMENT': [
    {'sub_code': 'cinema_outings', 'name_en': 'Cinema & Outings', 'name_ar': 'سينما ونزهات'},
    {'sub_code': 'gaming_subscriptions', 'name_en': 'Gaming & Subscriptions', 'name_ar': 'ألعاب واشتراكات'},
    {'sub_code': 'events_activities', 'name_en': 'Events & Activities', 'name_ar': 'فعاليات وأنشطة'},
  ],
  'CAPEX-EDUCATION': [
    {'sub_code': 'tuition_fees', 'name_en': 'Tuition Fees', 'name_ar': 'رسوم دراسية'},
    {'sub_code': 'books_supplies', 'name_en': 'Books & Supplies', 'name_ar': 'كتب ومستلزمات'},
  ],
};

  Future<void> _loadSubCategories() async {
    try {
      final res = await supabase
          .from('cost_control_sub_categories')
          .select('sub_code, name_en, name_ar')
          .eq('parent_code', widget.categoryCode)
          .order('id');

      List<Map<String, String>> rawDefs = [];
      if (res is List && res.isNotEmpty) {
        rawDefs = res.map((row) => {
          'sub_code': row['sub_code'] as String,
          'name_en': row['name_en'] as String? ?? (row['sub_code'] as String),
          'name_ar': row['name_ar'] as String? ?? '',
        }).toList();
      } else {
        rawDefs = kDefaultSubCategoriesCatalog[widget.categoryCode] ?? [];
      }

      final existingAllocs = widget.existingBudget?.subAllocations ?? {};
      final list = rawDefs.map((row) {
        final code = row['sub_code']!;
        final nameEn = row['name_en']!;
        final nameAr = row['name_ar'] ?? '';
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
      final defaultList = kDefaultSubCategoriesCatalog[widget.categoryCode] ?? [];
      final existingAllocs = widget.existingBudget?.subAllocations ?? {};
      final list = defaultList.map((row) {
        final code = row['sub_code']!;
        final nameEn = row['name_en']!;
        final nameAr = row['name_ar'] ?? '';
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
          final existingCheck = await supabase
              .from('budgets')
              .select('id')
              .eq('household_id', widget.householdId)
              .eq('category_code', widget.categoryCode)
              .maybeSingle();

          if (existingCheck != null) {
            await supabase.from('budgets').update({
              'allocated_amount': amount,
              'cycle_key': cycleKey,
              'is_active': true,
            }).eq('id', existingCheck['id']);
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
                  children: [
                    Expanded(
                      child: Column(
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
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          'SAR ${_currencyFmt.format(_totalSum)}',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
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
                          : FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                'Save SAR ${_currencyFmt.format(_totalSum)}',
                                style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
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
