import 'package:flutter/material.dart';
import '../../theme/app_themes.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/api_service.dart';
import '../../l10n/app_localizations.dart';
import '../../models/nafaqah.dart';
import '../../providers/household_role_provider.dart';
import '../nafaqah/nafaqah_review_section.dart';
import '../../models/category_catalog.dart';
import '../../models/money.dart';
import '../transactions/expense_date_chips.dart';

/// What the user corrected in the confirmation card (UX-12): the amount when
/// it differs from the preview (else null) and the date when it is not today
/// (else null: the server books it now).
class PendingExpenseEdits {
  final double? amount;
  final DateTime? occurredAt;
  final String? accountId;
  const PendingExpenseEdits({this.amount, this.occurredAt, this.accountId});
}

/// Confirmed values of a chat expense. [confirmedNafaqahClass] is set in
/// family mode only: 'wife_reimbursable', 'wife_personal' or 'none' (husband
/// paid), always derived from the confirmed payer / beneficiary so it never
/// contradicts them. [confirmedNafaqahSpouseId] names the wife when a husband
/// with several wives records what one of them paid.
typedef PendingExpenseConfirmCallback = void Function(
  String confirmedMerchant,
  String confirmedCategoryCode,
  String? confirmedSubCategory,
  String confirmedPaidBy,
  String confirmedBeneficiary,
  String? confirmedNafaqahClass,
  String? confirmedNafaqahSpouseId,
  PendingExpenseEdits edits,
);

/// Interactive confirmation card embedded within chat bubbles that allows
/// the user to review and modify Merchant, Category, Sub-Category, Who Paid,
/// and For Whom (beneficiary, including children) before committing.
class PendingExpenseConfirmationCard extends StatefulWidget {
  final Map<String, dynamic> pendingData;
  final PendingExpenseConfirmCallback onConfirm;
  final VoidCallback onCancel;

  /// The recorder is a household admin (defaults to the [HouseholdRoleProvider]).
  final bool? isAdmin;

  const PendingExpenseConfirmationCard({
    super.key,
    required this.pendingData,
    required this.onConfirm,
    required this.onCancel,
    this.isAdmin,
  });

  @override
  State<PendingExpenseConfirmationCard> createState() => _PendingExpenseConfirmationCardState();
}

class _PendingExpenseConfirmationCardState extends State<PendingExpenseConfirmationCard> {
  late final TextEditingController _merchantController;
  late final TextEditingController _amountController;
  late final double _previewAmount;
  bool _amountInvalid = false;
  DateTime _occurredAt = DateTime.now();
  late String _selectedCategoryCode;
  late String? _selectedSubCategory;
  late String _selectedPaidBy;
  late String _selectedBeneficiary;
  late List<Map<String, dynamic>> _availableSubCategories;
  bool _loadingSubs = false;
  String? _nafaqahChoice;
  late final NafaqahPreview _nafaqahPreview;
  String? _nafaqahWifeId;
  bool _showWifeRequired = false;

  /// 'wife' | 'husband' when the recorder is a spouse in a family household.
  String? get _spouseRole {
    if (widget.pendingData['household_mode'] != 'family_nafaqah') return null;
    final role = widget.pendingData['recorder_role'] as String?;
    return (role == 'wife' || role == 'husband') ? role : null;
  }

  bool get _isFamily =>
      widget.pendingData['household_mode'] == 'family_nafaqah' ||
      widget.pendingData['is_family'] == true;

  /// Recomputes the suggestion after the payer / beneficiary chips change.
  void _syncNafaqah() {
    // An admin who is neither spouse classifies directly, not from the chips.
    if (_spouseRole == null) return;
    _nafaqahChoice = classifyNafaqah(_spouseRole, _selectedPaidBy, _selectedBeneficiary);
  }

  bool get _isAdminClassifier => _nafaqahPreview.isAdminClassifier;

  void _setPaidBy(String v) => setState(() {
        _selectedPaidBy = v;
        _syncNafaqah();
      });

  void _setBeneficiary(String v) => setState(() {
        _selectedBeneficiary = v;
        _syncNafaqah();
      });

  void _chooseNafaqah(String? cls) {
    setState(() => _applyNafaqahChoice(cls));
  }

