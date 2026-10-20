import 'package:flutter/material.dart';
import '../../theme/app_themes.dart';
import '../../l10n/app_localizations.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../main.dart';
import '../../models/models.dart';
import '../../models/nafaqah.dart';
import '../../providers/budget_provider.dart';
import '../../providers/installment_provider.dart';
import '../../providers/recurring_bills_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../services/api_service.dart';
import '../../services/household_permissions.dart';
import '../../services/receipt_storage_service.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/nafaqah/nafaqah_class_selector.dart';
import '../../widgets/dispose_on_unmount.dart';
import '../../models/money.dart';

/// Reads the stored Nafaqah fields (`nafaqah_class`, `nafaqah_spouse_id`) of a transaction.
typedef NafaqahFieldsLoader = Future<Map<String, dynamic>?> Function(String transactionId);

class EditTransactionSheet extends StatefulWidget {
  final Transaction transaction;
  final List<String> householdDependents;

  /// Family-mode context; loaded from the API when omitted.
  final NafaqahSummary? nafaqah;
  final Future<NafaqahSummary> Function(String householdId)? loadNafaqah;
  final NafaqahFieldsLoader? loadNafaqahFields;

  const EditTransactionSheet({
    super.key,
    required this.transaction,
    this.householdDependents = const [],
    this.nafaqah,
    this.loadNafaqah,
    this.loadNafaqahFields,
  });

  static Future<String?> show(
    BuildContext context,
    Transaction transaction, {
    List<String> householdDependents = const [],
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: EditTransactionSheet(
          transaction: transaction,
          householdDependents: householdDependents,
        ),
      ),
    );
  }

  @override
  State<EditTransactionSheet> createState() => _EditTransactionSheetState();
}

class _EditTransactionSheetState extends State<EditTransactionSheet> {
  late TextEditingController _merchantCtrl;
  late TextEditingController _amountCtrl;
  late String _selectedCategory;
  late String? _selectedSubCategory;
  late String _selectedPaidBy;
  late String _selectedBeneficiary;
  late List<Map<String, dynamic>> _items;
  List<Map<String, dynamic>> _subCategories = [];
  List<String> _dependents = [];
  bool _isSaving = false;
  NafaqahSummary? _nafaqah;
  String? _storedSpouseId;

  /// The stored `nafaqah_class` has been read. Until then the class columns
  /// are left untouched on save (FR-A-01).
  bool _storedNafaqahLoaded = false;

  final List<Map<String, String>> _categories = const [
    {'code': 'OPEX-GROCERY', 'name': 'Groceries & Supermarkets'},
    {'code': 'OPEX-DINING', 'name': 'Dining & Cafes'},
    {'code': 'OPEX-SHOPPING', 'name': 'Shopping & Retail'},
    {'code': 'OPEX-UTILITIES', 'name': 'Utilities & Bills'},
    {'code': 'OPEX-FUEL', 'name': 'Fuel & Transport'},
    {'code': 'OPEX-ENTERTAINMENT', 'name': 'Entertainment'},
    {'code': 'OPEX-HEALTH', 'name': 'Health & Pharmacy'},
    {'code': 'CAPEX-EDUCATION', 'name': 'Education'},
    {'code': 'OPEX-GOV', 'name': 'Government & Fees'},
    {'code': 'OPEX-MISC', 'name': 'Miscellaneous'},
  ];

