import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../main.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../services/csv_export_service.dart';
import '../../services/offline_sync_service.dart';
import '../../widgets/dashboard/family_reimbursement_card.dart';
import '../../widgets/dashboard/multi_roommate_settlement_card.dart';
import '../../widgets/zatca_qr_camera_scanner.dart';
import 'package:provider/provider.dart';
import '../../providers/locale_provider.dart';
import '../../providers/theme_provider.dart';
import '../../widgets/settings/income_settings_card.dart';
import '../../widgets/settings/household_management_card.dart';
import '../../widgets/settings/add_household_member_sheet.dart';
import '../../widgets/settings/payday_settings_card.dart';
import '../../widgets/settings/rollover_settings_card.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/settings/household_switch_sheet.dart';
import '../../widgets/onboarding/user_guide_walkthrough_dialog.dart';
import '../onboarding/household_screen.dart';
import '../../theme/app_themes.dart';
import '../../l10n/app_localizations.dart';
import '../accounts/accounts_overview_screen.dart';
import 'help_support_screen.dart';

class IngestionSettingsScreen extends StatefulWidget {
  const IngestionSettingsScreen({super.key});

  @override
  State<IngestionSettingsScreen> createState() => _IngestionSettingsScreenState();
}

class _IngestionSettingsScreenState extends State<IngestionSettingsScreen>
    with WidgetsBindingObserver {
  bool _chatEnabled = true;
  bool _scannerEnabled = true;
  String _dedupPolicy = 'auto_enrich'; // 'auto_enrich' | 'prompt' | 'strict'
  bool _isLoading = true;

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
  double _monthlyIncome = 0.0;
  String _rolloverRule = 'send_to_savings';
  double _accumulatedSavings = 0.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPreferences();
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
            _userEmail = user.email ?? (data['display_name'] as String?) ?? 'User';
          });
          if (hid != null) {
            await _loadHouseholdDetails(hid);
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _loadHouseholdDetails(String hid) async {
    try {
      final hh = await supabase
          .from('households')
          .select('name, invite_code')
          .eq('id', hid)
          .maybeSingle();
      final membersData = await supabase
          .from('users')
          .select('display_name, role')
          .eq('household_id', hid);

      if (mounted) {
        setState(() {
          _householdName = hh?['name'] as String? ?? 'My Household';
          _inviteCode = hh?['invite_code'] as String? ?? '--------';
          _members = (membersData as List?)
                  ?.map((e) {
                    final map = Map<String, dynamic>.from(e as Map);
                    return {
                      'email': (map['display_name'] as String?) ?? 'Member',
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

  Future<bool> _savePayday(int newDay) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('payday_day', newDay);
      if (mounted) setState(() => _paydayDay = newDay);

      if (_householdId != null) {
        await ApiService.instance.setHouseholdPayday(_householdId!, newDay);
        try {
          await supabase.from('households').update({'payday_day': newDay}).eq('id', _householdId!);
        } catch (_) {}
      }
      return true;
    } catch (e) {
      if (mounted) {
        AppSnackBar.showError(
          context,
          'Failed to save payday: $e',
          title: 'Payday Error',
        );
      }
      return false;
    }
  }

  Future<bool> _saveIncome(double newIncome) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('household_monthly_income', newIncome);
      if (mounted) setState(() => _monthlyIncome = newIncome);

      if (_householdId != null) {
        await ApiService.instance.setHouseholdIncome(_householdId!, newIncome);
        try {
          await supabase.from('households').update({'monthly_income': newIncome}).eq('id', _householdId!);
        } catch (_) {}
      }
      return true;
    } catch (e) {
      if (mounted) {
        AppSnackBar.showError(
          context,
          'Failed to save income: $e',
          title: 'Income Error',
        );
      }
      return false;
    }
  }

  Future<bool> _saveRolloverRule(String newRule) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('household_rollover_rule', newRule);
      if (mounted) setState(() => _rolloverRule = newRule);

      if (_householdId != null) {
        await ApiService.instance.setHouseholdRolloverRule(_householdId!, newRule);
        try {
          await supabase.from('households').update({'rollover_rule': newRule}).eq('id', _householdId!);
        } catch (_) {}
      }
      return true;
    } catch (e) {
      if (mounted) {
        AppSnackBar.showError(
          context,
          'Failed to save rollover policy: $e',
          title: 'Rollover Error',
        );
      }
      return false;
    }
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _chatEnabled = prefs.getBool('channel_chat_enabled') ?? true;
        _scannerEnabled = prefs.getBool('channel_scanner_enabled') ?? true;
        _dedupPolicy = prefs.getString('dedup_policy') ?? 'auto_enrich';
        _isLoading = false;
      });
    }
  }

  Future<void> _savePreference(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) {
      await prefs.setBool(key, value);
    } else if (value is String) {
      await prefs.setString(key, value);
    }
  }

  Future<void> _requestCameraPermission() async {
    final status = await Permission.camera.request();
    if (mounted) {
      setState(() => _cameraStatus = status);
      if (status.isGranted) {
        AppSnackBar.showSuccess(
          context,
          'Camera permission granted! Ready to scan receipts & invoices.',
          title: 'Camera Enabled',
        );
      } else if (status.isPermanentlyDenied) {
        _showPermissionDialog(
          title: 'Camera Permission Denied',
          message:
              'Camera access has been permanently denied. Please tap "Open Settings" to enable Camera access for Budget Tracker in Android Settings.',
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
          'Microphone permission granted! Ready for voice invoice entries.',
          title: 'Microphone Enabled',
        );
      } else if (status.isPermanentlyDenied) {
        _showPermissionDialog(
          title: 'Microphone Permission Denied',
          message:
              'Microphone access has been permanently denied. Please tap "Open Settings" to enable Microphone access for Budget Tracker in Android Settings.',
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
            const Icon(Icons.settings_suggest_rounded, color: Color(0xFF00C896)),
            const SizedBox(width: 8),
            Text(title, style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 17, color: context.textPrimary)),
          ],
        ),
        content: Text(message, style: TextStyle(color: context.textSecondary, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: context.textSecondary)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00C896),
              foregroundColor: Colors.black,
            ),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('Open Settings', style: TextStyle(fontWeight: FontWeight.bold)),
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
        'Invite code "$_inviteCode" copied! Share with your partner.',
        title: 'Code Copied',
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
            child: Text('Cancel', style: TextStyle(color: context.textSecondary)),
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
            MaterialPageRoute(builder: (_) => const HouseholdScreen()),
            (route) => false,
          );
        }
      } catch (e) {
        if (mounted) {
          AppSnackBar.showError(
            context,
            'Failed to leave household: $e',
            title: 'Leave Household Error',
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
      builder: (ctx) => AlertDialog(
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
              maxLength: 8,
              style: GoogleFonts.jetBrainsMono(color: context.textPrimary, fontSize: 16, letterSpacing: 2),
              decoration: const InputDecoration(
                hintText: 'e.g. A1B2C3D4',
                counterText: '',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: context.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00C896),
              foregroundColor: Colors.black,
            ),
            child: Text(context.tr('join'), style: const TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () async {
              final code = codeCtrl.text.trim().toUpperCase();
              if (code.length != 8) return;
              Navigator.pop(ctx);
              try {
                final res = await supabase.rpc('join_household_by_code', params: {'p_invite_code': code});
                if (res is Map && res['error'] != null) {
                  throw Exception(res['error']);
                }
                if (mounted) {
                  AppSnackBar.showSuccess(
                    context,
                    'You have successfully joined the household!',
                    title: 'Household Joined',
                  );
                  _loadUserInfo();
                }
              } catch (e) {
                if (mounted) {
                  AppSnackBar.showError(
                    context,
                    'Failed to join: $e',
                    title: 'Join Error',
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _showCreateHouseholdDialog() async {
    final nameCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.cardBg,
        title: Text('New Household', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 17, color: context.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Enter a name for the new household:', style: TextStyle(color: context.textSecondary, fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: nameCtrl,
              style: TextStyle(color: context.textPrimary),
              decoration: const InputDecoration(
                hintText: 'e.g. Summer Beach House',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: context.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00C896),
              foregroundColor: Colors.black,
            ),
            child: const Text('Create', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              try {
                final res = await supabase.rpc('create_household_and_claim', params: {'p_name': name});
                final hhName = (res is Map && res['name'] != null) ? res['name'] : name;

                if (mounted) {
                  AppSnackBar.showSuccess(
                    context,
                    'Created household "$hhName"!',
                    title: 'Household Created',
                  );
                  _loadUserInfo();
                }
              } catch (e) {
                if (mounted) {
                  AppSnackBar.showError(
                    context,
                    'Failed to create household: $e',
                    title: 'Creation Error',
                  );
                }
              }
            },
          ),
        ],
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
              'Added member "${result.name}" successfully.',
              title: 'Member Added',
            );
          }
        }
      } catch (e) {
        if (mounted) {
          AppSnackBar.showError(
            context,
            'Failed to add member: $e',
            title: 'Error',
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
              'Remove Dependent',
              style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 17, color: context.textPrimary),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to remove "${dependent.name}" from your household dependents?',
          style: GoogleFonts.outfit(color: context.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: context.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF85149),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove', style: TextStyle(fontWeight: FontWeight.bold)),
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
              'Removed dependent "${dependent.name}".',
              title: 'Dependent Removed',
            );
          }
        }
      } catch (e) {
        if (mounted) {
          AppSnackBar.showError(
            context,
            'Failed to remove dependent: $e',
            title: 'Error',
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: context.scaffoldBg,
        body: const Center(child: CircularProgressIndicator(color: Color(0xFF00C896))),
      );
    }

    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: AppBar(
        title: Text(context.tr('settings_and_permissions'), style: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: context.textPrimary)),
        backgroundColor: context.scaffoldBg,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: context.textSecondary),
            tooltip: 'Refresh Permissions',
            onPressed: _checkPermissions,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        children: [
          // ── 0. HOUSEHOLD MANAGEMENT & INVITES ──
          _buildSectionHeader('HOUSEHOLD & MEMBERSHIP'),
          const SizedBox(height: 6),
          Text(
            'Manage your shared budget group, invite others with your code, or switch households.',
            style: GoogleFonts.outfit(fontSize: 12, color: context.textSecondary),
          ),
          const SizedBox(height: 12),
          if (_householdId != null) ...[
            HouseholdManagementCard(
              householdName: _householdName ?? 'Household',
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
                    'You have not joined any household yet.',
                    style: TextStyle(color: context.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00C896),
                      foregroundColor: Colors.black,
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const HouseholdScreen()),
                      );
                    },
                    child: const Text('Join or Create Household', style: TextStyle(fontWeight: FontWeight.bold)),
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
            'Customize your app theme and system language.',
            style: GoogleFonts.outfit(fontSize: 12, color: context.textSecondary),
          ),
          const SizedBox(height: 12),
          _buildAppearanceAndLanguageCard(),
          const SizedBox(height: 28),

          // ── 1. HARDWARE & APP PERMISSIONS ──
          _buildSectionHeader(context.tr('hardware_permissions')),
          const SizedBox(height: 6),
          Text(
            'Check and manage camera and microphone access for expense scanning and AI voice input.',
            style: GoogleFonts.outfit(fontSize: 12, color: context.textSecondary),
          ),
          const SizedBox(height: 12),

          // Camera Permission Card
          _buildPermissionCard(
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
          const SizedBox(height: 10),

          // Microphone Permission Card
          _buildPermissionCard(
            icon: Icons.mic_none_outlined,
            title: context.tr('microphone_access'),
            subtitle: context.tr('microphone_access_desc'),
            status: _microphoneStatus,
            onRequest: _requestMicrophonePermission,
            onOpenSettings: openAppSettings,
          ),
          const SizedBox(height: 10),

          // Notification Permission Card
          _buildPermissionCard(
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
          const SizedBox(height: 28),

          // ── 2. ACTIVE INPUT CHANNELS ──
          _buildSectionHeader(context.tr('expense_ingestion_channels')),
          const SizedBox(height: 10),
          _buildChannelTile(
            icon: Icons.chat_bubble_outline,
            title: context.tr('ai_conversational_chat'),
            subtitle: context.tr('ai_chat_desc'),
            value: _chatEnabled,
            onChanged: (val) {
              setState(() => _chatEnabled = val);
              _savePreference('channel_chat_enabled', val);
            },
          ),
          const SizedBox(height: 10),
          _buildChannelTile(
            icon: Icons.document_scanner_outlined,
            title: context.tr('camera_receipt_scanner'),
            subtitle: context.tr('camera_scanner_desc'),
            value: _scannerEnabled,
            onChanged: (val) {
              setState(() => _scannerEnabled = val);
              _savePreference('channel_scanner_enabled', val);
            },
          ),
          const SizedBox(height: 28),

          // ── 3. DUPLICATE RESOLUTION POLICY ──
          _buildSectionHeader(context.tr('duplicate_resolution')),
          const SizedBox(height: 6),
          Text(
            'Choose how the system handles transactions when multiple methods are used.',
            style: GoogleFonts.outfit(fontSize: 12, color: context.textSecondary),
          ),
          const SizedBox(height: 12),
          _buildPolicyTile(
            policy: 'auto_enrich',
            title: context.tr('auto_enrich'),
            description: context.tr('auto_enrich_desc'),
          ),
          const SizedBox(height: 8),
          _buildPolicyTile(
            policy: 'prompt',
            title: context.tr('prompt_on_conflict'),
            description: context.tr('prompt_desc'),
          ),
          const SizedBox(height: 8),
          _buildPolicyTile(
            policy: 'strict',
            title: context.tr('strict_isolation'),
            description: context.tr('strict_desc'),
          ),
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
                  householdId: _householdId!,
                  summary: snap.data?.familySummary,
                );
              },
            ),
            const SizedBox(height: 28),
          ],

          // ── DATA EXPORT & OFFLINE QUEUE ──
          _buildSectionHeader(context.tr('reports_offline_queue')),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.cardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: context.borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.table_view_rounded, color: Color(0xFF00C896), size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Export Monthly Report', style: GoogleFonts.outfit(color: context.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
                          Text('Generate standard CSV with Date, Merchant, Category, and Items', style: TextStyle(color: context.textSecondary, fontSize: 11)),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: context.chipBg,
                        foregroundColor: const Color(0xFF00C896),
                        side: const BorderSide(color: Color(0xFF00C896)),
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
                            'Export error: $e',
                            title: 'Export Failed',
                          );
                        }
                      },
                      child: const Text('Export CSV', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
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
                        Icon(count > 0 ? Icons.cloud_off_rounded : Icons.cloud_done_rounded, color: count > 0 ? Colors.orange : const Color(0xFF00C896), size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Offline SQLite Queue', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                              Text(count > 0 ? '$count transaction(s) pending sync' : 'All transactions synchronized', style: TextStyle(color: context.textSecondary, fontSize: 11)),
                            ],
                          ),
                        ),
                        if (count > 0)
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00C896), foregroundColor: Colors.black),
                            onPressed: () => OfflineSyncService.instance.flushQueue(),
                            child: const Text('Sync Now', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // ── HELP & SUPPORT ──
          _buildSectionHeader('HELP & SUPPORT'),
          const SizedBox(height: 6),
          Text(
            'Explore user guides, interactive walkthroughs, ask our AI assistant, or email the developer.',
            style: GoogleFonts.outfit(fontSize: 12, color: context.textSecondary),
          ),
          const SizedBox(height: 12),
          Card(
            color: context.cardBg,
            elevation: 0,
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: context.borderColor),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00C896).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.menu_book_rounded, color: Color(0xFF00C896), size: 20),
                  ),
                  title: Text(
                    'App Guide & Tutorial',
                    style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  subtitle: Text(
                    'Replay the 5-step interactive feature walkthrough',
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
                    'Help Center & AI Support',
                    style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  subtitle: Text(
                    'Searchable FAQs, salary cycle guide & AI chatbot',
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
                    'Contact Developer',
                    style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  subtitle: Text(
                    'Email fmscoinfo@fmsco.com.sa for feedback or bug reports',
                    style: GoogleFonts.outfit(color: context.textSecondary, fontSize: 12),
                  ),
                  trailing: Icon(Icons.chevron_right_rounded, color: context.textSecondary),
                  onTap: () {
                    Clipboard.setData(const ClipboardData(text: 'fmscoinfo@fmsco.com.sa'));
                    AppSnackBar.showSuccess(
                      context,
                      'Developer email copied: fmscoinfo@fmsco.com.sa',
                      title: 'Copied',
                      icon: Icons.copy_rounded,
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // ── 4. HOUSEHOLD & ACCOUNT ──
          _buildSectionHeader('HOUSEHOLD & ACCOUNT'),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.cardBg,
              borderRadius: BorderRadius.circular(14),
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
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
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
                          'Household: ${_householdId!.substring(0, 8)}...',
                          style: TextStyle(color: context.textSecondary, fontSize: 12, fontFamily: 'monospace'),
                        ),
                      ),
                      InkWell(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: _householdId!));
                          AppSnackBar.showSuccess(
                            context,
                            'Household ID copied to clipboard',
                            title: 'Copied',
                            icon: Icons.copy_rounded,
                          );
                        },
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          child: Text('Copy', style: TextStyle(color: Color(0xFF00C896), fontSize: 12, fontWeight: FontWeight.bold)),
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
                    label: const Text('Sign Out', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () => supabase.auth.signOut(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
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
    const activeBg = Color(0xFF00C896);

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
                  color: const Color(0xFF00C896).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.palette_rounded, color: Color(0xFF00C896), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.tr('appearance'), style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16, color: textColor)),
                    Text('System default, light mode, or dark mode', style: TextStyle(color: subtextColor, fontSize: 12)),
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
                  color: const Color(0xFF00C896).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.language_rounded, color: Color(0xFF00C896), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.tr('language'), style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16, color: textColor)),
                    Text('General application language (EN, AR, UR)', style: TextStyle(color: subtextColor, fontSize: 12)),
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

  Widget _buildPermissionCard({
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

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isGranted ? const Color(0xFF00C896).withValues(alpha: 0.3) : context.borderColor,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: isGranted ? const Color(0xFF00C896).withValues(alpha: 0.12) : Colors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  color: isGranted ? const Color(0xFF00C896) : Colors.orange,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: context.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 11, color: context.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isGranted ? const Color(0xFF00C896).withValues(alpha: 0.15) : Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isGranted ? const Color(0xFF00C896) : Colors.orange,
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isGranted ? Icons.check_circle : Icons.warning_amber_rounded,
                      size: 12,
                      color: isGranted ? const Color(0xFF00C896) : Colors.orange,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isGranted ? 'GRANTED' : 'NOT GRANTED',
                      style: TextStyle(
                        color: isGranted ? const Color(0xFF00C896) : Colors.orange,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (!isGranted) ...[
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00C896),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.lock_open, size: 15),
                    label: const Text('Grant Access', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    onPressed: onRequest,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.isDarkMode ? const Color(0xFF58A6FF) : const Color(0xFF0969DA),
                    side: BorderSide(
                      color: context.isDarkMode
                          ? const Color(0xFF1F6FEB).withValues(alpha: 0.5)
                          : const Color(0xFF0969DA).withValues(alpha: 0.4),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.settings_outlined, size: 15),
                  label: const Text('Open App Settings', style: TextStyle(fontSize: 12)),
                  onPressed: onOpenSettings,
                ),
              ),
              if (testAction != null) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.textPrimary,
                    side: BorderSide(color: context.borderColor),
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.visibility, size: 14),
                  label: Text(testLabel ?? 'Test', style: const TextStyle(fontSize: 11)),
                  onPressed: testAction,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChannelTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: value ? const Color(0xFF00C896).withValues(alpha: 0.12) : context.chipBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: value ? const Color(0xFF00C896) : context.textSecondary, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: context.textPrimary)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(fontSize: 12, color: context.textSecondary)),
              ],
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: const Color(0xFF00C896),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildPolicyTile({
    required String policy,
    required String title,
    required String description,
  }) {
    final isSelected = _dedupPolicy == policy;
    return InkWell(
      onTap: () {
        setState(() => _dedupPolicy = policy);
        _savePreference('dedup_policy', policy);
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? const Color(0xFF00C896) : context.borderColor,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: isSelected ? const Color(0xFF00C896) : context.textSecondary,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: isSelected ? context.textPrimary : context.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(fontSize: 11, color: context.textSecondary, height: 1.3),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
