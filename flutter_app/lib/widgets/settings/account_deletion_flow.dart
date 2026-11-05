import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/account_deletion.dart';
import '../../providers/account_deletion_provider.dart';
import '../../services/offline_sync_service.dart';
import '../../services/public_links.dart';
import '../../theme/app_themes.dart';
import '../../utils/failure_log.dart';
import '../app_snackbar.dart';

String _dateText(BuildContext context, DateTime date) => context.fmtDate(date.toLocal(), 'd MMMM yyyy');

/// What the Account section of Settings shows: Delete account or, for a pending
/// user, the date and Cancel at all times; and the public pages.
class AccountDeletionSection extends StatelessWidget {
  /// A handover in the flow changes roles: Settings reloads them.
  final VoidCallback? onRequested;

  const AccountDeletionSection({super.key, this.onRequested});

  Future<void> _open(BuildContext context, Uri uri) async {
    final opened = await openPublicLink(uri);
    if (!opened && context.mounted) AppSnackBar.showError(context, context.tr('del_link_failed'));
  }

  @override
  Widget build(BuildContext context) {
    final deletion = context.watch<AccountDeletionProvider?>();
    final language = Localizations.localeOf(context).languageCode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (deletion != null && deletion.isPending)
          const AccountDeletionPendingCard()
        else if (deletion != null)
          OutlinedButton.icon(
            key: const ValueKey('account_deletion_open'),
            style: OutlinedButton.styleFrom(
              foregroundColor: context.dangerColor,
              side: BorderSide(color: context.dangerColor),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.delete_forever_outlined, size: 18),
            label: Text(context.tr('del_delete_account'), style: const TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () async {
              final requested = await AccountDeletionFlowScreen.open(context);
              if (requested == true) onRequested?.call();
            },
          ),
        const SizedBox(height: 4),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          children: [
            TextButton(
              key: const ValueKey('account_deletion_page_link'),
              onPressed: () => _open(context, publicDeleteAccountUri(language)),
              child: Text(context.tr('del_link_delete_page'), style: TextStyle(color: context.accentText, fontSize: 12)),
            ),
            TextButton(
              key: const ValueKey('privacy_page_link'),
              onPressed: () => _open(context, publicPrivacyUri()),
              child: Text(context.tr('del_link_privacy'), style: TextStyle(color: context.accentText, fontSize: 12)),
            ),
          ],
        ),
      ],
    );
  }
}

/// The scheduled date and the only thing that cancels a deletion.
class AccountDeletionPendingCard extends StatefulWidget {
  final VoidCallback? onCancelled;

  const AccountDeletionPendingCard({super.key, this.onCancelled});

  @override
  State<AccountDeletionPendingCard> createState() => _AccountDeletionPendingCardState();
}

class _AccountDeletionPendingCardState extends State<AccountDeletionPendingCard> {
  bool _cancelling = false;

  Future<void> _cancel() async {
    setState(() => _cancelling = true);
    final deletion = context.read<AccountDeletionProvider>();
    try {
      await deletion.cancelDeletion();
      if (!mounted) return;
      AppSnackBar.showSuccess(context, context.tr('del_cancelled'));
      widget.onCancelled?.call();
    } on AccountDeletionException catch (e) {
      logFailure('AccountDeletion.cancel', e);
      if (mounted) AppSnackBar.showError(context, context.tr(e.messageKey));
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final deletion = context.watch<AccountDeletionProvider>();
    final status = deletion.status;
    final date = status.scheduledFor;
    final marked = status.markedHouseholds.map((h) => h.name).where((n) => n.isNotEmpty).toList();
    return Container(
      key: const ValueKey('account_deletion_pending'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.dangerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.schedule_rounded, color: context.dangerColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.tr('del_result_title'),
                  style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w700, color: context.textPrimary),
                ),
              ),
            ],
          ),
          if (date != null) ...[
            const SizedBox(height: 8),
            Text(
              context.trArgs('del_pending_date', {'date': _dateText(context, date)}),
              style: TextStyle(color: context.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
          if (marked.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              context.trArgs('del_pending_marked', {'names': marked.join(context.isRtl ? '، ' : ', ')}),
              style: TextStyle(color: context.textSecondary, fontSize: 12.5),
            ),
          ],
          const SizedBox(height: 8),
          Text(context.tr('del_cancel_only_note'), style: TextStyle(color: context.textSecondary, fontSize: 12.5)),
          if (deletion.isFromDevice) ...[
            const SizedBox(height: 8),
            Text(context.tr('del_pending_offline_note'), style: TextStyle(color: context.textSecondary, fontSize: 12)),
          ],
          const SizedBox(height: 12),
          if (status.canCancel)
            ElevatedButton(
              key: const ValueKey('account_deletion_cancel'),
              style: ElevatedButton.styleFrom(
                backgroundColor: context.primaryButtonBg,
                foregroundColor: context.primaryButtonFg,
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _cancelling ? null : _cancel,
              child: Text(context.tr('del_cancel_button'), style: const TextStyle(fontWeight: FontWeight.bold)),
            )
          else
            Text(
              context.tr('del_err_in_progress'),
              key: const ValueKey('account_deletion_in_progress'),
              style: TextStyle(color: context.dangerColor, fontSize: 13, fontWeight: FontWeight.w600),
            ),
        ],
      ),
    );
  }
}

