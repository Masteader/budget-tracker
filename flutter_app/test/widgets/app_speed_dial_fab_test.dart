import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/widgets/dashboard/app_speed_dial_fab.dart';

void main() {
  group('AppSpeedDialFab Widget Tests', () {
    testWidgets('Toggles Speed Dial FAB open and renders 4 distinct non-duplicate options', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: [AppLocalizationsDelegate()],
          supportedLocales: [Locale('en'), Locale('ar'), Locale('ur')],
          locale: Locale('en'),
          home: Scaffold(
            floatingActionButton: AppSpeedDialFab(householdId: 'hh_test_123'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Initially closed
      expect(find.byType(FloatingActionButton), findsWidgets);

      // Tap main FAB to expand speed dial
      await tester.tap(find.text('Add Expense'));
      await tester.pumpAndSettle();

      // Main FAB toggled to Close
      expect(find.text('Close'), findsOneWidget);

      // Verify all 4 distinct, non-duplicate feature options are visible:
      // 1. Scan Receipt
      expect(find.text('Scan Receipt'), findsOneWidget);
      expect(find.byIcon(Icons.camera_alt_rounded), findsOneWidget);

      // 2. Voice & AI Assistant
      expect(find.text('Voice & AI Assistant'), findsOneWidget);
      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);

      // 3. Can I Afford This? (Simulator)
      expect(find.text('Can I Afford This?'), findsOneWidget);
      expect(find.byIcon(Icons.calculate_outlined), findsOneWidget);

      // 4. Manual Log
      expect(find.text('Manual Log'), findsOneWidget);
      expect(find.byIcon(Icons.edit_note_rounded), findsOneWidget);

      // Tap close
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(find.text('Add Expense'), findsOneWidget);
    });
  });
}
