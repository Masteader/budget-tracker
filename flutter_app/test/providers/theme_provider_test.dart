import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:budget_tracker/providers/theme_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ThemeProvider', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('defaults to ThemeMode.system', () {
      final provider = ThemeProvider();
      expect(provider.themeMode, equals(ThemeMode.system));
      expect(provider.themeModeName, equals('system'));
    });

    test('sets and persists light theme mode', () async {
      final provider = ThemeProvider();
      await provider.setThemeMode(ThemeMode.light);

      expect(provider.themeMode, equals(ThemeMode.light));
      expect(provider.themeModeName, equals('light'));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_theme_mode'), equals('light'));
    });

    test('loads saved dark theme mode from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({'app_theme_mode': 'dark'});
      final provider = ThemeProvider();
      await provider.init();

      expect(provider.themeMode, equals(ThemeMode.dark));
      expect(provider.themeModeName, equals('dark'));
    });
  });
}
