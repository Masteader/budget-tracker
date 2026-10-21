import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../main.dart';
import '../../providers/budget_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../services/offline_sync_service.dart';
import '../../services/sync_worker.dart' show SyncWorker, kTransactionInsertOperation;
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../../models/manual_expense_row.dart';
import 'package:uuid/uuid.dart';
import '../../models/account.dart';
import '../../models/household_membership.dart';
import '../../services/account_service.dart';
import '../../services/api_service.dart';
import '../../services/nafaqah_write_errors.dart';
import '../../theme/app_themes.dart';
import '../app_snackbar.dart';
import '../nafaqah/nafaqah_class_selector.dart';
import '../../models/nafaqah.dart';
import '../../models/money.dart';

/// Modal bottom sheet for logging a manual expense quickly.
class ManualExpenseSheet extends StatefulWidget {
  final String? householdId;
  final String? initialMerchant;
  final double? initialAmount;
  final String? initialCategory;

  /// Test seams; default to the API / Supabase / the offline queue.
  /// [loadMembers] replaces the whole member lookup (rows with `id`,
  /// `display_name`, `role`, `financial_role`).
  final Future<List<Map<String, dynamic>>> Function(String householdId)? loadMembers;

  /// `GET /households/{id}/members` (roles per household membership).
  final Future<HouseholdRoster> Function(String householdId)? loadRoster;

  /// Fallback when the API fails: the caller's own `household_memberships`
  /// row(s) of this household (RLS shows admins every row). Never
  /// `users.financial_role`, which belongs to each member's active household.
  final Future<List<Map<String, dynamic>>> Function(String householdId)? loadOwnMemberships;
  final Future<void> Function(Map<String, dynamic> row)? insertRow;
  final Future<void> Function(Map<String, dynamic> row, String householdId)? enqueueRow;
  final String? Function()? currentUserId;
  final Future<NafaqahSummary> Function(String householdId)? loadNafaqah;

  const ManualExpenseSheet({
    super.key,
    this.householdId,
    this.initialMerchant,
    this.initialAmount,
    this.initialCategory,
    this.loadMembers,
    this.loadRoster,
    this.loadOwnMemberships,
    this.insertRow,
    this.enqueueRow,
    this.currentUserId,
    this.loadNafaqah,
  });

  static Future<void> show(
    BuildContext context, {
    String? householdId,
    String? initialMerchant,
    double? initialAmount,
    String? initialCategory,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: ManualExpenseSheet(
          householdId: householdId,
          initialMerchant: initialMerchant,
          initialAmount: initialAmount,
          initialCategory: initialCategory,
        ),
      ),
    );
  }

  @override
  State<ManualExpenseSheet> createState() => _ManualExpenseSheetState();
}

class _ManualExpenseSheetState extends State<ManualExpenseSheet> {
  late final TextEditingController _merchantCtrl;
  late final TextEditingController _amountCtrl;
  late String _selectedCategory;
  bool _isSaving = false;

  // Role-Aware Attribution & Living Model State
  bool _isRoommateMode = false;
  String _familyPayer = 'me'; // 'me' (husband paid), 'wife_reimbursable', 'wife_personal'
  bool _viewerIsWife = false;
  List<Map<String, dynamic>> _wives = [];
  String? _selectedWifeId;
  bool _canClassifyNafaqah = true;
  String? _selectedRoommateId;
  String _roommateSplit = 'all'; // 'all' (equal split) | 'personal'
  List<Map<String, dynamic>> _householdMembers = [];
  List<Account> _accounts = [];
  String? _selectedAccountId;

  static const List<Map<String, String>> _categories = [
    {'code': 'OPEX-GROCERY', 'emoji': '🛒 '},
    {'code': 'OPEX-DINING', 'emoji': '☕ '},
    {'code': 'OPEX-SHOPPING', 'emoji': '🛍️ '},
    {'code': 'OPEX-UTILITIES', 'emoji': '⚡ '},
    {'code': 'OPEX-FUEL', 'emoji': '⛽ '},
    {'code': 'OPEX-ENTERTAINMENT', 'emoji': '🎮 '},
    {'code': 'OPEX-HEALTH', 'emoji': '💊 '},
    {'code': 'CAPEX-EDUCATION', 'emoji': '🎓 '},
    {'code': 'OPEX-GOV', 'emoji': '🏛️ '},
    {'code': 'OPEX-MISC', 'emoji': '📦 '},
  ];

