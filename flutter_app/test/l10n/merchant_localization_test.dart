import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/l10n/app_localizations.dart';

void main() {
  group('Merchant Name Localization & Normalization', () {
    test('Translates standard merchants correctly in Arabic', () {
      final l10n = AppLocalizations(const Locale('ar'));

      expect(l10n.merchant('Panda'), equals('أسواق بندة'));
      expect(l10n.merchant('Hyper Panda'), equals('أسواق بندة'));
      expect(l10n.merchant('Al Othaim'), equals('أسواق العثيم'));
      expect(l10n.merchant('STC'), equals('شركة الاتصالات السعودية (stc)'));
      expect(l10n.merchant('STC-Pay'), equals('شركة الاتصالات السعودية (stc)'));
      expect(l10n.merchant('AlBaik'), equals('البيك'));
      expect(l10n.merchant('Jarir Bookstore'), equals('مكتبة جرير'));
      expect(l10n.merchant('eXtra'), equals('معارض إكسترا'));
    });

    test('Translates standard merchants correctly in Urdu', () {
      final l10n = AppLocalizations(const Locale('ur'));

      expect(l10n.merchant('Panda'), equals('پانڈا سپر مارکیٹ'));
      expect(l10n.merchant('Al Othaim'), equals('العثیم مارکیٹس'));
      expect(l10n.merchant('STC'), equals('ایس ٹی سی ٹیلی کام'));
    });

    test('Translates standard merchants correctly in English', () {
      final l10n = AppLocalizations(const Locale('en'));

      expect(l10n.merchant('panda'), equals('Panda Supermarket'));
      expect(l10n.merchant('othaim'), equals('Al Othaim Markets'));
      expect(l10n.merchant('stc'), equals('stc Telecom'));
    });

    test('Prevents greedy substring false positives on unrelated words', () {
      final l10nAr = AppLocalizations(const Locale('ar'));
      final l10nEn = AppLocalizations(const Locale('en'));

      // "Fastcare Pharmacy" contains 'stc' but should NOT match stc Telecom
      expect(l10nAr.merchant('Fastcare Pharmacy'), equals('Fastcare Pharmacy'));
      expect(l10nEn.merchant('Fastcare Pharmacy'), equals('Fastcare Pharmacy'));

      // "Postcard Shop" contains 'stc' but should NOT match stc Telecom
      expect(l10nAr.merchant('Postcard Shop'), equals('Postcard Shop'));
      expect(l10nEn.merchant('Postcard Shop'), equals('Postcard Shop'));

      // "Extraordinary Cafe" contains 'extra' but should NOT match eXtra Stores
      expect(l10nAr.merchant('Extraordinary Cafe'), equals('Extraordinary Cafe'));
      expect(l10nEn.merchant('Extraordinary Cafe'), equals('Extraordinary Cafe'));

      // "Panda Express" is a restaurant chain and should NOT match Panda Supermarket
      expect(l10nAr.merchant('Panda Express'), equals('Panda Express'));
      expect(l10nEn.merchant('Panda Express'), equals('Panda Express'));
    });

    test('Handles generic entries, null, and empty merchant names', () {
      final l10n = AppLocalizations(const Locale('ar'));

      expect(l10n.merchant(null), equals('تاجر غير محدد'));
      expect(l10n.merchant(''), equals('تاجر غير محدد'));
      expect(l10n.merchant('   '), equals('تاجر غير محدد'));
      expect(l10n.merchant('direct'), equals('إدخال مباشر'));
      expect(l10n.merchant('Direct Entry'), equals('إدخال مباشر'));
      expect(l10n.merchant('manual'), equals('مصروف يدوي'));
      expect(l10n.merchant('Manual Expense'), equals('مصروف يدوي'));
    });

    test('Verifies copy, sync count, and note keys across all three languages', () {
      final en = AppLocalizations(const Locale('en'));
      final ar = AppLocalizations(const Locale('ar'));
      final ur = AppLocalizations(const Locale('ur'));

      // copy_btn
      expect(en.get('copy_btn'), equals('Copy'));
      expect(ar.get('copy_btn'), equals('نسخ'));
      expect(ur.get('copy_btn'), equals('کاپی'));

      // pending_sync_count
      expect(en.get('pending_sync_count'), contains('{count}'));
      expect(ar.get('pending_sync_count'), contains('{count}'));
      expect(ur.get('pending_sync_count'), contains('{count}'));

      // developer_email_copied
      expect(en.get('developer_email_copied'), contains('{email}'));
      expect(ar.get('developer_email_copied'), contains('{email}'));
      expect(ur.get('developer_email_copied'), contains('{email}'));

      // household_id_copied
      expect(en.get('household_id_copied'), equals('Household ID copied to clipboard'));
      expect(ar.get('household_id_copied'), equals('تم نسخ معرف المنزل إلى الحافظة'));
      expect(ur.get('household_id_copied'), equals('گھرانے کا شناختی کوڈ کلپ بورڈ پر کاپی ہو گیا'));

      // nafaqah & roommate settlement note templates
      expect(en.get('nafaqah_reimbursement_note'), contains('{amount}'));
      expect(ar.get('nafaqah_reimbursement_note'), contains('{amount}'));
      expect(ur.get('nafaqah_reimbursement_note'), contains('{amount}'));

      expect(en.get('roommate_settlement_note'), contains('{amount}'));
      expect(en.get('roommate_settlement_note'), contains('{name}'));
      expect(ar.get('roommate_settlement_note'), contains('{amount}'));
      expect(ar.get('roommate_settlement_note'), contains('{name}'));
      expect(ur.get('roommate_settlement_note'), contains('{amount}'));
      expect(ur.get('roommate_settlement_note'), contains('{name}'));
    });
  });
}
