import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/app_localizations.dart';
import '../../models/household_membership.dart';
import '../../models/nafaqah.dart';
import '../../services/api/household_roles_api_client.dart';
import '../../services/api_service.dart';
import '../../theme/app_themes.dart';
import '../app_snackbar.dart';
import 'household_type_chooser.dart';

typedef RosterLoader = Future<HouseholdRoster> Function(String householdId);
typedef RosterAction = Future<HouseholdRoster> Function(String householdId, String userId);
typedef NafaqahProviderSetter = Future<NafaqahProviderChange> Function(String householdId, String userId);
typedef HouseholdTypeSetter = Future<String> Function(String householdId, String householdType);
typedef FinancialRoleSetter = Future<String> Function(String householdId, String userId, String financialRole);

enum _RoleAction { promote, revoke, makePrimary, financialRole }

/// Members of the household with their roles. Admins promote members to
/// co-admin and revoke co-admins; the primary admin also transfers primary
/// admin. Co-admins never see an action against the primary admin. Every
/// change is enforced by the server (DB-16 / DB-18); a refusal is explained.
///
/// In a family household the Nafaqah provider (husband) is marked, and any
/// admin chooses him among the non-spouse members (FABLE-LOGIC-04); a family
/// without a provider is prompted to set one.
///
/// The household type (Family / Roommates) is shown; admins change it
/// (`PUT /households/{id}/type`) and change a member's financial role
/// (`PUT .../members/{user_id}/financial-role`), offered only among the roles
/// valid for the household type and never "wife" for the Nafaqah provider.
class HouseholdRolesCard extends StatefulWidget {
  final String householdId;
  final RosterLoader? loadRoster;
  final RosterAction? promote;
  final RosterAction? revoke;
  final RosterAction? transferPrimary;
  final NafaqahProviderSetter? setNafaqahProvider;
  final HouseholdTypeSetter? setHouseholdType;
  final FinancialRoleSetter? setFinancialRole;

  /// Called after the server confirmed a new household type.
  final ValueChanged<String>? onHouseholdTypeChanged;

  /// Called after the server confirmed a new Nafaqah provider, with the
  /// refreshed Nafaqah summary when the server returned one (so the family
  /// card can reload).
  final ValueChanged<NafaqahSummary?>? onNafaqahProviderChanged;

  /// Called after a role change the server confirmed (e.g. to refresh the
  /// signed-in user's own role).
  final VoidCallback? onRolesChanged;

  const HouseholdRolesCard({
    super.key,
    required this.householdId,
    this.loadRoster,
    this.promote,
    this.revoke,
    this.transferPrimary,
    this.setNafaqahProvider,
    this.setHouseholdType,
    this.setFinancialRole,
    this.onHouseholdTypeChanged,
    this.onNafaqahProviderChanged,
    this.onRolesChanged,
  });

  @override
  State<HouseholdRolesCard> createState() => _HouseholdRolesCardState();
}

class _HouseholdRolesCardState extends State<HouseholdRolesCard> {
  HouseholdRoster? _roster;
  bool _loading = true;
  bool _failed = false;
  String? _busyUserId;
  bool _settingProvider = false;
  bool _settingType = false;