enum _Step { loading, loadFailed, consequences, choices, reauth, typedWord, result }

/// The deletion flow: consequences, a choice per affected household (only if
/// any), re-authentication, a typed word, then the date and Cancel. Everything
/// here is also enforced by the server; nothing is asked twice.
class AccountDeletionFlowScreen extends StatefulWidget {
  const AccountDeletionFlowScreen({super.key});

  /// Returns true when a deletion was scheduled.
  static Future<bool?> open(BuildContext context) => Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const AccountDeletionFlowScreen()),
      );

  @override
  State<AccountDeletionFlowScreen> createState() => _AccountDeletionFlowScreenState();
}

class _AccountDeletionFlowScreenState extends State<AccountDeletionFlowScreen> {
  _Step _step = _Step.loading;
  AccountDeletionPreflight? _preflight;
  bool _busy = false;
  bool _requested = false;

  /// The localization key of the message on the current step.
  String? _errorKey;

  // Choices, per household.
  final Map<String, String> _actions = {};
  final Map<String, String> _successors = {};

  // Re-authentication.
  final _passwordCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  bool _usingCode = false;

  final _wordCtrl = TextEditingController();

  // Sync first.
  int _unsynced = 0;
  bool _syncing = false;
  String? _syncResultKey;

  AccountDeletionProvider get _deletion => context.read<AccountDeletionProvider>();

  @override
  void initState() {
    super.initState();
    _loadPreflight();
    _loadUnsynced();
  }

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _codeCtrl.dispose();
    _wordCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPreflight() async {
    setState(() {
      _step = _Step.loading;
      _errorKey = null;
    });
    try {
      final preflight = await _deletion.loadPreflight();
      // The result step reads the provider: it has to know before it is shown.
      if (preflight.deletion.isPending) await _deletion.load();
      if (!mounted) return;
      setState(() {
        _preflight = preflight;
        _step = preflight.deletion.isPending ? _Step.result : _Step.consequences;
      });
    } on AccountDeletionException catch (e) {
      logFailure('AccountDeletion.preflight', e);
      if (!mounted) return;
      setState(() {
        _step = _Step.loadFailed;
        _errorKey = e.messageKey;
      });
    }
  }

  /// Offline items are not lost silently, and they never block the deletion.
  Future<void> _loadUnsynced() async {
    try {
      final sync = OfflineSyncService.instance;
      await sync.updatePendingCount();
      final count = await sync.unsyncedCount();
      if (mounted) setState(() => _unsynced = count);
    } catch (e) {
      logFailure('AccountDeletion.unsyncedCount', e);
    }
  }

  Future<void> _syncFirst() async {
    setState(() {
      _syncing = true;
      _syncResultKey = null;
    });
    var remaining = _unsynced;
    try {
      final sync = OfflineSyncService.instance;
      await sync.flushQueue();
      remaining = await sync.unsyncedCount();
    } catch (e) {
      logFailure('AccountDeletion.syncFirst', e);
    }
    if (!mounted) return;
    setState(() {
      _syncing = false;
      _unsynced = remaining;
      _syncResultKey = remaining == 0 ? 'del_sync_first_done' : 'del_sync_first_still';
    });
  }

  List<AccountDeletionHousehold> get _households => _preflight?.households ?? const [];
  List<AccountDeletionHousehold> get _choiceHouseholds => _preflight?.householdsNeedingChoice ?? const [];

  List<_Step> get _steps => [
        _Step.consequences,
        if (_choiceHouseholds.isNotEmpty) _Step.choices,
        _Step.reauth,
        _Step.typedWord,
      ];

