import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../main.dart';
import '../../services/sms_service.dart';
import '../../services/csv_export_service.dart';
import '../../services/offline_sync_service.dart';
import '../../widgets/partner_settlement_card.dart';
import '../../widgets/zatca_qr_camera_scanner.dart';
import '../../widgets/settings/household_management_card.dart';
import '../onboarding/household_screen.dart';

class IngestionSettingsScreen extends StatefulWidget {
  const IngestionSettingsScreen({super.key});

  @override
  State<IngestionSettingsScreen> createState() => _IngestionSettingsScreenState();
}

class _IngestionSettingsScreenState extends State<IngestionSettingsScreen>
    with WidgetsBindingObserver {
  bool _smsEnabled = true;
  bool _chatEnabled = true;
  bool _scannerEnabled = true;
  String _dedupPolicy = 'auto_enrich'; // 'auto_enrich' | 'prompt' | 'strict'
  bool _isLoading = true;

  // Permission statuses
  PermissionStatus _cameraStatus = PermissionStatus.denied;
  PermissionStatus _microphoneStatus = PermissionStatus.denied;
  PermissionStatus _smsStatus = PermissionStatus.denied;
  PermissionStatus _notificationStatus = PermissionStatus.denied;

  String? _householdId;
  String? _userEmail;
  String? _householdName;
  String? _inviteCode;
  String _userRole = 'member';
  List<Map<String, dynamic>> _members = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPreferences();
    _checkPermissions();
    _loadUserInfo();
    SmsService.instance.listeningNotifier.addListener(_onSmsListeningChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SmsService.instance.listeningNotifier.removeListener(_onSmsListeningChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Re-check permissions when user returns from phone App Settings
      _checkPermissions();
    }
  }

  void _onSmsListeningChanged() {
    if (mounted) {
      setState(() => _smsEnabled = SmsService.instance.listeningNotifier.value);
    }
  }

  Future<void> _checkPermissions() async {
    final camera = await Permission.camera.status;
    final microphone = await Permission.microphone.status;
    final sms = await Permission.sms.status;
    final notification = await Permission.notification.status;

    if (mounted) {
      setState(() {
        _cameraStatus = camera;
        _microphoneStatus = microphone;
        _smsStatus = sms;
        _notificationStatus = notification;
      });
    }
  }

  Future<void> _loadUserInfo() async {
    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
        final data = await supabase
            .from('users')
            .select('household_id, email, role')
            .eq('id', user.id)
            .maybeSingle();
        if (data != null && mounted) {
          final hid = data['household_id'] as String?;
          setState(() {
            _householdId = hid;
            _userRole = data['role'] as String? ?? 'member';
            _userEmail = data['email'] as String? ?? user.email;
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
          .select('email, role')
          .eq('household_id', hid);

      if (mounted) {
        setState(() {
          _householdName = hh?['name'] as String? ?? 'My Household';
          _inviteCode = hh?['invite_code'] as String? ?? '--------';
          _members = (membersData as List?)
                  ?.map((e) => Map<String, dynamic>.from(e as Map))
                  .toList() ??
              [];
        });
      }
    } catch (_) {}
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _smsEnabled = SmsService.instance.listeningNotifier.value;
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

  void _toggleSms(bool value) async {
    if (!value) {
      await SmsService.instance.stopService();
    } else {
      await SmsService.instance.startService();
    }
  }

  Future<void> _requestCameraPermission() async {
    final status = await Permission.camera.request();
    if (mounted) {
      setState(() => _cameraStatus = status);
      if (status.isGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Camera permission granted! Ready to scan receipts & invoices.'),
            backgroundColor: Color(0xFF00C896),
          ),
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Microphone permission granted! Ready for voice invoice entries.'),
            backgroundColor: Color(0xFF00C896),
          ),
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

  Future<void> _requestSmsPermission() async {
    final status = await Permission.sms.request();
    if (mounted) {
      setState(() => _smsStatus = status);
      if (status.isGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('SMS permission granted! Bank interceptor is ready.'),
            backgroundColor: Color(0xFF00C896),
          ),
        );
      } else if (status.isPermanentlyDenied) {
        _showPermissionDialog(
          title: 'SMS Permission Denied',
          message:
              'SMS access has been permanently denied. Please tap "Open Settings" to enable SMS access in Android Settings.',
        );
      }
    }
  }

  void _showPermissionDialog({required String title, required String message}) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        title: Row(
          children: [
            const Icon(Icons.settings_suggest_rounded, color: Color(0xFF00C896)),
            const SizedBox(width: 8),
            Text(title, style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 17)),
          ],
        ),
        content: Text(message, style: const TextStyle(color: Color(0xFF8B949E), fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF8B949E))),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Invite code "$_inviteCode" copied! Share with your partner.'),
          backgroundColor: const Color(0xFF00C896),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _confirmLeaveHousehold() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFF85149)),
            const SizedBox(width: 8),
            Text('Leave Household', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 17)),
          ],
        ),
        content: const Text(
          'Are you sure you want to leave this household? You will no longer have access to its shared budgets and transactions until you are re-invited.',
          style: TextStyle(color: Color(0xFF8B949E), fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF8B949E))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF85149),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Leave', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final uid = supabase.auth.currentUser?.id;
      if (uid == null) return;
      try {
        await supabase
            .from('users')
            .update({'household_id': null, 'role': null})
            .eq('id', uid);

        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const HouseholdScreen()),
            (route) => false,
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to leave household: $e'), backgroundColor: Colors.redAccent),
          );
        }
      }
    }
  }

  Future<void> _showJoinHouseholdDialog() async {
    final codeCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        title: Text('Join Household', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 17)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Enter the 8-character invite code:', style: TextStyle(color: Color(0xFF8B949E), fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: codeCtrl,
              textCapitalization: TextCapitalization.characters,
              maxLength: 8,
              style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 16, letterSpacing: 2),
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
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF8B949E))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00C896),
              foregroundColor: Colors.black,
            ),
            child: const Text('Join', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () async {
              final code = codeCtrl.text.trim().toUpperCase();
              if (code.length != 8) return;
              Navigator.pop(ctx);
              try {
                try {
                  await supabase.rpc('join_household_by_code', params: {'p_invite_code': code});
                } catch (_) {
                  final uid = supabase.auth.currentUser!.id;
                  final hh = await supabase
                      .from('households')
                      .select()
                      .eq('invite_code', code)
                      .single();
                  await supabase
                      .from('users')
                      .update({'household_id': hh['id'], 'role': 'member'})
                      .eq('id', uid);
                }
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Joined household!'), backgroundColor: Color(0xFF00C896)),
                  );
                  _loadUserInfo();
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to join: $e'), backgroundColor: Colors.redAccent),
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
        backgroundColor: const Color(0xFF161B22),
        title: Text('New Household', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 17)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Enter a name for the new household:', style: TextStyle(color: Color(0xFF8B949E), fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: nameCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'e.g. Summer Beach House',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF8B949E))),
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
                final uid = supabase.auth.currentUser!.id;
                final res = await supabase
                    .from('households')
                    .insert({'name': name})
                    .select()
                    .single();
                await supabase
                    .from('users')
                    .update({'household_id': res['id'], 'role': 'admin'})
                    .eq('id', uid);

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Created household "${res['name']}"!'), backgroundColor: const Color(0xFF00C896)),
                  );
                  _loadUserInfo();
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to create: $e'), backgroundColor: Colors.redAccent),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0D1117),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF00C896))),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        title: Text('Settings & Permissions', style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
        backgroundColor: const Color(0xFF161B22),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF8B949E)),
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
            style: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFF8B949E)),
          ),
          const SizedBox(height: 12),
          if (_householdId != null) ...[
            HouseholdManagementCard(
              householdName: _householdName ?? 'Household',
              inviteCode: _inviteCode ?? '--------',
              userRole: _userRole,
              members: _members,
              onCopyInviteCode: _copyInviteCode,
              onLeaveHousehold: _confirmLeaveHousehold,
              onSwitchHousehold: _showJoinHouseholdDialog,
              onCreateHousehold: _showCreateHouseholdDialog,
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF161B22),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF30363D)),
              ),
              child: Column(
                children: [
                  const Text(
                    'You have not joined any household yet.',
                    style: TextStyle(color: Color(0xFF8B949E), fontSize: 13),
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

          // ── 1. HARDWARE & APP PERMISSIONS ──
          _buildSectionHeader('HARDWARE & APP PERMISSIONS'),
          const SizedBox(height: 6),
          Text(
            'Check and manage camera and SMS access for expense scanning.',
            style: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFF8B949E)),
          ),
          const SizedBox(height: 12),

          // Camera Permission Card
          _buildPermissionCard(
            icon: Icons.camera_alt_outlined,
            title: 'Camera Access',
            subtitle: 'Required to scan physical receipts & Saudi ZATCA QR codes.',
            status: _cameraStatus,
            onRequest: _requestCameraPermission,
            onOpenSettings: openAppSettings,
            testAction: _cameraStatus.isGranted
                ? () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ZatcaQrCameraScanner()),
                    )
                : null,
            testLabel: 'Test Camera',
          ),
          const SizedBox(height: 10),

          // Microphone Permission Card
          _buildPermissionCard(
            icon: Icons.mic_none_outlined,
            title: 'Microphone Access',
            subtitle: 'Enables voice dictation for speaking items & expenses into AI chat.',
            status: _microphoneStatus,
            onRequest: _requestMicrophonePermission,
            onOpenSettings: openAppSettings,
          ),
          const SizedBox(height: 10),

          // SMS Permission Card
          _buildPermissionCard(
            icon: Icons.sms_outlined,
            title: 'SMS Access (Read & Receive)',
            subtitle: 'Allows automatic background detection of bank transaction alerts.',
            status: _smsStatus,
            onRequest: _requestSmsPermission,
            onOpenSettings: openAppSettings,
          ),
          const SizedBox(height: 10),

          // Notification Permission Card
          _buildPermissionCard(
            icon: Icons.notifications_active_outlined,
            title: 'Notifications',
            subtitle: 'Keeps background SMS monitoring service running reliably.',
            status: _notificationStatus,
            onRequest: () async {
              final status = await Permission.notification.request();
              setState(() => _notificationStatus = status);
            },
            onOpenSettings: openAppSettings,
          ),
          const SizedBox(height: 28),

          // ── 2. ACTIVE INPUT CHANNELS ──
          _buildSectionHeader('EXPENSE INGESTION CHANNELS'),
          const SizedBox(height: 10),
          _buildChannelTile(
            icon: Icons.sms_outlined,
            title: 'Bank SMS Interception',
            subtitle: 'Automatically captures incoming debit/credit card SMS.',
            value: _smsEnabled,
            onChanged: _toggleSms,
          ),
          const SizedBox(height: 10),
          _buildChannelTile(
            icon: Icons.chat_bubble_outline,
            title: 'AI Conversational Chat',
            subtitle: 'Log purchases via chat ("Dunkin 19 SAR: 16 latte 3 donut").',
            value: _chatEnabled,
            onChanged: (val) {
              setState(() => _chatEnabled = val);
              _savePreference('channel_chat_enabled', val);
            },
          ),
          const SizedBox(height: 10),
          _buildChannelTile(
            icon: Icons.document_scanner_outlined,
            title: 'Camera Receipt Scanner',
            subtitle: 'OCR scan thermal receipts and ZATCA tax invoices.',
            value: _scannerEnabled,
            onChanged: (val) {
              setState(() => _scannerEnabled = val);
              _savePreference('channel_scanner_enabled', val);
            },
          ),
          const SizedBox(height: 28),

          // ── 3. DUPLICATE RESOLUTION POLICY ──
          _buildSectionHeader('CROSS-CHANNEL DUPLICATE RESOLUTION'),
          const SizedBox(height: 6),
          Text(
            'Choose how the system handles transactions when multiple methods are used.',
            style: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFF8B949E)),
          ),
          const SizedBox(height: 12),
          _buildPolicyTile(
            policy: 'auto_enrich',
            title: 'Smart Auto-Enrichment (Recommended)',
            description:
                'If an SMS is already logged, scanning a receipt or chatting line items will attach the details to the SMS without creating a double charge.',
          ),
          const SizedBox(height: 8),
          _buildPolicyTile(
            policy: 'prompt',
            title: 'Prompt on Conflict',
            description:
                'Always prompt you whether to enrich the recent transaction or record it as a separate expense.',
          ),
          const SizedBox(height: 8),
          _buildPolicyTile(
            policy: 'strict',
            title: 'Strict Channel Isolation',
            description:
                'Prevent manual chat/scan entry when SMS interceptor is active to avoid double-entry.',
          ),
          // ── PARTNER FAIR-SHARE SETTLEMENT ──
          if (_householdId != null) ...[
            _buildSectionHeader('PARTNER FAIR-SHARE SETTLEMENT'),
            const SizedBox(height: 10),
            PartnerSettlementCard(householdId: _householdId!),
            const SizedBox(height: 28),
          ],

          // ── DATA EXPORT & OFFLINE QUEUE ──
          _buildSectionHeader('REPORTS & OFFLINE QUEUE'),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF161B22),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF30363D)),
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
                          Text('Export Monthly Report', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                          const Text('Generate standard CSV with Date, Merchant, Category, and Items', style: TextStyle(color: Color(0xFF8B949E), fontSize: 11)),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF21262D),
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
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export error: $e')));
                        }
                      },
                      child: const Text('Export CSV', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Divider(color: Color(0xFF30363D), height: 1),
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
                              Text(count > 0 ? '$count transaction(s) pending sync' : 'All transactions synchronized', style: const TextStyle(color: Color(0xFF8B949E), fontSize: 11)),
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

          // ── 4. HOUSEHOLD & ACCOUNT ──
          _buildSectionHeader('HOUSEHOLD & ACCOUNT'),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF161B22),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF30363D)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_userEmail != null) ...[
                  Row(
                    children: [
                      const Icon(Icons.account_circle_outlined, color: Color(0xFF8B949E), size: 18),
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
                      const Icon(Icons.home_outlined, color: Color(0xFF8B949E), size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Household: ${_householdId!.substring(0, 8)}...',
                          style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12, fontFamily: 'monospace'),
                        ),
                      ),
                      InkWell(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: _householdId!));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Household ID copied to clipboard!')),
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
        color: const Color(0xFF8B949E),
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
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isGranted ? const Color(0xFF00C896).withValues(alpha: 0.3) : const Color(0xFF30363D),
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
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.white),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 11, color: Color(0xFF8B949E)),
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
                    foregroundColor: const Color(0xFF58A6FF),
                    side: BorderSide(color: const Color(0xFF1F6FEB).withValues(alpha: 0.5)),
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
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFF30363D)),
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
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: value ? const Color(0xFF00C896).withValues(alpha: 0.12) : const Color(0xFF21262D),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: value ? const Color(0xFF00C896) : const Color(0xFF8B949E), size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.white)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF8B949E))),
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
          color: const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? const Color(0xFF00C896) : const Color(0xFF30363D),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: isSelected ? const Color(0xFF00C896) : const Color(0xFF8B949E),
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
                      color: isSelected ? Colors.white : const Color(0xFFC9D1D9),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(fontSize: 11, color: Color(0xFF8B949E), height: 1.3),
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
