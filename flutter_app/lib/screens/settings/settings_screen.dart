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
import '../../services/household_invite_share.dart';
import '../../services/csv_export_service.dart';
import '../../services/offline_sync_service.dart';
import '../../widgets/dashboard/family_reimbursement_card.dart';
import '../../widgets/zatca_qr_camera_scanner.dart';
import 'package:provider/provider.dart';
import '../../providers/household_role_provider.dart';
import '../../providers/locale_provider.dart';
import '../../providers/theme_provider.dart';
import '../../widgets/settings/household_management_card.dart';
import '../../widgets/settings/settings_section.dart';
import '../../widgets/settings/household_roles_card.dart';
import '../../widgets/settings/household_settlement_panel.dart';
import '../../widgets/settings/household_type_chooser.dart';
import '../../widgets/settings/add_household_member_sheet.dart';
import '../../widgets/settings/payday_settings_card.dart';
import '../../widgets/settings/reminder_settings_card.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/dispose_on_unmount.dart';
import '../../widgets/settings/household_switch_sheet.dart';
import '../../widgets/onboarding/user_guide_walkthrough_dialog.dart';
import '../../widgets/dashboard/household_setup_card.dart';
import '../../theme/app_themes.dart';
import '../../l10n/app_localizations.dart';
import '../accounts/accounts_overview_screen.dart';
import 'help_support_screen.dart';
import '../../services/salary_cycle_service.dart';
import '../../services/household_setting_saver.dart';
import '../../utils/failure_log.dart';

class SettingsScreen extends StatefulWidget {
  /// The time the export's current cycle is computed from; a seam for tests.
  @visibleForTesting
  final DateTime Function()? clock;

  const SettingsScreen({super.key, this.clock});

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

  /// Bumped when roles or the provider change so the settlement panel refetches.
  int _settlementRevision = 0;

  bool _exporting = false;

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
    PermissionStatus? camera;
    PermissionStatus? microphone;
    PermissionStatus? notification;

    try {
      camera = await Permission.camera.status;
    } catch (e) {
      debugPrint('Failed to query camera permission: $e');
    }

    try {
      microphone = await Permission.microphone.status;
    } catch (e) {
      debugPrint('Failed to query microphone permission: $e');
    }

    try {
      notification = await Permission.notification.status;
    } catch (e) {
      debugPrint('Failed to query notification permission: $e');
    }

