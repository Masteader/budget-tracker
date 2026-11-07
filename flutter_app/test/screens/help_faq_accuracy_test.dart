// The Help FAQ answers match what the app does (docs/HOW_IT_WORKS.md) and
// name the app's buttons exactly, in every language.
import 'dart:io';

import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/screens/settings/help_support_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/localized_app.dart';

const _langs = ['en', 'ar', 'ur'];

/// Every FAQ key (question, answer and group title) in the translation file.
final _faqKeys = RegExp(r"^\s*'(faq_[a-z0-9_]+)'\s*:", multiLine: true)
    .allMatches(File('lib/l10n/app_localizations.dart').readAsStringSync())
    .map((m) => m.group(1)!)
    .toSet();

void main() {
  test('the payday is the household\'s own: only the first answer names the 27th, as the default', () {
    for (final lang in _langs) {
      final l = AppLocalizations(Locale(lang));
      expect(l.get('faq_cat_salary'), isNot(contains('27')), reason: lang);
      expect(l.get('faq_salary_a2'), isNot(contains('27')), reason: lang);
      expect(l.get('faq_salary_a3'), isNot(contains('27')), reason: lang);
      expect(l.get('faq_salary_a1'), contains(l.get('pds_title')), reason: '$lang names where an admin changes it');
    }
    final en = AppLocalizations(const Locale('en'));
    expect(en.get('faq_salary_a1'), contains('unless an admin changes it'));
  });

  test('the rollover answer promises no rule choice and no savings reserve', () {
    final en = AppLocalizations(const Locale('en')).get('faq_salary_a2').toLowerCase();
    expect(en, isNot(contains('reserve')));
    expect(en, isNot(contains('roll over')));
    for (final lang in _langs) {
      final l = AppLocalizations(Locale(lang));
      expect(l.get('faq_salary_a2'), contains(l.get('sinking_fund_toggle')), reason: lang);
    }
  });

  test('the answers name the real buttons', () {
    for (final lang in _langs) {
      final l = AppLocalizations(Locale(lang));
      void names(String faq, List<String> labels) {
        for (final label in labels) {
          expect(l.get(faq), contains(l.get(label)), reason: '$lang $faq names $label');
        }
      }

      names('faq_receipts_a1', ['add_expense', 'scan_receipt']);
      names('faq_bills_a1', ['rb_configure', 'rb_manage_title', 'recurring_bills']);
      names('faq_bills_a3', ['rb_pay', 'rb_confirm_paid']);
      names('faq_bnpl_a1', ['installments_bnpl', 'add_installment_plan']);
      names('faq_household_a2', ['set_household_membership', 'hmc_invite_with_role', 'hh_your_household']);
      names('faq_household_a3', ['roles_title']);
      names('faq_household_a4', ['wife_acc_add_title', 'accounts_balances', 'shared_household_pool']);
      names('faq_nafaqah_a4', ['reimburse_wife', 'nafaqah_mark_received', 'rev_action']);
      names('faq_privacy_a2', ['del_delete_account', 'del_cancel_button', 'deleted_member']);
    }
  });

  test('no answer has the old errors', () {
    for (final lang in _langs) {
      final l = AppLocalizations(Locale(lang));
      final receipts = l.get('faq_receipts_a1');
      expect(receipts.contains('Gemini') || receipts.toLowerCase().contains('green'), isFalse, reason: lang);
      expect(receipts, isNot(contains('الأخضر')));
      expect(receipts, isNot(contains('سبز')));
      expect(_faqKeys.length, greaterThan(40));
      for (final key in _faqKeys) {
        expect(l.get(key), isNot(contains('400')), reason: '$lang $key names a fixed fee');
      }
      for (final key in ['faq_bills_a3', 'faq_bills_q2', 'faq_bills_a2', 'faq_cat_bills']) {
        final v = l.get(key);
        expect(v.toLowerCase(), isNot(contains('green')), reason: '$lang $key');
        expect(v, isNot(contains('الأخضر')), reason: '$lang $key');
        expect(v, isNot(contains('سبز')), reason: '$lang $key');
      }
      expect(l.get('faq_bills_a1'), isNot(contains('Manage Bills')), reason: lang);
    }
    expect(AppLocalizations(const Locale('en')).get('faq_nafaqah_a3'), contains('an admin who is not a wife'));
  });

  test('only the primary admin chooses to hand over or delete a household', () {
    final en = AppLocalizations(const Locale('en')).get('faq_privacy_a2');
    expect(en, contains('primary admin'));
    expect(en, contains('co-admin'));
    expect(AppLocalizations(const Locale('ar')).get('faq_privacy_a2'), contains('المشرف الرئيسي'));
    expect(AppLocalizations(const Locale('ur')).get('faq_privacy_a2'), contains('مرکزی ایڈمن'));
  });

  test('"Mark as received" is only for money paid outside the app', () {
    final en = AppLocalizations(const Locale('en'));
    expect(en.get('faq_nafaqah_a4'), contains('outside the app'));
    expect(en.get('tutor_role_wife_desc'), contains('outside the app'));
    expect(en.get('tutor_role_husband_desc'), contains('outside the app'));
    for (final lang in _langs) {
      final l = AppLocalizations(Locale(lang));
      expect(l.get('tutor_role_wife_desc'), contains('{reimburse}'), reason: '$lang: a direct repayment needs nothing from her');
    }
  });

  test('Log Prior Spending is described as part of the over-allocation warning', () {
    expect(AppLocalizations(const Locale('en')).get('tutor_stage_3_desc'), contains('exceed'));
    expect(AppLocalizations(const Locale('ar')).get('tutor_stage_3_desc'), contains('تتجاوز'));
    expect(AppLocalizations(const Locale('ur')).get('tutor_stage_3_desc'), contains('زیادہ'));
  });

  test('the deletion answer promises no email (rule 04 §6)', () {
    for (final lang in _langs) {
      final v = AppLocalizations(Locale(lang)).get('faq_privacy_a2');
      expect(v, contains('30'), reason: lang);
      for (final word in ['email', 'e-mail', 'بريد', 'ای میل', 'ای میل']) {
        expect(v.toLowerCase(), isNot(contains(word)), reason: '$lang $word');
      }
    }
  });

  test('the new family and privacy answers never split between spouses', () {
    for (final lang in _langs) {
      final l = AppLocalizations(Locale(lang));
      for (final key in ['faq_nafaqah_a3', 'faq_nafaqah_a4', 'faq_household_a3', 'faq_household_a4', 'faq_privacy_a1', 'faq_privacy_a2']) {
        final v = l.get(key);
        expect(v, isNot(key), reason: '$lang $key missing');
        expect(v.contains('50/50') || v.contains('%'), isFalse, reason: '$lang $key');
      }
    }
  });

  testWidgets('the privacy group and its questions are listed, and search finds them', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(localizedApp(const HelpSupportScreen(), lang: 'ar', scaffold: false));
    await tester.pumpAndSettle();

    final ar = AppLocalizations(const Locale('ar'));
    final topic = find.text(ar.get('faq_cat_privacy'));
    await tester.scrollUntilVisible(topic, 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(topic);
    await tester.pumpAndSettle();
    expect(find.text(ar.get('faq_privacy_q1')), findsOneWidget);
    expect(find.text(ar.get('faq_privacy_q2')), findsOneWidget);

    // A search for a word only the privacy and deletion answers share keeps
    // the privacy group listed.
    await tester.enterText(find.byType(TextField).first, ar.get('deleted_member'));
    await tester.pumpAndSettle();
    expect(find.text(ar.get('faq_cat_privacy')), findsOneWidget);
    expect(find.text(ar.get('faq_cat_salary')), findsNothing);
  });

  testWidgets('an English search for "delete" finds the deletion question', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(localizedApp(const HelpSupportScreen(), lang: 'en', scaffold: false));
    await tester.pumpAndSettle();
    final en = AppLocalizations(const Locale('en'));

    await tester.enterText(find.byType(TextField).first, 'delete');
    await tester.pumpAndSettle();
    final topic = find.text(en.get('faq_cat_privacy'));
    expect(topic, findsOneWidget);
    await tester.tap(topic);
    await tester.pumpAndSettle();
    expect(find.text(en.get('faq_privacy_q2')), findsOneWidget);
  });

  testWidgets('the household and wife groups list their new questions', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(localizedApp(const HelpSupportScreen(), lang: 'ar', scaffold: false));
    await tester.pumpAndSettle();
    final ar = AppLocalizations(const Locale('ar'));
    for (final (cat, qs) in [
      ('faq_cat_household', ['faq_household_q3', 'faq_household_q4']),
      ('faq_cat_nafaqah', ['faq_nafaqah_q4']),
    ]) {
      final topic = find.text(ar.get(cat));
      await tester.scrollUntilVisible(topic, 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(topic);
      await tester.pumpAndSettle();
      for (final q in qs) {
        expect(find.text(ar.get(q)), findsOneWidget, reason: q);
      }
    }
  });
}
