import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/l10n/app_localizations.dart';

void main() {
  group('AppLocalizations Tests', () {
    test('English translations return valid text', () {
      final loc = AppLocalizations(const Locale('en'));
      expect(loc.get('app_title'), 'Qawam Money قوام المال');
      expect(loc.get('app_title_short'), 'Qawam Money');
      expect(loc.get('nav_dashboard'), 'Dashboard');
      expect(loc.get('recurring_bills'), 'Recurring Bills & Reserves');
      expect(loc.get('installments_bnpl'), 'Installments & BNPL');
      expect(loc.get('settings_and_permissions'), 'Settings & Permissions');
      expect(loc.get('paid_for_whom'), 'Paid for Whom (Children & Dependents)');
    });

    test('Arabic translations return correct Arabic text and RTL readiness', () {
      final loc = AppLocalizations(const Locale('ar'));
      expect(loc.get('app_title'), 'قوام المال Qawam Money');
      expect(loc.get('app_title_short'), 'قوام المال');
      expect(loc.get('nav_dashboard'), 'الرئيسية');
      expect(loc.get('recurring_bills'), 'الفواتير والاحتياطيات');
      expect(loc.get('installments_bnpl'), 'الأقساط والشراء الآجل');
      expect(loc.get('settings_and_permissions'), 'الإعدادات والصلاحيات');
      expect(loc.get('paid_for_whom'), 'الدفع لمن (الأبناء والمعالين)');
    });

    test('Urdu translations return correct Urdu text', () {
      final loc = AppLocalizations(const Locale('ur'));
      expect(loc.get('app_title'), 'Qawam Money');
      expect(loc.get('app_title_short'), 'Qawam Money');
      expect(loc.get('nav_dashboard'), 'ڈیش بورڈ');
      expect(loc.get('recurring_bills'), 'باقاعدہ بلز اور ریزرو');
      expect(loc.get('installments_bnpl'), 'اقساط اور بی این پی ایل');
      expect(loc.get('settings_and_permissions'), 'ترتیبات اور اجازتیں');
      expect(loc.get('paid_for_whom'), 'کس کے لیے ادا کیا (بچے اور زیر کفالت)');
    });

    test('Fallback returns key or English if key not translated', () {
      final loc = AppLocalizations(const Locale('ar'));
      expect(loc.get('non_existent_key'), 'non_existent_key');
    });

    test('app_title_badge and dial_days_short exist in all three locales (Item 9)', () {
      for (final lang in ['en', 'ar', 'ur']) {
        final loc = AppLocalizations(Locale(lang));
        expect(loc.get('app_title_badge'), isNot(equals('app_title_badge')));
        expect(loc.get('dial_days_short'), isNot(equals('dial_days_short')));
      }
    });

    test('insufficient_funds_title and insufficient_funds_msg exist in all three locales (Item 6)', () {
      for (final lang in ['en', 'ar', 'ur']) {
        final loc = AppLocalizations(Locale(lang));
        expect(loc.get('insufficient_funds_title'), isNot(equals('insufficient_funds_title')));
        expect(loc.get('insufficient_funds_msg'), isNot(equals('insufficient_funds_msg')));
      }
    });

    test('budget management and prior spend keys exist in all three locales (Item 9 & 10)', () {
      const keys = [
        'prior_spend_spouse_blocked',
        'bm_spent_vs_cash',
        'account_capacity_deficit',
        'bm_toggle_failed',
        'bm_prior_spend_failed',
        'bm_deactivate_title',
        'item_generic',
      ];
      for (final lang in ['en', 'ar', 'ur']) {
        final loc = AppLocalizations(Locale(lang));
        for (final key in keys) {
          expect(loc.get(key), isNot(equals(key)), reason: 'Missing translation for $key in $lang');
        }
      }
    });

    test('prior_spend_spouse_blocked has updated natural copy in en/ar/ur', () {
      expect(
        AppLocalizations(const Locale('en')).get('prior_spend_spouse_blocked'),
        'Prior spending cannot be logged from a spouse account.',
      );
      expect(
        AppLocalizations(const Locale('ar')).get('prior_spend_spouse_blocked'),
        'لا يمكن تسجيل المصاريف السابقة من حساب الزوجة.',
      );
      expect(
        AppLocalizations(const Locale('ur')).get('prior_spend_spouse_blocked'),
        'شریکِ حیات کے اکاؤنٹ سے سابقہ اخراجات درج نہیں کیے جا سکتے۔',
      );
    });

    test('AppLocalizationsDelegate supports en, ar, ur', () {
      const delegate = AppLocalizationsDelegate();
      expect(delegate.isSupported(const Locale('en')), isTrue);
      expect(delegate.isSupported(const Locale('ar')), isTrue);
      expect(delegate.isSupported(const Locale('ur')), isTrue);
      expect(delegate.isSupported(const Locale('fr')), isFalse);
    });

    test('Arabic translations contain neither نفقة شرعية nor Compliance Engine', () {
      final arMap = AppLocalizations.localizedMap('ar');
      expect(arMap.isNotEmpty, isTrue);
      for (final entry in arMap.entries) {
        expect(
          entry.value.contains('نفقة شرعية'),
          isFalse,
          reason: 'Key ${entry.key} contains prohibited phrase "نفقة شرعية"',
        );
        expect(
          entry.value.contains('Compliance Engine'),
          isFalse,
          reason: 'Key ${entry.key} contains prohibited phrase "Compliance Engine"',
        );
      }
    });

    test('The three scan nafaqah badge keys contain no نفقة or Nafaqah in any locale', () {
      const badgeKeys = [
        'scan_nafaqah_husband_badge',
        'scan_nafaqah_wife_personal_badge',
        'scan_nafaqah_wife_reimbursable_badge',
      ];

      for (final lang in ['en', 'ar', 'ur']) {
        final loc = AppLocalizations(Locale(lang));
        for (final key in badgeKeys) {
          final text = loc.get(key);
          expect(
            text.contains('نفقة') || text.toLowerCase().contains('nafaqah'),
            isFalse,
            reason: 'Locale $lang key $key contains نفقة/Nafaqah: "$text"',
          );
        }
      }
    });

    test('void_income keys exist in all three locales and format properly', () {
      const keys = [
        'void_income_title',
        'void_income_confirmation',
        'void_income_action',
        'income_voided_success',
        'void_income_error',
      ];

      for (final lang in ['en', 'ar', 'ur']) {
        final loc = AppLocalizations(Locale(lang));
        for (final key in keys) {
          final val = loc.get(key);
          expect(val, isNot(equals(key)), reason: 'Key $key missing in $lang');
          expect(val.isNotEmpty, isTrue, reason: 'Key $key empty in $lang');
        }

        final formatted = loc.format('void_income_confirmation', {
          'title': 'Salary Nov',
          'amount': '500.00 SAR',
          'account': 'Al Rajhi',
        });
        expect(formatted.contains('Salary Nov'), isTrue);
        expect(formatted.contains('500.00 SAR'), isTrue);
        expect(formatted.contains('Al Rajhi'), isTrue);
      }
    });
  });
}
