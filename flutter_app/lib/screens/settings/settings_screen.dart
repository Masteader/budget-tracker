import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../main.dart';
import '../onboarding/household_screen.dart';
import '../../models/models.dart';
import '../../models/nafaqah.dart' show NafaqahSummary;
import '../../services/api_service.dart';
import '../../services/household_join.dart';
import '../../services/csv_export_service.dart';
import '../../services/offline_sync_service.dart';
import '../../widgets/dashboard/family_reimbursement_card.dart';
import '../../widgets/dashboard/multi_roommate_settlement_card.dart';
import '../../widgets/zatca_qr_camera_scanner.dart';
import 'package:provider/provider.dart';
import '../../providers/household_role_provider.dart';
import '../../providers/locale_provider.dart';
import '../../providers/theme_provider.dart';
import '../../widgets/settings/income_settings_card.dart';
import '../../widgets/settings/household_management_card.dart';
import '../../widgets/settings/household_roles_card.dart';
import '../../widgets/settings/household_type_chooser.dart';
import '../../widgets/settings/add_household_member_sheet.dart';
import '../../widgets/settings/payday_settings_card.dart';
import '../../widgets/settings/rollover_settings_card.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/dispose_on_unmount.dart';
import '../../widgets/settings/household_switch_sheet.dart';
import '../../widgets/onboarding/user_guide_walkthrough_dialog.dart';
import '../../theme/app_themes.dart';
import '../../l10n/app_localizations.dart';
import '../accounts/accounts_overview_screen.dart';
import 'help_support_screen.dart';
import '../../services/salary_cycle_service.dart';
import '../../services/household_setting_saver.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {

  // Permission statuses
  PermissionStatus _cameraStatus = PermissionStatus.denied;
  PermissionStatus _microphoneStatus = PermissionStatus.denied;
  PermissionStatus _notificationStatus = PermissionStatus.denied;

  String? _householdId;
  String? _userEmail;
  String? _householdName;
  String? _inviteCode;
  String _userRole = 'member';
  List<Map<String, dynamic>> _members = [];
  List<HouseholdDependent> _dependents = [];
  int _paydayDay = 27;

  /// Bumped when the Nafaqah provider changes so the family card reloads.
  int _nafaqahRevision = 0;
  double _monthlyIncome = 0.0;
  String _rolloverRule = 'send_to_savings';
  double _accumulatedSavings = 0.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissions();
    _loadUserInfo();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Re-check permissions when user returns from phone App Settings
      _checkPermissions();
    }
  }

  Future<void> _checkPermissions() async {
    try {
      final camera = await Permission.camera.status;
      final microphone = await Permission.microphone.status;
      final notification = await Permission.notification.status;

      if (mounted) {
        setState(() {
          _cameraStatus = camera;
          _microphoneStatus = microphone;
          _notificationStatus = notification;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadUserInfo() async {
    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
        final data = await supabase
            .from('users')
            .select('household_id, display_name, role')
            .eq('id', user.id)
            .maybeSingle();
        if (data != null && mounted) {
          final hid = data['household_id'] as String?;
          setState(() {
            _householdId = hid;
            _userRole = data['role'] as String? ?? 'member';
            _userEmail = user.email ?? (data['display_name'] as String?) ?? context.tr('set_user');
          });
          if (hid != null) {
            await _loadHouseholdDetails(hid);
          }
        }
      }
    } catch (_) {}
  }

  /// A role change was confirmed by the server: refresh the signed-in user's
  /// own role (badge, edit rights, shared-pool transfers).
  void _onRolesChanged() {
    try {
      context.read<HouseholdRoleProvider>().refresh();
    } catch (_) {}
    _loadUserInfo();
  }

  /// A new Nafaqah provider was confirmed: reload the family Nafaqah card.
  void _onNafaqahProviderChanged(NafaqahSummary? _) {
    if (mounted) setState(() => _nafaqahRevision++);
  }

  Future<void> _loadHouseholdDetails(String hid) async {
    try {
      // Via get_user_households(): the RPC returns the invite code to admins
      // only, so the households table no longer needs to expose it (DB-17).
      final membership = await ApiService.instance.getHouseholdMembership(hid);
      final membersData = await supabase
          .from('users')
          .select('display_name, role')
          .eq('household_id', hid);

      if (mounted) {
        setState(() {
          _householdName = membership?.householdName ?? context.tr('set_my_household');
          final code = membership?.inviteCode ?? '';
          _inviteCode = code.isNotEmpty ? code : '--------';
          _members = (membersData as List?)
                  ?.map((e) {
                    final map = Map<String, dynamic>.from(e as Map);
                    return {
                      'email': (map['display_name'] as String?) ?? context.tr('member'),
                      'role': map['role'] ?? 'member',
                    };
                  })
                  .toList() ??
              [];
        });
      }

      // Load configured monthly payday
      int payday = 27;
      try {
        final prefs = await SharedPreferences.getInstance();
        payday = prefs.getInt('payday_day') ?? 27;
        final serverDay = await ApiService.instance.getHouseholdPayday(hid);
        if (serverDay >= 1 && serverDay <= 31) {
          payday = serverDay;
          await prefs.setInt('payday_day', payday);
        }
      } catch (_) {}
      if (mounted) {
        setState(() => _paydayDay = payday);
      }

      // Load configured monthly income
      double income = 0.0;
      try {
        final prefs = await SharedPreferences.getInstance();
        income = prefs.getDouble('household_monthly_income') ?? 0.0;
        final serverIncome = await ApiService.instance.getHouseholdIncome(hid);
        if (serverIncome > 0) {
          income = serverIncome;
          await prefs.setDouble('household_monthly_income', income);
        }
      } catch (_) {}
      if (mounted) {
        setState(() => _monthlyIncome = income);
      }

      // Load configured budget rollover rule & savings surplus
      String rollover = 'send_to_savings';
      double savingsSurplus = 0.0;
      try {
        final prefs = await SharedPreferences.getInstance();
        rollover = prefs.getString('household_rollover_rule') ?? 'send_to_savings';
        final serverRule = await ApiService.instance.getHouseholdRolloverRule(hid);
        if (serverRule.isNotEmpty) {
          rollover = serverRule;
          await prefs.setString('household_rollover_rule', rollover);
        }
        final summary = await ApiService.instance.getHouseholdSavingsSummary(hid);
        savingsSurplus = (summary['accumulated_savings'] as num?)?.toDouble() ?? 0.0;
      } catch (_) {}
      if (mounted) {
        setState(() {
          _rolloverRule = rollover;
          _accumulatedSavings = savingsSurplus;
        });
      }

      // Load household dependents
      try {
        final deps = await ApiService.instance.getDependents(hid);
        if (mounted) {
          setState(() => _dependents = deps);
        }
      } catch (_) {}
    } catch (_) {}
  }

  /// Awaits the API save and, only when it succeeded, mirrors the column on
  /// `households` directly (best effort, as before) for DB parity.
  Future<bool> _confirmAndMirror(Future<bool> apiSave, String householdId, Map<String, dynamic> column) async {
    final confirmed = await apiSave;
    if (confirmed) {
      try {
        await supabase.from('households').update(column).eq('id', householdId);
      } catch (_) {}
    }
    return confirmed;
  }

  /// Error text for a failed household-setting save (MOB-27).
  String _settingSaveError(Object e) =>
      e is HouseholdSettingNotSavedException ? context.tr('setting_not_saved_server') : e.toString();

  // MOB-27: payday, income and rollover are saved server-first; the local
  // cache and on-screen value change only after the server confirmed, so a
  // rejected save keeps the previous value and shows an error.
  Future<bool> _savePayday(int newDay) async {
    try {
      await saveHouseholdSetting<int>(
        householdId: _householdId,
        value: newDay,
        saveRemote: (hid, day) => _confirmAndMirror(ApiService.instance.setHouseholdPayday(hid, day), hid, {'payday_day': day}),
        applyLocal: (day) async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt('payday_day', day);
          SalaryCycleService.paydayDay = day;
        },
      );
      if (mounted) setState(() => _paydayDay = newDay);
      return true;
    } catch (e) {
      if (mounted) {
        AppSnackBar.showError(
          context,
          context.trArgs('set_failed_save_payday', {'error': _settingSaveError(e)}),
          title: context.tr('set_payday_error'),
        );
      }
      return false;
    }
  }

  Future<bool> _saveIncome(double newIncome) async {
    try {
      await saveHouseholdSetting<double>(
        householdId: _householdId,
        value: newIncome,
        saveRemote: (hid, income) => _confirmAndMirror(ApiService.instance.setHouseholdIncome(hid, income), hid, {'monthly_income': income}),
        applyLocal: (income) async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setDouble('household_monthly_income', income);
        },
      );
      if (mounted) setState(() => _monthlyIncome = newIncome);
      return true;
    } catch (e) {
      if (mounted) {
        AppSnackBar.showError(
          context,
          context.trArgs('set_failed_save_income', {'error': _settingSaveError(e)}),
          title: context.tr('set_income_error'),
        );
      }
      return false;
    }
  }

  Future<bool> _saveRolloverRule(String newRule) async {
    try {
      await saveHouseholdSetting<String>(
        householdId: _householdId,
        value: newRule,
        saveRemote: (hid, rule) => _confirmAndMirror(ApiService.instance.setHouseholdRolloverRule(hid, rule), hid, {'rollover_rule': rule}),
        applyLocal: (rule) async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('household_rollover_rule', rule);
        },
      );
      if (mounted) setState(() => _rolloverRule = newRule);
      return true;
    } catch (e) {
      if (mounted) {
        AppSnackBar.showError(
          context,
          context.trArgs('set_failed_save_rollover_policy', {'error': _settingSaveError(e)}),
          title: context.tr('set_rollover_error'),
        );
      }
      return false;
    }
  }

  Future<void> _requestCameraPermission() async {
    final status = await Permission.camera.request();
    if (mounted) {
      setState(() => _cameraStatus = status);
      if (status.isGranted) {
        AppSnackBar.showSuccess(
          context,
          context.tr('set_camera_permission_granted_ready_scan'),
          title: context.tr('set_camera_enabled'),
        );
      } else if (status.isPermanentlyDenied) {
        _showPermissionDialog(
          title: context.tr('set_camera_permission_denied'),
          message:
              context.tr('set_camera_access_has_been_permanently'),
        );
      }
    }
  }

  Future<void> _requestMicrophonePermission() async {
    final status = await Permission.microphone.request();
    if (mounted) {
      setState(() => _microphoneStatus = status);
      if (status.isGranted) {
        AppSnackBar.showSuccess(
          context,
          context.tr('set_microphone_permission_granted_ready_voice'),
          title: context.tr('set_microphone_enabled'),
        );
      } else if (status.isPermanentlyDenied) {
        _showPermissionDialog(
          title: context.tr('set_microphone_permission_denied'),
          message:
              context.tr('set_microphone_access_has_been_permanently'),
        );
      }
    }
  }

  void _showPermissionDialog({required String title, required String message}) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.cardBg,
        title: Row(
          children: [
            const Icon(Icons.settings_suggest_rounded, color: AppThemes.success),
            const SizedBox(width: 8),
            Text(title, style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 17, color: context.textPrimary)),
          ],
        ),
        content: Text(message, style: TextStyle(color: context.textSecondary, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('cancel'), style: TextStyle(color: context.textSecondary)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppThemes.success,
              foregroundColor: Colors.black,
            ),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: Text(context.tr('open_settings'), style: const TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
          ),
        ],
      ),
    );
  }

  void _copyInviteCode() {
    if (_inviteCode != null && _inviteCode != '--------') {
      Clipboard.setData(ClipboardData(text: _inviteCode!));
      AppSnackBar.showSuccess(
        context,
        context.trArgs('set_invite_code_copied_share_partner', {'code': _inviteCode}),
        title: context.tr('set_code_copied'),
        icon: Icons.copy_rounded,
      );
    }
  }

  Future<void> _confirmLeaveHousehold() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.cardBg,
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFF85149)),
            const SizedBox(width: 8),
            Text(context.tr('leave_household'), style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 17, color: context.textPrimary)),
          ],
        ),
        content: Text(
          context.tr('leave_household_confirm'),
          style: TextStyle(color: context.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('cancel'), style: TextStyle(color: context.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF85149),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr('leave'), style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final uid = supabase.auth.currentUser?.id;
      if (uid == null) return;
      try {
        final res = await supabase.rpc('leave_household');
        if (res is Map && res['error'] != null) {
          throw Exception(res['error']);
        }

        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            // Back through the gate: it re-resolves (now no household) and
            // keeps sign-out handling at the root of the navigator.
            MaterialPageRoute(builder: (_) => const AuthGate()),
            (route) => false,
          );
        }
      } catch (e) {
        if (mounted) {
          AppSnackBar.showError(
            context,
            context.trArgs('set_failed_leave_household', {'error': e}),
            title: context.tr('set_leave_household_error'),
          );
        }
      }
    }
  }

  void _showHouseholdSwitchSheet() {
    if (_householdId == null) return;
    HouseholdSwitchSheet.show(
      context,
      currentHouseholdId: _householdId!,
      onSwitched: _loadUserInfo,
      onJoinNew: _showJoinHouseholdDialog,
      onCreateNew: _showCreateHouseholdDialog,
    );
  }

  Future<void> _showJoinHouseholdDialog() async {
    final codeCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => DisposeOnUnmount(
        disposables: [codeCtrl],
        child: AlertDialog(
        backgroundColor: context.cardBg,
        title: Text(context.tr('join_household'), style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 17, color: context.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.tr('join_household_desc'), style: TextStyle(color: context.textSecondary, fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: codeCtrl,
              textCapitalization: TextCapitalization.characters,
              maxLength: 16,
              style: GoogleFonts.jetBrainsMono(color: context.textPrimary, fontSize: 16, letterSpacing: 2),
              decoration: InputDecoration(
                hintText: context.tr('set_8_16_characters'),
                counterText: '',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('cancel'), style: TextStyle(color: context.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppThemes.success,
              foregroundColor: Colors.black,
            ),
            child: Text(context.tr('join'), style: const TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () async {
              final code = codeCtrl.text.trim().toUpperCase();
              if (code.length < 8 || code.length > 16) return;
              Navigator.pop(ctx);
              try {
                final res = await supabase.rpc('join_household_by_code', params: {'p_invite_code': code});
                checkHouseholdJoinResult(res);
                if (mounted) {
                  AppSnackBar.showSuccess(
                    context,
                    context.tr('set_have_successfully_joined_household'),
                    title: context.tr('set_household_joined'),
                  );
                  _loadUserInfo();
                }
              } catch (e) {
                if (mounted) {
                  AppSnackBar.showError(
                    context,
                    context.trArgs('set_failed_join', {'error': householdJoinErrorText(context, e)}),
                    title: context.tr('set_join_error'),
                  );
                }
              }
            },
          ),
        ],
      ),
      ),
    );
  }

  Future<void> _showCreateHouseholdDialog() async {
    final nameCtrl = TextEditingController();
    // Family or Roommates: asked when the household is created.
    String? householdType;
    var showTypeRequired = false;
    await showDialog(
      context: context,
      builder: (ctx) => DisposeOnUnmount(
        disposables: [nameCtrl],
        child: StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
        backgroundColor: context.cardBg,
        title: Text(context.tr('new_household'), style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 17, color: context.textPrimary)),
        content: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.tr('set_enter_name_new_household'), style: TextStyle(color: context.textSecondary, fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: nameCtrl,
              style: TextStyle(color: context.textPrimary),
              decoration: InputDecoration(
                hintText: context.tr('set_e_g_summer_beach_house'),
              ),
            ),
            const SizedBox(height: 12),
            HouseholdTypeChooser(
              value: householdType,
              showRequired: showTypeRequired,
              onChanged: (type) => setDialogState(() => householdType = type),
            ),
          ],
        ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('cancel'), style: TextStyle(color: context.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppThemes.success,
              foregroundColor: Colors.black,
            ),
            child: Text(context.tr('create'), style: const TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              final type = householdType;
              if (type == null) {
                setDialogState(() => showTypeRequired = true);
                return;
              }
              Navigator.pop(ctx);
              try {
                final res = await createHouseholdAndClaim(
                  name: name,
                  householdType: type,
                  rpc: (fn, params) => supabase.rpc(fn, params: params),
                );
                final hhName = res['name'] ?? name;

                if (mounted) {
                  AppSnackBar.showSuccess(
                    context,
                    context.trArgs('set_created_household', {'name': hhName}),
                    title: context.tr('set_household_created'),
                  );
                  _loadUserInfo();
                }
              } catch (e) {
                if (mounted) {
                  AppSnackBar.showError(
                    context,
                    context.trArgs('set_failed_create_household', {'error': e}),
                    title: context.tr('set_creation_error'),
                  );
                }
              }
            },
          ),
        ],
      ),
      ),
      ),
    );
  }

  Future<void> _showAddDependentDialog() async {
    final result = await AddHouseholdMemberSheet.show(context);

    if (result != null && result.name.isNotEmpty && _householdId != null) {
      try {
        final res = await ApiService.instance.createDependent(
          _householdId!,
          result.name,
          relationship: result.relationship,
          monthlyAllowance: result.monthlyAllowance,
          avatarIcon: result.avatarIcon,
        );
        if (res != null) {
          final updated = await ApiService.instance.getDependents(_householdId!);
          if (mounted) {
            setState(() => _dependents = updated);
            AppSnackBar.showSuccess(
              context,
              context.trArgs('set_added_member_successfully', {'name': result.name}),
              title: context.tr('set_member_added'),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          AppSnackBar.showError(
            context,
            context.trArgs('set_failed_add_member', {'error': e}),
            title: context.tr('set_error'),
          );
        }
      }
    }
  }

  Future<void> _removeDependent(HouseholdDependent dependent) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: context.borderColor),
        ),
        title: Row(
          children: [
            const Icon(Icons.delete_outline_rounded, color: Color(0xFFF85149)),
            const SizedBox(width: 8),
            Text(
              context.tr('set_remove_dependent'),
              style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 17, color: context.textPrimary),
            ),
          ],
        ),
        content: Text(
          context.trArgs('set_are_sure_want_remove_from', {'name': dependent.name}),
          style: GoogleFonts.outfit(color: context.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('cancel'), style: TextStyle(color: context.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF85149),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr('set_remove'), style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true && _householdId != null) {
      try {
        final ok = await ApiService.instance.deleteDependent(_householdId!, dependent.id);
        if (ok) {
          final updated = await ApiService.instance.getDependents(_householdId!);
          if (mounted) {
            setState(() => _dependents = updated);
            AppSnackBar.showSuccess(
              context,
              context.trArgs('set_removed_dependent', {'name': dependent.name}),
              title: context.tr('set_dependent_removed'),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          AppSnackBar.showError(
            context,
            context.trArgs('set_failed_remove_dependent', {'error': e}),
            title: context.tr('set_error'),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: AppBar(
        title: Text(context.tr('settings_and_permissions'), style: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: context.textPrimary)),
        backgroundColor: context.scaffoldBg,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: context.textSecondary),
            tooltip: context.tr('set_refresh_permissions'),
            onPressed: _checkPermissions,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
        children: [
          // ── 0. HOUSEHOLD MANAGEMENT & INVITES ──
          _buildSectionHeader(context.tr('set_household_membership')),
          const SizedBox(height: 6),
          Text(
            context.tr('set_manage_shared_budget_group_invite'),
            style: GoogleFonts.outfit(fontSize: 12, color: context.textSecondary),
          ),
          const SizedBox(height: 12),
          if (_householdId != null) ...[
            HouseholdManagementCard(
              householdName: _householdName ?? context.tr('set_household'),
              householdId: _householdId,
              inviteCode: _inviteCode ?? '--------',
              userRole: _userRole,
              members: _members,
              dependents: _dependents,
              onCopyInviteCode: _copyInviteCode,
              onLeaveHousehold: _confirmLeaveHousehold,
              onSwitchHousehold: _showHouseholdSwitchSheet,
              onCreateHousehold: _showCreateHouseholdDialog,
              onAddDependent: _showAddDependentDialog,
              onRemoveDependent: _removeDependent,
            ),
            const SizedBox(height: 16),
            HouseholdRolesCard(
              householdId: _householdId!,
              onRolesChanged: _onRolesChanged,
              onNafaqahProviderChanged: _onNafaqahProviderChanged,
            ),
            const SizedBox(height: 16),
            PaydaySettingsCard(
              initialPayday: _paydayDay,
              onSavePayday: _savePayday,
            ),
            const SizedBox(height: 16),
            IncomeSettingsCard(
              initialIncome: _monthlyIncome,
              onSaveIncome: _saveIncome,
            ),
            const SizedBox(height: 16),
            RolloverSettingsCard(
              initialRule: _rolloverRule,
              accumulatedSavings: _accumulatedSavings,
              onSaveRule: _saveRolloverRule,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.borderColor),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: context.electricTeal.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.account_balance_wallet_rounded,
                      color: context.electricTeal,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr('accounts_balances'),
                          style: GoogleFonts.outfit(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: context.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          context.tr('accounts_balances_desc'),
                          style: TextStyle(
                            fontSize: 12,
                            color: context.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AccountsOverviewScreen(
                            householdId: _householdId!,
                          ),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.electricTeal,
                      foregroundColor: context.scaffoldBg,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      context.tr('manage'),
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.cardBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: context.borderColor),
              ),
              child: Column(
                children: [
                  Text(
                    context.tr('set_have_not_joined_any_household'),
                    style: TextStyle(color: context.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppThemes.success,
                      foregroundColor: Colors.black,
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const HouseholdScreen()),
                      );
                    },
                    child: Text(context.tr('set_join_create_household'), style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 28),

          // ── APPEARANCE & LANGUAGE ──
          _buildSectionHeader(context.tr('appearance_language')),
          const SizedBox(height: 6),
          Text(
            context.tr('set_customize_app_theme_system_language'),
            style: GoogleFonts.outfit(fontSize: 12, color: context.textSecondary),
          ),
          const SizedBox(height: 12),
          _buildAppearanceAndLanguageCard(),
          const SizedBox(height: 24),

          // ── 1. HARDWARE & APP PERMISSIONS ──
          _buildSectionHeader(context.tr('hardware_permissions')),
          const SizedBox(height: 6),
          Text(
            context.tr('set_check_manage_camera_microphone_access'),
            style: GoogleFonts.outfit(fontSize: 12, color: context.textSecondary),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: context.cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.borderColor),
            ),
            child: Column(
              children: [
                _buildCompactPermissionRow(
                  icon: Icons.camera_alt_outlined,
                  title: context.tr('camera_access'),
                  subtitle: context.tr('camera_access_desc'),
                  status: _cameraStatus,
                  onRequest: _requestCameraPermission,
                  onOpenSettings: openAppSettings,
                  testAction: _cameraStatus.isGranted
                      ? () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const ZatcaQrCameraScanner()),
                          )
                      : null,
                  testLabel: context.tr('test_camera'),
                ),
                Divider(color: context.borderColor, height: 1),
                _buildCompactPermissionRow(
                  icon: Icons.mic_none_outlined,
                  title: context.tr('microphone_access'),
                  subtitle: context.tr('microphone_access_desc'),
                  status: _microphoneStatus,
                  onRequest: _requestMicrophonePermission,
                  onOpenSettings: openAppSettings,
                ),
                Divider(color: context.borderColor, height: 1),
                _buildCompactPermissionRow(
                  icon: Icons.notifications_active_outlined,
                  title: context.tr('notifications'),
                  subtitle: context.tr('notifications_desc'),
                  status: _notificationStatus,
                  onRequest: () async {
                    final status = await Permission.notification.request();
                    setState(() => _notificationStatus = status);
                  },
                  onOpenSettings: openAppSettings,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── HOUSEHOLD SETTLEMENT & NAFAQAH ──
          if (_householdId != null && _members.length > 1) ...[
            _buildSectionHeader(context.tr('partner_settlement')),
            const SizedBox(height: 10),
            FutureBuilder<SettlementV2Summary>(
              future: ApiService.instance.getSettlementV2(_householdId!),
              builder: (context, snap) {
                if (snap.hasData && snap.data!.isRoommateMode) {
                  return MultiRoommateSettlementCard(
                    householdId: _householdId!,
                    summary: snap.data,
                  );
                }
                return FamilyReimbursementCard(
                  key: ValueKey('family-nafaqah-$_nafaqahRevision'),
                  householdId: _householdId!,
                );
              },
            ),
            const SizedBox(height: 24),
          ],

          // ── DATA EXPORT & OFFLINE QUEUE ──
          _buildSectionHeader(context.tr('reports_offline_queue')),
          const SizedBox(height: 10),
          Container(
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
                    const Icon(Icons.table_view_rounded, color: AppThemes.success, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(context.tr('set_export_monthly_report'), style: GoogleFonts.outfit(color: context.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
                          Text(context.tr('set_generate_standard_csv_date_merchant'), style: TextStyle(color: context.textSecondary, fontSize: 11)),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: context.chipBg,
                        foregroundColor: AppThemes.success,
                        side: const BorderSide(color: AppThemes.success),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      ),
                      onPressed: () async {
                        if (_householdId == null) return;
                        try {
                          final res = await supabase
                              .from('transactions')
                              .select()
                              .eq('household_id', _householdId!)
                              .order('timestamp', ascending: false)
                              .limit(500);
                          if (!context.mounted) return;
                          CsvExportService.showExportDialog(context, List<Map<String, dynamic>>.from(res), monthLabel: 'Monthly Export');
                        } catch (e) {
                          if (!context.mounted) return;
                          AppSnackBar.showError(
                            context,
                            context.trArgs('set_export_error', {'error': e}),
                            title: context.tr('set_export_failed'),
                          );
                        }
                      },
                      child: Text(context.tr('export_csv'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Divider(color: context.borderColor, height: 1),
                const SizedBox(height: 14),
                ValueListenableBuilder<int>(
                  valueListenable: OfflineSyncService.instance.pendingCountNotifier,
                  builder: (ctx, count, _) {
                    return Row(
                      children: [
                        Icon(count > 0 ? Icons.cloud_off_rounded : Icons.cloud_done_rounded, color: count > 0 ? Colors.orange : context.electricTeal, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(context.tr('set_offline_sqlite_queue'), style: GoogleFonts.outfit(color: context.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
                              Text(count > 0 ? context.trPlural('set_transaction_s_pending_sync', count) : context.tr('set_all_transactions_synchronized'), style: TextStyle(color: context.textSecondary, fontSize: 11)),
                            ],
                          ),
                        ),
                        if (count > 0)
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: context.electricTeal,
                              foregroundColor: context.isDark ? Colors.black : Colors.white,
                            ),
                            onPressed: () => OfflineSyncService.instance.flushQueue(),
                            child: Text(context.tr('sync_now'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── HELP & SUPPORT ──
          _buildSectionHeader(context.tr('set_help_support')),
          const SizedBox(height: 6),
          Text(
            context.tr('set_explore_user_guides_interactive_walkthroughs'),
            style: GoogleFonts.outfit(fontSize: 12, color: context.textSecondary),
          ),
          const SizedBox(height: 10),
          Card(
            color: context.cardBg,
            elevation: 0,
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: context.borderColor),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppThemes.success.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.menu_book_rounded, color: AppThemes.success, size: 20),
                  ),
                  title: Text(
                    context.tr('set_app_guide_tutorial'),
                    style: GoogleFonts.outfit(color: context.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  subtitle: Text(
                    context.tr('set_replay_5_step_interactive_feature'),
                    style: GoogleFonts.outfit(color: context.textSecondary, fontSize: 12),
                  ),
                  trailing: Icon(Icons.chevron_right_rounded, color: context.textSecondary),
                  onTap: () => UserGuideWalkthroughDialog.show(context),
                ),
                Divider(color: context.borderColor, height: 1),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.support_agent_rounded, color: Color(0xFF3B82F6), size: 20),
                  ),
                  title: Text(
                    context.tr('set_help_center_ai_support'),
                    style: GoogleFonts.outfit(color: context.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  subtitle: Text(
                    context.tr('set_searchable_faqs_salary_cycle_guide'),
                    style: GoogleFonts.outfit(color: context.textSecondary, fontSize: 12),
                  ),
                  trailing: Icon(Icons.chevron_right_rounded, color: context.textSecondary),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => HelpSupportScreen(
                          householdId: _householdId,
                          userEmail: _userEmail,
                        ),
                      ),
                    );
                  },
                ),
                Divider(color: context.borderColor, height: 1),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.mail_outline_rounded, color: Color(0xFFF59E0B), size: 20),
                  ),
                  title: Text(
                    context.tr('contact_developer'),
                    style: GoogleFonts.outfit(color: context.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  subtitle: Text(
                    context.trArgs('set_email_dev_feedback', {'email': 'fmscoinfo@fmsco.com.sa'}),
                    style: GoogleFonts.outfit(color: context.textSecondary, fontSize: 12),
                  ),
                  trailing: Icon(Icons.chevron_right_rounded, color: context.textSecondary),
                  onTap: () {
                    Clipboard.setData(const ClipboardData(text: 'fmscoinfo@fmsco.com.sa'));
                    AppSnackBar.showSuccess(
                      context,
                      context.trArgs('set_dev_email_copied', {'email': 'fmscoinfo@fmsco.com.sa'}),
                      title: context.tr('set_copied'),
                      icon: Icons.copy_rounded,
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── 4. HOUSEHOLD & ACCOUNT ──
          _buildSectionHeader(context.tr('set_household_account')),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_userEmail != null) ...[
                  Row(
                    children: [
                      Icon(Icons.account_circle_outlined, color: context.textSecondary, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _userEmail!,
                          style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                if (_householdId != null) ...[
                  Row(
                    children: [
                      Icon(Icons.home_outlined, color: context.textSecondary, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          context.trArgs('set_household_short_id', {'id': _householdId!.substring(0, 8)}),
                          style: TextStyle(color: context.textSecondary, fontSize: 12, fontFamily: 'monospace'),
                        ),
                      ),
                      InkWell(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: _householdId!));
                          AppSnackBar.showSuccess(
                            context,
                            context.tr('set_household_id_copied_clipboard'),
                            title: context.tr('set_copied'),
                            icon: Icons.copy_rounded,
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          child: Text(context.tr('set_copy'), style: TextStyle(color: context.successText, fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      side: const BorderSide(color: Color(0xFFDA3633)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.logout, size: 18),
                    label: Text(context.tr('sign_out'), style: const TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () => supabase.auth.signOut(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: GoogleFonts.outfit(
        fontSize: 12,
        letterSpacing: 1,
        fontWeight: FontWeight.w700,
        color: context.textSecondary,
      ),
    );
  }

  Widget _buildAppearanceAndLanguageCard() {
    final themeProvider = context.watch<ThemeProvider>();
    final localeProvider = context.watch<LocaleProvider>();

    final cardColor = context.cardBg;
    final borderColor = context.borderColor;
    final textColor = context.textPrimary;
    final subtextColor = context.textSecondary;
    const activeBg = AppThemes.success;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Theme Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppThemes.success.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.palette_rounded, color: AppThemes.success, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.tr('appearance'), style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16, color: textColor)),
                    Text(context.tr('set_system_default_light_mode_dark'), style: TextStyle(color: subtextColor, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Theme Switcher Buttons (System, Light, Dark)
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: context.inputBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              children: [
                _buildThemeOption(
                  label: context.tr('theme_system'),
                  icon: Icons.brightness_auto_rounded,
                  isSelected: themeProvider.themeMode == ThemeMode.system,
                  onTap: () => themeProvider.setThemeMode(ThemeMode.system),
                  activeBg: activeBg,
                  textColor: textColor,
                ),
                _buildThemeOption(
                  label: context.tr('theme_light'),
                  icon: Icons.light_mode_rounded,
                  isSelected: themeProvider.themeMode == ThemeMode.light,
                  onTap: () => themeProvider.setThemeMode(ThemeMode.light),
                  activeBg: activeBg,
                  textColor: textColor,
                ),
                _buildThemeOption(
                  label: context.tr('theme_dark'),
                  icon: Icons.dark_mode_rounded,
                  isSelected: themeProvider.themeMode == ThemeMode.dark,
                  onTap: () => themeProvider.setThemeMode(ThemeMode.dark),
                  activeBg: activeBg,
                  textColor: textColor,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Divider(color: borderColor, height: 1),
          const SizedBox(height: 16),

          // Language Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: context.electricTeal.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.language_rounded, color: context.electricTeal, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.tr('language'), style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16, color: textColor)),
                    Text(context.tr('set_general_application_language_en_ar'), style: TextStyle(color: subtextColor, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Language Switcher Buttons (English, Arabic, Urdu)
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: context.inputBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              children: [
                _buildLanguageOption(
                  label: 'English',
                  code: 'en',
                  flag: '🇺🇸',
                  isSelected: localeProvider.languageCode == 'en',
                  onTap: () => localeProvider.setLanguageCode('en'),
                  activeBg: activeBg,
                  textColor: textColor,
                ),
                _buildLanguageOption(
                  label: 'العربية',
                  code: 'ar',
                  flag: '🇸🇦',
                  isSelected: localeProvider.languageCode == 'ar',
                  onTap: () => localeProvider.setLanguageCode('ar'),
                  activeBg: activeBg,
                  textColor: textColor,
                ),
                _buildLanguageOption(
                  label: 'اردو',
                  code: 'ur',
                  flag: '🇵🇰',
                  isSelected: localeProvider.languageCode == 'ur',
                  onTap: () => localeProvider.setLanguageCode('ur'),
                  activeBg: activeBg,
                  textColor: textColor,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeOption({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
    required Color activeBg,
    required Color textColor,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? activeBg : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: isSelected ? Colors.black : textColor),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.black : textColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLanguageOption({
    required String label,
    required String code,
    required String flag,
    required bool isSelected,
    required VoidCallback onTap,
    required Color activeBg,
    required Color textColor,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? activeBg : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Center(
            child: Text(
              '$flag $label',
              style: TextStyle(
                color: isSelected ? Colors.black : textColor,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactPermissionRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required PermissionStatus status,
    required VoidCallback onRequest,
    required VoidCallback onOpenSettings,
    VoidCallback? testAction,
    String? testLabel,
  }) {
    final isGranted = status.isGranted;
    final activeColor = context.electricTeal;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isGranted ? activeColor.withValues(alpha: 0.12) : Colors.orange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: isGranted ? activeColor : Colors.orange,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: context.textPrimary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isGranted ? activeColor.withValues(alpha: 0.15) : Colors.orange.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        isGranted ? context.tr('set_granted') : context.tr('set_not_granted'),
                        style: TextStyle(
                          color: isGranted ? activeColor : Colors.orange,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 11, color: context.textSecondary),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (!isGranted)
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: activeColor,
                foregroundColor: context.isDark ? Colors.black : Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: onRequest,
              child: Text(context.tr('set_grant_access'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            )
          else if (testAction != null)
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: context.textPrimary,
                side: BorderSide(color: context.borderColor),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: testAction,
              child: Text(testLabel ?? context.tr('set_test'), style: const TextStyle(fontSize: 11)),
            )
          else
            IconButton(
              icon: Icon(Icons.settings_outlined, size: 18, color: context.textSecondary),
              tooltip: context.tr('set_open_app_settings'),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: onOpenSettings,
            ),
        ],
      ),
    );
  }
}
