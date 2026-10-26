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
import 'expense_date_chips.dart';
import '../../models/nafaqah.dart';
import '../../models/money.dart';
import '../../models/category_catalog.dart';

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
  final Future<List<Account>> Function(String householdId)? loadAccounts;

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
    this.loadAccounts,
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

  /// When the expense happened (UX-12): today by default, or a past day.
  DateTime _occurredAt = DateTime.now();
  bool _datePicked = false;

  // Role-Aware Attribution & Living Model State
  bool _isRoommateMode = false;
  String _familyPayer = 'me'; // 'me' (husband paid), 'wife_reimbursable', 'wife_personal'
  bool _viewerIsWife = false;
  List<Map<String, dynamic>> _wives = [];
  String? _selectedWifeId;
  String? _husbandName;
  /// Only the wife, the Nafaqah provider (husband) or an admin classifies a
  /// family expense; unknown until the members or the summary are loaded.
  bool _canClassifyNafaqah = false;

  /// The viewer classifies as an admin who is neither spouse: a class then
  /// names the wife who paid by her member id.
  bool _adminClassifier = false;
  String? _selectedRoommateId;
  String _roommateSplit = 'all'; // 'all' (equal split) | 'personal'
  List<Map<String, dynamic>> _householdMembers = [];
  List<Account> _accounts = [];
  String? _selectedAccountId;

  static final List<Map<String, String>> _categories = [
    for (final code in CategoryCatalog.pickerCodes) {'code': code, 'emoji': CategoryCatalog.emoji(code)},
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
      final list = widget.loadAccounts != null
          ? await widget.loadAccounts!(hid)
          : await AccountService.instance.getAccounts(hid);
      if (mounted) {
        setState(() {
          _accounts = list;
        });
        await _updateDefaultAccountForCategory(_selectedCategory);
        if (_selectedAccountId == null && list.isNotEmpty && mounted) {
          final defaultAcc = list.where((a) => a.accountType.isOperatingPool).firstOrNull ?? list.first;
          setState(() {
            _selectedAccountId = defaultAcc.id;
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
          final me = list.where((m) => m['id'] == uid).firstOrNull;
          final myFinancialRole = (me?['financial_role'] as String?)?.toLowerCase();
          final iAmAdmin = (me?['role'] as String?)?.toLowerCase() == 'admin';
          _canClassifyNafaqah = _viewerIsWife || myFinancialRole == 'provider' || iAmAdmin;
          _adminClassifier = _canClassifyNafaqah && !_viewerIsWife && myFinancialRole != 'provider';
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
        _husbandName = summary.husbandName;
        // Only the wife, the provider (husband) or an admin records a Nafaqah
        // class (as in chat, receipts and the edit sheet). `can_set_provider`
        // is true for household admins.
        final isSpouse = summary.callerRole == 'husband' || summary.callerRole == 'wife';
        final isAdmin = summary.canSetProvider ||
            _householdMembers.any((m) => m['id'] == _currentUserId && (m['role'] as String?)?.toLowerCase() == 'admin');
        _canClassifyNafaqah = isSpouse || isAdmin;
        _adminClassifier = _canClassifyNafaqah && !isSpouse;
        if (!_canClassifyNafaqah) _familyPayer = 'me';
        final uid = summary.callerUserId ?? _currentUserId;
        _selectedWifeId = _viewerIsWife ? uid : summary.wives.first.id;
        if (_viewerIsWife && _familyPayer == 'me') _familyPayer = kWifeReimbursable;
      });
    } catch (e) {
      debugPrint('[ManualExpenseSheet] Nafaqah context unavailable: $e');
    }
  }

  /// The display name of the chosen wife, or null.
  String? get _selectedWifeName {
    for (final w in _wives) {
      if (w['id'] == _selectedWifeId) {
        final n = (w['display_name'] as String? ?? '').trim();
        return n.isEmpty ? null : n;
      }
    }
    return null;
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

    // Zero-Balance Overdraft Guard: prevent spending more than available account balance.
    if (_selectedAccountId != null && _accounts.isNotEmpty) {
      final selectedAcc = _accounts.where((a) => a.id == _selectedAccountId).firstOrNull;
      if (selectedAcc != null && amount > selectedAcc.balance) {
        AppSnackBar.showError(
          context,
          context.trArgs('insufficient_funds_msg', {
            'account': selectedAcc.name,
            'balance': context.sar(selectedAcc.balance),
            'amount': context.sar(amount),
          }),
          title: context.tr('insufficient_funds_title'),
        );
        return;
      }
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
      // An admin who is neither spouse names the wife by her member id.
      final wifeSide = _viewerIsWife ? 'me' : (_adminClassifier ? (_selectedWifeId ?? 'wife') : 'wife');
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
      // A day the user chose, else the moment of saving.
      occurredAt: _datePicked ? _occurredAt : DateTime.now(),
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
                      gradient: context.icedHeroGradient,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: context.primaryButtonBg.withValues(alpha: 0.25),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(Icons.edit_note_rounded, color: context.primaryButtonFg, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      context.tr('manual_log'),
                      style: GoogleFonts.outfit(
                        color: context.textPrimary,
                        fontSize: 17,
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

              // Amount first, focused, decimal keypad (UX-12)
              TextField(
                key: const ValueKey('manual_amount'),
                controller: _amountCtrl,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: GoogleFonts.outfit(color: context.textPrimary, fontWeight: FontWeight.w700, fontSize: 20),
                decoration: InputDecoration(
                  labelText: context.tr('amount_sar'),
                  prefixText: '${context.tr('sar')} ',
                  prefixStyle: GoogleFonts.outfit(color: context.accentText, fontWeight: FontWeight.w700, fontSize: 18),
                  labelStyle: TextStyle(color: context.textSecondary),
                  filled: true,
                  fillColor: context.inputBg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: context.borderColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: context.accentText, width: 1.8),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Quick increment chips
              Wrap(
                spacing: 8,
                children: [10, 50, 100].map((inc) {
                  return InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () {
                      final current = double.tryParse(_amountCtrl.text.trim()) ?? 0.0;
                      final updated = current + inc;
                      setState(() {
                        _amountCtrl.text = updated % 1 == 0 ? updated.toInt().toString() : updated.toStringAsFixed(2);
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: context.subtleCardBg,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: context.accentSubtleBorder,
                          width: 1,
                        ),
                      ),
                      child: Text(
                        '+$inc ${context.tr('sar')}',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: context.accentText,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),

              // Merchant
              TextField(
                key: const ValueKey('manual_merchant'),
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

              // When (UX-12): yesterday's cash purchase is not booked today.
              ExpenseDateChips(
                value: _occurredAt,
                maxDaysBack: 365,
                onChanged: (d) => setState(() {
                  _occurredAt = d;
                  _datePicked = true;
                }),
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
                    prefixIcon: Icon(Icons.account_balance_wallet_outlined, color: context.accentText, size: 20),
                    filled: true,
                    fillColor: context.inputBg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  items: _accounts.map((acc) {
                    return DropdownMenuItem<String>(
                      value: acc.id,
                      child: Row(
                        children: [
                          Icon(acc.accountType.defaultIcon, size: 16, color: context.accentText),
                          const SizedBox(width: 8),
                          Text('${acc.name} (${context.money(acc.balance, acc.currency)})'),
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
                  viewerRole: _viewerIsWife ? 'wife' : (_adminClassifier ? 'admin' : 'husband'),
                  wifeName: _viewerIsWife ? null : _selectedWifeName,
                  husbandName: _husbandName,
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
                            selectedColor: (context.primaryButtonBg),
                            backgroundColor: context.subtleCardBg,
                            labelStyle: TextStyle(
                              color: isSelected
                                  ? (context.primaryButtonFg)
                                  : context.textSecondary,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              fontSize: 11.5,
                            ),
                            side: BorderSide(
                              color: isSelected
                                  ? (context.accentText)
                                  : context.borderColor,
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
                      activeColor: context.accentText,
                      onTap: () => setState(() => _roommateSplit = 'all'),
                    ),
                    const SizedBox(width: 8),
                    _buildSegmentOption(
                      isSelected: _roommateSplit == 'personal',
                      label: context.tr('roommate_split_personal'),
                      icon: Icons.lock_outline_rounded,
                      activeColor: context.textSecondary,
                      onTap: () => setState(() => _roommateSplit = 'personal'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: (_roommateSplit == 'all'
                            ? (context.accentText)
                            : (context.textSecondary))
                        .withValues(alpha: context.isDark ? 0.12 : 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: (_roommateSplit == 'all'
                              ? (context.accentText)
                              : (context.textSecondary))
                          .withValues(alpha: context.isDark ? 0.35 : 0.25),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _roommateSplit == 'all' ? Icons.pie_chart_outline_rounded : Icons.lock_outline_rounded,
                        size: 15,
                        color: _roommateSplit == 'all'
                            ? (context.accentText)
                            : (context.textSecondary),
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
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: context.icedHeroGradient,
                  boxShadow: [
                    BoxShadow(
                      color: context.primaryButtonBg.withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    shadowColor: Colors.transparent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: _isSaving ? null : _saveExpense,
                  child: _isSaving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_rounded, size: 20, color: context.primaryButtonFg),
                            const SizedBox(width: 8),
                            Text(
                              context.tr('record_expense'),
                              style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                            ),
                          ],
                        ),
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
              ? (context.primaryButtonBg)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: isSelected
              ? Border.all(
                  color: context.accentText,
                )
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 12,
              color: isSelected
                  ? (context.primaryButtonFg)
                  : context.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected
                    ? (context.primaryButtonFg)
                    : context.textSecondary,
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
