import 'package:flutter/material.dart';
import '../theme/app_themes.dart';
import '../l10n/app_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../main.dart';
import '../models/models.dart';
import '../providers/budget_provider.dart';
import '../providers/recurring_bills_provider.dart';
import '../services/api_service.dart';
import 'app_snackbar.dart';
import 'dispose_on_unmount.dart';
import '../models/money.dart';

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
    'OPEX-EDUCATION': [
      {'sub_code': 'tuition_fees', 'name_en': 'Tuition Fees', 'name_ar': 'رسوم دراسية'},
      {'sub_code': 'books_supplies', 'name_en': 'Books & Supplies', 'name_ar': 'كتب ومستلزمات'},
    ],
  };

  @override
  State<SubBudgetAllocationDialog> createState() =>
      _SubBudgetAllocationDialogState();
}

class _SubCategoryItemDef {
  final String subCode;
  String nameEn;
  String nameAr;
  final TextEditingController controller;

  _SubCategoryItemDef({
    required this.subCode,
    required this.nameEn,
    required this.nameAr,
    required this.controller,
  });
}

class _SubBudgetAllocationDialogState extends State<SubBudgetAllocationDialog> {
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
        final val = parseMoneyInput(item.controller.text.trim()) ?? 0.0;
        sum += val;
      }
    } else {
      sum = parseMoneyInput(_fallbackParentController.text.trim()) ?? 0.0;
    }
    setState(() {
      _totalSum = sum;
    });
  }

  Future<void> _loadSubCategories() async {
    try {
      // 1. Fetch sub-categories from backend API (uses service-role key, bypassing RLS)
      final apiSubs = await ApiService.instance.getSubCategories(widget.categoryCode);

      List<Map<String, String>> rawDefs = [];
      if (apiSubs.isNotEmpty) {
        rawDefs = apiSubs.map((row) => {
          'sub_code': row['sub_code'] as String,
          'name_en': row['name_en'] as String? ?? (row['sub_code'] as String),
          'name_ar': row['name_ar'] as String? ?? '',
        }).toList();
      } else {
        // Fallback to Supabase direct query or local default catalog
        try {
          final res = await supabase
              .from('cost_control_sub_categories')
              .select('sub_code, name_en, name_ar')
              .eq('parent_code', widget.categoryCode);
          if (res.isNotEmpty) {
            rawDefs = res.map((row) => {
              'sub_code': row['sub_code'] as String,
              'name_en': row['name_en'] as String? ?? (row['sub_code'] as String),
              'name_ar': row['name_ar'] as String? ?? '',
            }).toList();
          }
        } catch (_) {}

        if (rawDefs.isEmpty) {
          rawDefs = List<Map<String, String>>.from(
            SubBudgetAllocationDialog.kDefaultSubCategoriesCatalog[widget.categoryCode] ?? [],
          );
        }
      }

      // 2. Fetch the latest budget row for this household & cycle to get any saved subAllocations
      Map<String, double> existingAllocs = Map<String, double>.from(
        widget.existingBudget?.subAllocations ?? {},
      );
      try {
        final cycleKey = widget.cycleKey;
        var query = supabase
            .from('budgets')
            .select('sub_allocations')
            .eq('household_id', widget.householdId)
            .eq('category_code', widget.categoryCode);
        if (cycleKey != null && cycleKey.isNotEmpty) {
          query = query.eq('cycle_key', cycleKey);
        }
        final bData = await query.maybeSingle();
        if (bData != null && bData['sub_allocations'] is Map) {
          final dbAllocs = (bData['sub_allocations'] as Map<String, dynamic>).map(
            (k, v) => MapEntry(k, (v as num).toDouble()),
          );
          existingAllocs = {...existingAllocs, ...dbAllocs};
        }
      } catch (_) {}

      // 3. Ensure any sub-category present in existingAllocs is included in rawDefs
      for (final entry in existingAllocs.entries) {
        if (!rawDefs.any((d) => d['sub_code'] == entry.key)) {
          final cleanName = entry.key
              .replaceAll('sub-', '')
              .replaceAll('_', ' ')
              .replaceAll('-', ' ')
              .trim();
          final formattedName = cleanName
              .split(' ')
              .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
              .join(' ');
          rawDefs.add({
            'sub_code': entry.key,
            'name_en': formattedName,
            'name_ar': '',
          });
        }
      }

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

      _replaceSubItems(list);
    } catch (e) {
      final defaultList = SubBudgetAllocationDialog.kDefaultSubCategoriesCatalog[widget.categoryCode] ?? [];
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

      _replaceSubItems(list);
    }
  }

  /// Swaps in a freshly loaded list (UI-20). The replaced controllers are
  /// disposed after the next frame, once their TextFields use the new ones;
  /// if the dialog is already gone, the new controllers are disposed instead.
  void _replaceSubItems(List<_SubCategoryItemDef> list) {
    if (!mounted) {
      for (final item in list) {
        item.controller.dispose();
      }
      return;
    }
    final replaced = List<_SubCategoryItemDef>.of(_subItems);
    setState(() {
      _subItems
        ..clear()
        ..addAll(list);
      _isLoading = false;
    });
    _recomputeTotal();
    if (replaced.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final item in replaced) {
        item.controller.removeListener(_recomputeTotal);
        item.controller.dispose();
      }
    });
  }

  Future<void> _promptAddSubCategory() async {
    final nameCtrl = TextEditingController();
    final amountCtrl = TextEditingController(text: '100');

    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => DisposeOnUnmount(
        disposables: [nameCtrl, amountCtrl],
        child: AlertDialog(
        backgroundColor: context.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          context.trArgs('sba_add_sub_for', {'category': widget.categoryName}),
          style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              style: TextStyle(color: context.textPrimary),
              decoration: InputDecoration(
                labelText: context.tr('sub_category_name'),
                hintText: context.tr('sba_name_hint'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(color: context.textPrimary),
              decoration: InputDecoration(
                labelText: context.tr('initial_allocation'),
                prefixText: '${context.tr('sar')} ',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('cancel'), style: TextStyle(color: context.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: context.isDark ? const Color(0xFF5E1327) : const Color(0xFF4A0E1E),
              foregroundColor: context.isDark ? const Color(0xFFF0A3BC) : Colors.white,
            ),
            child: Text(context.tr('add'), style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      ),
    );

    // Read synchronously after the pop; the controllers are disposed only
    // when the dialog's exit animation has finished.
    if (res != true) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return;
    final amount = parseMoneyInput(amountCtrl.text) ?? 0.0;
    final slug = name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '-').toLowerCase();
    final subCode = 'sub-$slug';

    // Persist to cost_control_sub_categories via ApiService
    try {
      await ApiService.instance.addSubCategory(
        householdId: widget.householdId,
        parentCode: widget.categoryCode,
        nameEn: name,
        allocatedAmount: amount,
        subCode: subCode,
        cycleKey: widget.cycleKey,
      );
    } catch (_) {}

    final ctrl = TextEditingController(text: amount > 0 ? amount.toStringAsFixed(2) : '');
    ctrl.addListener(_recomputeTotal);

    setState(() {
      _subItems.add(_SubCategoryItemDef(
        subCode: subCode,
        nameEn: name,
        nameAr: name,
        controller: ctrl,
      ));
    });
    _recomputeTotal();
    widget.onSaved?.call();
  }

  Future<void> _promptRenameSubCategory(_SubCategoryItemDef item) async {
    final nameCtrl = TextEditingController(text: item.nameEn);

    final res = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => DisposeOnUnmount(
        disposables: [nameCtrl],
        child: AlertDialog(
        backgroundColor: context.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          context.tr('rename_sub_category'),
          style: GoogleFonts.inter(color: context.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.trArgs('sba_code', {'code': item.subCode}),
              style: GoogleFonts.inter(color: context.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameCtrl,
              autofocus: true,
              style: TextStyle(color: context.textPrimary),
              decoration: InputDecoration(
                labelText: context.tr('sub_category_name'),
                hintText: context.tr('sba_enter_new_name'),
                labelStyle: TextStyle(color: context.textSecondary),
                filled: true,
                fillColor: context.inputBg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: context.borderColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: context.isDark ? const Color(0xFFF0A3BC) : const Color(0xFF4A0E1E),
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('cancel'), style: TextStyle(color: context.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: context.isDark ? const Color(0xFF5E1327) : const Color(0xFF4A0E1E),
              foregroundColor: context.isDark ? const Color(0xFFF0A3BC) : Colors.white,
            ),
            child: Text(context.tr('sba_rename'), style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      ),
    );

    if (res != true) return;
    final newName = nameCtrl.text.trim();
    if (newName.isEmpty || newName == item.nameEn) return;

    try {
      final resp = await ApiService.instance.renameSubCategory(
        parentCode: widget.categoryCode,
        subCode: item.subCode,
        nameEn: newName,
      );

      if (!mounted) return;
      if (resp['status'] == 'success') {
        setState(() {
          item.nameEn = newName;
        });
        widget.onSaved?.call();
        if (mounted) {
          AppSnackBar.showSuccess(
            context,
            context.trArgs('sba_renamed_to', {'name': newName}),
            title: context.tr('sba_renamed'),
            duration: const Duration(seconds: 2),
          );
        }
      } else {
        if (mounted) {
          AppSnackBar.showError(
            context,
            context.trArgs('sba_rename_failed_msg', {'error': resp['message']}),
            title: context.tr('sba_rename_failed'),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.showError(
          context,
          context.trArgs('sba_rename_failed_msg', {'error': e}),
          title: context.tr('sba_rename_error'),
        );
      }
    }
  }

  Future<void> _promptRemoveSubCategory(_SubCategoryItemDef item) async {
    final confirm = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          context.tr('sba_remove_title'),
          style: GoogleFonts.inter(color: context.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: Text(
          context.trArgs('sba_remove_confirm', {'name': context.trSub(item.subCode, nameAr: item.nameAr, nameEn: item.nameEn), 'category': widget.categoryName}),
          style: GoogleFonts.inter(color: context.textSecondary, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('cancel'), style: TextStyle(color: context.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: Text(context.tr('set_remove'), style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      final resp = await ApiService.instance.removeSubCategory(
        householdId: widget.householdId,
        parentCode: widget.categoryCode,
        subCode: item.subCode,
        cycleKey: widget.cycleKey,
      );

      if (!mounted) return;
      if (resp['status'] == 'success') {
        setState(() {
          item.controller.removeListener(_recomputeTotal);
          item.controller.dispose();
          _subItems.remove(item);
        });
        _recomputeTotal();
        widget.onSaved?.call();
        if (mounted) {
          AppSnackBar.showDelete(
            context,
            context.trArgs('sba_removed_from_budget', {'name': context.trSub(item.subCode, nameAr: item.nameAr, nameEn: item.nameEn)}),
            title: context.tr('sba_removed_title'),
            duration: const Duration(seconds: 3),
          );
        }
      } else {
        if (mounted) {
          AppSnackBar.showError(
            context,
            context.trArgs('sba_remove_failed_msg', {'error': resp['message']}),
            title: context.tr('sba_remove_failed'),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.showError(
          context,
          context.trArgs('sba_remove_failed_msg', {'error': e}),
          title: context.tr('sba_remove_error'),
        );
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
          final val = parseMoneyInput(item.controller.text.trim()) ?? 0.0;
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
        final amount = parseMoneyInput(_fallbackParentController.text.trim()) ?? 0.0;
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
        try {
          context.read<BudgetProvider>().refresh();
          context.read<RecurringBillsProvider>().fetchBills();
        } catch (_) {}
        widget.onSaved?.call();
        Navigator.pop(context, true);
        AppSnackBar.showSuccess(
          context,
          context.trArgs('sba_budget_saved_msg', {'category': widget.categoryName, 'amount': context.sar(_totalSum)}),
          title: context.tr('sba_budget_saved'),
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
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
                color: context.borderColor,
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
                          context.trCat(widget.categoryCode),
                          style: GoogleFonts.inter(
                            color: context.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${context.trCat(widget.categoryCode)} • ${widget.cycleKey != null ? context.cycleLabel(widget.cycleKey!) : context.tr('sba_current')}',
                          style: GoogleFonts.inter(
                            color: context.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: context.tr('close'),
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close_rounded, color: context.textSecondary),
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
                  gradient: LinearGradient(
                    colors: context.isDark
                        ? const [Color(0xFF380C18), Color(0xFF1E0B12)]
                        : const [Color(0xFFFDF2F4), Color(0xFFF8F3F5)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: (context.isDark ? const Color(0xFFF0A3BC) : const Color(0xFF4A0E1E)).withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.tr('total_main_category_budget'),
                            style: GoogleFonts.inter(
                              color: context.isDark ? const Color(0xFFF0A3BC) : const Color(0xFF4A0E1E),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            context.tr('auto_sums_sub_categories'),
                            style: GoogleFonts.inter(
                              color: context.textSecondary,
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
                        alignment: AlignmentDirectional.centerEnd,
                        child: Text(
                          context.sar(_totalSum),
                          style: GoogleFonts.inter(
                            color: context.textPrimary,
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
                  ? Center(
                      child: CircularProgressIndicator(
                        color: context.isDark ? const Color(0xFFF0A3BC) : const Color(0xFF4A0E1E),
                      ),
                    )
                  : _subItems.isEmpty
                      ? SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                context.trArgs('sba_allocate_for', {'category': widget.categoryName}),
                                style: TextStyle(color: context.textSecondary, fontSize: 14),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _fallbackParentController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                style: TextStyle(color: context.textPrimary, fontSize: 16),
                                decoration: InputDecoration(
                                  hintText: '0.00',
                                  prefixText: '${context.tr('sar')} ',
                                  prefixStyle: TextStyle(
                                    color: context.successText,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  filled: true,
                                  fillColor: context.inputBg,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: context.borderColor),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: context.isDark ? const Color(0xFFF0A3BC) : const Color(0xFF4A0E1E),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                          itemCount: _subItems.length + 1,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (ctx, i) {
                            if (i == _subItems.length) {
                              return OutlinedButton.icon(
                                onPressed: _promptAddSubCategory,
                                icon: Icon(
                                  Icons.add_rounded,
                                  size: 18,
                                  color: context.isDark ? const Color(0xFFF0A3BC) : const Color(0xFF4A0E1E),
                                ),
                                label: Text(
                                  context.tr('add_custom_sub_category'),
                                  style: TextStyle(
                                    color: context.isDark ? const Color(0xFFF0A3BC) : const Color(0xFF4A0E1E),
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  side: BorderSide(color: context.borderColor),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              );
                            }
                            final item = _subItems[i];
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: context.subtleCardBg,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: context.borderColor),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            context.trSub(item.subCode, nameAr: item.nameAr, nameEn: item.nameEn),
                                            style: GoogleFonts.inter(
                                              color: context.textPrimary,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: () => _promptRenameSubCategory(item),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 4.0),
                                            child: Icon(
                                              Icons.edit_outlined,
                                              size: 15,
                                              color: context.textSecondary,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 2),
                                        GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: () => _promptRemoveSubCategory(item),
                                          child: const Padding(
                                            padding: EdgeInsets.symmetric(horizontal: 6.0, vertical: 4.0),
                                            child: Icon(
                                              Icons.delete_outline_rounded,
                                              size: 16,
                                              color: Color(0xFFF85149),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 115,
                                    height: 44,
                                    child: TextField(
                                      controller: item.controller,
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      style: GoogleFonts.inter(
                                        color: context.textPrimary,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      textAlign: TextAlign.end,
                                      decoration: InputDecoration(
                                        hintText: '0.00',
                                        hintStyle: const TextStyle(color: Color(0xFF484F58), fontSize: 13),
                                        prefixText: '${context.tr('sar')} ',
                                        prefixStyle: TextStyle(
                                          color: context.successText,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        filled: true,
                                        fillColor: context.inputBg,
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(10),
                                          borderSide: BorderSide(color: context.borderColor),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(10),
                                          borderSide: BorderSide(color: context.borderColor),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(10),
                                          borderSide: BorderSide(
                                            color: context.isDark ? const Color(0xFFF0A3BC) : const Color(0xFF4A0E1E),
                                          ),
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
              decoration: BoxDecoration(
                color: context.cardBg,
                border: Border(top: BorderSide(color: context.borderColor)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSaving ? null : () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(color: context.borderColor),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        context.tr('cancel'),
                        style: GoogleFonts.inter(color: context.textSecondary, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _handleSave,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: context.isDark ? const Color(0xFF5E1327) : const Color(0xFF4A0E1E),
                        foregroundColor: context.isDark ? const Color(0xFFF0A3BC) : Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: _isSaving
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: context.isDark ? const Color(0xFFF0A3BC) : Colors.white,
                              ),
                            )
                          : FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                '${context.tr('save')} ${context.sar(_totalSum)}',
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
