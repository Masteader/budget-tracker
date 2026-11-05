import 'dart:async';
import 'dart:io' show SocketException;

import 'package:http/http.dart' show ClientException;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/account_deletion.dart';

/// Account deletion through the client RPCs, which act only on `auth.uid()`:
/// no call here can name another user. Goes straight to Supabase, like the role
/// RPCs, not through the FastAPI facade.
///
/// Every failure is an [AccountDeletionException] carrying a machine code, so
/// server text can never reach the screen.
class AccountDeletionService {
  AccountDeletionService({SupabaseClient? client}) : _injected = client;

  final SupabaseClient? _injected;

  SupabaseClient get _client => _injected ?? Supabase.instance.client;

  String? get currentUserId {
    try {
      return _client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  String? get currentEmail {
    try {
      return _client.auth.currentUser?.email;
    } catch (_) {
      return null;
    }
  }

  Future<AccountDeletionStatus> getStatus() async =>
      AccountDeletionStatus.fromMap(await _rpc('get_account_deletion_status'));

  Future<AccountDeletionPreflight> getPreflight() async =>
      AccountDeletionPreflight.fromMap(await _rpc('get_account_deletion_preflight'));

  /// Schedules the deletion. Needs a session created in the last 15 minutes (the
  /// server checks), so [reauthenticateWithPassword] or [verifyEmailCode] first.
  /// A repeated request answers with the existing one.
  Future<AccountDeletionStatus> request({
    required String confirmation,
    required List<HouseholdDeletionChoice> choices,
    required String locale,
  }) async {
    final res = await _rpc('request_account_deletion', {
      'p_confirmation': confirmation,
      'p_household_choices': choices.map((c) => c.toJson()).toList(),
      'p_locale': locale,
    });
    return AccountDeletionStatus.fromMap(res);
  }

  Future<void> cancel() async {
    await _rpc('cancel_account_deletion');
  }

  /// A fresh session from the password. A wrong password leaves the current one.
  Future<void> reauthenticateWithPassword(String password) => _auth(() async {
        await _client.auth.signInWithPassword(email: _requireEmail(), password: password);
      });

  /// Emails a one-time code to the signed-in address, for a forgotten password.
  Future<void> sendEmailCode() => _auth(() async {
        await _client.auth.signInWithOtp(email: _requireEmail(), shouldCreateUser: false);
      });

  /// A fresh session from the emailed code.
  Future<void> verifyEmailCode(String code) => _auth(() async {
        await _client.auth.verifyOTP(email: _requireEmail(), token: code, type: OtpType.email);
      }, wrongSecret: AccountDeletionException.invalidCode);

  /// Reads the deletion mark of [householdId]. RLS shows only the active
  /// household, so no row means it is gone or no longer the active one.
  Future<HouseholdDeletionMark> readHouseholdMark(String householdId) => _guard(() async {
        final row = await _client.from('households').select('deletion_scheduled_for').eq('id', householdId).maybeSingle();
        if (row == null) return const HouseholdDeletionMark(readable: false);
        final raw = row['deletion_scheduled_for'];
        return HouseholdDeletionMark(readable: true, scheduledFor: raw == null ? null : DateTime.tryParse(raw.toString()));
      });

  /// Whether the signed-in user's profile row still exists. After a purge the
  /// JWT stays valid until it expires, but the row is gone.
  Future<bool> accountRowExists() => _guard(() async {
        final uid = currentUserId;
        if (uid == null) return false;
        final row = await _client.from('users').select('id').eq('id', uid).maybeSingle();
        return row != null;
      });

  String _requireEmail() {
    final email = currentEmail;
    if (email == null || email.isEmpty) throw const AccountDeletionException(AccountDeletionException.unknown);
    return email;
  }

  Future<Map<String, dynamic>> _rpc(String function, [Map<String, dynamic>? params]) => _guard(() async {
        final res = await _client.rpc<dynamic>(function, params: params);
        if (res is Map) return Map<String, dynamic>.from(res);
        throw const AccountDeletionException(AccountDeletionException.unknown);
      });

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on AccountDeletionException {
      rethrow;
    } on PostgrestException catch (e) {
      final hint = e.hint;
      throw AccountDeletionException(hint == null || hint.isEmpty ? AccountDeletionException.unknown : hint);
    } catch (e) {
      throw AccountDeletionException(_isNetwork(e) ? AccountDeletionException.network : AccountDeletionException.unknown);
    }
  }

  Future<void> _auth(Future<void> Function() call, {String wrongSecret = AccountDeletionException.invalidCredentials}) async {
    try {
      await call();
    } on AccountDeletionException {
      rethrow;
    } on AuthRetryableFetchException {
      throw const AccountDeletionException(AccountDeletionException.network);
    } on AuthException catch (e) {
      final status = int.tryParse(e.statusCode ?? '');
      if (status == 429 || e.code == 'over_request_rate_limit' || e.code == 'over_email_send_rate_limit') {
        throw const AccountDeletionException(AccountDeletionException.rateLimited);
      }
      if (e.code == 'invalid_credentials' || e.code == 'otp_expired' || status == 400 || status == 401 || status == 403) {
        throw AccountDeletionException(wrongSecret);
      }
      throw const AccountDeletionException(AccountDeletionException.unknown);
    } catch (e) {
      throw AccountDeletionException(_isNetwork(e) ? AccountDeletionException.network : AccountDeletionException.unknown);
    }
  }

  static bool _isNetwork(Object e) => e is SocketException || e is TimeoutException || e is ClientException;
}