  void _goTo(_Step step, {String? errorKey}) {
    setState(() {
      _step = step;
      _errorKey = errorKey;
    });
  }

  void _next() {
    final steps = _steps;
    _goTo(steps[steps.indexOf(_step) + 1]);
  }

  void _back() {
    final steps = _steps;
    final index = steps.indexOf(_step);
    if (index <= 0) {
      Navigator.of(context).pop(_requested);
    } else {
      _goTo(steps[index - 1]);
    }
  }

  // ── Choices ────────────────────────────────────────────────────────────────

  bool _choiceComplete(AccountDeletionHousehold household) {
    final action = _actions[household.id];
    if (action == 'delete') return true;
    if (action != 'transfer') return false;
    final successor = _successors[household.id];
    return household.candidates.any((c) => c.userId == successor && !c.pendingDeletion);
  }

  void _submitChoices() {
    if (_choiceHouseholds.every(_choiceComplete)) {
      _next();
    } else {
      setState(() => _errorKey = 'del_err_choice_missing');
    }
  }

  List<HouseholdDeletionChoice> _buildChoices() => _choiceHouseholds.map((household) {
        return _actions[household.id] == 'transfer'
            ? HouseholdDeletionChoice.transfer(household.id, _successors[household.id]!)
            : HouseholdDeletionChoice.delete(household.id);
      }).toList();

  // ── Re-authentication ──────────────────────────────────────────────────────

