import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:budget_tracker/screens/onboarding/household_screen.dart';
import 'package:budget_tracker/providers/budget_provider.dart';
import 'package:budget_tracker/providers/transaction_provider.dart';
import 'package:budget_tracker/providers/household_role_provider.dart';
import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

void main() {
  Widget buildTestableScreen({required Widget home}) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => BudgetProvider()),
        ChangeNotifierProvider(create: (_) => TransactionProvider()),
        ChangeNotifierProvider(create: (_) => HouseholdRoleProvider()),
      ],
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('ar'), Locale('ur')],
        locale: const Locale('en'),
        home: home,
      ),
    );
  }

  group('HouseholdScreen Back Button Tests', () {
    testWidgets('hides back button when HouseholdScreen is the root screen (cannot pop)', (tester) async {
      await tester.pumpWidget(
        buildTestableScreen(
          home: const HouseholdScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('household_back_button')), findsNothing);
    });

    testWidgets('shows back button when HouseholdScreen can pop, and tapping pops screen', (tester) async {
      await tester.pumpWidget(
        buildTestableScreen(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  key: const Key('open_household_screen_button'),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const HouseholdScreen()),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap to push HouseholdScreen onto navigation stack
      await tester.tap(find.byKey(const Key('open_household_screen_button')));
      await tester.pumpAndSettle();

      // Back button should now be present
      final backButton = find.byKey(const Key('household_back_button'));
      expect(backButton, findsOneWidget);

      // Tap back button
      await tester.tap(backButton);
      await tester.pumpAndSettle();

      // Should have returned to initial screen
      expect(find.byKey(const Key('open_household_screen_button')), findsOneWidget);
      expect(find.byKey(const Key('household_back_button')), findsNothing);
    });
  });
}
