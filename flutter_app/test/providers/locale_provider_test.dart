import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:budget_tracker/providers/locale_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocaleProvider', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('defaults to English or system supported locale', () {
      final provider = LocaleProvider();
      expect(provider.currentLocale.languageCode, isIn(['en', 'ar', 'ur']));
    });

    test('updates and persists new locale (Arabic)', () async {
      final provider = LocaleProvider();
      await provider.setLocale(const Locale('ar'));

      expect(provider.currentLocale.languageCode, equals('ar'));
      expect(provider.isRtl, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_language_code'), equals('ar'));
    });

    test('updates and persists Urdu locale', () async {
      final provider = LocaleProvider();
      await provider.setLanguageCode('ur');

      expect(provider.currentLocale.languageCode, equals('ur'));
      expect(provider.isRtl, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_language_code'), equals('ur'));
    });

    test('loads saved locale from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({'app_language_code': 'ur'});
      final provider = LocaleProvider();
      await provider.init();

      expect(provider.currentLocale.languageCode, equals('ur'));
    });
  });
}
