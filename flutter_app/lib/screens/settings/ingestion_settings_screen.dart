import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/sms_service.dart';

class IngestionSettingsScreen extends StatefulWidget {
  const IngestionSettingsScreen({super.key});

  @override
  State<IngestionSettingsScreen> createState() => _IngestionSettingsScreenState();
}

class _IngestionSettingsScreenState extends State<IngestionSettingsScreen> {
  bool _smsEnabled = true;
  bool _chatEnabled = true;
  bool _scannerEnabled = true;
  String _dedupPolicy = 'auto_enrich'; // 'auto_enrich' | 'prompt' | 'strict'
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _smsEnabled = prefs.getBool('channel_sms_enabled') ?? true;
      _chatEnabled = prefs.getBool('channel_chat_enabled') ?? true;
      _scannerEnabled = prefs.getBool('channel_scanner_enabled') ?? true;
      _dedupPolicy = prefs.getString('dedup_policy') ?? 'auto_enrich';
      _isLoading = false;
    });
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
    setState(() => _smsEnabled = value);
    await _savePreference('channel_sms_enabled', value);
    if (!value) {
      SmsService.instance.stopService();
    } else {
      SmsService.instance.startService();
    }
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
        title: Text('Ingestion & Channels', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
        backgroundColor: const Color(0xFF161B22),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        children: [
          Text(
            'ACTIVE INPUT CHANNELS',
            style: GoogleFonts.outfit(
              fontSize: 12,
              letterSpacing: 1,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF8B949E),
            ),
          ),
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

          Text(
            'CROSS-CHANNEL DUPLICATE PREVENTION',
            style: GoogleFonts.outfit(
              fontSize: 12,
              letterSpacing: 1,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF8B949E),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Choose how the app resolves transactions when multiple channels are used simultaneously.',
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
              color: value ? const Color(0xFF00C896).withOpacity(0.12) : const Color(0xFF21262D),
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
                Text(subtitle, style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: const Color(0xFF00C896),
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
              isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
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
                      fontSize: 14,
                      color: isSelected ? Colors.white : const Color(0xFFC9D1D9),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12, height: 1.3),
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
