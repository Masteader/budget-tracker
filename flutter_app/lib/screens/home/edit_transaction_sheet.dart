import 'package:flutter/material.dart';
import '../../theme/app_themes.dart';
import '../../l10n/app_localizations.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../main.dart';
import '../../models/models.dart';
import '../../models/nafaqah.dart';
import '../../models/transaction_attribution.dart';
import '../../providers/household_role_provider.dart';
import '../../providers/budget_provider.dart';
import '../../providers/installment_provider.dart';
import '../../providers/recurring_bills_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../services/api_service.dart';
import '../../services/household_permissions.dart';
import '../../services/nafaqah_write_errors.dart';
import '../../services/receipt_storage_service.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/nafaqah/nafaqah_class_selector.dart';
import '../../widgets/dispose_on_unmount.dart';
import '../../models/money.dart';
import '../../models/category_catalog.dart';
import '../../services/salary_cycle_service.dart';
import '../../widgets/transactions/expense_date_chips.dart';

/// Reads the stored Nafaqah fields (`nafaqah_class`, `nafaqah_spouse_id`) of a transaction.
typedef NafaqahFieldsLoader = Future<Map<String, dynamic>?> Function(String transactionId);

/// Writes [values] to the transaction row (defaults to a Supabase update).
typedef TransactionRowUpdater = Future<void> Function(String transactionId, Map<String, dynamic> values);

/// Deletes the transaction row (defaults to a Supabase delete).
typedef TransactionRowRemover = Future<void> Function(String transactionId);

/// Loads the household roster (defaults to `GET /households/{id}/members`).
typedef HouseholdRosterLoader = Future<HouseholdRoster> Function(String householdId);

class EditTransactionSheet extends StatefulWidget {
  final Transaction transaction;
  final List<String> householdDependents;

  /// Family-mode context; loaded from the API when omitted.
  final NafaqahSummary? nafaqah;
  final Future<NafaqahSummary> Function(String householdId)? loadNafaqah;
  final NafaqahFieldsLoader? loadNafaqahFields;

  /// Test seams for the row update / delete; default to Supabase.
  final TransactionRowUpdater? updateRow;
  final TransactionRowRemover? deleteRow;

  /// The signed-in user (defaults to the Supabase session).
  final String? Function()? currentUserId;

  /// Roster used to tell who "partner" is when the viewer did not record the
  /// expense, and whether the viewer is an admin.
  final HouseholdRosterLoader? loadRoster;

  /// Whether the viewer is a household admin (defaults to the
  /// [HouseholdRoleProvider], else the roster).
  final bool? isAdmin;