  @override
  void initState() {
    super.initState();
    _merchantCtrl = TextEditingController(text: widget.transaction.merchant ?? '');
    _amountCtrl = TextEditingController(text: widget.transaction.amount.toStringAsFixed(2));
    var initialCat = widget.transaction.categoryCode ?? 'OPEX-MISC';
    if (initialCat == 'OPEX-GROCERIES') initialCat = 'OPEX-GROCERY';
    if (initialCat == 'OPEX-TRANSPORT') initialCat = 'OPEX-FUEL';
    if (initialCat == 'OPEX-EDUCATION') initialCat = 'CAPEX-EDUCATION';
    if (initialCat == 'OPEX-HOUSING') initialCat = 'OPEX-UTILITIES';
    _selectedCategory = initialCat;
    _selectedSubCategory = widget.transaction.subCategory;
    _selectedPaidBy = widget.transaction.paidBy.isNotEmpty ? widget.transaction.paidBy : 'me';
    _selectedBeneficiary = widget.transaction.beneficiary.isNotEmpty ? widget.transaction.beneficiary : 'both';
    if (widget.transaction.paidBy.isEmpty && widget.transaction.spentBy.isNotEmpty) {
      if (widget.transaction.spentBy == 'partner') {
        _selectedPaidBy = 'partner';
        _selectedBeneficiary = 'partner';
      } else if (widget.transaction.spentBy == 'both') {
        _selectedPaidBy = 'me';
        _selectedBeneficiary = 'both';
      } else {
        _selectedPaidBy = 'me';
        _selectedBeneficiary = 'me';
      }
    }
    _items = widget.transaction.items
        .map((it) => Map<String, dynamic>.from(it))
        .toList();
    _dependents = List<String>.from(widget.householdDependents);
    _loadSubCategories(_selectedCategory);
    if (_dependents.isEmpty && widget.transaction.householdId.isNotEmpty) {
      _loadDependents();
    }
    _nafaqah = widget.nafaqah;
    if (_nafaqah != null) {
      _loadStoredNafaqah();
    } else if (widget.transaction.householdId.isNotEmpty) {
      _loadNafaqah();
    }
  }

  // ── Family mode (Islamic Nafaqah: no spousal split) ────────────────────────

  bool get _isFamily => _nafaqah?.isFamily ?? false;

  /// 'wife' | 'husband' when the viewer is one of the spouses of a family household.
  String? get _spouseRole {
    final role = _isFamily ? _nafaqah!.callerRole : null;
    return (role == 'wife' || role == 'husband') ? role : null;
  }

  String? get _nafaqahClass =>
      _spouseRole == null ? null : classifyNafaqah(_spouseRole, _selectedPaidBy, _selectedBeneficiary);

  /// Maps the Nafaqah choice onto the viewer-relative payer / beneficiary.
  void _applyNafaqahChoice(String? nafaqahClass) {
    final wifeSide = _spouseRole == 'wife' ? 'me' : 'partner';
    final husbandSide = _spouseRole == 'wife' ? 'partner' : 'me';
    if (nafaqahClass == kWifeReimbursable) {
      _selectedPaidBy = wifeSide;
      _selectedBeneficiary = 'both';
    } else if (nafaqahClass == kWifePersonal) {
      _selectedPaidBy = wifeSide;
      _selectedBeneficiary = wifeSide;
    } else {
      _selectedPaidBy = husbandSide;
      if (classifyNafaqah(_spouseRole, _selectedPaidBy, _selectedBeneficiary) != null) {
        _selectedBeneficiary = 'both';
      }
    }
  }

  Future<void> _loadNafaqah() async {
    try {
      final loader = widget.loadNafaqah ?? ApiService.instance.getNafaqahSummary;
      final summary = await loader(widget.transaction.householdId);
      if (!mounted) return;
      setState(() => _nafaqah = summary);
      await _loadStoredNafaqah();
    } catch (_) {}
  }

  /// The stored class is authoritative in family mode. `paid_by` /
  /// `beneficiary` are relative to whoever recorded the row ('me' is the
  /// recorder), so on another spouse's phone they cannot tell who paid: a
  /// stored "no class" is the husband's household expense (FR-A-01), and a
  /// stored class keeps the wife's claim when the husband edits it.
  Future<void> _loadStoredNafaqah() async {
    if (_spouseRole == null) return;
    try {
      final loader = widget.loadNafaqahFields ??
          (String id) => supabase.from('transactions').select('nafaqah_class, nafaqah_spouse_id').eq('id', id).maybeSingle();
      final fields = await loader(widget.transaction.id);
      if (!mounted || fields == null) return;
      final stored = fields['nafaqah_class'] as String?;
      setState(() {
        _storedSpouseId = fields['nafaqah_spouse_id'] as String?;
        _applyNafaqahChoice(stored == kWifeReimbursable || stored == kWifePersonal ? stored : null);
        _storedNafaqahLoaded = true;
      });
    } catch (_) {}
  }

