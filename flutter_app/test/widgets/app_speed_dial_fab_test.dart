import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/widgets/dashboard/app_speed_dial_fab.dart';

void main() {
  group('AppSpeedDialFab Widget Tests', () {
    testWidgets('opens with exactly 3 actions: manual expense, chat, scan receipt (R3)', (tester) async {
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
      expect(find.byType(FloatingActionButton), findsWidgets);

      await tester.tap(find.text('Add Expense'));
      await tester.pumpAndSettle();
      expect(find.text('Close'), findsOneWidget);

      expect(find.text('Manual Log'), findsOneWidget);
      expect(find.byIcon(Icons.edit_note_rounded), findsOneWidget);
      expect(find.text('Voice & AI Assistant'), findsOneWidget);
      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
      expect(find.text('Scan Receipt'), findsOneWidget);
      expect(find.byIcon(Icons.camera_alt_rounded), findsOneWidget);
      // One small FAB per action plus the main one.
      expect(find.byType(FloatingActionButton), findsNWidgets(4));

      // Moved to the Tools screen.
      expect(find.text('Can I Afford This?'), findsNothing);
      expect(find.text('Batch Scan Receipts'), findsNothing);
      expect(find.text('Record Income'), findsNothing);
      expect(find.text('Transfer Funds'), findsNothing);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Add Expense'), findsOneWidget);
    });
  });
}
