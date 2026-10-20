import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/app_localizations.dart';
import '../../models/household_membership.dart';
import '../../services/api/household_roles_api_client.dart';
import '../../services/api_service.dart';
import '../../theme/app_themes.dart';
import '../app_snackbar.dart';

typedef RosterLoader = Future<HouseholdRoster> Function(String householdId);
typedef RosterAction = Future<HouseholdRoster> Function(String householdId, String userId);

enum _RoleAction { promote, revoke, makePrimary }

/// Members of the household with their roles. Admins promote members to
/// co-admin and revoke co-admins; the primary admin also transfers primary
/// admin. Co-admins never see an action against the primary admin. Every
/// change is enforced by the server (DB-16 / DB-18); a refusal is explained.
class HouseholdRolesCard extends StatefulWidget {
  final String householdId;
  final RosterLoader? loadRoster;
  final RosterAction? promote;
  final RosterAction? revoke;
  final RosterAction? transferPrimary;

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

  RosterLoader get _load => widget.loadRoster ?? ApiService.instance.getHouseholdMembers;
  RosterAction get _promote => widget.promote ?? ApiService.instance.promoteHouseholdAdmin;
  RosterAction get _revoke => widget.revoke ?? ApiService.instance.revokeHouseholdAdmin;
  RosterAction get _transfer => widget.transferPrimary ?? ApiService.instance.transferPrimaryAdmin;

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
              style: ElevatedButton.styleFrom(backgroundColor: AppThemes.success, foregroundColor: Colors.black),
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
      _RoleAction.makePrimary => _transfer,
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

  List<PopupMenuEntry<_RoleAction>> _actionsFor(HouseholdRoster roster, HouseholdMember m) => [
        if (roster.canPromote(m))
          PopupMenuItem(value: _RoleAction.promote, child: Text(context.tr('roles_make_admin'))),
        if (roster.canRevoke(m))
          PopupMenuItem(value: _RoleAction.revoke, child: Text(context.tr('roles_remove_admin'))),
        if (roster.canMakePrimary(m))
          PopupMenuItem(value: _RoleAction.makePrimary, child: Text(context.tr('roles_make_primary'))),
      ];

  Widget _badge(HouseholdMember m) {
    final String label;
    final Color color;
    if (m.isPrimary) {
      label = context.tr('roles_primary_admin');
      color = context.champagneGold;
    } else if (m.isAdmin) {
      label = context.tr('admin');
      color = context.successText;
    } else {
      label = context.tr('member');
      color = context.textSecondary;
    }
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
            color: m.isPrimary ? context.champagneGold : (m.isAdmin ? context.successText : context.textSecondary),
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
                _badge(m),
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
              const Icon(Icons.admin_panel_settings_outlined, color: AppThemes.success, size: 20),
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
          else
            ...roster.members.map((m) => _memberRow(roster, m)),
        ],
      ),
    );
  }
}