  Map<String, dynamic> _nafaqahPayload() {
    // Unknown stored class (still loading or unreadable): never rewrite it.
    if (_spouseRole == null || !_storedNafaqahLoaded) return const {};
    final cls = _nafaqahClass;
    final spouseId = _spouseRole == 'wife'
        ? _nafaqah!.callerUserId
        : (_storedSpouseId ?? _nafaqah!.primaryWife?.id);
    if (cls == null || spouseId == null || spouseId.isEmpty) {
      return const {'nafaqah_class': null, 'nafaqah_spouse_id': null};
    }
    return {'nafaqah_class': cls, 'nafaqah_spouse_id': spouseId};
  }

  Future<void> _loadSubCategories(String catCode) async {
    try {
      final subs = await ApiService.instance.getSubCategories(catCode);
      if (mounted) {
        setState(() {
          _subCategories = subs;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadDependents() async {
    try {
      final deps = await ApiService.instance.getDependents(widget.transaction.householdId);
      if (mounted) {
        setState(() {
          _dependents = deps.map((d) => d.name).toList();
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _merchantCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  void _addItem() {
    setState(() {
      _items.add({'name': context.tr('new_item'), 'quantity': 1.0, 'price': 0.0});
    });
  }

  void _removeItem(int index) {
    setState(() {
      _items.removeAt(index);
    });
  }

  Future<void> _saveChanges() async {
    final amount = parseMoneyInput(_amountCtrl.text);
    if (amount == null || amount <= 0) {
      AppSnackBar.showError(context, context.tr('invalid_amount_msg'), title: context.tr('invalid_amount'));
      return;
    }

    setState(() => _isSaving = true);

    String derivedSpentBy = 'both';
    if (_selectedBeneficiary == 'both') {
      derivedSpentBy = 'both';
    } else if (_selectedPaidBy == 'partner' && _selectedBeneficiary == 'partner') {
      derivedSpentBy = 'partner';
    } else if (_selectedPaidBy == 'me' && _selectedBeneficiary == 'me') {
      derivedSpentBy = 'me';
    } else {
      derivedSpentBy = _selectedBeneficiary;
    }

    final basePayload = <String, dynamic>{
      'merchant': _merchantCtrl.text.trim(),
      'amount': amount,
      'category_code': _selectedCategory,
      'sub_category': _selectedSubCategory,
      'items': _items,
    };

    try {
      try {
        await supabase.from('transactions').update({
          ...basePayload,
          ..._nafaqahPayload(),
          'paid_by': _selectedPaidBy,
          'beneficiary': _selectedBeneficiary,
          'spent_by': derivedSpentBy,
        }).eq('id', widget.transaction.id);
      } catch (e) {
        // Another member's transaction and the user is no admin (DB-18): no fallback.
        if (HouseholdPermissions.isPermissionDenied(e)) rethrow;
        // Fallback: update raw_sms with PaidBy and Beneficiary tags
        final raw = widget.transaction.rawSms ?? '';
        final cleanRaw = raw
            .replaceAll(RegExp(r'\|\s*SpentBy:\s*(me|partner|both)', caseSensitive: false), '')
            .replaceAll(RegExp(r'\|\s*PaidBy:\s*(me|partner)', caseSensitive: false), '')
            .replaceAll(RegExp(r'\|\s*Beneficiary:\s*([^\s\|]+)', caseSensitive: false), '')
            .replaceAll(RegExp(r'\|\s*SubCategory:\s*([^\s\|]+)', caseSensitive: false), '')
            .trim();
        final newRaw = '$cleanRaw | PaidBy: $_selectedPaidBy | Beneficiary: $_selectedBeneficiary | SubCategory: ${_selectedSubCategory ?? ""} | SpentBy: $derivedSpentBy';
        await supabase.from('transactions').update({
          ...basePayload,
          ..._nafaqahPayload(),
          'raw_sms': newRaw,
          'spent_by': derivedSpentBy,
        }).eq('id', widget.transaction.id);
      }

      if (mounted) {
        Navigator.pop(context, 'updated');
        AppSnackBar.showSuccess(
          context,
          context.tr('tx_updated_msg'),
          title: context.tr('changes_saved'),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        AppSnackBar.showError(
          context,
          HouseholdPermissions.isPermissionDenied(e)
              ? context.tr('perm_tx_admin_only')
              : context.trArgs('tx_update_failed_msg', {'error': e}),
          title: context.tr('update_error'),
        );
      }
    }
  }

  Future<void> _deleteTransaction() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.cardBg,
        title: Text(context.tr('delete_transaction'), style: TextStyle(color: context.textPrimary)),
        content: Text(
          context.trArgs('tx_delete_confirm_long', {'amount': context.sar(widget.transaction.amount), 'merchant': widget.transaction.merchant ?? context.tr('unknown')}),
          style: TextStyle(color: context.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('cancel'), style: TextStyle(color: context.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr('delete')),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _isSaving = true);

    try {
      await supabase.from('transactions').delete().eq('id', widget.transaction.id);
      // Only after the server accepted the delete: a refused delete keeps its receipt.
      if (widget.transaction.receiptUrl != null && widget.transaction.receiptUrl!.trim().isNotEmpty) {
        ReceiptStorageService().deleteReceiptByUrl(widget.transaction.receiptUrl!);
      }
      if (mounted) {
        Navigator.pop(context, 'deleted');
        AppSnackBar.showDelete(
          context,
          context.trArgs('tx_removed_msg', {'amount': context.sar(widget.transaction.amount), 'merchant': widget.transaction.merchant ?? context.tr('merchant_generic')}),
          title: context.tr('tx_deleted'),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        AppSnackBar.showError(
          context,
          HouseholdPermissions.isPermissionDenied(e)
              ? context.tr('perm_tx_admin_only')
              : context.trArgs('tx_delete_failed_err', {'error': e}),
          title: context.tr('delete_error'),
        );
      }
    }
  }

  Widget _buildSegmentOption({
    required bool isSelected,
    required String title,
    required IconData icon,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? activeColor.withValues(alpha: 0.18) : context.subtleCardBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? activeColor : context.borderColor,
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: isSelected ? activeColor : context.textSecondary),
              const SizedBox(height: 4),
              Text(
                title,
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? (context.isDark ? Colors.white : const Color(0xFF0F172A)) : context.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettlementPreviewBanner(double amount) {
    String text;
    IconData icon;
    Color color;

    if (_isFamily) {
      // Family (Nafaqah): never a 50/50 split between the spouses.
      final cls = _nafaqahClass;
      if (cls == kWifeReimbursable) {
        text = context.trArgs('nafaqah_banner_shared', {'amount': context.sar(amount)});
        icon = Icons.currency_exchange_rounded;
      } else if (cls == kWifePersonal) {
        text = context.trArgs('nafaqah_banner_personal', {'amount': context.sar(amount)});
        icon = Icons.shopping_bag_outlined;
      } else {
        text = context.tr('nafaqah_banner_husband');
        icon = Icons.shield_outlined;
      }
      color = NafaqahClassSelector.colorFor(cls);
    } else if (_selectedPaidBy == 'me' && _selectedBeneficiary == 'both') {
      final half = amount * 0.5;
      text = context.trArgs('settle_shared_partner_owes', {'amount': context.sar(half)});
      icon = Icons.handshake_outlined;
      color = AppThemes.success;
    } else if (_selectedPaidBy == 'me' && _selectedBeneficiary == 'partner') {
      text = context.trArgs('settle_paid_for_partner', {'amount': context.sar(amount)});
      icon = Icons.volunteer_activism_outlined;
      color = const Color(0xFFBC8CFF);
    } else if (_selectedPaidBy == 'partner' && _selectedBeneficiary == 'both') {
      final half = amount * 0.5;
      text = context.trArgs('settle_shared_you_owe', {'amount': context.sar(half)});
      icon = Icons.handshake_outlined;
      color = const Color(0xFFFF9E79);
    } else if (_selectedPaidBy == 'partner' && _selectedBeneficiary == 'me') {
      text = context.trArgs('settle_partner_paid_for_you', {'amount': context.sar(amount)});
      icon = Icons.card_giftcard_rounded;
      color = const Color(0xFFFF6B6B);
    } else if (_selectedPaidBy == 'me' && _selectedBeneficiary == 'me') {
      text = context.tr('settle_personal_me');
      icon = Icons.person_outline;
      color = const Color(0xFF58A6FF);
    } else {
      text = context.tr('settle_personal_partner');
      icon = Icons.favorite_outline;
      color = const Color(0xFFBC8CFF);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProviderRadio(String provider, Color color, String currentSelected, ValueChanged<String> onSelected) {
    final isSelected = currentSelected == provider;
    return Expanded(
      child: InkWell(
        onTap: () => onSelected(provider),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.15) : context.subtleCardBg,
            border: Border.all(color: isSelected ? color : context.borderColor),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            provider == 'Bank / Other' ? context.tr('bnpl_provider_bank_other') : provider,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? color : context.textPrimary,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _convertToInstallmentPlan() async {
    final amount = parseMoneyInput(_amountCtrl.text);
    if (amount == null || amount <= 0) {
      AppSnackBar.showError(context, context.tr('enter_valid_amount_first'), title: context.tr('amount_required'));
      return;
    }

    String selectedProvider = 'Tamara';
    int selectedCount = 4;
    bool isProcessing = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (sheetCtx, setModalState) {
            final monthly = amount / selectedCount;
            final remainingBalance = amount - monthly;

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 20,
                left: 20,
                right: 20,
                top: 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: context.borderColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    context.tr('bnpl_convert_title'),
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: context.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.tr('bnpl_convert_desc'),
                    style: TextStyle(fontSize: 12, color: context.textSecondary),
                  ),
                  const SizedBox(height: 16),

                  // Provider Selector
                  Text(context.tr('provider_caps'), style: GoogleFonts.outfit(fontSize: 11, color: context.textSecondary, letterSpacing: 1)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildProviderRadio('Tamara', const Color(0xFFFF6B6B), selectedProvider, (p) {
                        setModalState(() => selectedProvider = p);
                      }),
                      const SizedBox(width: 8),
                      _buildProviderRadio('Tabby', const Color(0xFF00E676), selectedProvider, (p) {
                        setModalState(() => selectedProvider = p);
                      }),
                      const SizedBox(width: 8),
                      _buildProviderRadio('Bank / Other', const Color(0xFF58A6FF), selectedProvider, (p) {
                        setModalState(() => selectedProvider = p);
                      }),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Duration selector
                  Text(context.tr('installment_duration_caps'), style: GoogleFonts.outfit(fontSize: 11, color: context.textSecondary, letterSpacing: 1)),
                  const SizedBox(height: 8),
                  Row(
                    children: [3, 4, 6].map((count) {
                      final isSelected = selectedCount == count;
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: InkWell(
                            onTap: () => setModalState(() => selectedCount = count),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: isSelected ? AppThemes.success.withValues(alpha: 0.2) : context.subtleCardBg,
                                border: Border.all(
                                  color: isSelected ? AppThemes.success : context.borderColor,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                context.trArgs('n_months', {'count': count}),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: isSelected ? AppThemes.success : context.textPrimary,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
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

                  // Plan Summary Box
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: context.subtleCardBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: context.borderColor),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(context.tr('first_month_this_cycle'), style: TextStyle(color: context.textSecondary, fontSize: 12)),
                            Text(context.sar(monthly), style: TextStyle(color: context.successText, fontWeight: FontWeight.bold, fontSize: 13)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(context.trArgs('deferred_next_cycles', {'count': selectedCount - 1}), style: TextStyle(color: context.textSecondary, fontSize: 12)),
                            Text(context.sar(remainingBalance), style: TextStyle(color: context.textPrimary, fontSize: 13)),
                          ],
                        ),
                        Divider(color: context.borderColor, height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(context.tr('immediate_headroom'), style: TextStyle(color: context.textSecondary, fontSize: 12)),
                            Text('+${context.sar(remainingBalance)}', style: TextStyle(color: context.successText, fontWeight: FontWeight.bold, fontSize: 13)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppThemes.success,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: isProcessing ? null : () async {
                      setModalState(() => isProcessing = true);
                      try {
                        final noteSuffix = ' [Financed via $selectedProvider: Installment 1 of $selectedCount. Full price: SAR ${amount.toStringAsFixed(2)}]';
                        final updatedNotes = '${widget.transaction.rawSms ?? ''}$noteSuffix';

                        await ApiService.instance.createInstallmentPlan({
                          'household_id': widget.transaction.householdId,
                          'merchant': _merchantCtrl.text.trim(),
                          'provider': selectedProvider,
                          'total_amount': amount,
                          'installment_count': selectedCount,
                          'paid_installments': 1,
                          'category_code': _selectedCategory,
                          'original_transaction_id': widget.transaction.id,
                          'adjust_original_transaction': true,
                          'notes': 'Converted from transaction via mobile app',
                        });

                        try {
                          await supabase.from('transactions').update({
                            'amount': monthly,
                            'raw_sms': updatedNotes,
                          }).eq('id', widget.transaction.id);
                        } catch (_) {}

                        if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                        if (mounted) {
                          try {
                            context.read<InstallmentProvider>().fetchPlans(silent: true);
                            context.read<TransactionProvider>().fetchTransactions();
                            context.read<BudgetProvider>().refresh();
                            context.read<RecurringBillsProvider>().fetchBills(silent: true);
                          } catch (_) {}
                          Navigator.pop(context, 'updated');
                          AppSnackBar.showSuccess(
                            context,
                            context.trArgs('bnpl_converted_msg', {'provider': selectedProvider == 'Bank / Other' ? context.tr('bnpl_provider_bank_other') : selectedProvider, 'count': selectedCount}),
                            title: context.tr('plan_active_title'),
                          );
                        }
                      } catch (e) {
                        if (sheetCtx.mounted) {
                          setModalState(() => isProcessing = false);
                          AppSnackBar.showError(sheetCtx, sheetCtx.trArgs('bnpl_convert_failed_msg', {'error': e}), title: sheetCtx.tr('conversion_failed'));
                        }
                      }
                    },
                    child: isProcessing
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                        : Text(context.tr('confirm_installment_plan'), style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _quickAddChild() async {
    final nameCtrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dCtx) => DisposeOnUnmount(
        disposables: [nameCtrl],
        child: AlertDialog(
        backgroundColor: context.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.child_care_rounded, color: AppThemes.success),
            const SizedBox(width: 8),
            Text(
              context.tr('add_child_dependent'),
              style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16, color: context.textPrimary),
            ),
          ],
        ),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          style: TextStyle(color: context.textPrimary),
          decoration: InputDecoration(
            labelText: context.tr('child_name_label'),
            labelStyle: TextStyle(color: context.textSecondary),
            hintText: context.tr('child_name_hint'),
            hintStyle: const TextStyle(color: Color(0xFF484F58)),
            filled: true,
            fillColor: context.inputBg,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: Text(context.tr('cancel'), style: TextStyle(color: context.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppThemes.success, foregroundColor: Colors.black),
            onPressed: () {
              final n = nameCtrl.text.trim();
              if (n.isNotEmpty) Navigator.pop(dCtx, n);
            },
            child: Text(context.tr('add'), style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      ),
    );

    if (name != null && name.isNotEmpty) {
      try {
        await ApiService.instance.createDependent(
          widget.transaction.householdId,
          name,
        );
      } catch (_) {}
      if (mounted) {
        setState(() {
          if (!_dependents.contains(name)) {
            _dependents.add(name);
          }
          _selectedBeneficiary = name;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 20,
          right: 20,
          top: 16,
        ),
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.borderColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  context.tr('edit_transaction'),
                  style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w700, color: context.textPrimary),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  tooltip: context.tr('delete_transaction'),
                  onPressed: _deleteTransaction,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Merchant
            TextField(
              controller: _merchantCtrl,
              style: TextStyle(color: context.textPrimary),
              decoration: InputDecoration(
                labelText: context.tr('merchant_name'),
                labelStyle: TextStyle(color: context.textSecondary),
                filled: true,
                fillColor: context.inputBg,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),

            // Amount
            TextField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                labelText: context.tr('amount_sar'),
                prefixText: '${context.tr('sar')} ',
                labelStyle: TextStyle(color: context.textSecondary),
                filled: true,
                fillColor: context.inputBg,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),

            // BNPL / Installment Action Banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: context.subtleCardBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.borderColor),
              ),
              child: Row(
                children: [
                  const Icon(Icons.credit_score_rounded, color: Color(0xFFFF6B6B), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr('installment_plans_title'),
                          style: GoogleFonts.outfit(
                            color: context.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          context.tr('bnpl_empty_desc'),
                          style: TextStyle(color: context.textSecondary, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: _convertToInstallmentPlan,
                    child: Text(context.tr('convert'), style: const TextStyle(color: Color(0xFF58A6FF), fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Category Dropdown
            DropdownButtonFormField<String>(
              initialValue: _categories.any((c) => c['code'] == _selectedCategory) ? _selectedCategory : 'OPEX-MISC',
              dropdownColor: context.cardBg,
              style: TextStyle(color: context.textPrimary),
              decoration: InputDecoration(
                labelText: context.tr('category'),
                labelStyle: TextStyle(color: context.textSecondary),
                filled: true,
                fillColor: context.inputBg,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              items: _categories.map((c) {
                return DropdownMenuItem(
                  value: c['code'],
                  child: Text(context.trCat(c['code']!)),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _selectedCategory = val;
                    _selectedSubCategory = null;
                  });
                  _loadSubCategories(val);
                }
              },
            ),
            const SizedBox(height: 12),

            // Sub-Category Dropdown
            DropdownButtonFormField<String?>(
              initialValue: _subCategories.any((s) => s['sub_code'] == _selectedSubCategory)
                  ? _selectedSubCategory
                  : null,
              dropdownColor: context.cardBg,
              style: TextStyle(color: context.textPrimary),
              decoration: InputDecoration(
                labelText: context.tr('sub_category'),
                labelStyle: TextStyle(color: context.textSecondary),
                filled: true,
                fillColor: context.inputBg,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text(context.tr('select_sub_category'), style: TextStyle(color: context.textSecondary)),
                ),
                ..._subCategories.map((s) {
                  final code = s['sub_code'] as String? ?? '';
                  final nameEn = s['name_en'] as String? ?? code;
                  final nameAr = s['name_ar'] as String? ?? '';
                  return DropdownMenuItem<String?>(
                    value: code,
                    child: Text(context.trSub(code, nameAr: nameAr, nameEn: nameEn)),
                  );
                }),
              ],
              onChanged: (val) {
                setState(() => _selectedSubCategory = val);
              },
            ),
            const SizedBox(height: 16),

            // ── WHO PAID? ────────────────────────────────────────────────
            Text(
              context.tr('who_paid'),
              style: GoogleFonts.outfit(
                fontSize: 12,
                letterSpacing: 1,
                fontWeight: FontWeight.w600,
                color: context.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildSegmentOption(
                  isSelected: _selectedPaidBy == 'me',
                  title: context.tr('i_paid'),
                  icon: Icons.credit_card_rounded,
                  activeColor: const Color(0xFF58A6FF),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _selectedPaidBy = 'me');
                  },
                ),
                const SizedBox(width: 8),
                _buildSegmentOption(
                  isSelected: _selectedPaidBy == 'partner',
                  title: context.tr('partner_paid'),
                  icon: Icons.favorite_outline,
                  activeColor: const Color(0xFFBC8CFF),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _selectedPaidBy = 'partner');
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── FOR WHOM? ────────────────────────────────────────────────
            Text(
              context.tr('for_whom_title'),
              style: GoogleFonts.outfit(
                fontSize: 12,
                letterSpacing: 1,
                fontWeight: FontWeight.w600,
                color: context.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildSegmentOption(
                  isSelected: _selectedBeneficiary == 'me',
                  title: context.tr('me_solo'),
                  icon: Icons.person_outline,
                  activeColor: const Color(0xFF58A6FF),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _selectedBeneficiary = 'me');
                  },
                ),
                const SizedBox(width: 8),
                _buildSegmentOption(
                  isSelected: _selectedBeneficiary == 'partner',
                  title: context.tr('partner'),
                  icon: Icons.favorite_outline,
                  activeColor: const Color(0xFFBC8CFF),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _selectedBeneficiary = 'partner');
                  },
                ),
                const SizedBox(width: 8),
                _buildSegmentOption(
                  isSelected: _selectedBeneficiary == 'both',
                  title: context.tr('both_shared'),
                  icon: Icons.people_alt_outlined,
                  activeColor: AppThemes.success,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _selectedBeneficiary = 'both');
                  },
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  context.tr('paid_for_whom_title'),
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w700,
                    color: context.textSecondary,
                  ),
                ),
                InkWell(
                  onTap: _quickAddChild,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Row(
                      children: [
                        const Icon(Icons.add_rounded, size: 14, color: AppThemes.success),
                        const SizedBox(width: 2),
                        Text(
                          context.tr('add_child'),
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: context.successText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_dependents.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                decoration: BoxDecoration(
                  color: context.subtleCardBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: context.borderColor),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 14, color: context.textSecondary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        context.tr('no_children_hint'),
                        style: GoogleFonts.outfit(fontSize: 11, color: context.textSecondary),
                      ),
                    ),
                  ],
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _dependents.map((depName) {
                  final isSelected = _selectedBeneficiary.toLowerCase() == depName.toLowerCase();
                  return ChoiceChip(
                    label: Text(depName),
                    avatar: const Icon(Icons.child_care_rounded, size: 14, color: Color(0xFF58A6FF)),
                    selected: isSelected,
                    selectedColor: const Color(0xFF58A6FF).withValues(alpha: 0.2),
                    backgroundColor: context.chipBg,
                    labelStyle: TextStyle(
                      color: isSelected ? const Color(0xFF58A6FF) : context.textPrimary,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      fontSize: 12,
                    ),
                    side: BorderSide(
                      color: isSelected ? const Color(0xFF58A6FF) : context.borderColor,
                    ),
                    onSelected: (selected) {
                      HapticFeedback.selectionClick();
                      setState(() {
                        _selectedBeneficiary = selected ? depName : 'both';
                      });
                    },
                  );
                }).toList(),
              ),
            const SizedBox(height: 10),

            if (_spouseRole != null) ...[
              NafaqahClassSelector(
                value: _nafaqahClass,
                viewerIsWife: _spouseRole == 'wife',
                onChanged: (cls) {
                  HapticFeedback.selectionClick();
                  setState(() => _applyNafaqahChoice(cls));
                },
              ),
              const SizedBox(height: 10),
            ],

            // Live Settlement Preview
            _buildSettlementPreviewBanner(parseMoneyInput(_amountCtrl.text) ?? 0.0),
            const SizedBox(height: 20),

            // Line items header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  context.tr('exact_line_items'),
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w600,
                    color: context.textSecondary,
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.add, size: 16, color: AppThemes.success),
                  label: Text(context.tr('add_item'), style: TextStyle(color: context.successText, fontSize: 12)),
                  onPressed: _addItem,
                ),
              ],
            ),
            const SizedBox(height: 6),

            if (_items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  context.tr('no_itemized_breakdown'),
                  style: GoogleFonts.outfit(color: context.textSecondary, fontSize: 12),
                ),
              ),

            ..._items.asMap().entries.map((entry) {
              final idx = entry.key;
              final it = entry.value;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: context.subtleCardBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: context.borderColor),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        initialValue: it['name'] ?? '',
                        style: TextStyle(color: context.textPrimary, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: context.tr('item_name'),
                          hintStyle: TextStyle(color: context.textSecondary, fontSize: 12),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                        onChanged: (val) => it['name'] = val,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        initialValue: ((it['price'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: TextStyle(color: context.successText, fontSize: 13, fontWeight: FontWeight.w600),
                        decoration: InputDecoration(
                          prefixText: '${context.tr('sar')} ',
                          border: InputBorder.none,
                          isDense: true,
                        ),
                        onChanged: (val) {
                          it['price'] = parseMoneyInput(val) ?? 0.0;
                        },
                      ),
                    ),
                    IconButton(
                      tooltip: context.tr('close'),
                      icon: Icon(Icons.close, size: 18, color: context.textSecondary),
                      onPressed: () => _removeItem(idx),
                    ),
                  ],
                ),
              );
            }),

            const SizedBox(height: 20),

            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppThemes.success,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _isSaving ? null : _saveChanges,
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                    )
                  : Text(context.tr('save_changes'), style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    ),
  );
}
}
