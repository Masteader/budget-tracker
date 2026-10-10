import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleProvider extends ChangeNotifier {
  static const String _prefKey = 'app_language_code';

  Locale _currentLocale = const Locale('en');

  Locale get currentLocale => _currentLocale;

  String get languageCode => _currentLocale.languageCode;

  bool get isRtl => languageCode == 'ar' || languageCode == 'ur';

  static const List<Locale> supportedLocales = [
    Locale('en'),
    Locale('ar'),
    Locale('ur'),
  ];

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString(_prefKey);
      if (code != null && (code == 'ar' || code == 'ur' || code == 'en')) {
        _currentLocale = Locale(code);
      } else {
        // Fallback or system check
        final systemCode = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
        if (systemCode == 'ar' || systemCode == 'ur') {
          _currentLocale = Locale(systemCode);
        } else {
          _currentLocale = const Locale('en');
        }
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> setLocale(Locale locale) async {
    if (_currentLocale.languageCode == locale.languageCode) return;
    _currentLocale = locale;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, locale.languageCode);
    } catch (_) {}
  }

  Future<void> setLanguageCode(String code) async {
    final clean = code.split('_').first.toLowerCase();
    if (clean == 'ar' || clean == 'ur' || clean == 'en') {
      await setLocale(Locale(clean));
    }
  }
}
