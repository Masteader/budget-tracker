import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/l10n/app_localizations.dart';

void main() {
  group('AppLocalizations Tests', () {
    test('English translations return valid text', () {
      final loc = AppLocalizations(const Locale('en'));
      expect(loc.get('app_title'), 'Budget Tracker');
      expect(loc.get('nav_dashboard'), 'Dashboard');
      expect(loc.get('recurring_bills'), 'Recurring Bills & Reserves');
      expect(loc.get('installments_bnpl'), 'Installments & BNPL');
      expect(loc.get('settings_and_permissions'), 'Settings & Permissions');
      expect(loc.get('paid_for_whom'), 'Paid for Whom (Children & Dependents)');
    });

    test('Arabic translations return correct Arabic text and RTL readiness', () {
      final loc = AppLocalizations(const Locale('ar'));
      expect(loc.get('app_title'), 'ميزانية الأسرة');
      expect(loc.get('nav_dashboard'), 'لوحة التحكم');
      expect(loc.get('recurring_bills'), 'الفواتير الدورية والاحتياطيات');
      expect(loc.get('installments_bnpl'), 'الأقساط والشراء الآجل');
      expect(loc.get('settings_and_permissions'), 'الإعدادات والصلاحيات');
      expect(loc.get('paid_for_whom'), 'الدفع لمن (الأبناء والمعالين)');
    });

    test('Urdu translations return correct Urdu text', () {
      final loc = AppLocalizations(const Locale('ur'));
      expect(loc.get('app_title'), 'بجٹ ٹریکر');
      expect(loc.get('nav_dashboard'), 'ڈیش بورڈ');
      expect(loc.get('recurring_bills'), 'ماہانہ بلز اور ریزرو');
      expect(loc.get('installments_bnpl'), 'اقساط اور بی این پی ایل');
      expect(loc.get('settings_and_permissions'), 'ترتیبات اور اجازتیں');
      expect(loc.get('paid_for_whom'), 'کس کے لیے ادا کیا (بچے اور زیر کفالت)');
    });

    test('Fallback returns key or English if key not translated', () {
      final loc = AppLocalizations(const Locale('ar'));
      expect(loc.get('non_existent_key'), 'non_existent_key');
    });

    test('AppLocalizationsDelegate supports en, ar, ur', () {
      const delegate = AppLocalizationsDelegate();
      expect(delegate.isSupported(const Locale('en')), isTrue);
      expect(delegate.isSupported(const Locale('ar')), isTrue);
      expect(delegate.isSupported(const Locale('ur')), isTrue);
      expect(delegate.isSupported(const Locale('fr')), isFalse);
    });
  });
}
