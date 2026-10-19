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
import '../../providers/transaction_provider.dart';
import '../../services/api_service.dart';
import '../../widgets/app_snackbar.dart';
import '../home/dashboard_screen.dart';

class HouseholdScreen extends StatefulWidget {
  final ApiService? apiService;
  final WidgetBuilder? destinationBuilder;
  final Future<Map<String, dynamic>> Function(String code)? joinHandler;

  const HouseholdScreen({
    super.key,
    this.apiService,
    this.destinationBuilder,
    this.joinHandler,
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
    if (code.length == 8) {
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
    if (name.isEmpty) return;
    setState(() => _loading = true);
    try {
      Map<String, dynamic> hh;
      final res = await supabase.rpc(
        'create_household_and_claim',
        params: {'p_name': name},
      );
      if (res is Map && res['error'] != null) {
        throw Exception(res['error']);
      }
      hh = Map<String, dynamic>.from(res as Map);
      final householdId = hh['id'] as String;
      if (mounted) {
        context.read<TransactionProvider>().init(householdId);
        context.read<BudgetProvider>().init(householdId);
        AppSnackBar.showSuccess(
          context,
          'Household "${hh['name']}" created! Invite code: ${hh['invite_code']}',
          title: 'Household Ready',
        );
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: widget.destinationBuilder ?? (_) => const DashboardScreen()),
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
      _showError('Invite code must be between 8 and 16 characters.');
      return;
    }
    setState(() => _loading = true);
    try {
      final invite = _inspectedInvite ?? await _api.inspectInviteCode(code);
      final targetMemberId = invite.targetMemberId;
      final targetMemberName = invite.targetMemberName;
      final uid = _currentUserId;

      if (targetMemberId != null && targetMemberId.isNotEmpty) {
        try {
          await _api.claimMemberProfile(code, uid);
        } catch (_) {}
      }

      final Map<String, dynamic> hh;
      if (widget.joinHandler != null) {
        hh = await widget.joinHandler!(code);
      } else {
        final res = await supabase.rpc(
          'join_household_by_code',
          params: {'p_invite_code': code},
        );
        if (res is Map && res['error'] != null) {
          throw Exception(res['error']);
        }
        hh = Map<String, dynamic>.from(res as Map);
      }
      final householdId = hh['id'] as String;
      if (mounted) {
        try {
          await context.read<TransactionProvider>().init(householdId);
        } catch (_) {}
        if (!mounted) return;
        try {
          await context.read<BudgetProvider>().init(householdId);
        } catch (_) {}
        if (!mounted) return;
        final roleLabel = invite.isSpouse
            ? 'Wife / Spouse'
            : (invite.isPeer ? 'Roommate' : 'Family Member');
        final welcomeMsg = targetMemberName != null && targetMemberName.isNotEmpty
            ? 'Welcome $targetMemberName! Claimed profile as $roleLabel!'
            : 'Joined household "${hh['name'] ?? code}" as $roleLabel!';
        AppSnackBar.showSuccess(
          context,
          welcomeMsg,
          title: 'Welcome to Household',
        );
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: widget.destinationBuilder ?? (_) => const DashboardScreen()),
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

  void _showError(String msg) {
    AppSnackBar.showError(
      context,
      msg,
      title: 'Action Failed',
    );
  }

  Widget _buildTargetedClaimBanner(HouseholdInvite invite) {
    Color bannerColor = const Color(0xFF00C896);
    IconData roleIcon = Icons.stars_rounded;
    String roleLabel = 'Member';

    if (invite.isSpouse) {
      bannerColor = const Color(0xFFE5A93C);
      roleIcon = Icons.favorite_rounded;
      roleLabel = 'Wife / Spouse';
    } else if (invite.isPeer) {
      bannerColor = const Color(0xFF38BDF8);
      roleIcon = Icons.group_outlined;
      roleLabel = 'Roommate';
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
                  'Welcome ${invite.targetMemberName}!',
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: context.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Joining as $roleLabel. Your pre-created profile & balance will merge automatically.',
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
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 32),
              Text('Your Household',
                  style: GoogleFonts.outfit(
                      fontSize: 28, fontWeight: FontWeight.w700, color: context.textPrimary)),
              const SizedBox(height: 8),
              Text('Create a new household or join one.',
                  style: TextStyle(color: context.textSecondary)),
              const SizedBox(height: 32),

              // Tab bar
              TabBar(
                controller: _tab,
                indicatorColor: const Color(0xFF00C896),
                labelColor: const Color(0xFF00C896),
                unselectedLabelColor: context.textSecondary,
                tabs: const [Tab(text: 'Create'), Tab(text: 'Join')],
              ),
              const SizedBox(height: 28),

              Expanded(
                child: TabBarView(
                  controller: _tab,
                  children: [
                    // ── Create ───────────────────────────────────────────
                    Column(
                      children: [
                        TextField(
                          controller: _createNameCtrl,
                          decoration: const InputDecoration(
                            hintText: 'Household name (e.g. Al-Rashidi Family)',
                            prefixIcon: Icon(Icons.home_outlined),
                          ),
                        ),
                        const SizedBox(height: 24),
                        _BigButton(
                          label: 'Create Household',
                          icon: Icons.add_home_outlined,
                          loading: _loading,
                          onTap: _createHousehold,
                        ),
                      ],
                    ),

                    // ── Join ─────────────────────────────────────────────
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _joinCodeCtrl,
                          textCapitalization: TextCapitalization.characters,
                          maxLength: 16,
                          decoration: const InputDecoration(
                            hintText: '8 to 16 character invite code',
                            prefixIcon: Icon(Icons.qr_code_outlined),
                          ),
                        ),
                        if (_inspectedInvite != null &&
                            _inspectedInvite!.targetMemberName != null &&
                            _inspectedInvite!.targetMemberName!.isNotEmpty)
                          _buildTargetedClaimBanner(_inspectedInvite!),
                        const SizedBox(height: 24),
                        _BigButton(
                          label: 'Join Household',
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
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Icon(icon),
        label: Text(label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        onPressed: loading ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF00C896),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}
