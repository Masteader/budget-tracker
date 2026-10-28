import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:budget_tracker/providers/theme_provider.dart';
import 'package:budget_tracker/providers/locale_provider.dart';
import 'package:budget_tracker/screens/settings/settings_screen.dart';

void main() {
  testWidgets('SettingsScreen contains HELP & SUPPORT section with Help Center', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider(create: (_) => LocaleProvider()),
        ],
        child: const MaterialApp(
          home: SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Scroll down to HELP & SUPPORT section
    final helpHeaderFinder = find.text('HELP & SUPPORT');
    await tester.scrollUntilVisible(helpHeaderFinder, 300);
    await tester.pumpAndSettle();

    // Verify Help & Support section exists
    expect(helpHeaderFinder, findsOneWidget);
    expect(find.text('App Guide & Tutorial'), findsOneWidget);
    expect(find.text('Help Center & AI Support'), findsOneWidget);
  });

  test('SMS-era settings are gone: no ingestion channel toggles or duplicate policy', () {
    final src = File('lib/screens/settings/settings_screen.dart').readAsStringSync();
    for (final dead in [
      'channel_chat_enabled',
      'channel_scanner_enabled',
      'dedup_policy',
      'expense_ingestion_channels',
      'duplicate_resolution',
      'IncomeSettingsCard',
      'RolloverSettingsCard',
    ]) {
      expect(src, isNot(contains(dead)), reason: dead);
    }
  });
}

