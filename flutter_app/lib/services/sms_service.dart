/// SMS service: bridges the native Kotlin SmsListenerService with Flutter.
/// Implements strict client-side pre-filtering (bank allowlist and OTP/verification
/// keyword rejection) before transmitting to the FastAPI webhook.
library;

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'api_service.dart';

class SmsService {
  SmsService._();
  static final SmsService instance = SmsService._();

  static const _channel = MethodChannel('com.budgettracker/sms');
  static const _serviceChannel = MethodChannel('com.budgettracker/service');

  // ── Strict Client-Side Filtering Configuration ───────────────────────────
  static const List<String> allowedBankSenders = [
    'snb',
    'alrajhi',
    'al rajhi',
    'rajhibank',
    'alinma',
    'riyad',
    'anb',
    'sab',
    'bsf',
    'albilad',
    'aljazira',
    'gib',
    '9200',
  ];

  static const List<String> otpKeywords = [
    'otp',
    'code',
    'رمز',
    'تحقق',
  ];

  static final RegExp otpRegex = RegExp(
    r'\b(otp|code)\b|رمز|تحقق',
    caseSensitive: false,
  );

  /// Checks sender ID against the allowlist of Saudi banks.
  static bool isAllowedSender(String sender) {
    final s = sender.toLowerCase().trim();
    return allowedBankSenders.any((bank) => s.contains(bank));
  }

  /// Returns true if the message body contains OTP or verification keywords.
  static bool isOtpMessage(String body) {
    final lower = body.toLowerCase();
    return otpKeywords.any((k) => lower.contains(k)) || otpRegex.hasMatch(body);
  }

  bool _isListening = false;
  bool get isListening => _isListening;

  final StreamController<Map<String, dynamic>> _smsController =
      StreamController.broadcast();

  /// Stream of processed SMS results from the API.
  Stream<Map<String, dynamic>> get onSmsProcessed => _smsController.stream;

  // ── Initialise ────────────────────────────────────────────────────────────

  void init() {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  // ── Start / Stop service ──────────────────────────────────────────────────

  Future<void> startService() async {
    try {
      await _serviceChannel.invokeMethod('startService');
      _isListening = true;
    } on PlatformException {
      _isListening = false;
      rethrow;
    }
  }

  Future<void> stopService() async {
    try {
      await _serviceChannel.invokeMethod('stopService');
    } finally {
      _isListening = false;
    }
  }

  /// Drain any SMS messages that were queued offline (native SQLite).
  Future<void> drainOfflineQueue() async {
    try {
      final queued = await _serviceChannel.invokeMethod<List>('drainQueue');
      if (queued == null || queued.isEmpty) return;
      for (final item in queued) {
        await _processSms(
          body: item['body'] as String,
          sender: item['sender'] as String,
          timestamp: item['timestamp'] as int,
        );
      }
    } on PlatformException {
      // Silently ignore — queue will be retried next resume
    }
  }

  // ── Native method call handler ────────────────────────────────────────────

  Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method == 'onSmsReceived') {
      final args = Map<String, dynamic>.from(call.arguments as Map);
      await _processSms(
        body: args['body'] as String,
        sender: args['sender'] as String,
        timestamp: args['timestamp'] as int,
      );
    }
  }

  // ── Core processing ───────────────────────────────────────────────────────

  Future<void> _processSms({
    required String body,
    required String sender,
    required int timestamp,
  }) async {
    // 1. Strict Client-Side Filter: Drop if sender not in bank allowlist
    if (!isAllowedSender(sender)) {
      debugPrint('[SmsService] Dropped SMS from non-bank sender: $sender');
      return;
    }

    // 2. Strict Client-Side Filter: Drop if message contains OTP or verification keywords
    if (isOtpMessage(body)) {
      debugPrint('[SmsService] Dropped OTP / verification SMS from: $sender');
      return;
    }

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        await _enqueueOffline(body, sender, timestamp);
        return;
      }

      final profile = await Supabase.instance.client
          .from('users')
          .select('household_id')
          .eq('id', user.id)
          .maybeSingle();

      final householdId = profile?['household_id'] as String?;
      if (householdId == null) {
        await _enqueueOffline(body, sender, timestamp);
        return;
      }

      final receivedAt =
          DateTime.fromMillisecondsSinceEpoch(timestamp).toIso8601String();

      final result = await ApiService.instance.postSms(
        rawSms: body,
        sender: sender,
        receivedAt: receivedAt,
        householdId: householdId,
      );

      if (result['status'] == 'error') {
        debugPrint('[SmsService] Webhook error (${result['message']}); caching to offline queue.');
        await _enqueueOffline(body, sender, timestamp);
      }

      _smsController.add(result);
    } catch (e) {
      debugPrint('[SmsService] Error processing SMS: $e; caching to offline queue.');
      await _enqueueOffline(body, sender, timestamp);
    }
  }

  Future<void> _enqueueOffline(String body, String sender, int timestamp) async {
    try {
      await _serviceChannel.invokeMethod('enqueueSms', {
        'body': body,
        'sender': sender,
        'timestamp': timestamp,
      });
    } catch (e) {
      debugPrint('[SmsService] Could not enqueue offline SMS: $e');
    }
  }

  void dispose() {
    _smsController.close();
  }
}

