// Round 1 review fixes (owner decisions 2026-11-06).
//
// R1-09: every code the Nafaqah API names has its own localized message in
// en, ar and ur (never the generic failure), and the decline reason is
// counted in Unicode code points, as the API and the database count it.
// R1-01: a wife is offered no account to pay from, a pool least of all.
import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/models/account.dart';
import 'package:budget_tracker/models/nafaqah.dart';
import 'package:budget_tracker/widgets/nafaqah/repayment_account_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Future<BuildContext> _context(WidgetTester tester, String lang) async {
  late BuildContext captured;
  await tester.pumpWidget(MaterialApp(
    locale: Locale(lang),
    supportedLocales: const [Locale('en'), Locale('ar'), Locale('ur')],
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Builder(builder: (context) {
      captured = context;
      return const SizedBox.shrink();
    }),
  ));
  await tester.pumpAndSettle();
  return captured;
}

Account _acct(String id, {String owner = 'u-wife', bool pool = false}) => Account(
      id: id,
      householdId: 'hh',
      ownerUserId: owner,
      name: id,
      accountType: pool ? AccountType.sharedPool : AccountType.bank,
      currency: 'SAR',
      balance: 1000,
      isSharedPool: pool,
    );

void main() {
  group('R1-09: every refusal has its own words', () {
    for (final lang in ['en', 'ar', 'ur']) {
      testWidgets('$lang: each code the API names', (tester) async {
        final context = await _context(tester, lang);
        final generic = context.tr('settle_record_failed_msg');
        for (final code in kNafaqahErrorCodes) {
          final text = repaymentErrorText(context, NafaqahApiException(code, 'refused', statusCode: 409, outstanding: 12.5), owedNow: 30);
          expect(text, isNot(generic), reason: code);
          expect(text, isNot(contains('_')), reason: '$code reads as a key: $text');
          expect(text, isNot(contains('{')), reason: '$code has an unfilled placeholder: $text');
        }
      });
    }

    test('the new keys exist in en, ar and ur with the same placeholders', () {
      const keys = [
        'req_status_already_repaid', 'repay_err_key_reused', 'repay_err_forbidden', 'req_err_reason_long',
        'nafaqah_err_not_family', 'repay_unconfirmed_hold', 'husband_owes_wife_label', 'nafaqah_owed_to_you_label',
        'fmd_remaining_label', 'req_decline_counter', 'acct_activity_action', 'acct_activity_title', 'acct_activity_desc',
        'acct_activity_empty', 'acct_line_wife_repayment', 'acct_line_wife_repayment_reversal',
        'acct_line_former_member_payment', 'acct_line_former_member_payment_reversal', 'acct_line_transfer_to',
        'acct_line_transfer_from', 'acct_line_transfer_out', 'acct_line_transfer_in', 'acct_line_fee',
      ];
      final placeholder = RegExp(r'\{(\w+)\}');
      Set<String> names(String s) => placeholder.allMatches(s).map((m) => m.group(1)!).toSet();
      for (final key in keys) {
        final en = AppLocalizations.localizedMap('en')[key];
        expect(en, isNotNull, reason: key);
        for (final lang in ['ar', 'ur']) {
          final other = AppLocalizations.localizedMap(lang)[key];
          expect(other, isNotNull, reason: '$lang $key');
          expect(names(other!), names(en!), reason: '$lang $key');
        }
      }
    });
  });

  group('R1-09: the decline reason counts Unicode code points', () {
    test('the limit is the server\'s 200 code points', () {
      expect(kDeclineReasonMaxCodePoints, 200);
    });

    test('a reason with harakat is cut at 200 code points, never at 200 graphemes', () {
      const formatter = CodePointLengthFormatter(200);
      final marked = 'بِ' * 101; // 202 code points, 101 graphemes
      final out = formatter.formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: marked));
      expect(out.text.runes.length, 200);
    });

    test('a surrogate pair is never split', () {
      const formatter = CodePointLengthFormatter(3);
      final out = formatter.formatEditUpdate(TextEditingValue.empty, const TextEditingValue(text: 'ab😀😀'));
      expect(out.text, 'ab😀');
    });
  });

  group('R1-01: a wife pays from no account', () {
    final accounts = [_acct('a-hers'), _acct('a-pool', owner: 'u-admin', pool: true)];

    test('not even as an admin, a pool least of all', () {
      expect(repaymentAccounts(accounts, householdId: 'hh', currentUserId: 'u-wife', isAdmin: true, isWife: true), isEmpty);
    });

    test('an admin who is not a wife still pays from the pool', () {
      expect(
        repaymentAccounts(accounts, householdId: 'hh', currentUserId: 'u-admin', isAdmin: true).map((a) => a.id),
        ['a-pool'],
      );
    });
  });
}