  RosterLoader get _load => widget.loadRoster ?? ApiService.instance.getHouseholdMembers;
  RosterAction get _promote => widget.promote ?? ApiService.instance.promoteHouseholdAdmin;
  RosterAction get _revoke => widget.revoke ?? ApiService.instance.revokeHouseholdAdmin;
  RosterAction get _transfer => widget.transferPrimary ?? ApiService.instance.transferPrimaryAdmin;
  NafaqahProviderSetter get _setProvider => widget.setNafaqahProvider ?? ApiService.instance.setNafaqahProvider;
  HouseholdTypeSetter get _setType => widget.setHouseholdType ?? ApiService.instance.setHouseholdType;
  FinancialRoleSetter get _setFinancialRole => widget.setFinancialRole ?? ApiService.instance.setMemberFinancialRole;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void didUpdateWidget(covariant HouseholdRolesCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.householdId != widget.householdId) _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final roster = await _load(widget.householdId);
      if (!mounted) return;
      setState(() {
        _roster = roster;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  String _nameOf(HouseholdMember m) {
    final name = (m.displayName ?? '').trim();
    return name.isEmpty ? context.tr('member') : name;
  }

  String _errorText(Object e) {
    if (e is HouseholdRolesApiException) {
      if (e.code == 'forbidden') return context.tr('roles_forbidden');
      if (e.code == 'last_admin') return context.tr('roles_last_admin');
    }
    return context.trArgs('roles_update_failed', {'error': e});
  }

  Future<void> _run(_RoleAction action, HouseholdMember member) async {
    if (action == _RoleAction.financialRole) return _changeFinancialRole(member);
    if (action == _RoleAction.makePrimary) {
      final name = _nameOf(member);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dCtx) => AlertDialog(
          backgroundColor: context.cardBg,
          title: Text(context.tr('roles_transfer_title'), style: TextStyle(color: context.textPrimary)),
          content: Text(
            context.trArgs('roles_transfer_msg', {'name': name}),
            style: TextStyle(color: context.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dCtx, false),
              child: Text(context.tr('cancel'), style: TextStyle(color: context.textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: context.isDark ? const Color(0xFF5E1327) : const Color(0xFF4A0E1E),
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(dCtx, true),
              child: Text(context.tr('roles_transfer_confirm')),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    final RosterAction call = switch (action) {
      _RoleAction.promote => _promote,
      _RoleAction.revoke => _revoke,
      _RoleAction.makePrimary || _RoleAction.financialRole => _transfer,
    };
    setState(() => _busyUserId = member.userId);
    try {
      final roster = await call(widget.householdId, member.userId);
      if (!mounted) return;
      setState(() {
        _roster = roster;
        _busyUserId = null;
      });
      widget.onRolesChanged?.call();
      AppSnackBar.showSuccess(context, context.tr('roles_updated'));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyUserId = null);
      AppSnackBar.showError(context, _errorText(e));
    }
  }

  // ── Household type and financial roles ──────────────────────────────────────

  /// l10n key of a financial role, or null when it has no label of its own
  /// (the provider is marked by his badge).
  static String? _financialRoleKey(String? role) => switch ((role ?? '').toLowerCase()) {
        kFinancialRoleSpouse => 'wife_spouse_title',
        kFinancialRoleFamilyMember => 'role_family_member',
        kFinancialRoleDependent => 'fin_role_dependent',
        kFinancialRolePeer => 'role_roommate',
        _ => null,
      };

  String _typeErrorText(Object e) {
    if (e is HouseholdRolesApiException) {
      if (e.code == 'forbidden') return context.tr('hh_type_forbidden');
      if (e.code == 'type_change_blocked') return e.serverMessage ?? context.tr('hh_type_blocked');
      if (e.code == 'invalid') return context.tr('hh_type_invalid');
    }
    return context.trArgs('hh_type_failed', {'error': e});
  }

  String _financialRoleErrorText(Object e) {
    if (e is HouseholdRolesApiException) {
      if (e.code == 'forbidden') return context.tr('fin_role_forbidden');
      if (e.code == 'not_found') return context.tr('fin_role_not_found');
      if (e.code == 'invalid' || e.code == 'financial_role_not_allowed') return context.tr('fin_role_invalid');
      if (e.code == 'provider_is_spouse') return context.tr('fin_role_provider_is_spouse');
      if (e.code == 'spouse_has_ledger') return context.tr('fin_role_spouse_has_ledger');
      if (e.statusCode == 409) return context.tr('fin_role_conflict');
    }
    return context.trArgs('fin_role_failed', {'error': e});
  }

  Future<void> _changeHouseholdType(HouseholdRoster roster) async {
    final current = roster.effectiveHouseholdType;
    String? picked = current;
    final chosen = await showDialog<String>(
      context: context,
      builder: (dCtx) => StatefulBuilder(
        builder: (dCtx, setDialogState) => AlertDialog(
          backgroundColor: context.cardBg,
          title: Text(context.tr('hh_type_change_title'), style: TextStyle(color: context.textPrimary)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(context.tr('hh_type_change_hint'), style: TextStyle(color: context.textSecondary, fontSize: 12)),
                const SizedBox(height: 10),
                HouseholdTypeChooser(value: picked, onChanged: (t) => setDialogState(() => picked = t)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dCtx),
              child: Text(context.tr('cancel'), style: TextStyle(color: context.textSecondary)),
            ),
            ElevatedButton(
              key: const ValueKey('household_type_save'),
              style: ElevatedButton.styleFrom(
                backgroundColor: context.isDark ? const Color(0xFF5E1327) : const Color(0xFF4A0E1E),
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(dCtx, picked),
              child: Text(context.tr('hh_type_save')),
            ),
          ],
        ),
      ),
    );
    if (chosen == null || chosen == current || !mounted) return;

    setState(() => _settingType = true);
    try {
      final stored = await _setType(widget.householdId, chosen);
      HouseholdRoster? refreshed;
      try {
        refreshed = await _load(widget.householdId);
      } catch (_) {
        refreshed = null; // the change is confirmed; the next load shows it
      }
      if (!mounted) return;
      setState(() {
        if (refreshed != null) _roster = refreshed;
        _settingType = false;
      });
      widget.onHouseholdTypeChanged?.call(stored);
      widget.onRolesChanged?.call();
      AppSnackBar.showSuccess(
        context,
        context.trArgs('hh_type_changed', {'type': context.tr(HouseholdTypeChooser.labelKey(stored))}),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _settingType = false);
      AppSnackBar.showError(context, _typeErrorText(e));
    }
  }

  Future<void> _changeFinancialRole(HouseholdMember member) async {
    final roster = _roster;
    if (roster == null) return;
    final options = roster.financialRoleOptions(member);
    final current = (member.financialRole ?? '').toLowerCase();
    final name = _nameOf(member);
    final chosen = await showDialog<String>(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: context.cardBg,
        title: Text(context.trArgs('fin_role_pick_title', {'name': name}), style: TextStyle(color: context.textPrimary)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.tr('fin_role_pick_desc'), style: TextStyle(color: context.textSecondary, fontSize: 12)),
              const SizedBox(height: 8),
              for (final role in options)
                ListTile(
                  key: ValueKey('fin-role-option-$role'),
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    role == current ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                    color: role == current ? context.iceCyan : context.textSecondary,
                  ),
                  title: Text(context.tr(_financialRoleKey(role)!), style: TextStyle(color: context.textPrimary, fontSize: 14)),
                  onTap: () => Navigator.pop(dCtx, role),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: Text(context.tr('cancel'), style: TextStyle(color: context.textSecondary)),
          ),
        ],
      ),
    );
    if (chosen == null || chosen == current || !mounted) return;

    setState(() => _busyUserId = member.userId);
    try {
      final stored = await _setFinancialRole(widget.householdId, member.userId, chosen);
      HouseholdRoster? refreshed;
      try {
        refreshed = await _load(widget.householdId);
      } catch (_) {
        refreshed = null;
      }
      if (!mounted) return;
      setState(() {
        if (refreshed != null) _roster = refreshed;
        _busyUserId = null;
      });
      widget.onRolesChanged?.call();
      final key = _financialRoleKey(stored) ?? _financialRoleKey(chosen)!;
      AppSnackBar.showSuccess(context, context.trArgs('fin_role_changed', {'name': name, 'role': context.tr(key)}));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyUserId = null);
      AppSnackBar.showError(context, _financialRoleErrorText(e));
    }
  }

  /// The household type and, for admins, a way to change it.
  Widget _typeSection(HouseholdRoster roster) {
    final type = roster.effectiveHouseholdType;
    final isFamily = type == kHouseholdTypeFamily;
    return Row(
      key: const ValueKey('roles_household_type'),
      children: [
        Icon(
          isFamily ? Icons.family_restroom_rounded : Icons.group_outlined,
          color: isFamily ? context.champagneGold : context.successText,
          size: 18,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            context.trArgs('hh_type_label', {'type': context.tr(HouseholdTypeChooser.labelKey(type))}),
            style: TextStyle(color: context.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ),
        if (roster.mayChangeHouseholdType)
          _settingType
              ? const Padding(
                  padding: EdgeInsets.all(8),
                  child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : TextButton(
                  key: const ValueKey('household_type_change'),
                  onPressed: _busyUserId == null ? () => _changeHouseholdType(roster) : null,
                  child: Text(context.tr('hh_type_change')),
                ),
      ],
    );
  }


  String _providerErrorText(Object e) {
    if (e is NafaqahApiException) {
      if (e.code == 'forbidden') return context.tr('nafaqah_provider_forbidden');
      if (e.code == 'invalid') return context.tr('nafaqah_provider_invalid');
      if (e.code == 'not_family') return context.tr('nafaqah_provider_not_family');
    }
    return context.trArgs('nafaqah_provider_failed', {'error': e});
  }

  Future<void> _chooseProvider(HouseholdRoster roster) async {
    final current = roster.nafaqahProvider?.userId;
    final candidates = roster.nafaqahProviderCandidates;
    final chosen = await showDialog<String>(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: context.cardBg,
        title: Text(context.tr('nafaqah_provider_pick_title'), style: TextStyle(color: context.textPrimary)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('nafaqah_provider_pick_desc'),
                style: TextStyle(color: context.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 8),
              for (final m in candidates)
                ListTile(
                  key: ValueKey('provider-option-${m.userId}'),
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    m.userId == current ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                    color: m.userId == current ? context.champagneGold : context.textSecondary,
                  ),
                  title: Text(
                    m.isSelf ? '${_nameOf(m)} (${context.tr('roles_you')})' : _nameOf(m),
                    style: TextStyle(color: context.textPrimary, fontSize: 14),
                  ),
                  onTap: () => Navigator.pop(dCtx, m.userId),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: Text(context.tr('cancel'), style: TextStyle(color: context.textSecondary)),
          ),
        ],
      ),
    );
    if (chosen == null || chosen == current || !mounted) return;

    setState(() => _settingProvider = true);
    try {
      final change = await _setProvider(widget.householdId, chosen);
      HouseholdRoster? refreshed;
      try {
        refreshed = await _load(widget.householdId);
      } catch (_) {
        refreshed = null; // the change is confirmed; the next load shows it
      }
      if (!mounted) return;
      setState(() {
        if (refreshed != null) _roster = refreshed;
        _settingProvider = false;
      });
      widget.onNafaqahProviderChanged?.call(change.summary);
      AppSnackBar.showSuccess(context, context.tr('nafaqah_provider_updated'));
    } catch (e) {
      if (!mounted) return;
      setState(() => _settingProvider = false);
      AppSnackBar.showError(context, _providerErrorText(e));
    }
  }

  Widget _providerAction(HouseholdRoster roster, String labelKey) {
    if (_settingProvider) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return TextButton(
      onPressed: _busyUserId == null ? () => _chooseProvider(roster) : null,
      child: Text(context.tr(labelKey)),
    );
  }

  /// The Nafaqah provider line (family households only): who he is and, for
  /// admins, a way to change him; or a prompt when the family has none.
  Widget? _providerSection(HouseholdRoster roster) {
    if (roster.isRoommateHousehold) return null;
    if (roster.needsNafaqahProvider) {
      final color = context.dangerColor;
      return Container(
        key: const ValueKey('roles_needs_provider'),
        padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 4, 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: context.isDarkMode ? 0.12 : 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.person_search_rounded, color: color, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('nafaqah_provider_missing_title'),
                    style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    context.tr(roster.canSetNafaqahProvider
                        ? 'nafaqah_provider_missing_admin'
                        : 'nafaqah_provider_missing_member'),
                    style: TextStyle(color: context.textSecondary, fontSize: 11),
                  ),
                ],
              ),
            ),
            if (roster.canSetNafaqahProvider) _providerAction(roster, 'nafaqah_provider_choose'),
          ],
        ),
      );
    }
    final provider = roster.nafaqahProvider;
    if (provider == null || !roster.canSetNafaqahProvider) return null;
    return Row(
      key: const ValueKey('roles_provider_row'),
      children: [
        Icon(Icons.family_restroom_rounded, color: context.champagneGold, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            context.trArgs('nafaqah_provider_current', {'name': _nameOf(provider)}),
            style: TextStyle(color: context.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
        _providerAction(roster, 'nafaqah_provider_change'),
      ],
    );
  }

  List<PopupMenuEntry<_RoleAction>> _actionsFor(HouseholdRoster roster, HouseholdMember m) => [
        if (roster.canPromote(m))
          PopupMenuItem(value: _RoleAction.promote, child: Text(context.tr('roles_make_admin'))),
        if (roster.canRevoke(m))
          PopupMenuItem(value: _RoleAction.revoke, child: Text(context.tr('roles_remove_admin'))),
        if (roster.canMakePrimary(m))
          PopupMenuItem(value: _RoleAction.makePrimary, child: Text(context.tr('roles_make_primary'))),
        // Co-admins never get an action against the primary admin.
        if (roster.maySetFinancialRoles &&
            (!m.isPrimary || roster.callerIsPrimary) &&
            roster.financialRoleOptions(m).isNotEmpty)
          PopupMenuItem(value: _RoleAction.financialRole, child: Text(context.tr('fin_role_change'))),
      ];

  Widget _badge(HouseholdMember m) {
    final String label;
    final Color color;
    if (m.isPrimary) {
      label = context.tr('roles_primary_admin');
      color = context.champagneGold;
    } else if (m.isAdmin) {
      label = context.tr('admin');
      color = context.accentText;
    } else {
      label = context.tr('member');
      color = context.textSecondary;
    }
    return _chip(label, color);
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }

  Widget _memberRow(HouseholdRoster roster, HouseholdMember m) {
    final actions = _actionsFor(roster, m);
    final name = _nameOf(m);
    return Container(
      key: ValueKey('role-member-${m.userId}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: context.scaffoldBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        children: [
          Icon(
            m.isPrimary ? Icons.workspace_premium_rounded : (m.isAdmin ? Icons.shield_outlined : Icons.person_outline_rounded),
            size: 18,
            color: m.isPrimary ? context.champagneGold : (m.isAdmin ? context.accentText : context.textSecondary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  m.isSelf ? '$name (${context.tr('roles_you')})' : name,
                  style: TextStyle(color: context.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _badge(m),
                    if (!roster.isRoommateHousehold && roster.nafaqahProvider?.userId == m.userId)
                      _chip(context.tr('nafaqah_provider_badge'), context.champagneGold),
                    if (_financialRoleKey(m.financialRole) != null)
                      _chip(context.tr(_financialRoleKey(m.financialRole)!), context.accentText),
                  ],
                ),
              ],
            ),
          ),
          if (_busyUserId == m.userId)
            const Padding(
              padding: EdgeInsetsDirectional.only(end: 12),
              child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (actions.isNotEmpty)
            PopupMenuButton<_RoleAction>(
              tooltip: context.trArgs('roles_actions_for', {'name': name}),
              icon: Icon(Icons.more_vert_rounded, color: context.textSecondary),
              color: context.cardBg,
              enabled: _busyUserId == null,
              onSelected: (action) => _run(action, m),
              itemBuilder: (_) => actions,
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final roster = _roster;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.admin_panel_settings_outlined, color: context.accentText, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.tr('roles_title'),
                  style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: context.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            context.tr('roles_subtitle'),
            style: TextStyle(color: context.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            )
          else if (_failed || roster == null)
            Row(
              children: [
                Expanded(
                  child: Text(context.tr('roles_load_failed'), style: TextStyle(color: context.dangerColor, fontSize: 12)),
                ),
                TextButton(onPressed: _fetch, child: Text(context.tr('roles_retry'))),
              ],
            )
          else ...[
            _typeSection(roster),
            const SizedBox(height: 10),
            ...roster.members.map((m) => _memberRow(roster, m)),
            ...[_providerSection(roster)].nonNulls.expand((section) => [const SizedBox(height: 4), section]),
          ],
        ],
      ),
    );
  }
}
