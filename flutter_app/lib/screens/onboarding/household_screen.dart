/// Household onboarding: create a new household or join one with an invite code.
library;

import 'package:flutter/material.dart';
import '../../theme/app_themes.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../main.dart';
import '../../models/models.dart';
import '../../providers/budget_provider.dart';
import '../../providers/household_role_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../services/api_service.dart';
import '../../services/household_join.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/settings/household_type_chooser.dart';
import '../../l10n/app_localizations.dart';

class HouseholdScreen extends StatefulWidget {
  final ApiService? apiService;
  final WidgetBuilder? destinationBuilder;
  final Future<Map<String, dynamic>> Function(String code)? joinHandler;

  /// Calls `create_household_and_claim` (defaults to `supabase.rpc`).
  final HouseholdRpc? createRpc;

  const HouseholdScreen({
    super.key,
    this.apiService,
    this.destinationBuilder,
    this.joinHandler,
    this.createRpc,
  });

  @override
  State<HouseholdScreen> createState() => _HouseholdScreenState();
}

class _HouseholdScreenState extends State<HouseholdScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  final _createNameCtrl = TextEditingController();
  final _joinCodeCtrl   = TextEditingController();
  bool _loading = false;
  HouseholdInvite? _inspectedInvite;

  /// Family or Roommates: asked when the household is created.
  String? _householdType;
  bool _showTypeRequired = false;
  bool _showNameRequired = false;

  ApiService get _api => widget.apiService ?? ApiService.instance;

  String get _currentUserId {
    try {
      return supabase.auth.currentUser?.id ?? 'usr_local_test';
    } catch (_) {
      return 'usr_local_test';
    }
  }

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _joinCodeCtrl.addListener(_onJoinCodeChanged);
  }

  void _onJoinCodeChanged() {
    final code = _joinCodeCtrl.text.trim().toUpperCase();
    if (code.length >= 8 && code.length <= 16) {
      _inspectInvite(code);
    } else if (_inspectedInvite != null) {
      setState(() => _inspectedInvite = null);
    }
  }

  Future<void> _inspectInvite(String code) async {
    try {
      final inv = await _api.inspectInviteCode(code);
      if (mounted && _joinCodeCtrl.text.trim().toUpperCase() == code) {
        setState(() => _inspectedInvite = inv);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _joinCodeCtrl.removeListener(_onJoinCodeChanged);
    _tab.dispose();
    _createNameCtrl.dispose();
    _joinCodeCtrl.dispose();
    super.dispose();
  }

  Future<void> _createHousehold() async {
    final name = _createNameCtrl.text.trim();
    if (name.isEmpty) {
      // UX-17: say what is missing instead of doing nothing.
      setState(() => _showNameRequired = true);
      return;
    }
    final type = _householdType;
    if (type == null) {
      setState(() => _showTypeRequired = true);
      return;
    }
    setState(() => _loading = true);
    try {
      final hh = await createHouseholdAndClaim(
        name: name,
        householdType: type,
        rpc: widget.createRpc ?? (fn, params) => supabase.rpc(fn, params: params),
      );
      final householdId = hh['id'] as String;
      if (mounted) {
        context.read<TransactionProvider>().init(householdId);
        context.read<BudgetProvider>().init(householdId);
        try {
          context.read<HouseholdRoleProvider>().load(householdId);
        } catch (_) {}
        AppSnackBar.showSuccess(
          context,
          context.trArgs('hh_created_with_code', {'name': hh['name'], 'code': hh['invite_code']}),
          title: context.tr('hh_ready'),
        );
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: widget.destinationBuilder ?? (_) => const AuthGate()),
          (route) => false,
        );
      }
    } on PostgrestException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _joinHousehold() async {
    final code = _joinCodeCtrl.text.trim().toUpperCase();
    if (code.length < 8 || code.length > 16) {
      _showError(context.tr('hh_invite_code_length'));
      return;
    }
    setState(() => _loading = true);
    try {
      final invite = _inspectedInvite ?? await _api.inspectInviteCode(code);
      final targetMemberId = invite.targetMemberId;
      final targetMemberName = invite.targetMemberName;
      final uid = _currentUserId;

      if (targetMemberId != null && targetMemberId.isNotEmpty) {
        Map<String, dynamic>? claim;
        try {
          claim = await _api.claimMemberProfile(code, uid);
        } catch (_) {}
        // A refused claim (400: already a member of this household, invite
        // used or invalid) stops here with the server's reason; a network
        // failure falls through to the join below.
        if (claim != null) checkInviteClaimResponse(claim);
      }

      final Map<String, dynamic> hh;
      if (widget.joinHandler != null) {
        hh = checkHouseholdJoinResult(await widget.joinHandler!(code));
      } else {
        final res = await supabase.rpc(
          'join_household_by_code',
          params: {'p_invite_code': code},
        );
        hh = checkHouseholdJoinResult(res);
      }
      final householdId = hh['id'] as String;
      if (mounted) {
        try {
          await context.read<TransactionProvider>().init(householdId);
        } catch (_) {}
        if (!mounted) return;
        try {
          context.read<HouseholdRoleProvider>().load(householdId);
        } catch (_) {}
        try {
          await context.read<BudgetProvider>().init(householdId);
        } catch (_) {}
        if (!mounted) return;
        final roleLabel = invite.isSpouse
            ? context.tr('wife_spouse_title')
            : (invite.isPeer ? context.tr('role_roommate') : context.tr('role_family_member'));
        final welcomeMsg = targetMemberName != null && targetMemberName.isNotEmpty
            ? context.trArgs('hh_welcome_claimed', {'name': targetMemberName, 'role': roleLabel})
            : context.trArgs('hh_joined_as', {'name': hh['name'] ?? code, 'role': roleLabel});
        AppSnackBar.showSuccess(
          context,
          welcomeMsg,
          title: context.tr('hh_welcome_to_household'),
        );
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: widget.destinationBuilder ?? (_) => const AuthGate()),
          (route) => false,
        );
      }
    } on PostgrestException catch (e) {
      _showError(e.message);
    } catch (e) {
      if (mounted) _showError(householdJoinErrorText(context, e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    AppSnackBar.showError(
      context,
      msg,
      title: context.tr('action_failed'),
    );
  }

  Widget _buildTargetedClaimBanner(HouseholdInvite invite) {
    Color bannerColor = AppThemes.success;
    IconData roleIcon = Icons.stars_rounded;
    String roleLabel = context.tr('member');

    if (invite.isSpouse) {
      bannerColor = context.warnText;
      roleIcon = Icons.favorite_rounded;
      roleLabel = context.tr('wife_spouse_title');
    } else if (invite.isPeer) {
      bannerColor = context.infoColor;
      roleIcon = Icons.group_outlined;
      roleLabel = context.tr('role_roommate');
    }

    return Container(
      key: const Key('targeted_claim_banner'),
      margin: const EdgeInsets.only(top: 10, bottom: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bannerColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: bannerColor.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: bannerColor.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(roleIcon, color: bannerColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.trArgs('hh_welcome_name', {'name': invite.targetMemberName}),
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: context.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  context.trArgs('hh_joining_as_merge', {'role': roleLabel}),
                  style: TextStyle(
                    fontSize: 11,
                    color: context.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (canPop) ...[
                IconButton(
                  key: const Key('household_back_button'),
                  tooltip: context.tr('nav_back'),
                  icon: Icon(Icons.arrow_back_ios_new_rounded, color: context.textPrimary, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  alignment: AlignmentDirectional.centerStart,
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(height: 16),
              ] else
                const SizedBox(height: 32),
              Text(context.tr('hh_your_household'),
                  style: GoogleFonts.outfit(
                      fontSize: 28, fontWeight: FontWeight.w700, color: context.textPrimary)),
              const SizedBox(height: 8),
              Text(context.tr('hh_create_or_join'),
                  style: TextStyle(color: context.textSecondary)),
              const SizedBox(height: 32),

              // Tab bar
              TabBar(
                controller: _tab,
                indicatorColor: AppThemes.success,
                labelColor: AppThemes.success,
                unselectedLabelColor: context.textSecondary,
                tabs: [Tab(text: context.tr('create')), Tab(text: context.tr('join'))],
              ),
              const SizedBox(height: 28),

              Expanded(
                child: TabBarView(
                  controller: _tab,
                  children: [
                    // ── Create ───────────────────────────────────────────
                    SingleChildScrollView(
                      child: Column(
                      children: [
                        TextField(
                          controller: _createNameCtrl,
                          onChanged: (_) {
                            if (_showNameRequired) setState(() => _showNameRequired = false);
                          },
                          decoration: InputDecoration(
                            hintText: context.tr('hh_name_hint'),
                            prefixIcon: const Icon(Icons.home_outlined),
                            errorText: _showNameRequired ? context.tr('hh_name_required') : null,
                          ),
                        ),
                        const SizedBox(height: 16),
                        HouseholdTypeChooser(
                          value: _householdType,
                          showRequired: _showTypeRequired,
                          onChanged: (type) => setState(() => _householdType = type),
                        ),
                        const SizedBox(height: 24),
                        _BigButton(
                          label: context.tr('hh_create_household'),
                          icon: Icons.add_home_outlined,
                          loading: _loading,
                          onTap: _createHousehold,
                        ),
                      ],
                    ),
                    ),

                    // ── Join ─────────────────────────────────────────────
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _joinCodeCtrl,
                          textCapitalization: TextCapitalization.characters,
                          maxLength: 16,
                          decoration: InputDecoration(
                            hintText: context.tr('hh_invite_code_hint'),
                            prefixIcon: const Icon(Icons.qr_code_outlined),
                          ),
                        ),
                        if (_inspectedInvite != null &&
                            _inspectedInvite!.targetMemberName != null &&
                            _inspectedInvite!.targetMemberName!.isNotEmpty)
                          _buildTargetedClaimBanner(_inspectedInvite!),
                        const SizedBox(height: 24),
                        _BigButton(
                          label: context.tr('join_household'),
                          icon: Icons.group_add_outlined,
                          loading: _loading,
                          onTap: _joinHousehold,
                        ),
                      ],
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
}

class _BigButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool loading;
  final VoidCallback onTap;

  const _BigButton({
    required this.label,
    required this.icon,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        icon: loading
            ? const SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppThemes.onSuccessFill))
            : Icon(icon),
        label: Text(label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        onPressed: loading ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppThemes.success,
          foregroundColor: AppThemes.onSuccessFill,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}
