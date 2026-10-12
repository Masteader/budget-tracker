import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/api_service.dart';

/// Interactive confirmation card embedded within chat bubbles that allows
/// the user to review and modify Merchant, Category, Sub-Category, Who Paid,
/// and For Whom (beneficiary, including children) before committing.
class PendingExpenseConfirmationCard extends StatefulWidget {
  final Map<String, dynamic> pendingData;
  final void Function(
    String confirmedMerchant,
    String confirmedCategoryCode,
    String? confirmedSubCategory,
    String confirmedPaidBy,
    String confirmedBeneficiary,
  ) onConfirm;
  final VoidCallback onCancel;

  const PendingExpenseConfirmationCard({
    super.key,
    required this.pendingData,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  State<PendingExpenseConfirmationCard> createState() => _PendingExpenseConfirmationCardState();
}

class _PendingExpenseConfirmationCardState extends State<PendingExpenseConfirmationCard> {
  late final TextEditingController _merchantController;
  late String _selectedCategoryCode;
  late String? _selectedSubCategory;
  late String _selectedPaidBy;
  late String _selectedBeneficiary;
  late List<Map<String, dynamic>> _availableSubCategories;
  bool _loadingSubs = false;

  static const List<Map<String, String>> _defaultCategories = [
    {'code': 'OPEX-DINING', 'label': 'Dining'},
    {'code': 'OPEX-GROCERY', 'label': 'Grocery'},
    {'code': 'OPEX-UTILITIES', 'label': 'Utilities & Rent'},
    {'code': 'OPEX-FUEL', 'label': 'Fuel & Transport'},
    {'code': 'OPEX-HEALTH', 'label': 'Healthcare'},
    {'code': 'OPEX-SHOPPING', 'label': 'Shopping'},
    {'code': 'OPEX-EDUCATION', 'label': 'Education'},
    {'code': 'OPEX-ENTERTAINMENT', 'label': 'Entertainment'},
    {'code': 'OPEX-MISC', 'label': 'General / Misc'},
  ];

  @override
  void initState() {
    super.initState();
    final defaultMerchant = widget.pendingData['merchant'] as String? ?? 'Store Name';
    _merchantController = TextEditingController(text: defaultMerchant);

    var rawCat = (widget.pendingData['category_code'] as String? ?? 'OPEX-MISC').toUpperCase();
    if (rawCat == 'OPEX-GROCERIES') rawCat = 'OPEX-GROCERY';
    if (rawCat == 'OPEX-TRANSPORT') rawCat = 'OPEX-FUEL';
    if (rawCat == 'OPEX-HEALTHCARE') rawCat = 'OPEX-HEALTH';
    _selectedCategoryCode = rawCat;

    _selectedSubCategory = widget.pendingData['sub_category'] as String?;

    // Attribution: Who Paid (me | partner)
    _selectedPaidBy = (widget.pendingData['paid_by'] as String? ?? 'me').toLowerCase();
    if (!['me', 'partner'].contains(_selectedPaidBy)) {
      _selectedPaidBy = 'me';
    }

    // Attribution: For Whom (both | me | partner | child name)
    _selectedBeneficiary = (widget.pendingData['beneficiary'] as String? ?? 'both').toLowerCase();

    // Available subcategories from backend preview payload
    final rawSubs = widget.pendingData['available_sub_categories'] as List?;
    if (rawSubs != null && rawSubs.isNotEmpty) {
      _availableSubCategories = rawSubs.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (_selectedSubCategory == null && _availableSubCategories.isNotEmpty) {
        _selectedSubCategory = _availableSubCategories.first['sub_code'] as String?;
      }
    } else {
      _availableSubCategories = [];
      _loadSubCategoriesForCategory(_selectedCategoryCode);
    }
  }

  Future<void> _loadSubCategoriesForCategory(String catCode) async {
    setState(() => _loadingSubs = true);
    try {
      final subs = await ApiService.instance.getSubCategories(catCode);
      if (mounted) {
        setState(() {
          _availableSubCategories = subs;
          if (_selectedSubCategory == null ||
              !_availableSubCategories.any((s) => s['sub_code'] == _selectedSubCategory)) {
            _selectedSubCategory = _availableSubCategories.isNotEmpty
                ? _availableSubCategories.first['sub_code'] as String?
                : null;
          }
          _loadingSubs = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingSubs = false);
    }
  }

  @override
  void dispose() {
    _merchantController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final amount = (widget.pendingData['amount'] as num?)?.toDouble() ?? 0.0;
    final rawItems = widget.pendingData['items'] as List?;
    final items = rawItems != null
        ? rawItems.map((e) => Map<String, dynamic>.from(e as Map)).toList()
        : <Map<String, dynamic>>[];

    final rawDependents = widget.pendingData['dependents'] as List?;
    final dependents = rawDependents != null
        ? rawDependents.map((e) => e.toString()).toList()
        : <String>[];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF00C896).withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Title & Total
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.edit_note_rounded, color: Color(0xFF00C896), size: 18),
                  const SizedBox(width: 6),
                  Text(
                    'Confirm Expense Details',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF00C896).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'SAR ${amount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Color(0xFF00C896),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Merchant name input
          TextField(
            controller: _merchantController,
            style: GoogleFonts.outfit(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              labelText: 'Merchant / Store',
              labelStyle: const TextStyle(color: Color(0xFF8B949E), fontSize: 12),
              isDense: true,
              filled: true,
              fillColor: const Color(0xFF0D1117),
              prefixIcon: const Icon(Icons.storefront_rounded, size: 16, color: Color(0xFF00C896)),
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
          const SizedBox(height: 10),

          // Category & Subcategory Selectors
          Row(
            children: [
              // Category Dropdown
              Expanded(
                flex: 5,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D1117),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF30363D)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _defaultCategories.any((c) => c['code'] == _selectedCategoryCode)
                          ? _selectedCategoryCode
                          : _defaultCategories.first['code'],
                      isExpanded: true,
                      dropdownColor: const Color(0xFF161B22),
                      style: GoogleFonts.outfit(color: Colors.white, fontSize: 12),
                      items: _defaultCategories.map((c) {
                        return DropdownMenuItem(
                          value: c['code'],
                          child: Text(c['label'] ?? c['code']!),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _selectedCategoryCode = val;
                            _selectedSubCategory = null;
                          });
                          _loadSubCategoriesForCategory(val);
                        }
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Sub-Category Dropdown
              Expanded(
                flex: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D1117),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF30363D)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: _loadingSubs
                        ? const SizedBox(
                            height: 40,
                            child: Center(
                              child: SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00C896)),
                              ),
                            ),
                          )
                        : DropdownButton<String>(
                            value: _availableSubCategories.any((s) => s['sub_code'] == _selectedSubCategory)
                                ? _selectedSubCategory
                                : (_availableSubCategories.isNotEmpty
                                    ? _availableSubCategories.first['sub_code'] as String?
                                    : null),
                            isExpanded: true,
                            hint: Text(
                              _availableSubCategories.isEmpty ? 'General' : 'Sub-Category',
                              style: const TextStyle(color: Color(0xFF6E7681), fontSize: 11),
                            ),
                            dropdownColor: const Color(0xFF161B22),
                            style: GoogleFonts.outfit(color: Colors.white, fontSize: 12),
                            items: _availableSubCategories.map((s) {
                              final subCode = s['sub_code'] as String? ?? '';
                              final nameEn = s['name_en'] as String? ?? subCode;
                              return DropdownMenuItem<String>(
                                value: subCode,
                                child: Text(
                                  nameEn,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              );
                            }).toList(),
                            onChanged: (val) {
                              setState(() => _selectedSubCategory = val);
                            },
                          ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── WHO PAID? ──
          Text(
            'WHO PAID?',
            style: GoogleFonts.outfit(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF8B949E),
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              _buildChoiceChip(
                label: 'Me',
                isSelected: _selectedPaidBy == 'me',
                onSelected: () => setState(() => _selectedPaidBy = 'me'),
              ),
              const SizedBox(width: 8),
              _buildChoiceChip(
                label: 'Partner',
                isSelected: _selectedPaidBy == 'partner',
                onSelected: () => setState(() => _selectedPaidBy = 'partner'),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // ── FOR WHOM? ──
          Text(
            'FOR WHOM?',
            style: GoogleFonts.outfit(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF8B949E),
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _buildChoiceChip(
                label: 'Both / Family',
                isSelected: _selectedBeneficiary == 'both',
                onSelected: () => setState(() => _selectedBeneficiary = 'both'),
              ),
              _buildChoiceChip(
                label: 'Me',
                isSelected: _selectedBeneficiary == 'me',
                onSelected: () => setState(() => _selectedBeneficiary = 'me'),
              ),
              _buildChoiceChip(
                label: 'Partner',
                isSelected: _selectedBeneficiary == 'partner',
                onSelected: () => setState(() => _selectedBeneficiary = 'partner'),
              ),
              ...dependents.map((depName) {
                return _buildChoiceChip(
                  label: depName,
                  icon: Icons.child_care_rounded,
                  isSelected: _selectedBeneficiary == depName.toLowerCase(),
                  onSelected: () => setState(() => _selectedBeneficiary = depName.toLowerCase()),
                );
              }),
            ],
          ),
          const SizedBox(height: 12),

          // Items Preview (with subcategory badge)
          if (items.isNotEmpty) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF0D1117),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF21262D)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${items.length} item(s) found:',
                    style: const TextStyle(color: Color(0xFF8B949E), fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  ...items.map((it) {
                    final itemSub = it['sub_category'] as String?;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Text(
                                  '${it['quantity']}x ${it['name']}',
                                  style: const TextStyle(color: Colors.white, fontSize: 12),
                                ),
                                if (itemSub != null && itemSub.isNotEmpty) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF58A6FF).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      itemSub,
                                      style: const TextStyle(color: Color(0xFF58A6FF), fontSize: 9),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Text(
                            'SAR ${(it['price'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
                            style: const TextStyle(color: Color(0xFF00C896), fontSize: 11),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],

          // Action buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00C896),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.check_circle_rounded, size: 16),
                  label: const Text(
                    'Confirm & Add Expense',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  onPressed: () {
                    final store = _merchantController.text.trim();
                    final resolvedSub = _selectedSubCategory ??
                        (_availableSubCategories.isNotEmpty
                            ? _availableSubCategories.first['sub_code'] as String?
                            : null);
                    widget.onConfirm(
                      store.isNotEmpty ? store : 'Store Name',
                      _selectedCategoryCode,
                      resolvedSub,
                      _selectedPaidBy,
                      _selectedBeneficiary,
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: widget.onCancel,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF8B949E),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
                child: const Text('Cancel', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChoiceChip({
    required String label,
    required bool isSelected,
    required VoidCallback onSelected,
    IconData? icon,
  }) {
    return GestureDetector(
      onTap: onSelected,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF00C896).withValues(alpha: 0.15) : const Color(0xFF0D1117),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFF00C896) : const Color(0xFF30363D),
            width: isSelected ? 1.2 : 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: isSelected ? const Color(0xFF00C896) : const Color(0xFF8B949E)),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? const Color(0xFF00C896) : const Color(0xFFC9D1D9),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
