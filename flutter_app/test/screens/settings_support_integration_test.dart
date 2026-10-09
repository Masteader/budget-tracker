import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:budget_tracker/screens/settings/ingestion_settings_screen.dart';

void main() {
  testWidgets('IngestionSettingsScreen contains HELP & SUPPORT section with Help Center', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      const MaterialApp(
        home: IngestionSettingsScreen(),
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
}