  @override
  void initState() {
    super.initState();
    _merchantCtrl = TextEditingController(text: widget.initialMerchant ?? '');
    _amountCtrl = TextEditingController(
      text: widget.initialAmount != null && widget.initialAmount! > 0
          ? widget.initialAmount!.toStringAsFixed(2)
          : '',
    );
    _selectedCategory = widget.initialCategory ?? 'OPEX-GROCERY';
    _loadHouseholdMembers();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    final hid = widget.householdId;
    if (hid == null || hid.isEmpty) return;
    try {
      final list = await AccountService.instance.getAccounts(hid);
      if (mounted) {
        setState(() {
          _accounts = list;
        });
        await _updateDefaultAccountForCategory(_selectedCategory);
        if (_selectedAccountId == null && list.isNotEmpty && mounted) {
          setState(() {
            _selectedAccountId = list.first.id;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _updateDefaultAccountForCategory(String categoryCode) async {
    final hid = widget.householdId;
    if (hid == null || hid.isEmpty) return;
    try {
      final bRes = await supabase
          .from('budgets')
          .select('account_id')
          .eq('household_id', hid)
          .eq('category_code', categoryCode)
          .not('account_id', 'is', null)
          .maybeSingle();
      if (bRes != null && bRes['account_id'] != null && mounted) {
        final accId = bRes['account_id'] as String;
        if (_accounts.any((a) => a.id == accId)) {
          setState(() => _selectedAccountId = accId);
        }
      }
    } catch (_) {}
  }

  Future<void> _loadHouseholdMembers() async {
    final hid = widget.householdId;
    if (hid == null || hid.isEmpty) return;
    try {
      final List<Map<String, dynamic>> list =
          widget.loadMembers != null ? await widget.loadMembers!(hid) : await _membersOfHousehold(hid);
      if (mounted) {
        final hasPeers = list.any((m) => (m['financial_role'] as String?)?.toLowerCase() == 'peer');
        final hasSpouse = list.any((m) => (m['financial_role'] as String?)?.toLowerCase() == 'spouse');
        final uid = _currentUserId;
        setState(() {
          _householdMembers = list;
          _isRoommateMode = hasPeers && !hasSpouse;
          _wives = list.where((m) => (m['financial_role'] as String?)?.toLowerCase() == 'spouse').toList();
          _viewerIsWife = _wives.any((w) => w['id'] == uid);
          _selectedWifeId = _viewerIsWife ? uid : (_wives.isNotEmpty ? _wives.first['id'] as String? : null);
          // The wife records mostly what she paid herself; shared is the default so
          // her claim is never lost silently (the husband sees and can dispute it).
          if (_viewerIsWife && _familyPayer == 'me') _familyPayer = kWifeReimbursable;
          if (_isRoommateMode && list.isNotEmpty) {
            final uid = _currentUserId;
            final myMember = list.firstWhere(
              (m) => m['id'] == uid,
              orElse: () => list.first,
            );
            _selectedRoommateId = myMember['id'] as String?;
          }
        });
      }
    } catch (_) {}
    await _loadNafaqahContext(hid);
  }

  /// Members with their financial role in THIS household, from
  /// `GET /households/{id}/members`. A member whose active household is
  /// another one keeps the role of this household (a wife stays the wife, a
  /// roommate elsewhere is not a spouse here). If the API fails, only the
  /// membership rows the caller may read are used, so a spouse is never
  /// invented from another household's role.
  Future<List<Map<String, dynamic>>> _membersOfHousehold(String hid) async {
    try {
      final loadRoster = widget.loadRoster ?? ApiService.instance.getHouseholdMembers;
      final roster = await loadRoster(hid);
      return [
        for (final m in roster.members)
          {'id': m.userId, 'display_name': m.displayName, 'role': m.role, 'financial_role': m.financialRole},
      ];
    } catch (e) {
      debugPrint('[ManualExpenseSheet] Members API unavailable, using own membership: $e');
    }
    final rows = widget.loadOwnMemberships != null
        ? await widget.loadOwnMemberships!(hid)
        : List<Map<String, dynamic>>.from(await supabase
            .from('household_memberships')
            .select('user_id, role, financial_role')
            .eq('household_id', hid));
    return [
      for (final r in rows)
        {'id': r['user_id'], 'display_name': null, 'role': r['role'], 'financial_role': r['financial_role']},
    ];
  }

  /// The family context from `GET /households/{id}/nafaqah`, the same source as
  /// the chat, receipt and edit flows (household memberships, not the
  /// `users.household_id` of each member's *active* household). Offline, the
  /// member list above stays in effect (FR-A-07).
  Future<void> _loadNafaqahContext(String hid) async {
    try {
      final loader = widget.loadNafaqah ?? ApiService.instance.getNafaqahSummary;
      final summary = await loader(hid);
      if (!mounted) return;
      setState(() {
        if (!summary.isFamily) {
          _wives = [];
          _viewerIsWife = false;
          _selectedWifeId = null;
          if (_familyPayer != 'me') _familyPayer = 'me';
          return;
        }
        _isRoommateMode = false;
        _wives = [
          for (final w in summary.wives) {'id': w.id, 'display_name': w.displayName},
        ];
        _viewerIsWife = summary.callerIsWife;
        // Only the husband or a wife records a Nafaqah class (as in chat/receipts).
        _canClassifyNafaqah = summary.callerRole == 'husband' || summary.callerRole == 'wife';
        if (!_canClassifyNafaqah) _familyPayer = 'me';
        final uid = summary.callerUserId ?? _currentUserId;
        _selectedWifeId = _viewerIsWife ? uid : summary.wives.first.id;
        if (_viewerIsWife && _familyPayer == 'me') _familyPayer = kWifeReimbursable;
      });
    } catch (e) {
      debugPrint('[ManualExpenseSheet] Nafaqah context unavailable: $e');
    }
  }

  /// Family household (a member is a spouse): Nafaqah rules, never a split.
  bool get _hasSpouse => _wives.isNotEmpty;

  String? get _currentUserId =>
      widget.currentUserId != null ? widget.currentUserId!() : supabase.auth.currentUser?.id;

  /// Best-effort refresh; a missing provider must not turn a saved expense
  /// into a second (offline) save.
  void _refreshProviders() {
    try {
      context.read<TransactionProvider>().fetchTransactions();
      context.read<BudgetProvider>().refresh();
    } catch (e) {
      debugPrint('[ManualExpenseSheet] Refresh after save skipped: $e');
    }
  }

  @override
  void dispose() {
    _merchantCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveExpense() async {
    final rounded = roundedMoneyTextIfRounded(_amountCtrl.text);
    if (rounded != null) _amountCtrl.text = rounded; // show the amount that is stored
    final amount = parseMoneyInput(_amountCtrl.text, allowNegative: false) ?? 0.0;
    final merchant = _merchantCtrl.text.trim();

    if (amount <= 0) {
      AppSnackBar.showError(context, context.tr('ris_invalid_amount'));
      return;
    }
    if (merchant.isEmpty) {
      AppSnackBar.showError(context, context.tr('mes_merchant_required'));
      return;
    }

    setState(() => _isSaving = true);
    final hid = widget.householdId ?? '';

    // Determine role-aware attribution fields
    final String paidBy;
    final String benType;
    final String benId;
    final String spentBy;
    String? nafaqahClass;

    if (_isRoommateMode) {
      paidBy = _selectedRoommateId ?? _currentUserId ?? 'me';
      benType = _roommateSplit == 'all' ? 'all_peers' : 'individual';
      benId = _roommateSplit == 'all' ? 'all_peers' : (_selectedRoommateId ?? 'me');
      spentBy = _roommateSplit == 'all' ? 'both' : 'me';
    } else {
      // Family (Islamic Nafaqah): never split between the spouses. The payer is
      // stored relative to the recorder ('me'), the wife is 'wife' otherwise.
      final wifeSide = _viewerIsWife ? 'me' : 'wife';
      if (_familyPayer == kWifeReimbursable) {
        paidBy = wifeSide;
        benType = 'household';
        benId = 'household';
        spentBy = _viewerIsWife ? 'me' : 'partner';
        nafaqahClass = kWifeReimbursable;
      } else if (_familyPayer == kWifePersonal) {
        paidBy = wifeSide;
        benType = 'individual';
        benId = wifeSide;
        spentBy = _viewerIsWife ? 'me' : 'partner';
        nafaqahClass = kWifePersonal;
      } else {
        paidBy = _viewerIsWife ? 'husband' : 'me';
        benType = 'household';
        benId = 'household';
        spentBy = _viewerIsWife ? 'partner' : 'me';
      }
    }

    final row = buildManualExpenseRow(
      id: const Uuid().v4(),
      householdId: hid,
      userId: _currentUserId,
      amount: amount,
      merchant: merchant,
      categoryCode: _selectedCategory,
      spentBy: spentBy,
      paidBy: paidBy,
      beneficiaryType: benType,
      beneficiaryId: benId,
      accountId: _selectedAccountId,
      occurredAt: DateTime.now(),
      nafaqahClass: nafaqahClass,
      nafaqahSpouseId: nafaqahClass == null ? null : _selectedWifeId,
    );

    Object? insertError;
    try {
      // 1. Direct Supabase insert
      if (widget.insertRow != null) {
        await widget.insertRow!(row);
      } else {
        await supabase.from('transactions').insert(row);
      }
    } catch (e) {
      insertError = e;
    }

    if (insertError == null) {
      if (mounted) {
        _refreshProviders();
        Navigator.pop(context);
        AppSnackBar.showSuccess(
          context,
          context.trArgs('mes_recorded', {'amount': context.sar(amount), 'merchant': merchant}),
          title: context.tr('mes_logged_title'),
        );
      }
    } else if (SyncWorker.isPermanentInsertError(insertError)) {
      // FR-A-08: the database rejected the row itself (permissions, a check,
      // the Nafaqah trigger). Replaying it can never succeed, so say so and
      // keep the sheet open instead of reporting "saved offline".
      if (mounted) {
        setState(() => _isSaving = false);
        AppSnackBar.showError(
          context,
          nafaqahWriteErrorText(context, insertError) ??
              context.trArgs('mes_failed', {
                'error': insertError is PostgrestException ? insertError.message : insertError,
              }),
        );
      }
    } else {
      // 2. Offline fallback queue
      try {
        // Replayed verbatim later; the client-generated id makes the replay
        // idempotent if the insert above actually reached the server.
        if (widget.enqueueRow != null) {
          await widget.enqueueRow!(row, hid);
        } else {
          await OfflineSyncService.instance.enqueue(
            endpoint: kTransactionInsertOperation,
            payload: row,
            householdId: hid,
            customId: row['id'] as String,
          );
        }

        if (mounted) {
          _refreshProviders();
          Navigator.pop(context);
          AppSnackBar.showSuccess(
            context,
            context.trArgs('mes_saved_offline', {'amount': context.sar(amount), 'merchant': merchant}),
            title: context.tr('mp_queued_offline'),
            icon: Icons.cloud_off_rounded,
          );
        }
      } catch (err) {
        // MOB-28: the queue write failed, so nothing was saved anywhere; keep
        // the sheet open with the entered values so the user can retry.
        if (mounted) {
          setState(() => _isSaving = false);
          AppSnackBar.showError(
            context,
            context.trArgs('mes_failed', {
              'error': err is OfflineQueueWriteException ? context.tr('offline_queue_failed') : err,
            }),
            title: context.tr('offline_queue_failed_title'),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: context.borderColor),
          left: BorderSide(color: context.borderColor),
          right: BorderSide(color: context.borderColor),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFA657).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.edit_note_rounded, color: Color(0xFFFFA657), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      context.tr('manual_log'),
                      style: GoogleFonts.outfit(
                        color: context.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: context.tr('close'),
                    icon: Icon(Icons.close_rounded, color: context.textSecondary),
                    onPressed: () => Navigator.pop(context),
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
                  prefixIcon: Icon(Icons.storefront_outlined, color: context.textSecondary, size: 20),
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
                style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
                decoration: InputDecoration(
                  labelText: context.tr('amount_sar'),
                  prefixText: '${context.tr('sar')} ',
                  labelStyle: TextStyle(color: context.textSecondary),
                  prefixIcon: const Icon(Icons.attach_money_rounded, color: AppThemes.success, size: 20),
                  filled: true,
                  fillColor: context.inputBg,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),

              // Category
              DropdownButtonFormField<String>(
                initialValue: _selectedCategory,
                dropdownColor: context.cardBg,
                style: TextStyle(color: context.textPrimary),
                decoration: InputDecoration(
                  labelText: context.tr('category'),
                  labelStyle: TextStyle(color: context.textSecondary),
                  prefixIcon: Icon(Icons.category_outlined, color: context.textSecondary, size: 20),
                  filled: true,
                  fillColor: context.inputBg,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                items: _categories.map((c) {
                  final code = c['code']!;
                  final emoji = c['emoji']!;
                  return DropdownMenuItem(
                    value: code,
                    child: Text('$emoji${context.trCat(code)}'),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedCategory = val);
                    _updateDefaultAccountForCategory(val);
                  }
                },
              ),
              const SizedBox(height: 12),

              // Payment Account Dropdown
              if (_accounts.isNotEmpty) ...[
                DropdownButtonFormField<String>(
                  initialValue: _selectedAccountId,
                  dropdownColor: context.cardBg,
                  style: TextStyle(color: context.textPrimary),
                  decoration: InputDecoration(
                    labelText: context.tr('payment_account'),
                    labelStyle: TextStyle(color: context.textSecondary),
                    prefixIcon: Icon(Icons.account_balance_wallet_outlined, color: context.electricTeal, size: 20),
                    filled: true,
                    fillColor: context.inputBg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  items: _accounts.map((acc) {
                    return DropdownMenuItem<String>(
                      value: acc.id,
                      child: Row(
                        children: [
                          Icon(acc.accountType.defaultIcon, size: 16, color: context.electricTeal),
                          const SizedBox(width: 8),
                          Text('${acc.name} (${acc.currency} ${acc.balance.toStringAsFixed(2)})'),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedAccountId = val);
                  },
                ),
                const SizedBox(height: 16),
              ] else ...[
                const SizedBox(height: 4),
              ],

              // Paid By & Responsibility Attribution
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      context.tr('paid_by_label'),
                      style: TextStyle(
                        color: context.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  // A household with a spouse is a family (Nafaqah): there is
                  // no roommate equal split between the spouses (FR-A-05).
                  if (!_hasSpouse)
                  Container(
                    key: const ValueKey('manual_mode_toggle'),
                    decoration: BoxDecoration(
                      color: context.subtleCardBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: context.borderColor),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildModeTogglePill(
                          label: context.tr('household_model_family'),
                          icon: Icons.family_restroom_rounded,
                          isSelected: !_isRoommateMode,
                          onTap: () => setState(() => _isRoommateMode = false),
                        ),
                        _buildModeTogglePill(
                          label: context.tr('household_model_roommates'),
                          icon: Icons.groups_rounded,
                          isSelected: _isRoommateMode,
                          onTap: () => setState(() => _isRoommateMode = true),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              if (!_isRoommateMode && _hasSpouse && _canClassifyNafaqah) ...[
                // Family Islamic Nafaqah: husband's expense, wife's shared
                // advance (husband reimburses) or wife's personal purchase.
                NafaqahClassSelector(
                  value: _familyPayer == 'me' ? null : _familyPayer,
                  viewerIsWife: _viewerIsWife,
                  onChanged: (cls) => setState(() => _familyPayer = cls ?? 'me'),
                ),
                if (_familyPayer != 'me' && !_viewerIsWife && _wives.length > 1) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: _wives.map((w) {
                      final wid = w['id'] as String? ?? '';
                      final name = (w['display_name'] as String?)?.isNotEmpty == true
                          ? w['display_name'] as String
                          : context.tr('wife_spouse_title');
                      return ChoiceChip(
                        label: Text(name),
                        selected: _selectedWifeId == wid,
                        onSelected: (sel) {
                          if (sel) setState(() => _selectedWifeId = wid);
                        },
                      );
                    }).toList(),
                  ),
                ],
              ] else if (_isRoommateMode) ...[
                // Multi-Roommate Living Mode
                if (_householdMembers.isNotEmpty) ...[
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      context.tr('mes_select_payer'),
                      style: TextStyle(
                        color: context.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _householdMembers.map((m) {
                        final mid = m['id'] as String? ?? '';
                        final name = (m['display_name'] as String?)?.isNotEmpty == true
                            ? m['display_name'] as String
                            : context.tr('role_roommate');
                        final isSelected = _selectedRoommateId == mid;
                        return Padding(
                          padding: const EdgeInsetsDirectional.only(end: 8),
                          child: ChoiceChip(
                            label: Text(name),
                            selected: isSelected,
                            onSelected: (sel) {
                              if (sel) setState(() => _selectedRoommateId = mid);
                            },
                            selectedColor: AppThemes.success.withValues(alpha: 0.2),
                            backgroundColor: context.subtleCardBg,
                            labelStyle: TextStyle(
                              color: isSelected
                                  ? (context.isDark ? AppThemes.electricTeal : const Color(0xFF00A87A))
                                  : context.textSecondary,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              fontSize: 11.5,
                            ),
                            side: BorderSide(
                              color: isSelected ? AppThemes.success : context.borderColor,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Row(
                  children: [
                    _buildSegmentOption(
                      isSelected: _roommateSplit == 'all',
                      label: context.tr('roommate_split_all'),
                      icon: Icons.groups_rounded,
                      activeColor: AppThemes.success,
                      onTap: () => setState(() => _roommateSplit = 'all'),
                    ),
                    const SizedBox(width: 8),
                    _buildSegmentOption(
                      isSelected: _roommateSplit == 'personal',
                      label: context.tr('roommate_split_personal'),
                      icon: Icons.lock_outline_rounded,
                      activeColor: AppThemes.iceCyan,
                      onTap: () => setState(() => _roommateSplit = 'personal'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: (_roommateSplit == 'all'
                            ? AppThemes.success
                            : AppThemes.iceCyan)
                        .withValues(alpha: context.isDark ? 0.12 : 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: (_roommateSplit == 'all'
                              ? AppThemes.success
                              : AppThemes.iceCyan)
                          .withValues(alpha: context.isDark ? 0.35 : 0.25),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _roommateSplit == 'all' ? Icons.pie_chart_outline_rounded : Icons.lock_outline_rounded,
                        size: 15,
                        color: _roommateSplit == 'all' ? AppThemes.success : AppThemes.iceCyan,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _roommateSplit == 'all'
                              ? context.tr('roommate_split_all_hint')
                              : context.tr('roommate_split_personal_hint'),
                          style: GoogleFonts.outfit(
                            color: context.textPrimary,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),

              // Save Button
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppThemes.success,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _isSaving ? null : _saveExpense,
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.check_rounded, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            context.tr('record_expense'),
                            style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeTogglePill({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? (context.isDark ? AppThemes.success : const Color(0xFF00A87A))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 12,
              color: isSelected ? Colors.black : context.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.black : context.textSecondary,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSegmentOption({
    required bool isSelected,
    required String label,
    required IconData icon,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
          decoration: BoxDecoration(
            color: isSelected ? activeColor.withValues(alpha: context.isDark ? 0.18 : 0.12) : context.subtleCardBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? activeColor : context.borderColor,
              width: isSelected ? 1.4 : 1.0,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: isSelected ? activeColor : context.textSecondary),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isSelected ? activeColor : context.textSecondary,
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
