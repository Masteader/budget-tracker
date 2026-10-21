import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/services/household_invite_share.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('household invite share text', () {
    test('contains the household name, the code and the join steps in each language', () {
      for (final lang in ['en', 'ar', 'ur']) {
        final l = AppLocalizations(Locale(lang));
        final text = inviteShareText(l, householdName: 'Villa 7', code: 'ABCD1234');
        expect(text, contains('Villa 7'), reason: lang);
        expect(text, contains('ABCD1234'), reason: lang);
        expect(text, contains(l.get('join_household')), reason: '$lang names the Join household step');
        expect(text, isNot(contains('{')), reason: '$lang placeholders filled');
      }
      expect(
        inviteShareText(AppLocalizations(const Locale('en')), householdName: 'Villa 7', code: 'ABCD1234'),
        contains('Open Budget Tracker'),
      );
    });

    test('a blank household name falls back to a generic one', () {
      final l = AppLocalizations(const Locale('en'));
      expect(inviteShareText(l, householdName: '  ', code: 'ABCD1234'), contains(l.get('set_my_household')));
    });

    test('only real 8-16 character codes are shareable', () {
      expect(isShareableInviteCode('ABCD1234'), isTrue);
      expect(isShareableInviteCode('ABCDEFGH12345678'), isTrue);
      expect(isShareableInviteCode('--------'), isFalse);
      expect(isShareableInviteCode('ABC'), isFalse);
      expect(isShareableInviteCode('ABCDEFGH123456789'), isFalse);
      expect(isShareableInviteCode(null), isFalse);
    });

    test('shareHouseholdInvite hands text and subject to the share sheet', () async {
      final l = AppLocalizations(const Locale('ar'));
      String? sharedText;
      String? sharedSubject;
      await shareHouseholdInvite(
        l,
        householdName: 'بيتنا',
        code: 'ZXCV5678',
        launcher: (text, subject) async {
          sharedText = text;
          sharedSubject = subject;
        },
      );
      expect(sharedText, contains('ZXCV5678'));
      expect(sharedText, contains('بيتنا'));
      expect(sharedSubject, l.get('invite_share_subject'));
    });
  });
}