  const EditTransactionSheet({
    super.key,
    required this.transaction,
    this.householdDependents = const [],
    this.nafaqah,
    this.loadNafaqah,
    this.loadNafaqahFields,
    this.updateRow,
    this.deleteRow,
    this.currentUserId,
    this.loadRoster,
    this.isAdmin,
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

  /// Reading the stored class failed (UX-23): the choice is not shown.
  bool _storedNafaqahFailed = false;

  /// The user changed who paid / for whom. Untouched attribution is never
  /// rewritten, so an unrelated edit keeps exactly what the server reads
  /// (FABLE2-APP-01: a merchant edit used to rewrite the payer).
  bool _payerTouched = false;
  bool _beneficiaryTouched = false;

  HouseholdRoster? _roster;

  /// Class chosen by an admin who is not one of the spouses (they classify
  /// directly: the me/partner vocabulary does not name the wife for them).
  String? _adminClass;

  late DateTime _occurredAt;
  bool _dateTouched = false;

  SaudiCycle get _currentCycle => SalaryCycleService.currentCycle();
  SaudiCycle get _previousCycle {
    final curr = _currentCycle;
    return SalaryCycleService.cycleForInstant(curr.start.subtract(const Duration(days: 1)));
  }
  SaudiCycle get _targetCycle => SalaryCycleService.cycleForInstant(_occurredAt);


  @override
  void initState() {
    super.initState();
    _merchantCtrl = TextEditingController(text: widget.transaction.merchant ?? '');
    _amountCtrl = TextEditingController(text: widget.transaction.amount.toStringAsFixed(2));
    _occurredAt = widget.transaction.timestamp;
    var initialCat = widget.transaction.categoryCode ?? 'OPEX-MISC';
    // Keep the stored category (new system codes included); only known
    // aliases are normalised, never remapped to another category.
    _selectedCategory = CategoryCatalog.normalize(initialCat);
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
    // The stored payer/beneficiary are relative to the creator; the sheet
    // speaks to the viewer ("I paid"), so turn them around for the partner.
    if (!_viewerIsCreator) {
      _selectedPaidBy = _swapRelative(_selectedPaidBy);
      _selectedBeneficiary = _swapRelative(_selectedBeneficiary);
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
    if (widget.loadRoster != null || !_viewerIsCreator) {
      _loadRoster();
    }
    if (_nafaqah != null) {
      _loadStoredNafaqah();
    } else if (widget.transaction.householdId.isNotEmpty) {
      _loadNafaqah();
    }
  }

  // ── Who paid / for whom (FABLE2-APP-01) ────────────────────────────────────

  static String _swapRelative(String value) => switch (value) {
        'me' => 'partner',
        'partner' => 'me',
        _ => value,
      };

  String? get _viewerId {
    final reader = widget.currentUserId;
    if (reader != null) return reader()?.toLowerCase();
    try {
      return supabase.auth.currentUser?.id.toLowerCase();
    } catch (_) {
      return null;
    }
  }

  String? get _creatorId {
    final id = widget.transaction.userId?.trim().toLowerCase();
    return (id == null || id.isEmpty) ? null : id;
  }

  /// The viewer recorded the expense (or either is unknown: legacy rows).
  bool get _viewerIsCreator {
    final viewer = _viewerId;
    final creator = _creatorId;
    return viewer == null || creator == null || viewer == creator;
  }

  bool get _isStoredManual =>
      (widget.transaction.storedSource ?? widget.transaction.source).trim().toLowerCase() == 'manual';

  HouseholdRelations get _relations {
    final roster = _roster;
    if (roster != null && roster.members.isNotEmpty) {
      return HouseholdRelations(
        memberIds: roster.members.map((m) => m.userId).toList(),
        husbandId: roster.nafaqahProvider?.userId ?? _nafaqah?.husbandId,
        wifeIds: roster.members.where((m) => m.isSpouse).map((m) => m.userId).toList(),
        rosterComplete: true,
      );
    }
    final summary = _nafaqah;
    return HouseholdRelations(
      husbandId: summary?.husbandId ?? summary?.providerUserId,
      wifeIds: summary?.wives.map((w) => w.id).toList() ?? const [],
    );
  }

  Future<void> _loadRoster() async {
    final householdId = widget.transaction.householdId;
    if (householdId.isEmpty) return;
    try {
      final loader = widget.loadRoster ?? ApiService.instance.getHouseholdMembers;
      final roster = await loader(householdId);
      if (!mounted) return;
      setState(() => _roster = roster);
      if (_canClassify && !_storedNafaqahLoaded) await _loadStoredNafaqah();
    } catch (_) {}
  }

  /// The viewer's admin flag from the [HouseholdRoleProvider] (read once).
  bool? _providerAdmin;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    try {
      final roles = Provider.of<HouseholdRoleProvider>(context, listen: false);
      if (roles.isLoaded && roles.householdId == widget.transaction.householdId && _providerAdmin == null) {
        _providerAdmin = roles.isAdmin;
        if (roles.isAdmin && _nafaqah != null && !_storedNafaqahLoaded) _loadStoredNafaqah();
      }
    } catch (_) {}
  }

  /// Household admin: the explicit flag, the role provider, else what the
  /// API says (`can_set_provider` is for admins; the roster's caller role).
  bool get _isAdmin =>
      widget.isAdmin ??
      _providerAdmin ??
      ((_nafaqah?.canSetProvider ?? false) || (_roster?.callerRole ?? '').toLowerCase() == 'admin');

  /// The member a viewer-relative token names ('me' = the viewer).
  String? _memberOfViewerToken(String token) {
    final viewer = _viewerId;
    if (token == 'me') return viewer;
    if (token == 'partner') return _relations.counterpartOf(viewer);
    return null;
  }

  /// [member] relative to the creator: 'me', 'partner', or null when the
  /// creator's 'partner' is someone else (or unknown).
  String? _creatorRelative(String? member, {String? spouseId}) {
    final creator = _creatorId;
    if (member == null || creator == null) return null;
    final m = member.toLowerCase();
    if (m == creator) return 'me';
    if (m == _relations.counterpartOf(creator)) return 'partner';
    // A classified row is paid by the wife it names: the server takes the
    // payer from nafaqah_spouse_id (several wives, or recorded by an admin).
    if (spouseId != null && m == spouseId.toLowerCase()) return 'partner';
    return null;
  }

  /// The wife a Nafaqah class refers to.
  String? get _classSpouseId => _spouseRole == 'wife'
      ? _nafaqah?.callerUserId
      : (_storedSpouseId ?? _nafaqah?.primaryWife?.id);

  /// Payer to write: the `raw_sms` tail value (a manual row may name a member)
  /// and `spent_by` ('me' | 'partner', relative to the creator). Null when it
  /// cannot be expressed for the creator.
  ({String tail, String spentBy})? _resolvedPayer() {
    if (!_payerTouched) {
      final stored = (widget.transaction.payerRef ?? widget.transaction.paidBy).toLowerCase();
      if (stored == 'me' || stored == 'partner') return (tail: stored, spentBy: stored);
      return (tail: stored, spentBy: _creatorRelative(stored) ?? (stored == _creatorId ? 'me' : 'partner'));
    }
    String? member;
    final cls = _nafaqahClass;
    if (_canClassify && cls != null) {
      member = _classSpouseId; // the wife paid (rules 2 and 3)
    } else if (_canClassify && _spouseRole != null) {
      member = _relations.husbandId; // the husband paid (rule 4)
    }
    if (member == null && _viewerIsCreator) {
      return (tail: _selectedPaidBy, spentBy: _selectedPaidBy);
    }
    member ??= _memberOfViewerToken(_selectedPaidBy);
    final relative = _creatorRelative(member, spouseId: cls != null ? _classSpouseId : null);
    if (relative != null) return (tail: relative, spentBy: relative);
    // A manual row's note may name the paying member; spent_by stays relative.
    if (member != null && _isStoredManual) return (tail: member, spentBy: 'partner');
    return null;
  }

  /// `beneficiary_type` / `beneficiary_id` to write, or null when the
  /// beneficiary cannot be named.
  ({String type, String id})? _resolvedBeneficiary() {
    final tx = widget.transaction;
    if (!_beneficiaryTouched && (tx.beneficiaryId ?? '').trim().isNotEmpty) {
      return (type: tx.beneficiaryType ?? 'household', id: tx.beneficiaryId!.trim());
    }
    final cls = _nafaqahClass;
    if (_canClassify && cls == kWifeReimbursable) return (type: 'household', id: 'household');
    final wife = _classSpouseId;
    if (_canClassify && cls == kWifePersonal && wife != null) return (type: 'individual', id: wife.toLowerCase());
    final ben = _selectedBeneficiary;
    if (ben != 'me' && ben != 'partner') return beneficiaryColumns(ben, creatorId: _creatorId);
    if (_viewerIsCreator) {
      return beneficiaryColumns(ben, creatorId: _creatorId, partnerId: _relations.counterpartOf(_creatorId));
    }
    final member = _memberOfViewerToken(ben);
    return member == null ? null : (type: 'individual', id: member);
  }

  /// The structured columns (and, for a manual row, the rebuilt note tail)
  /// for a changed attribution; null when it cannot be expressed.
  Map<String, dynamic>? _attributionPayload(String merchant) {
    final payer = _resolvedPayer();
    final ben = _resolvedBeneficiary();
    if (payer == null || ben == null) return null;
    return {
      'spent_by': payer.spentBy,
      'beneficiary_type': ben.type,
      'beneficiary_id': ben.id,
      // The server reads a manual row's payer from the end of its note.
      if (_isStoredManual)
        'raw_sms': manualAuditNote(
          head: auditNoteHead(widget.transaction.rawSms, fallback: 'Manual: $merchant'),
          payer: payer.tail,
          beneficiaryId: ben.id,
          spentBy: payer.spentBy,
        ),
    };
  }

  // ── Family mode (Islamic Nafaqah: no spousal split) ────────────────────────

  bool get _isFamily => _nafaqah?.isFamily ?? false;

  /// 'wife' | 'husband' when the viewer is one of the spouses of a family household.
  String? get _spouseRole {
    final role = _isFamily ? _nafaqah!.callerRole : null;
    return (role == 'wife' || role == 'husband') ? role : null;
  }

  /// Only the wife, the Nafaqah provider (husband) or an admin classifies.
  bool get _canClassify => _isFamily && (_spouseRole != null || _isAdmin);

  String? get _nafaqahClass {
    if (!_canClassify) return null;
    if (_spouseRole == null) return _adminClass;
    return classifyNafaqah(_spouseRole, _selectedPaidBy, _selectedBeneficiary);
  }

  /// Maps the Nafaqah choice onto the viewer-relative payer / beneficiary.
  void _applyNafaqahChoice(String? nafaqahClass) {
    if (_spouseRole == null) {
      _adminClass = nafaqahClass;
      if (nafaqahClass == kWifeReimbursable) _selectedBeneficiary = 'both';
      return;
    }
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
    if (!_canClassify) return;
    final tx = widget.transaction;
    try {
      // The feed row already carries the class (UX-23): no second read.
      final Map<String, dynamic>? fields;
      if (tx.hasNafaqahFields) {
        fields = {'nafaqah_class': tx.nafaqahClass, 'nafaqah_spouse_id': tx.nafaqahSpouseId};
      } else {
        final loader = widget.loadNafaqahFields ??
            (String id) => supabase.from('transactions').select('nafaqah_class, nafaqah_spouse_id').eq('id', id).maybeSingle();
        fields = await loader(tx.id);
      }
      if (!mounted) return;
      if (fields == null) {
        // No readable row: nothing stored to keep; the choice follows the entry.
        setState(() {
          _storedNafaqahLoaded = true;
          _storedNafaqahFailed = false;
        });
        return;
      }
      final stored = fields['nafaqah_class'] as String?;
      setState(() {
        _storedSpouseId = fields!['nafaqah_spouse_id'] as String?;
        _applyNafaqahChoice(stored == kWifeReimbursable || stored == kWifePersonal ? stored : null);
        _storedNafaqahLoaded = true;
        _storedNafaqahFailed = false;
      });
    } catch (_) {
      if (mounted) setState(() => _storedNafaqahFailed = true);
    }
  }

  /// The wife the Nafaqah choice names, by display name (UX-03).
  String? get _classWifeName {
    final id = _classSpouseId?.toLowerCase();
    for (final w in _nafaqah?.wives ?? const <NafaqahWife>[]) {
      if (w.id.toLowerCase() == id) {
        final n = (w.displayName ?? '').trim();
        return n.isEmpty ? null : n;
      }
    }
    return null;
  }

  /// The Nafaqah question, or a placeholder until the stored class is known
  /// (UX-23: never a default class that may be wrong).
  Widget _buildNafaqahChoice() {
    if (_storedNafaqahFailed) {
      return Container(
        key: const ValueKey('nafaqah_class_failed'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: context.subtleCardBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: context.borderColor),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded, size: 18, color: context.warnText),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                context.tr('nafaqah_class_load_failed'),
                style: TextStyle(color: context.textPrimary, fontSize: 13),
              ),
            ),
            TextButton(
              key: const ValueKey('nafaqah_class_retry'),
              onPressed: () {
                setState(() => _storedNafaqahFailed = false);
                _loadStoredNafaqah();
              },
              child: Text(context.tr('try_again')),
            ),
          ],
        ),
      );
    }
    if (!_storedNafaqahLoaded) {
      return Semantics(
        label: context.tr('nafaqah_class_loading'),
        child: Container(
          key: const ValueKey('nafaqah_class_loading'),
          height: 160,
          decoration: BoxDecoration(
            color: context.subtleCardBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: context.borderColor),
          ),
        ),
      );
    }
    return NafaqahClassSelector(
      value: _nafaqahClass,
      viewerRole: _spouseRole ?? 'admin',
      wifeName: _spouseRole == 'wife' ? null : _classWifeName,
      husbandName: _nafaqah?.husbandName,
      onChanged: (cls) {
        HapticFeedback.selectionClick();
        setState(() {
          _applyNafaqahChoice(cls);
          _payerTouched = true;
          _beneficiaryTouched = true;
        });
      },
    );
  }

  Map<String, dynamic> _nafaqahPayload() {
    // Unknown stored class (still loading or unreadable): never rewrite it.
    if (!_canClassify || !_storedNafaqahLoaded) return const {};
    final cls = _nafaqahClass;
    final spouseId = _classSpouseId;
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

  Future<void> _updateRow(Map<String, dynamic> values) async {
    final update = widget.updateRow;
    if (update != null) return update(widget.transaction.id, values);
    await supabase.from('transactions').update(values).eq('id', widget.transaction.id);
  }

  Future<void> _deleteRow() async {
    final delete = widget.deleteRow;
    if (delete != null) return delete(widget.transaction.id);
    await supabase.from('transactions').delete().eq('id', widget.transaction.id);
  }

  Future<void> _saveChanges() async {
    final rounded = roundedMoneyTextIfRounded(_amountCtrl.text);
    if (rounded != null) _amountCtrl.text = rounded; // show the amount that is stored
    final amount = parseMoneyInput(_amountCtrl.text, allowNegative: false);
    if (amount == null || amount <= 0) {
      AppSnackBar.showError(context, context.tr('invalid_amount_msg'), title: context.tr('invalid_amount'));
      return;
    }

    final merchant = _merchantCtrl.text.trim();
    final values = <String, dynamic>{
      'merchant': merchant,
      'amount': amount,
      'category_code': _selectedCategory,
      'sub_category': _selectedSubCategory,
      'items': _items,
      if (_dateTouched && _occurredAt != widget.transaction.timestamp)
        'timestamp': _occurredAt.toUtc().toIso8601String(),
      ..._nafaqahPayload(),
    };
    // Who paid / for whom: only when the user changed it, and only in the
    // columns the server reads (FABLE2-APP-01). There is no paid_by or
    // beneficiary column, so there is no second, note-only attempt.
    if (_payerTouched || _beneficiaryTouched) {
      final attribution = _attributionPayload(merchant);
      if (attribution == null) {
        AppSnackBar.showError(context, context.tr('tx_attr_unresolvable'), title: context.tr('update_error'));
        return;
      }
      values.addAll(attribution);
    }

    setState(() => _isSaving = true);

    try {
      await _updateRow(values);

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
          nafaqahWriteErrorText(context, e) ??
              (HouseholdPermissions.isPermissionDenied(e)
                  ? context.tr('perm_tx_admin_only')
                  : context.trArgs('tx_update_failed_msg', {'error': e})),
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
      await _deleteRow();
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
          nafaqahWriteErrorText(context, e) ??
              (HouseholdPermissions.isPermissionDenied(e)
                  ? context.tr('perm_tx_admin_only')
                  : context.trArgs('tx_delete_failed_err', {'error': e})),
          title: context.tr('delete_error'),
        );
      }
    }
  }

  Widget _buildCyclePill({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? context.primaryButtonBg : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? context.accentText : context.borderColor,
            width: isSelected ? 1.4 : 1.0,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? context.primaryButtonFg : context.textSecondary,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
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
                  color: isSelected ? (context.textPrimary) : context.textSecondary,
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
      color = context.textSecondary;
    } else if (_selectedPaidBy == 'me' && _selectedBeneficiary == 'partner') {
      text = context.trArgs('settle_paid_for_partner', {'amount': context.sar(amount)});
      icon = Icons.volunteer_activism_outlined;
      color = context.accentText;
    } else if (_selectedPaidBy == 'partner' && _selectedBeneficiary == 'both') {
      final half = amount * 0.5;
      text = context.trArgs('settle_shared_you_owe', {'amount': context.sar(half)});
      icon = Icons.handshake_outlined;
      color = context.warnText;
    } else if (_selectedPaidBy == 'partner' && _selectedBeneficiary == 'me') {
      text = context.trArgs('settle_partner_paid_for_you', {'amount': context.sar(amount)});
      icon = Icons.card_giftcard_rounded;
      color = context.dangerColor;
    } else if (_selectedPaidBy == 'me' && _selectedBeneficiary == 'me') {
      text = context.tr('settle_personal_me');
      icon = Icons.person_outline;
      color = context.accentText;
    } else {
      text = context.tr('settle_personal_partner');
      icon = Icons.favorite_outline;
      color = context.accentText;
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
                      _buildProviderRadio('Bank / Other', context.accentText, selectedProvider, (p) {
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
                                color: isSelected ? (context.pillBg) : context.subtleCardBg,
                                border: Border.all(
                                  color: isSelected ? (context.accentText) : context.borderColor,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                context.trPlural('n_months', count),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: isSelected ? (context.accentText) : context.textPrimary,
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
                      backgroundColor: context.primaryButtonBg,
                      foregroundColor: Colors.white,
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
                          AppSnackBar.showError(
                            sheetCtx,
                            nafaqahWriteErrorText(sheetCtx, e) ?? sheetCtx.trArgs('bnpl_convert_failed_msg', {'error': e}),
                            title: sheetCtx.tr('conversion_failed'),
                          );
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
            Icon(Icons.child_care_rounded, color: context.accentText),
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
            hintStyle: TextStyle(color: context.textSecondary),
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
            style: ElevatedButton.styleFrom(
              backgroundColor: context.primaryButtonBg,
              foregroundColor: Colors.white,
            ),
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
          _beneficiaryTouched = true;
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
                  Icon(Icons.credit_score_rounded, color: context.warnText, size: 20),
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
                    child: Text(context.tr('convert'), style: TextStyle(color: context.accentText, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Date & Cycle Attribution
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.subtleCardBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: context.borderColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.calendar_month_rounded, size: 16, color: context.accentText),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          context.tr('change_cycle_date'),
                          style: GoogleFonts.outfit(
                            color: context.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Quick Cycle Pills
                      _buildCyclePill(
                        label: context.tr('current_cycle'),
                        isSelected: _targetCycle.key == _currentCycle.key,
                        onTap: () => setState(() {
                          _occurredAt = DateTime.now();
                          _dateTouched = true;
                        }),
                      ),
                      const SizedBox(width: 6),
                      _buildCyclePill(
                        label: context.tr('previous_cycle'),
                        isSelected: _targetCycle.key == _previousCycle.key,
                        onTap: () => setState(() {
                          _occurredAt = _previousCycle.end;
                          _dateTouched = true;
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ExpenseDateChips(
                    value: _occurredAt,
                    maxDaysBack: 365,
                    onChanged: (d) => setState(() {
                      _occurredAt = d;
                      _dateTouched = true;
                    }),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: context.cardBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: context.borderColor),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.bolt_rounded, size: 14, color: context.accentText),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            context.trArgs('books_to_cycle', {
                              'cycle': '${context.cycleRange(_targetCycle.start, _targetCycle.end)} (${_targetCycle.key})',
                            }),
                            style: TextStyle(
                              color: context.accentText,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Category Dropdown
            DropdownButtonFormField<String>(
              initialValue: _selectedCategory,
              dropdownColor: context.cardBg,
              style: TextStyle(color: context.textPrimary),
              decoration: InputDecoration(
                labelText: context.tr('category'),
                labelStyle: TextStyle(color: context.textSecondary),
                filled: true,
                fillColor: context.inputBg,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              items: CategoryCatalog.pickerCodesIncluding(_selectedCategory).map((code) {
                return DropdownMenuItem(
                  value: code,
                  child: Text(context.trCat(code)),
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

            // ── WHO PAID? / FOR WHOM? (roommates and partners) ───────────
            // A family household answers one Nafaqah question instead (UX-03).
            if (!_isFamily) ...[
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
                  activeColor: context.accentText,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _selectedPaidBy = 'me';
                      _payerTouched = true;
                    });
                  },
                ),
                const SizedBox(width: 8),
                _buildSegmentOption(
                  isSelected: _selectedPaidBy == 'partner',
                  title: context.tr('partner_paid'),
                  icon: Icons.favorite_outline,
                  activeColor: context.accentText,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _selectedPaidBy = 'partner';
                      _payerTouched = true;
                    });
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
                  activeColor: context.accentText,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _selectedBeneficiary = 'me';
                      _beneficiaryTouched = true;
                    });
                  },
                ),
                const SizedBox(width: 8),
                _buildSegmentOption(
                  isSelected: _selectedBeneficiary == 'partner',
                  title: context.tr('partner'),
                  icon: Icons.favorite_outline,
                  activeColor: context.accentText,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _selectedBeneficiary = 'partner';
                      _beneficiaryTouched = true;
                    });
                  },
                ),
                const SizedBox(width: 8),
                _buildSegmentOption(
                  isSelected: _selectedBeneficiary == 'both',
                  title: context.tr('both_shared'),
                  icon: Icons.people_alt_outlined,
                  activeColor: context.textSecondary,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _selectedBeneficiary = 'both';
                      _beneficiaryTouched = true;
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 14),
            ],
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
                        Icon(Icons.add_rounded, size: 14, color: context.accentText),
                        const SizedBox(width: 2),
                        Text(
                          context.tr('add_child'),
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: context.accentText,
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
                    avatar: Icon(Icons.child_care_rounded, size: 14, color: context.champagneGold),
                    selected: isSelected,
                    selectedColor: context.champagneGold.withValues(alpha: 0.2),
                    backgroundColor: context.chipBg,
                    labelStyle: TextStyle(
                      color: isSelected ? context.champagneGold : context.textPrimary,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      fontSize: 12,
                    ),
                    side: BorderSide(
                      color: isSelected ? context.champagneGold : context.borderColor,
                    ),
                    onSelected: (selected) {
                      HapticFeedback.selectionClick();
                      setState(() {
                        _selectedBeneficiary = selected ? depName : 'both';
                        _beneficiaryTouched = true;
                      });
                    },
                  );
                }).toList(),
              ),
            const SizedBox(height: 10),

            // Only the wife, the provider (husband) or an admin classifies.
            if (_canClassify) ...[
              _buildNafaqahChoice(),
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
                  icon: Icon(Icons.add, size: 16, color: context.accentText),
                  label: Text(context.tr('add_item'), style: TextStyle(color: context.accentText, fontSize: 12)),
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
                        style: TextStyle(color: context.accentText, fontSize: 13, fontWeight: FontWeight.w600),
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
                backgroundColor: context.primaryButtonBg,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _isSaving ? null : _saveChanges,
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
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