  /// Family (UX-03): the Nafaqah choice is the one question. For a spouse it
  /// sets who paid and for whom, so the confirmed payer / beneficiary always
  /// classify to the chosen class (the server contract is unchanged).
  void _applyNafaqahChoice(String? cls) {
    _nafaqahChoice = cls;
    if (_spouseRole == null) return;
    final wifeSide = _spouseRole == 'wife' ? 'me' : 'partner';
    final husbandSide = _spouseRole == 'wife' ? 'partner' : 'me';
    if (cls == kWifePersonal) {
      _selectedPaidBy = wifeSide;
      _selectedBeneficiary = wifeSide;
    } else if (cls == kWifeReimbursable) {
      _selectedPaidBy = wifeSide;
      if (_selectedBeneficiary == wifeSide) _selectedBeneficiary = 'both';
    } else {
      // The husband paid: an ordinary household expense (also when it was for his wife).
      _selectedPaidBy = husbandSide;
    }
  }

  /// A child the family expense was for (optional), or null.
  String? _childBeneficiary(List<String> dependents) {
    for (final d in dependents) {
      if (d.toLowerCase() == _selectedBeneficiary) return d;
    }
    return null;
  }


  @override
  void initState() {
    super.initState();
    // Empty (with a localized hint) instead of an English placeholder value.
    final defaultMerchant = widget.pendingData['merchant'] as String? ?? '';
    _merchantController = TextEditingController(text: defaultMerchant);
    _previewAmount = (widget.pendingData['amount'] as num?)?.toDouble() ?? 0.0;
    _amountController = TextEditingController(text: _previewAmount > 0 ? _previewAmount.toStringAsFixed(2) : '');

    _selectedCategoryCode = CategoryCatalog.normalize(widget.pendingData['category_code'] as String?);

    _selectedSubCategory = widget.pendingData['sub_category'] as String?;

    // Attribution: Who Paid (me | partner)
    _selectedPaidBy = (widget.pendingData['paid_by'] as String? ?? 'me').toLowerCase();
    if (!['me', 'partner'].contains(_selectedPaidBy)) {
      _selectedPaidBy = 'me';
    }

    // Attribution: For Whom (both | me | partner | child name)
    _selectedBeneficiary = (widget.pendingData['beneficiary'] as String? ?? 'both').toLowerCase();

    // Family (Nafaqah): the server's suggestion, else derived from the chips.
    // Only the wife, the provider (husband) or an admin classifies.
    _nafaqahPreview = NafaqahPreview.fromPreview(widget.pendingData)
        .withAdmin(widget.isAdmin ?? viewerIsAdminOf(context, widget.pendingData['household_id'] as String?));
    _nafaqahWifeId = _nafaqahPreview.defaultSpouseId;
    final suggested = widget.pendingData['nafaqah_class'] as String?;
    _nafaqahChoice = (suggested == kWifeReimbursable || suggested == kWifePersonal)
        ? suggested
        : classifyNafaqah(_spouseRole, _selectedPaidBy, _selectedBeneficiary);
    // Keep who paid / for whom consistent with the (suggested) class.
    if (_spouseRole != null) _applyNafaqahChoice(_nafaqahChoice);

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
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
        color: context.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppThemes.success.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.edit_note_rounded, color: AppThemes.success, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  context.tr('pec_title'),
                  style: GoogleFonts.outfit(
                    color: context.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Amount first, editable (UX-12): a misheard 816 is fixed here, not retyped.
          TextField(
            key: const ValueKey('pec_amount'),
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: GoogleFonts.outfit(color: context.textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
            onChanged: (_) {
              if (_amountInvalid) setState(() => _amountInvalid = false);
            },
            decoration: InputDecoration(
              labelText: context.tr('pec_amount_label'),
              suffixText: context.tr('sar'),
              errorText: _amountInvalid ? context.tr('pec_amount_invalid') : null,
              labelStyle: TextStyle(color: context.textSecondary, fontSize: 13),
              isDense: true,
              filled: true,
              fillColor: context.inputBg,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
                borderSide: const BorderSide(color: AppThemes.success),
              ),
            ),
          ),
          const SizedBox(height: 8),
          ExpenseDateChips(
            value: _occurredAt,
            onChanged: (d) => setState(() => _occurredAt = d),
          ),
          const SizedBox(height: 12),

          // Merchant name input
          TextField(
            controller: _merchantController,
            style: GoogleFonts.outfit(color: context.textPrimary, fontSize: 13),
            decoration: InputDecoration(
              labelText: context.tr('merchant'),
              hintText: context.tr('store_name'),
              labelStyle: TextStyle(color: context.textSecondary, fontSize: 12),
              isDense: true,
              filled: true,
              fillColor: context.inputBg,
              prefixIcon: const Icon(Icons.storefront_rounded, size: 16, color: AppThemes.success),
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
                borderSide: const BorderSide(color: AppThemes.success),
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
                    color: context.inputBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: context.borderColor),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedCategoryCode,
                      isExpanded: true,
                      dropdownColor: context.cardBg,
                      style: GoogleFonts.outfit(color: context.textPrimary, fontSize: 12),
                      items: CategoryCatalog.pickerCodesIncluding(_selectedCategoryCode).map((code) {
                        return DropdownMenuItem(
                          value: code,
                          child: Text(context.trCat(code)),
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
                    color: context.inputBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: context.borderColor),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: _loadingSubs
                        ? const SizedBox(
                            height: 40,
                            child: Center(
                              child: SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppThemes.success),
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
                              _availableSubCategories.isEmpty ? context.tr('pec_general') : context.tr('sub_category'),
                              style: TextStyle(color: context.textSecondary, fontSize: 11),
                            ),
                            dropdownColor: context.cardBg,
                            style: GoogleFonts.outfit(color: context.textPrimary, fontSize: 12),
                            items: _availableSubCategories.map((s) {
                              final subCode = s['sub_code'] as String? ?? '';
                              final nameEn = s['name_en'] as String? ?? subCode;
                              return DropdownMenuItem<String>(
                                value: subCode,
                                child: Text(
                                  context.trSub(subCode, nameAr: s['name_ar'] as String?, nameEn: nameEn),
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

          // ── WHO PAID? / FOR WHOM? (roommates and partners only) ──
          // A family household answers one Nafaqah question instead (UX-03).
          if (!_isFamily) ...[
          Text(
            context.tr('pec_who_paid_caps'),
            style: GoogleFonts.outfit(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: context.textSecondary,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              _buildChoiceChip(
                label: context.tr('me'),
                isSelected: _selectedPaidBy == 'me',
                onSelected: () => _setPaidBy('me'),
              ),
              const SizedBox(width: 8),
              _buildChoiceChip(
                label: context.tr('pec_payer_other'),
                isSelected: _selectedPaidBy == 'partner',
                onSelected: () => _setPaidBy('partner'),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // ── FOR WHOM? ──
          Text(
            context.tr('pec_for_whom_caps'),
            style: GoogleFonts.outfit(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: context.textSecondary,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _buildChoiceChip(
                label: context.tr('pec_both_family'),
                isSelected: _selectedBeneficiary == 'both',
                onSelected: () => _setBeneficiary('both'),
              ),
              _buildChoiceChip(
                label: context.tr('me'),
                isSelected: _selectedBeneficiary == 'me',
                onSelected: () => _setBeneficiary('me'),
              ),
              _buildChoiceChip(
                label: context.tr('partner'),
                isSelected: _selectedBeneficiary == 'partner',
                onSelected: () => _setBeneficiary('partner'),
              ),
              ...dependents.map((depName) {
                return _buildChoiceChip(
                  label: depName,
                  icon: Icons.child_care_rounded,
                  isSelected: _selectedBeneficiary == depName.toLowerCase(),
                  onSelected: () => _setBeneficiary(depName.toLowerCase()),
                );
              }),
            ],
          ),
          const SizedBox(height: 12),
          ],

          // Family: the wife's own money is either a shared advance the husband
          // reimburses or a personal purchase from her allowance (never split).
          if (_isAdminClassifier || _spouseRole != null) ...[
            NafaqahReviewSection(
              preview: _nafaqahPreview,
              value: _nafaqahChoice,
              wifeId: _nafaqahWifeId,
              showWifeRequired: _showWifeRequired,
              onChanged: _chooseNafaqah,
              onWifeChanged: (id) => setState(() => _nafaqahWifeId = id),
            ),
            const SizedBox(height: 12),
          ],
          // Family: optionally, which child it was for (never for a personal purchase).
          if (_isFamily && dependents.isNotEmpty && _nafaqahChoice != kWifePersonal) ...[
            Text(
              context.tr('nafaqah_for_child_optional'),
              style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600, color: context.textSecondary),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: dependents.map((depName) {
                final selected = _childBeneficiary(dependents) == depName;
                return _buildChoiceChip(
                  label: depName,
                  icon: Icons.child_care_rounded,
                  isSelected: selected,
                  onSelected: () => setState(() => _selectedBeneficiary = selected ? 'both' : depName.toLowerCase()),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
          ],

          // Items Preview (with subcategory badge)
          if (items.isNotEmpty) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: context.subtleCardBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: context.borderColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.trArgs('pec_items_found', {'count': items.length}),
                    style: TextStyle(color: context.textSecondary, fontSize: 11, fontWeight: FontWeight.bold),
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
                                  style: TextStyle(color: context.textPrimary, fontSize: 12),
                                ),
                                if (itemSub != null && itemSub.isNotEmpty) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: context.infoSubtleBg,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      itemSub,
                                      style: TextStyle(color: context.infoColor, fontSize: 9),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Text(
                            context.sar((it['price'] as num?) ?? 0),
                            style: TextStyle(color: context.successText, fontSize: 11),
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
                  key: const ValueKey('pec_confirm'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppThemes.success,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.check_circle_rounded, size: 16),
                  label: Text(
                    context.tr('pec_confirm_add'),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  onPressed: () {
                    final typed = parseMoneyInput(_amountController.text, allowNegative: false);
                    if (typed == null || typed <= 0) {
                      setState(() => _amountInvalid = true);
                      return;
                    }
                    final now = DateTime.now();
                    final isToday = _occurredAt.year == now.year && _occurredAt.month == now.month && _occurredAt.day == now.day;
                    final edits = PendingExpenseEdits(
                      amount: (typed - _previewAmount).abs() < 0.005 ? null : typed,
                      occurredAt: isToday ? null : _occurredAt,
                      accountId: widget.pendingData['account_id'] as String?,
                    );
                    // The class follows the confirmed chips (the selector keeps
                    // them in sync), so a stale suggestion is never sent.
                    final derived = _isAdminClassifier
                        ? _nafaqahChoice
                        : (_spouseRole == null
                            ? null
                            : classifyNafaqah(_spouseRole, _selectedPaidBy, _selectedBeneficiary));
                    // An admin's class names the wife who paid ('partner' with
                    // nafaqah_spouse_id), so the attribution never contradicts it.
                    final adminFields = _isAdminClassifier && derived != null
                        ? _nafaqahPreview.requestFields(derived, chosenWifeId: _nafaqahWifeId)
                        : const <String, String>{};
                    if (!NafaqahReviewSection.hasRequiredWife(_nafaqahPreview, derived, _nafaqahWifeId)) {
                      setState(() => _showWifeRequired = true);
                      return;
                    }
                    final store = _merchantController.text.trim();
                    final resolvedSub = _selectedSubCategory ??
                        (_availableSubCategories.isNotEmpty
                            ? _availableSubCategories.first['sub_code'] as String?
                            : null);
                    widget.onConfirm(
                      store.isNotEmpty ? store : context.tr('store_name'),
                      _selectedCategoryCode,
                      resolvedSub,
                      adminFields['paid_by'] ?? _selectedPaidBy,
                      adminFields['beneficiary'] ?? _selectedBeneficiary,
                      !_isFamily ? null : (derived ?? kNafaqahNone),
                      _isFamily && derived != null && (_spouseRole == 'husband' || _isAdminClassifier)
                          ? _nafaqahWifeId
                          : null,
                      edits,
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: widget.onCancel,
                style: TextButton.styleFrom(
                  foregroundColor: context.textSecondary,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
                child: Text(context.tr('cancel'), style: const TextStyle(fontSize: 12)),
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
          color: isSelected ? AppThemes.success.withValues(alpha: 0.15) : context.chipBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppThemes.success : context.borderColor,
            width: isSelected ? 1.2 : 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: isSelected ? AppThemes.success : context.textSecondary),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? AppThemes.success : context.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