    if (mounted) {
      setState(() {
        if (camera != null) _cameraStatus = camera;
        if (microphone != null) _microphoneStatus = microphone;
        if (notification != null) _notificationStatus = notification;
      });
    }
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
    if (mounted) setState(() => _settlementRevision++);
    _loadUserInfo();
  }

  /// A new Nafaqah provider was confirmed: reload the family Nafaqah card.
  void _onNafaqahProviderChanged(NafaqahSummary? _) {
    if (mounted) {
      setState(() {
        _nafaqahRevision++;
        _settlementRevision++;
      });
    }
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

      // The user may have switched household while this was loading.
      if (mounted && _householdId == hid) {
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
      if (mounted && _householdId == hid) {
        setState(() => _paydayDay = payday);
      }

      // Load household dependents
      try {
        final deps = await ApiService.instance.getDependents(hid);
        if (mounted && _householdId == hid) {
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
      e is HouseholdSettingNotSavedException ? context.tr('setting_not_saved_server') : context.tr('set_failed_save_payday');

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
      logFailure('Settings.savePayday', e);
      if (mounted) {
        AppSnackBar.showError(
          context,
          _settingSaveError(e),
          title: context.tr('set_payday_error'),
        );
      }
      return false;
    }
  }



  Future<void> _requestCameraPermission() async {
    final status = await Permission.camera.request();
    if (mounted) {
      setState(() => _cameraStatus = status);
      if (status.isGranted || status.isLimited) {
        AppSnackBar.showSuccess(
          context,
          context.tr('set_camera_permission_granted_ready_scan'),
          title: context.tr('set_camera_enabled'),
        );
      } else {
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
      if (status.isGranted || status.isLimited) {
        AppSnackBar.showSuccess(
          context,
          context.tr('set_microphone_permission_granted_ready_voice'),
          title: context.tr('set_microphone_enabled'),
        );
      } else {
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
            Icon(Icons.settings_suggest_rounded, color: context.accentText),
            const SizedBox(width: 8),
            Expanded(
              child: Text(title, style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 17, color: context.textPrimary)),
            ),
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
              backgroundColor: context.primaryButtonBg,
              foregroundColor: context.primaryButtonFg,
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

  Future<void> _shareInvite() async {
    final code = _inviteCode;
    if (!isShareableInviteCode(code)) return;
    final l = AppLocalizations.of(context);
    final name = _householdName ?? '';
    try {
      await shareHouseholdInvite(l, householdName: name, code: code!);
    } catch (_) {
      // No share target (or the sheet failed): copy the same message.
      await Clipboard.setData(ClipboardData(text: inviteShareText(l, householdName: name, code: code!)));
      if (mounted) {
        AppSnackBar.showInfo(context, context.tr('share_invite_failed'), title: context.tr('set_code_copied'));
      }
    }
  }

  Future<void> _confirmLeaveHousehold() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.cardBg,
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: context.dangerColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(context.tr('leave_household'), style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 17, color: context.textPrimary)),
            ),
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
              backgroundColor: context.dangerColor,
              foregroundColor: context.cardBg,
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
        logFailure('Settings.leaveHousehold', e);
        if (mounted) {
          AppSnackBar.showError(
            context,
            context.tr(householdRefusalKey(e) ?? 'set_failed_leave_household'),
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
                hintStyle: TextStyle(color: context.textSecondary),
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
              backgroundColor: context.primaryButtonBg,
              foregroundColor: context.primaryButtonFg,
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
                logFailure('Settings.joinHousehold', e);
                if (mounted) {
                  AppSnackBar.showError(
                    context,
                    householdJoinErrorText(context, e),
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
                hintStyle: TextStyle(color: context.textSecondary),
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
              backgroundColor: context.primaryButtonBg,
              foregroundColor: context.primaryButtonFg,
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
                logFailure('Settings.createHousehold', e);
                if (mounted) {
                  AppSnackBar.showError(
                    context,
                    context.tr(householdRefusalKey(e) ?? 'set_failed_create_household'),
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
        logFailure('Settings.addDependent', e);
        if (mounted) {
          AppSnackBar.showError(
            context,
            context.tr('set_failed_add_member'),
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
            Icon(Icons.delete_outline_rounded, color: context.dangerColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                context.tr('set_remove_dependent'),
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 17, color: context.textPrimary),
              ),
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
              backgroundColor: context.dangerColor,
              foregroundColor: context.cardBg,
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
        logFailure('Settings.removeDependent', e);
        if (mounted) {
          AppSnackBar.showError(
            context,
            context.tr('set_failed_remove_dependent'),
            title: context.tr('set_error'),
          );
        }
      }
    }
  }

  Future<void> _confirmSignOut() async {
    final sync = OfflineSyncService.instance;
    var pending = sync.pendingCountNotifier.value;
    try {
      // Scanners write to the queue directly, so the notifier can lag behind.
      await sync.updatePendingCount();
      pending = await sync.unsyncedCount();
    } catch (e) {
      logFailure('Settings.unsyncedCount', e);
    }
    if (!mounted) return;
    if (pending > 0) {
      final shouldSignOut = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: ctx.cardBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            ctx.tr('sign_out_unsynced_title'),
            style: TextStyle(color: ctx.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          content: Text(
            ctx.trPlural('sign_out_unsynced_warning', pending),
            style: TextStyle(color: ctx.textSecondary, fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ctx.tr('cancel'), style: TextStyle(color: ctx.textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: ctx.dangerColor,
                foregroundColor: ctx.cardBg,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(ctx.tr('sign_out'), style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
      if (shouldSignOut != true) return;
      try {
        // The dialog promises they wait for this account: legacy items without
        // an owner would otherwise replay under whoever signs in next.
        await sync.claimOwnerlessItems();
      } catch (e) {
        logFailure('Settings.claimOwnerlessItems', e);
      }
    }
    await supabase.auth.signOut();
  }

  /// Exports this household's current cycle, with its own payday read fresh.
  Future<void> _exportCycle() async {
    final hid = _householdId;
    if (hid == null || _exporting) return;
    setState(() => _exporting = true);
    try {
      final export = await CsvExportService.loadCurrentCycle(supabase, householdId: hid, now: widget.clock?.call());
      // A switch while this loaded: these rows belong to the previous household.
      if (!mounted || _householdId != hid) return;
      final cycleLabel = context.cycleRange(export.cycle.start, export.cycle.end);
      if (export.rows.isEmpty) {
        AppSnackBar.showInfo(
          context,
          context.trArgs('set_export_empty_cycle', {'cycle': cycleLabel}),
          title: context.tr('set_export_monthly_report'),
        );
        return;
      }
      CsvExportService.showExportDialog(context, export.rows, monthLabel: cycleLabel);
    } catch (e) {
      logFailure('Settings.exportCycle', e);
      if (!mounted || _householdId != hid) return;
      AppSnackBar.showError(
        context,
        context.tr('load_error_generic'),
        title: context.tr('set_export_failed'),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: AppBar(
        foregroundColor: context.textPrimary,
        iconTheme: IconThemeData(color: context.textPrimary),
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
          // UX-15: Settings in foldable sections; the everyday ones open,
          // the rarely used ones folded. Nothing is removed.
          // Who is in the household and how far its setup has come.
          SettingsSection(
            id: 'household',
            title: context.tr('set_household_membership'),
            subtitle: context.tr('set_manage_shared_budget_group_invite'),
            icon: Icons.home_work_outlined,
            initiallyExpanded: true,
            children: [
              if (_householdId != null) ...[
                HouseholdManagementCard(
                  householdName: _householdName ?? context.tr('set_household'),
                  householdId: _householdId,
                  inviteCode: _inviteCode ?? '--------',
                  userRole: _userRole,
                  members: _members,
                  dependents: _dependents,
                  onCopyInviteCode: _copyInviteCode,
                  onShareInvite: _shareInvite,
                  onLeaveHousehold: _confirmLeaveHousehold,
                  onSwitchHousehold: _showHouseholdSwitchSheet,
                  onCreateHousehold: _showCreateHouseholdDialog,
                  onAddDependent: _showAddDependentDialog,
                  onRemoveDependent: _removeDependent,
                  rolesSection: HouseholdRolesCard(
                    householdId: _householdId!,
                    isEmbedded: true,
                    onRolesChanged: _onRolesChanged,
                    onNafaqahProviderChanged: _onNafaqahProviderChanged,
                  ),
                ),
                const SizedBox(height: 16),
                _buildRowCard(
                  icon: context.isRtl ? Icons.checklist_rtl_rounded : Icons.checklist_rounded,
                  title: context.tr('household_setup_checklist'),
                  subtitle: context.tr('household_setup_checklist_desc'),
                  onTap: () {
                    HouseholdSetupCard.showChecklistSheet(
                      context,
                      householdId: _householdId!,
                    );
                  },
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: context.accentText,
                    size: 20,
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
                          backgroundColor: context.primaryButtonBg,
                          foregroundColor: context.primaryButtonFg,
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
            ],
          ),

          // Salary day and the accounts it lands in.
          if (_householdId != null)
            SettingsSection(
              id: 'money',
              title: context.tr('set_money_section'),
              subtitle: context.trArgs('set_salary_section_summary', {'day': _paydayDay}),
              icon: Icons.account_balance_wallet_outlined,
              children: [
                PaydaySettingsCard(
                  initialPayday: _paydayDay,
                  onSavePayday: _savePayday,
                ),
                const SizedBox(height: 16),
                _buildRowCard(
                  icon: Icons.account_balance_wallet_rounded,
                  title: context.tr('accounts_balances'),
                  subtitle: context.tr('accounts_balances_desc'),
                  action: ElevatedButton(
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
                      backgroundColor: context.primaryButtonBg,
                      foregroundColor: context.primaryButtonFg,
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
                ),
              ],
            ),

          // What the household members owe each other.
          if (_householdId != null && _members.length > 1)
            SettingsSection(
              id: 'partner_settlement',
              title: context.tr('set_partner_settlement_section'),
              subtitle: context.tr('partner_settlement_desc'),
              icon: Icons.handshake_outlined,
              children: [
                HouseholdSettlementPanel(
                  key: ValueKey('settlement-panel-$_householdId'),
                  householdId: _householdId!,
                  refreshToken: _settlementRevision,
                  familyBuilder: (context) => FamilyReimbursementCard(
                    key: ValueKey('family-nafaqah-$_householdId-$_nafaqahRevision'),
                    householdId: _householdId!,
                    emptyPlaceholder: _buildNoWifeSettlementPlaceholder(context),
                  ),
                ),
              ],
            ),

          // How the app looks and reads.
          SettingsSection(
            id: 'appearance',
            title: context.tr('appearance_language'),
            subtitle: context.tr('set_customize_app_theme_system_language'),
            icon: Icons.palette_outlined,
            initiallyExpanded: true,
            children: [_buildAppearanceAndLanguageCard()],
          ),

          // Reminders, then the device permission they depend on.
          SettingsSection(
            id: 'reminders',
            title: context.tr('set_reminders_section'),
            subtitle: context.tr('reminders_desc'),
            icon: Icons.notifications_none_rounded,
            children: const [ReminderSettingsCard()],
          ),

          // Device access the app asks for.
          SettingsSection(
            id: 'permissions',
            title: context.tr('hardware_permissions'),
            subtitle: context.tr('set_check_manage_camera_microphone_access'),
            icon: Icons.verified_user_outlined,
            children: [
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
                      testAction: _cameraStatus.isGranted || _cameraStatus.isLimited
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
            ],
          ),

          // Getting data out, and what is still waiting to sync.
          SettingsSection(
            id: 'reports',
            title: context.tr('reports_offline_queue'),
            icon: Icons.table_view_outlined,
            children: [
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
                    _rowWithAction(
                      lead: [
                        Icon(Icons.table_view_rounded, color: context.accentText, size: 20),
                        const SizedBox(width: 10),
                      ],
                      text: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(context.tr('set_export_monthly_report'), style: GoogleFonts.outfit(color: context.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
                          Text(context.tr('set_generate_standard_csv_date_merchant'), style: TextStyle(color: context.textSecondary, fontSize: 11)),
                        ],
                      ),
                      action: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: context.primaryButtonBg,
                          foregroundColor: context.primaryButtonFg,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        ),
                        onPressed: _exporting ? null : _exportCycle,
                        child: Text(context.tr('export_csv'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Divider(color: context.borderColor, height: 1),
                    const SizedBox(height: 14),
                    ValueListenableBuilder<int>(
                      valueListenable: OfflineSyncService.instance.pendingCountNotifier,
                      builder: (ctx, count, _) {
                        return _rowWithAction(
                          lead: [
                            Icon(count > 0 ? Icons.cloud_off_rounded : Icons.cloud_done_rounded, color: count > 0 ? context.warnText : context.electricTeal, size: 20),
                            const SizedBox(width: 10),
                          ],
                          text: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(context.tr('set_offline_sqlite_queue'), style: GoogleFonts.outfit(color: context.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
                              Text(count > 0 ? context.trPlural('set_transaction_s_pending_sync', count) : context.tr('set_all_transactions_synchronized'), style: TextStyle(color: context.textSecondary, fontSize: 11)),
                            ],
                          ),
                          action: count > 0
                              ? ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: context.primaryButtonBg,
                                    foregroundColor: context.primaryButtonFg,
                                  ),
                                  onPressed: () => OfflineSyncService.instance.flushQueue(),
                                  child: Text(context.tr('sync_now'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                )
                              : null,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Guides, the help centre and the developer contact.
          SettingsSection(
            id: 'help',
            title: context.tr('set_help_support'),
            subtitle: context.tr('set_explore_user_guides_interactive_walkthroughs'),
            icon: Icons.help_outline_rounded,
            initiallyExpanded: true,
            children: [
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
                          color: context.accentSubtleBg,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.menu_book_rounded, color: context.accentText, size: 20),
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
                          color: context.infoSubtleBg,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.support_agent_rounded, color: context.infoColor, size: 20),
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
                          color: context.alertWarningBg,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.mail_outline_rounded, color: context.warnText, size: 20),
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
            ],
          ),

          // Who is signed in, and signing out.
          SettingsSection(
            id: 'account',
            title: context.tr('set_account_section'),
            icon: Icons.manage_accounts_outlined,
            initiallyExpanded: true,
            children: [
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
                      const SizedBox(height: 16),
                    ],
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: context.dangerColor,
                          side: BorderSide(color: context.dangerColor),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: Transform.flip(flipX: context.isRtl, child: const Icon(Icons.logout, size: 18)),
                        label: Text(context.tr('sign_out'), style: const TextStyle(fontWeight: FontWeight.bold)),
                        onPressed: _confirmSignOut,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNoWifeSettlementPlaceholder(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: context.accentText.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.family_restroom_rounded,
              color: context.accentText,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('nafaqah_no_wife_configured_title'),
                  style: GoogleFonts.outfit(
                    color: context.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  context.tr('nafaqah_no_wife_configured_desc'),
                  style: TextStyle(
                    color: context.textSecondary,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Large text: a button moves under its row's text, where it has the whole
  /// width, so no word in the text or the button has to break.
  bool get _largeText => isLargeText(context);

  /// A selector's options: side by side and equal in height, or one per line at
  /// large text, where three in a row would break their words.
  Widget _optionsRow(List<Widget> options) {
    if (_largeText) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: options);
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final option in options) Expanded(child: option)],
      ),
    );
  }

  /// [lead] and [text], with the button [action] beside them, or under them at
  /// large text. Beside them its label wraps between words rather than pushing
  /// the row past the card. A small [trailing] widget always stays in the row.
  Widget _rowWithAction({required List<Widget> lead, required Widget text, Widget? action, Widget? trailing}) {
    if (action != null && _largeText) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [...lead, Expanded(child: text)]),
          const SizedBox(height: 8),
          Align(alignment: AlignmentDirectional.centerEnd, child: action),
        ],
      );
    }
    return Row(
      children: [
        ...lead,
        Expanded(child: text),
        if (action != null) ...[
          const SizedBox(width: 8),
          ConstrainedBox(constraints: const BoxConstraints(maxWidth: 120), child: action),
        ],
        if (trailing != null) ...[
          const SizedBox(width: 8),
          trailing,
        ],
      ],
    );
  }

  /// One setting as a card: icon, title and description, then [action] or [trailing].
  Widget _buildRowCard({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? action,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    final row = _rowWithAction(
      lead: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: context.pillBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: context.accentText, size: 24),
        ),
        const SizedBox(width: 14),
      ],
      text: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.outfit(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: context.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: context.textSecondary,
            ),
          ),
        ],
      ),
      action: action,
      trailing: trailing,
    );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      child: onTap == null
          ? row
          : InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: row,
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
    final activeBg = context.accentText;

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
                  color: context.accentSubtleBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.palette_rounded, color: context.accentText, size: 20),
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
            child: _optionsRow([
                  _buildThemeOption(
                    id: 'system',
                    label: context.tr('theme_system'),
                    icon: Icons.brightness_auto_rounded,
                    isSelected: themeProvider.themeMode == ThemeMode.system,
                    onTap: () => themeProvider.setThemeMode(ThemeMode.system),
                    activeBg: activeBg,
                    textColor: textColor,
                  ),
                  _buildThemeOption(
                    id: 'light',
                    label: context.tr('theme_light'),
                    icon: Icons.light_mode_rounded,
                    isSelected: themeProvider.themeMode == ThemeMode.light,
                    onTap: () => themeProvider.setThemeMode(ThemeMode.light),
                    activeBg: activeBg,
                    textColor: textColor,
                  ),
                  _buildThemeOption(
                    id: 'dark',
                    label: context.tr('theme_dark'),
                    icon: Icons.dark_mode_rounded,
                    isSelected: themeProvider.themeMode == ThemeMode.dark,
                    onTap: () => themeProvider.setThemeMode(ThemeMode.dark),
                    activeBg: activeBg,
                    textColor: textColor,
                  ),
            ]),
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
            child: _optionsRow([
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
            ]),
          ),
        ],
      ),
    );
  }

  /// Text and icons on a selected option, which sits on the [ThemeContextExtension.accentText] fill.
  Color get _onSelectedOption => context.cardBg;

  Widget _buildThemeOption({
    required String id,
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
    required Color activeBg,
    required Color textColor,
  }) {
    final foreground = isSelected ? _onSelectedOption : textColor;
    return Semantics(
      key: ValueKey('theme_option_$id'),
      button: true,
      selected: isSelected,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? activeBg : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          // The icon above the label leaves the label the whole width, and it
          // wraps rather than being cut off in long languages or large text.
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: foreground),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: foreground,
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
    return Semantics(
      key: ValueKey('language_option_$code'),
      button: true,
      selected: isSelected,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? activeBg : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Center(
            child: Text(
              '$flag $label',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isSelected ? _onSelectedOption : textColor,
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
    final isGranted = status.isGranted || status.isLimited;
    final activeColor = context.electricTeal;
    final notGrantedColor = context.warnText;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: _rowWithAction(
        lead: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isGranted ? activeColor.withValues(alpha: 0.12) : notGrantedColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: isGranted ? activeColor : notGrantedColor,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
        ],
        text: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: context.textPrimary),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isGranted ? activeColor.withValues(alpha: 0.15) : notGrantedColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    isGranted ? context.tr('set_granted') : context.tr('set_not_granted'),
                    style: TextStyle(
                      color: isGranted ? activeColor : notGrantedColor,
                      fontSize: 11,
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
        action: !isGranted
            ? ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.primaryButtonBg,
                  foregroundColor: context.primaryButtonFg,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  minimumSize: const Size(48, 40),
                ),
                onPressed: onRequest,
                child: Text(context.tr('set_grant_access'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              )
            : testAction != null
                ? OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.textPrimary,
                      side: BorderSide(color: context.borderColor),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      minimumSize: const Size(48, 40),
                    ),
                    onPressed: testAction,
                    child: Text(testLabel ?? context.tr('set_test'), style: const TextStyle(fontSize: 12)),
                  )
                : null,
        trailing: isGranted && testAction == null
            ? IconButton(
                icon: Icon(Icons.settings_outlined, size: 18, color: context.textSecondary),
                tooltip: context.tr('set_open_app_settings'),
                onPressed: onOpenSettings,
              )
            : null,
      ),
    );
  }
}