  Future<void> _runBusy(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _errorKey = null;
    });
    try {
      await action();
    } on AccountDeletionException catch (e) {
      logFailure('AccountDeletion.flow', e);
      if (mounted) setState(() => _errorKey = e.messageKey);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitPassword() async {
    final password = _passwordCtrl.text;
    if (password.isEmpty) {
      setState(() => _errorKey = 'del_err_wrong_password');
      return;
    }
    await _runBusy(() async {
      await _deletion.service.reauthenticateWithPassword(password);
      _passwordCtrl.clear();
      if (mounted) _next();
    });
  }

  Future<void> _sendCode() => _runBusy(() async {
        await _deletion.service.sendEmailCode();
        if (mounted) setState(() => _usingCode = true);
      });

  Future<void> _submitCode() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) {
      setState(() => _errorKey = 'del_err_wrong_code');
      return;
    }
    await _runBusy(() async {
      await _deletion.service.verifyEmailCode(code);
      _codeCtrl.clear();
      if (mounted) _next();
    });
  }

  // ── Typed word ─────────────────────────────────────────────────────────────

  Future<void> _submitWord() async {
    final typed = _wordCtrl.text;
    if (!confirmationWordMatches(typed)) {
      setState(() => _errorKey = 'del_err_confirmation_mismatch');
      return;
    }
    final locale = Localizations.localeOf(context).languageCode;
    setState(() {
      _busy = true;
      _errorKey = null;
    });
    try {
      await _deletion.requestDeletion(confirmation: typed, choices: _buildChoices(), locale: locale);
      if (!mounted) return;
      setState(() {
        _requested = true;
        _step = _Step.result;
      });
    } on AccountDeletionException catch (e) {
      logFailure('AccountDeletion.request', e);
      if (!mounted) return;
      if (e.needsReauthentication) {
        _goTo(_Step.reauth, errorKey: e.messageKey);
      } else if (e.choicesOutOfDate) {
        await _reloadChoices(e);
      } else {
        setState(() => _errorKey = e.messageKey);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The households changed under the flow, or a successor went pending: ask again
  /// from what the server says now.
  Future<void> _reloadChoices(AccountDeletionException cause) async {
    try {
      final preflight = await _deletion.loadPreflight();
      if (!mounted) return;
      setState(() {
        _preflight = preflight;
        final ids = preflight.householdsNeedingChoice.map((h) => h.id).toSet();
        _actions.removeWhere((id, _) => !ids.contains(id));
        _successors.removeWhere((id, _) {
          if (!ids.contains(id)) return true;
          final household = preflight.householdsNeedingChoice.firstWhere((h) => h.id == id);
          return !household.candidates.any((c) => c.userId == _successors[id] && !c.pendingDeletion);
        });
        // The list stays open on a handover that now needs another pick, unless no
        // member is left to pick.
        _actions.removeWhere((id, action) =>
            action == 'transfer' &&
            !preflight.householdsNeedingChoice.firstWhere((h) => h.id == id).hasSelectableSuccessor);
      });
      _goTo(_choiceHouseholds.isNotEmpty ? _Step.choices : _Step.consequences, errorKey: cause.messageKey);
    } on AccountDeletionException catch (e) {
      logFailure('AccountDeletion.reloadChoices', e);
      if (mounted) setState(() => _errorKey = e.messageKey);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final steps = _steps;
    final index = steps.indexOf(_step);
    final canPop = index <= 0 || _step == _Step.result;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (canPop) {
          Navigator.of(context).pop(_requested);
        } else {
          _back();
        }
      },
      child: Scaffold(
        backgroundColor: context.scaffoldBg,
        appBar: AppBar(
          foregroundColor: context.textPrimary,
          iconTheme: IconThemeData(color: context.textPrimary),
          backgroundColor: context.scaffoldBg,
          elevation: 0,
          title: Text(
            context.tr('del_delete_account'),
            style: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: context.textPrimary),
          ),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              if (index >= 0) ...[
                Text(
                  context.trArgs('del_step_of', {'current': index + 1, 'total': steps.length}),
                  key: const ValueKey('account_deletion_progress'),
                  style: TextStyle(color: context.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
              ],
              ..._buildStep(context),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildStep(BuildContext context) => switch (_step) {
        _Step.loading => [
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
          ],
        _Step.loadFailed => [
            _errorText(context),
            const SizedBox(height: 12),
            _PrimaryButton(label: context.tr('try_again'), onPressed: _loadPreflight),
          ],
        _Step.consequences => _buildConsequences(context),
        _Step.choices => _buildChoiceStep(context),
        _Step.reauth => _buildReauth(context),
        _Step.typedWord => _buildTypedWord(context),
        _Step.result => [
            // A handover made on the way here stands after a cancel, so roles reload.
            AccountDeletionPendingCard(onCancelled: () => Navigator.of(context).pop(_requested)),
            const SizedBox(height: 12),
            TextButton(
              key: const ValueKey('account_deletion_done'),
              onPressed: () => Navigator.of(context).pop(_requested),
              child: Text(context.tr('done'), style: TextStyle(color: context.accentText)),
            ),
          ],
      };

  Widget _errorText(BuildContext context) {
    final key = _errorKey;
    if (key == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        context.tr(key),
        key: const ValueKey('account_deletion_error'),
        style: TextStyle(color: context.dangerColor, fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }

  List<Widget> _buildConsequences(BuildContext context) {
    final othersStay = _households.isEmpty ? false : _households.any((h) => h.position != HouseholdDeletionPosition.soleMember);
    final anyDeletable = _households.any((h) => h.needsChoice || h.position == HouseholdDeletionPosition.soleMember);
    return [
      _Heading(context.tr('del_consequences_title')),
      const SizedBox(height: 12),
      _Note(icon: Icons.schedule_rounded, text: context.tr('del_grace_body')),
      _Note(icon: Icons.info_outline_rounded, text: context.tr('del_cancel_only_note'), emphasized: true),
      _Note(icon: Icons.person_off_outlined, text: context.tr('del_personal_data')),
      if (othersStay) ...[
        _Note(icon: Icons.receipt_long_outlined, text: context.tr('del_shared_rows')),
        _Note(
          key: const ValueKey('account_deletion_settlement_warning'),
          icon: Icons.handshake_outlined,
          text: context.tr('del_settlement_warning'),
          emphasized: true,
        ),
        _Note(icon: Icons.account_balance_wallet_outlined, text: context.tr('del_wife_ledger_member')),
      ],
      if (anyDeletable)
        _Note(
          key: const ValueKey('account_deletion_household_warning'),
          icon: Icons.warning_amber_rounded,
          text: context.tr('del_household_delete_warning'),
          emphasized: true,
        ),
      if (_households.isNotEmpty) ...[
        const SizedBox(height: 8),
        _Subheading(context.tr('del_your_households')),
        const SizedBox(height: 6),
        for (final household in _households)
          _Note(
            icon: Icons.home_outlined,
            text: context.trArgs(switch (household.position) {
              HouseholdDeletionPosition.member => 'del_pos_member',
              HouseholdDeletionPosition.soleMember => 'del_pos_sole',
              HouseholdDeletionPosition.primaryAdmin => 'del_pos_primary',
              HouseholdDeletionPosition.coAdmin => 'del_pos_coadmin',
            }, {'name': household.name}),
          ),
      ],
      if (_unsynced > 0 || _syncResultKey != null) _buildSyncFirst(context),
      const SizedBox(height: 12),
      _errorText(context),
      _PrimaryButton(key: const ValueKey('account_deletion_continue'), label: context.tr('del_continue'), onPressed: _next),
    ];
  }

  Widget _buildSyncFirst(BuildContext context) {
    return Container(
      key: const ValueKey('account_deletion_sync_first'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_unsynced > 0) ...[
            Text(
              context.tr('del_sync_first_title'),
              style: TextStyle(color: context.textPrimary, fontSize: 13, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(context.tr('del_sync_first_body'), style: TextStyle(color: context.textSecondary, fontSize: 12.5)),
          ],
          if (_syncResultKey != null) ...[
            const SizedBox(height: 4),
            Text(context.tr(_syncResultKey!), style: TextStyle(color: context.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w600)),
          ],
          if (_unsynced > 0)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                key: const ValueKey('account_deletion_sync_now'),
                onPressed: _syncing ? null : _syncFirst,
                child: Text(context.tr('sync_now'), style: TextStyle(color: context.accentText, fontWeight: FontWeight.bold)),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildChoiceStep(BuildContext context) {
    return [
      _Heading(context.tr('del_choice_title')),
      const SizedBox(height: 12),
      for (final household in _choiceHouseholds) _buildHouseholdChoice(context, household),
      _errorText(context),
      _PrimaryButton(key: const ValueKey('account_deletion_continue'), label: context.tr('del_continue'), onPressed: _submitChoices),
    ];
  }

  Widget _buildHouseholdChoice(BuildContext context, AccountDeletionHousehold household) {
    final action = _actions[household.id];
    final canTransfer = household.hasSelectableSuccessor;
    return Container(
      key: ValueKey('account_deletion_household_${household.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(household.name, style: TextStyle(color: context.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          _ChoiceTile(
            key: ValueKey('account_deletion_action_transfer_${household.id}'),
            label: context.tr('del_choice_transfer'),
            selected: action == 'transfer',
            enabled: canTransfer,
            onTap: () => setState(() {
              _actions[household.id] = 'transfer';
              _errorKey = null;
            }),
          ),
          if (!canTransfer)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 32, bottom: 4),
              child: Text(
                context.tr('del_choice_no_successor'),
                key: ValueKey('account_deletion_no_successor_${household.id}'),
                style: TextStyle(color: context.textSecondary, fontSize: 12),
              ),
            ),
          if (action == 'transfer') ...[
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 32, top: 4, bottom: 2),
              child: Text(
                context.tr('del_choice_pick_member'),
                style: TextStyle(color: context.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ),
            for (final candidate in household.candidates)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 20),
                child: _ChoiceTile(
                  key: ValueKey('account_deletion_successor_${household.id}_${candidate.userId}'),
                  label: (candidate.displayName ?? '').trim().isEmpty ? context.tr('member') : candidate.displayName!.trim(),
                  caption: candidate.pendingDeletion ? context.tr('del_choice_pending_label') : null,
                  selected: _successors[household.id] == candidate.userId,
                  enabled: !candidate.pendingDeletion,
                  onTap: () => setState(() {
                    _successors[household.id] = candidate.userId;
                    _errorKey = null;
                  }),
                ),
              ),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 32, top: 4, bottom: 4),
              child: Text(context.tr('del_choice_transfer_note'), style: TextStyle(color: context.textSecondary, fontSize: 12)),
            ),
          ],
          _ChoiceTile(
            key: ValueKey('account_deletion_action_delete_${household.id}'),
            label: context.tr('del_choice_delete'),
            selected: action == 'delete',
            enabled: true,
            onTap: () => setState(() {
              _actions[household.id] = 'delete';
              _errorKey = null;
            }),
          ),
          if (action == 'delete')
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 32, top: 4, bottom: 4),
              child: Text(context.tr('del_household_delete_warning'), style: TextStyle(color: context.dangerColor, fontSize: 12)),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildReauth(BuildContext context) {
    final email = _deletion.service.currentEmail ?? '';
    return [
      _Heading(context.tr('del_reauth_title')),
      const SizedBox(height: 12),
      if (_usingCode) ...[
        Text(context.trArgs('del_reauth_code_sent', {'email': email}), style: TextStyle(color: context.textSecondary, fontSize: 13)),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('account_deletion_code'),
          controller: _codeCtrl,
          keyboardType: TextInputType.number,
          autofillHints: const [AutofillHints.oneTimeCode],
          onSubmitted: (_) => _busy ? null : _submitCode(),
          decoration: InputDecoration(labelText: context.tr('del_reauth_code')),
        ),
        const SizedBox(height: 12),
        _errorText(context),
        _PrimaryButton(key: const ValueKey('account_deletion_continue'), label: context.tr('del_continue'), onPressed: _busy ? null : _submitCode),
        const SizedBox(height: 4),
        TextButton(
          key: const ValueKey('account_deletion_resend'),
          onPressed: _busy ? null : _sendCode,
          child: Text(context.tr('del_reauth_resend'), style: TextStyle(color: context.accentText)),
        ),
        TextButton(
          key: const ValueKey('account_deletion_use_password'),
          onPressed: _busy
              ? null
              : () => setState(() {
                    _usingCode = false;
                    _errorKey = null;
                  }),
          child: Text(context.tr('del_reauth_use_password'), style: TextStyle(color: context.accentText)),
        ),
      ] else ...[
        Text(context.trArgs('del_reauth_body', {'email': email}), style: TextStyle(color: context.textSecondary, fontSize: 13)),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('account_deletion_password'),
          controller: _passwordCtrl,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          autofillHints: const [AutofillHints.password],
          onSubmitted: (_) => _busy ? null : _submitPassword(),
          decoration: InputDecoration(labelText: context.tr('del_reauth_password')),
        ),
        const SizedBox(height: 12),
        _errorText(context),
        _PrimaryButton(key: const ValueKey('account_deletion_continue'), label: context.tr('del_continue'), onPressed: _busy ? null : _submitPassword),
        const SizedBox(height: 4),
        TextButton(
          key: const ValueKey('account_deletion_forgot'),
          onPressed: _busy ? null : _sendCode,
          child: Text(context.tr('del_reauth_forgot'), style: TextStyle(color: context.accentText)),
        ),
      ],
    ];
  }

  List<Widget> _buildTypedWord(BuildContext context) {
    return [
      _Heading(context.tr('del_typed_title')),
      const SizedBox(height: 12),
      Text(
        context.trArgs('del_typed_body', {'word': context.tr('del_confirm_word')}),
        key: const ValueKey('account_deletion_typed_body'),
        style: TextStyle(color: context.textPrimary, fontSize: 14),
      ),
      const SizedBox(height: 4),
      Text(context.tr('del_cancel_only_note'), style: TextStyle(color: context.textSecondary, fontSize: 12.5)),
      const SizedBox(height: 12),
      TextField(
        key: const ValueKey('account_deletion_word'),
        controller: _wordCtrl,
        autocorrect: false,
        enableSuggestions: false,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _busy ? null : _submitWord(),
        decoration: InputDecoration(labelText: context.tr('del_typed_hint')),
      ),
      const SizedBox(height: 12),
      _errorText(context),
      ElevatedButton(
        key: const ValueKey('account_deletion_confirm'),
        style: ElevatedButton.styleFrom(
          backgroundColor: context.dangerColor,
          foregroundColor: context.cardBg,
          minimumSize: const Size.fromHeight(46),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        onPressed: _busy ? null : _submitWord,
        child: Text(context.tr('del_confirm_button'), style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    ];
  }
}

class _Heading extends StatelessWidget {
  final String text;
  const _Heading(this.text);

  @override
  Widget build(BuildContext context) =>
      Text(text, style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w700, color: context.textPrimary));
}

class _Subheading extends StatelessWidget {
  final String text;
  const _Subheading(this.text);

  @override
  Widget build(BuildContext context) =>
      Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: context.textPrimary));
}

class _Note extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool emphasized;

  const _Note({super.key, required this.icon, required this.text, this.emphasized = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: emphasized ? context.dangerColor : context.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: emphasized ? context.textPrimary : context.textSecondary,
                fontSize: 13,
                fontWeight: emphasized ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const _PrimaryButton({super.key, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: context.primaryButtonBg,
        foregroundColor: context.primaryButtonFg,
        minimumSize: const Size.fromHeight(46),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onPressed: onPressed,
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }
}

/// A radio row, in the same drawn style as the household type chooser.
class _ChoiceTile extends StatelessWidget {
  final String label;
  final String? caption;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _ChoiceTile({
    super.key,
    required this.label,
    this.caption,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = enabled ? context.textPrimary : context.textSecondary;
    return Semantics(
      selected: selected,
      enabled: enabled,
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                size: 20,
                color: selected ? context.accentText : context.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: TextStyle(color: color, fontSize: 13.5, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
                    if (caption != null)
                      Text(caption!, style: TextStyle(color: context.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
