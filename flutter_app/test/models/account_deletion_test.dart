// Parsing and error mapping of the account deletion RPC answers. The payloads
// are the shapes built in supabase/migrations/20261105000200_account_deletion_rpcs.sql.
import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/models/account_deletion.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AccountDeletionStatus', () {
    test('none means nothing is pending and nothing can be cancelled', () {
      final status = AccountDeletionStatus.fromMap(const {'status': 'none', 'can_cancel': false});
      expect(status.state, AccountDeletionState.none);
      expect(status.isPending, isFalse);
      expect(status.canCancel, isFalse);
      expect(status.scheduledFor, isNull);
    });

    test('scheduled carries the date, the marks, and can be cancelled', () {
      final status = AccountDeletionStatus.fromMap(const {
        'request_id': 'r-1',
        'status': 'scheduled',
        'requested_at': '2026-11-05T10:00:00+00:00',
        'scheduled_for': '2026-12-05T10:00:00+00:00',
        'locale': 'ar',
        'can_cancel': true,
        'marked_households': [
          {'household_id': 'h-1', 'household_name': 'Home', 'scheduled_for': '2026-12-05T10:00:00+00:00'},
        ],
      });
      expect(status.state, AccountDeletionState.scheduled);
      expect(status.isPending, isTrue);
      expect(status.canCancel, isTrue);
      expect(status.scheduledFor!.toUtc(), DateTime.utc(2026, 12, 5, 10));
      expect(status.markedHouseholds.single.name, 'Home');
      expect(status.markedHouseholds.single.scheduledFor!.toUtc(), DateTime.utc(2026, 12, 5, 10));
    });

    for (final (wire, state) in [
      ('processing', AccountDeletionState.processing),
      ('failed', AccountDeletionState.failed),
    ]) {
      test('$wire is pending and cannot be cancelled', () {
        final status = AccountDeletionStatus.fromMap({
          'status': wire,
          'scheduled_for': '2026-12-05T10:00:00+00:00',
          'can_cancel': false,
        });
        expect(status.state, state);
        expect(status.isPending, isTrue);
        expect(status.canCancel, isFalse);
      });
    }

    test('an unknown status is never read as nothing pending', () {
      final status = AccountDeletionStatus.fromMap(const {'status': 'something_new'});
      expect(status.isPending, isTrue);
      expect(status.canCancel, isFalse);
    });

    test('a device flag says scheduled with the remembered date', () {
      final status = AccountDeletionStatus.fromDeviceFlag(DateTime.utc(2026, 12, 5));
      expect(status.isPending, isTrue);
      expect(status.canCancel, isTrue);
      expect(status.scheduledFor, DateTime.utc(2026, 12, 5));
    });
  });

  group('AccountDeletionPreflight', () {
    final preflight = AccountDeletionPreflight.fromMap(const {
      'deletion': {'status': 'none', 'can_cancel': false},
      'households': [
        {'household_id': 'h-m', 'household_name': 'As member', 'position': 'member', 'needs_choice': false, 'candidates': []},
        {'household_id': 'h-s', 'household_name': 'Alone', 'position': 'sole_member', 'needs_choice': false, 'candidates': []},
        {'household_id': 'h-c', 'household_name': 'Co-admin', 'position': 'co_admin', 'needs_choice': false, 'candidates': []},
        {
          'household_id': 'h-p',
          'household_name': 'Primary',
          'position': 'primary_admin',
          'needs_choice': true,
          'candidates': [
            {'user_id': 'u-2', 'display_name': 'Salem', 'pending_deletion': false},
            {'user_id': 'u-3', 'display_name': null, 'pending_deletion': true},
          ],
        },
      ],
    });

    test('reads all four positions', () {
      expect(preflight.households.map((h) => h.position), [
        HouseholdDeletionPosition.member,
        HouseholdDeletionPosition.soleMember,
        HouseholdDeletionPosition.coAdmin,
        HouseholdDeletionPosition.primaryAdmin,
      ]);
      expect(preflight.deletion.isPending, isFalse);
    });

    test('only the household the server flags needs a choice', () {
      expect(preflight.householdsNeedingChoice.map((h) => h.id), ['h-p']);
    });

    test('keeps a pending candidate flagged, and a nameless one nameless', () {
      final candidates = preflight.householdsNeedingChoice.single.candidates;
      expect(candidates.first.pendingDeletion, isFalse);
      expect(candidates.last.pendingDeletion, isTrue);
      expect(candidates.last.displayName, isNull);
    });

    test('a household whose only candidates are pending has no selectable successor', () {
      const onlyPending = AccountDeletionHousehold(
        id: 'h',
        name: 'n',
        position: HouseholdDeletionPosition.primaryAdmin,
        needsChoice: true,
        candidates: [AccountDeletionCandidate(userId: 'u', pendingDeletion: true)],
      );
      expect(onlyPending.hasSelectableSuccessor, isFalse);
      expect(preflight.householdsNeedingChoice.single.hasSelectableSuccessor, isTrue);
    });
  });

  group('HouseholdDeletionChoice', () {
    test('a transfer names the successor', () {
      expect(const HouseholdDeletionChoice.transfer('h', 'u').toJson(),
          {'household_id': 'h', 'action': 'transfer', 'successor_user_id': 'u'});
    });

    test('a delete sends no successor key at all: the server refuses one', () {
      final json = const HouseholdDeletionChoice.delete('h').toJson();
      expect(json, {'household_id': 'h', 'action': 'delete'});
      expect(json.containsKey('successor_user_id'), isFalse);
    });
  });

  group('error hints', () {
    const hints = {
      'reauthentication_required': 'del_err_reauth_required',
      'confirmation_mismatch': 'del_err_confirmation_mismatch',
      'household_choice_missing': 'del_err_choice_missing',
      'household_choice_invalid': 'del_err_choice_invalid',
      'successor_invalid': 'del_err_successor_invalid',
      'successor_pending_deletion': 'del_err_successor_pending',
      'account_pending_deletion': 'del_err_account_pending',
      'household_pending_deletion': 'del_err_household_pending',
      'deletion_in_progress': 'del_err_in_progress',
      AccountDeletionException.invalidCredentials: 'del_err_wrong_password',
      AccountDeletionException.invalidCode: 'del_err_wrong_code',
      AccountDeletionException.rateLimited: 'del_err_rate_limited',
      AccountDeletionException.network: 'del_err_network',
      AccountDeletionException.unknown: 'del_err_generic',
    };

    hints.forEach((hint, key) {
      test('$hint has its own message', () {
        expect(AccountDeletionException(hint).messageKey, key);
      });
    });

    test('a hint this build does not know gets the generic message', () {
      expect(const AccountDeletionException('raw server text').messageKey, 'del_err_generic');
    });

    test('every message exists in all three languages and differs from English', () {
      for (final key in hints.values) {
        final en = AppLocalizations(const Locale('en')).get(key);
        final ar = AppLocalizations(const Locale('ar')).get(key);
        final ur = AppLocalizations(const Locale('ur')).get(key);
        expect(en, isNot(key), reason: 'en $key missing');
        expect(ar, isNot(en), reason: 'ar $key not translated');
        expect(ur, isNot(en), reason: 'ur $key not translated');
      }
    });

    test('the flow knows which errors send it back a step', () {
      expect(const AccountDeletionException('reauthentication_required').needsReauthentication, isTrue);
      expect(const AccountDeletionException('confirmation_mismatch').needsReauthentication, isFalse);
      for (final hint in ['household_choice_missing', 'household_choice_invalid', 'successor_invalid', 'successor_pending_deletion']) {
        expect(AccountDeletionException(hint).choicesOutOfDate, isTrue, reason: hint);
      }
      expect(const AccountDeletionException('confirmation_mismatch').choicesOutOfDate, isFalse);
    });

    test('a grace-period guard code maps wherever it arrives; other codes do not', () {
      expect(accountDeletionGuardKey('account_pending_deletion'), 'del_err_account_pending');
      expect(accountDeletionGuardKey('household_pending_deletion'), 'del_err_household_pending');
      expect(accountDeletionGuardKey('successor_pending_deletion'), 'del_err_successor_pending');
      expect(accountDeletionGuardKey('type_change_blocked'), isNull);
      expect(accountDeletionGuardKey(null), isNull);
    });
  });

  group('confirmationWordMatches', () {
    test('accepts each language\'s word, as the server does', () {
      expect(confirmationWordMatches('DELETE'), isTrue);
      expect(confirmationWordMatches('حذف'), isTrue);
      expect(confirmationWordMatches('حذف کریں'), isTrue);
    });

    test('ignores case, outer spaces, repeated spaces and bidi marks', () {
      expect(confirmationWordMatches('  delete '), isTrue);
      expect(confirmationWordMatches('DeLeTe'), isTrue);
      expect(confirmationWordMatches('حذف   کریں'), isTrue);
      expect(confirmationWordMatches('‏حذف‎'), isTrue);
    });

    test('refuses anything else', () {
      for (final typed in ['', ' ', 'delet', 'deletee', 'yes', 'حذ', 'کریں']) {
        expect(confirmationWordMatches(typed), isFalse, reason: typed);
      }
    });
  });
}
