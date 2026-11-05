// AccountDeletionService against a real Supabase client whose HTTP never leaves
// the process: RPC names and payloads as the migration defines them, and every
// failure reduced to a machine code.
import 'package:budget_tracker/models/account_deletion.dart';
import 'package:budget_tracker/services/account_deletion_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../support/fake_settings_supabase.dart';

final _http = FakeSettingsHttpClient();

Matcher _refusedWith(String code) =>
    throwsA(isA<AccountDeletionException>().having((e) => e.code, 'code', code));

void main() {
  late AccountDeletionService service;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    TestWidgetsFlutterBinding.ensureInitialized();
    await initFakeSettingsSupabase(_http);
  });

  setUp(() async {
    _http.resetScenario();
    await resetFakeSettingsAuth();
    service = AccountDeletionService();
  });

  group('RPCs', () {
    test('status reads get_account_deletion_status', () async {
      _http.rpcResults['get_account_deletion_status'] = {
        'status': 'scheduled',
        'scheduled_for': '2026-12-05T10:00:00+00:00',
        'can_cancel': true,
      };
      final status = await service.getStatus();
      expect(_http.rpcCalls.single.function, 'get_account_deletion_status');
      expect(status.state, AccountDeletionState.scheduled);
      expect(status.canCancel, isTrue);
    });

    test('preflight reads get_account_deletion_preflight', () async {
      _http.rpcResults['get_account_deletion_preflight'] = {
        'deletion': {'status': 'none', 'can_cancel': false},
        'households': [
          {'household_id': 'h', 'household_name': 'Home', 'position': 'primary_admin', 'needs_choice': true, 'candidates': []},
        ],
      };
      final preflight = await service.getPreflight();
      expect(_http.rpcCalls.single.function, 'get_account_deletion_preflight');
      expect(preflight.householdsNeedingChoice.single.name, 'Home');
    });

    test('a request sends the typed word, the choices and the locale, and no reason', () async {
      _http.rpcResults['request_account_deletion'] = {
        'status': 'scheduled',
        'scheduled_for': '2026-12-05T10:00:00+00:00',
        'can_cancel': true,
        'success': true,
        'already_requested': false,
      };
      final status = await service.request(
        confirmation: 'حذف',
        choices: const [HouseholdDeletionChoice.transfer('h-1', 'u-2'), HouseholdDeletionChoice.delete('h-2')],
        locale: 'ar',
      );
      final call = _http.rpcCalls.single;
      expect(call.function, 'request_account_deletion');
      expect(call.params, {
        'p_confirmation': 'حذف',
        'p_household_choices': [
          {'household_id': 'h-1', 'action': 'transfer', 'successor_user_id': 'u-2'},
          {'household_id': 'h-2', 'action': 'delete'},
        ],
        'p_locale': 'ar',
      });
      expect(status.scheduledFor!.toUtc(), DateTime.utc(2026, 12, 5, 10));
    });

    test('cancel calls cancel_account_deletion and takes no arguments', () async {
      _http.rpcResults['cancel_account_deletion'] = {'success': true, 'cancelled': true, 'status': 'none', 'can_cancel': false};
      await service.cancel();
      expect(_http.rpcCalls.single.function, 'cancel_account_deletion');
      expect(_http.rpcCalls.single.params, isEmpty);
    });
  });

  group('refusals carry the hint, never the server text', () {
    for (final hint in const [
      'confirmation_mismatch',
      'household_choice_missing',
      'household_choice_invalid',
      'successor_invalid',
      'successor_pending_deletion',
      'deletion_in_progress',
    ]) {
      test(hint, () async {
        _http.rpcRefusals['request_account_deletion'] = FakeRpcRefusal(hint);
        await expectLater(
          service.request(confirmation: 'x', choices: const [], locale: 'en'),
          _refusedWith(hint),
        );
      });
    }

    test('reauthentication_required arrives as a 403 and maps the same way', () async {
      _http.rpcRefusals['request_account_deletion'] =
          const FakeRpcRefusal('reauthentication_required', code: '42501', status: 403);
      await expectLater(
        service.request(confirmation: 'x', choices: const [], locale: 'en'),
        _refusedWith('reauthentication_required'),
      );
    });

    test('a refusal without a hint is unknown, not its message', () async {
      _http.rpcErrors['get_account_deletion_status'] = 'raw server text';
      await expectLater(service.getStatus(), _refusedWith(AccountDeletionException.unknown));
    });

    test('no answer at all is a network failure', () async {
      _http.rpcOffline.add('get_account_deletion_status');
      await expectLater(service.getStatus(), _refusedWith(AccountDeletionException.network));
    });

    test('an answer that is not an object is unknown', () async {
      _http.rpcResults['get_account_deletion_status'] = ['not', 'an', 'object'];
      await expectLater(service.getStatus(), _refusedWith(AccountDeletionException.unknown));
    });
  });

  group('re-authentication', () {
    test('the right password signs in again with the account email', () async {
      await service.reauthenticateWithPassword(fakeSettingsPassword);
      expect(_http.authCalls, ['password:$fakeSettingsEmail']);
      expect(Supabase.instance.client.auth.currentUser?.id, fakeSettingsUserId);
    });

    test('a wrong password is refused and the user stays signed in', () async {
      await expectLater(service.reauthenticateWithPassword('wrong'), _refusedWith(AccountDeletionException.invalidCredentials));
      expect(Supabase.instance.client.auth.currentUser?.id, fakeSettingsUserId);
    });

    test('the email code never creates an account', () async {
      await service.sendEmailCode();
      expect(_http.authCalls.single, 'otp:$fakeSettingsEmail:false');
    });

    test('the right email code signs in again as an email OTP', () async {
      await service.verifyEmailCode(fakeSettingsEmailCode);
      expect(_http.authCalls.single, 'verify:$fakeSettingsEmail:email');
    });

    test('a wrong email code is its own failure', () async {
      await expectLater(service.verifyEmailCode('000000'), _refusedWith(AccountDeletionException.invalidCode));
      expect(Supabase.instance.client.auth.currentUser?.id, fakeSettingsUserId);
    });

    test('too many attempts is its own failure', () async {
      _http.authFailure = (status: 429, code: 'over_request_rate_limit');
      await expectLater(service.reauthenticateWithPassword(fakeSettingsPassword), _refusedWith(AccountDeletionException.rateLimited));
      await expectLater(service.sendEmailCode(), _refusedWith(AccountDeletionException.rateLimited));
    });
  });

  group('household mark', () {
    test('a marked household reports its date', () async {
      _http.householdDeletionDates['h-1'] = '2026-12-05T10:00:00+00:00';
      final mark = await service.readHouseholdMark('h-1');
      expect(mark.readable, isTrue);
      expect(mark.scheduledFor!.toUtc(), DateTime.utc(2026, 12, 5, 10));
    });

    test('an unmarked household is readable with no date', () async {
      final mark = await service.readHouseholdMark('h-1');
      expect(mark.readable, isTrue);
      expect(mark.scheduledFor, isNull);
    });

    test('no row back means the household cannot be read', () async {
      _http.unreadableHouseholds.add('h-1');
      expect((await service.readHouseholdMark('h-1')).readable, isFalse);
    });

    test('a failed read is a failure, never "no household"', () async {
      _http.failPaydayRead = true;
      await expectLater(service.readHouseholdMark('h-1'), throwsA(isA<AccountDeletionException>()));
    });
  });

  test('accountRowExists follows the users row', () async {
    expect(await service.accountRowExists(), isTrue);
    _http.userRowExists = false;
    expect(await service.accountRowExists(), isFalse);
  });
}
