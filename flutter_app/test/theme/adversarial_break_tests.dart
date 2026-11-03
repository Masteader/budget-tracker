import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:budget_tracker/core/widgets/three_d_icon_puck.dart';
import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/models/account.dart';
import 'package:budget_tracker/models/nafaqah.dart';
import 'package:budget_tracker/models/recurring_bill.dart';
import 'package:budget_tracker/providers/account_provider.dart';
import 'package:budget_tracker/providers/budget_provider.dart';
import 'package:budget_tracker/providers/installment_provider.dart';
import 'package:budget_tracker/providers/recurring_bills_provider.dart';
import 'package:budget_tracker/providers/transaction_provider.dart';
import 'package:budget_tracker/screens/accounts/accounts_overview_screen.dart';
import 'package:budget_tracker/theme/app_themes.dart';
import 'package:budget_tracker/widgets/accounts/account_card.dart';
import 'package:budget_tracker/widgets/dashboard/recurring_bills_card.dart';
import 'package:budget_tracker/widgets/nafaqah/wife_allowance_card.dart';
import 'package:budget_tracker/widgets/settings/rollover_settings_card.dart';

double _luminance(Color c) {
  double linearize(double val) {
    return val <= 0.03928
        ? val / 12.92
        : math.pow((val + 0.055) / 1.055, 2.4).toDouble();
  }

  final r = linearize(c.r);
  final g = linearize(c.g);
  final b = linearize(c.b);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

double _contrast(Color fg, Color bg) {
  final l1 = _luminance(fg);
  final l2 = _luminance(bg);
  final lighter = math.max(l1, l2);
  final darker = math.min(l1, l2);
  return (lighter + 0.05) / (darker + 0.05);
}

Widget _wrapTestApp({
  required Widget child,
  ThemeData? theme,
  Locale locale = const Locale('en'),
  TextScaler textScaler = TextScaler.noScaling,
  Size size = const Size(390, 844),
}) {
  return MediaQuery(
    data: MediaQueryData(size: size, textScaler: textScaler),
    child: MaterialApp(
      theme: theme ?? AppThemes.lightTheme,
      locale: locale,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('ar'), Locale('ur')],
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Adversarial Test 1: Dynamic Runtime Theme Toggling', () {
    testWidgets(
        'Switching ThemeMode dynamically updates ThreeDIconPuck without stale colors',
        (tester) async {
      ThemeMode currentMode = ThemeMode.dark;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return MaterialApp(
              theme: AppThemes.lightTheme,
              darkTheme: AppThemes.darkTheme,
              themeMode: currentMode,
              home: Scaffold(
                body: Column(
                  children: [
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          currentMode = currentMode == ThemeMode.dark
                              ? ThemeMode.light
                              : ThemeMode.dark;
                        });
                      },
                      child: const Text('Toggle Theme'),
                    ),
                    const ThreeDIconPuck(
                      icon: Icons.star_rounded,
                      size: 40,
                      isRoseGold: true,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      // In dark mode: isRoseGold icon should be Colors.white
      var icon = tester.widget<Icon>(find.byIcon(Icons.star_rounded));
      expect(icon.color, Colors.white);

      // Toggle to Light mode
      await tester.tap(find.text('Toggle Theme'));
      await tester.pumpAndSettle();

      // In light mode: isRoseGold icon should be 0xFF4A0E1E (dark burgundy)
      icon = tester.widget<Icon>(find.byIcon(Icons.star_rounded));
      expect(icon.color, const Color(0xFF4A0E1E));

      // Toggle back to Dark mode
      await tester.tap(find.text('Toggle Theme'));
      await tester.pumpAndSettle();

      // In dark mode: isRoseGold icon should immediately flip back to Colors.white
      icon = tester.widget<Icon>(find.byIcon(Icons.star_rounded));
      expect(icon.color, Colors.white);
    });

    testWidgets(
        'Dynamic Theme toggle repaints WifeAllowanceCard and RecurringBillsCard without stale tokens',
        (tester) async {
      ThemeMode currentMode = ThemeMode.dark;

      final billsProvider = RecurringBillsProvider();
      const summary = RecurringBillsSummary(
        cycleKey: '2026-11',
        cycleLabel: 'November 2026',
        totalRecurringMonthly: 300.0,
        paidThisCycle: 0.0,
        reservedAmount: 300.0,
        bills: [
          RecurringBillItem(
            merchant: 'STC Telecom',
            normalizedMerchant: 'stc',
            categoryCode: 'OPEX-UTILITIES',
            subCode: 'telecom',
            averageAmount: 300.0,
            expectedDayOfMonth: 20,
            status: 'UPCOMING',
          ),
        ],
      );
      billsProvider.setSummaryForTesting(summary, householdId: 'hh1');

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<RecurringBillsProvider>.value(
                value: billsProvider),
            ChangeNotifierProvider<TransactionProvider>(
                create: (_) => TransactionProvider()),
            ChangeNotifierProvider<BudgetProvider>(
                create: (_) => BudgetProvider()),
          ],
          child: StatefulBuilder(
            builder: (context, setState) {
              return MaterialApp(
                theme: AppThemes.lightTheme,
                darkTheme: AppThemes.darkTheme,
                themeMode: currentMode,
                localizationsDelegates: const [
                  AppLocalizationsDelegate(),
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                supportedLocales: const [Locale('en'), Locale('ar')],
                home: Scaffold(
                  body: SingleChildScrollView(
                    child: Column(
                      children: [
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              currentMode = currentMode == ThemeMode.dark
                                  ? ThemeMode.light
                                  : ThemeMode.dark;
                            });
                          },
                          child: const Text('Toggle Theme'),
                        ),
                        const WifeAllowanceCard(
                          householdId: 'hh1',
                          wife: NafaqahWife(
                            id: 'w1',
                            displayName: 'Fatima',
                            allowance: AllowanceStatus(
                                cycleKey: '2026-11', isSet: false),
                          ),
                          cycleKey: '2026-11',
                          canSet: true,
                        ),
                        const RecurringBillsCard(householdId: 'hh1'),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially Dark Mode: WifeAllowance button text color is roseGoldGlow (0xFFF9D2D9)
      var wifeBtn = tester.widget<OutlinedButton>(
          find.widgetWithText(OutlinedButton, 'Set allowance'));
      var wifeFg = wifeBtn.style?.foregroundColor?.resolve({});
      expect(wifeFg, VelvetBurgundyColors.roseGoldGlow);

      // Toggle to Light Mode
      await tester.tap(find.text('Toggle Theme'));
      await tester.pumpAndSettle();

      // Now Light Mode: WifeAllowance button text color must be primaryLight (0xFF4A0E1E)
      wifeBtn = tester.widget<OutlinedButton>(
          find.widgetWithText(OutlinedButton, 'Set allowance'));
      wifeFg = wifeBtn.style?.foregroundColor?.resolve({});
      expect(wifeFg, VelvetBurgundyColors.primaryLight);

      // Open recurring bill payment dialog in light mode
      await tester.tap(find.text('Pay'));
      await tester.pumpAndSettle();

      final confirmBtn = find.widgetWithText(FilledButton, 'Confirm Paid');
      expect(confirmBtn, findsOneWidget);
      final btnWidget = tester.widget<FilledButton>(confirmBtn);
      // In light mode, primaryButtonFg is Colors.white
      expect(btnWidget.style?.foregroundColor?.resolve({}), Colors.white);

      // Dismiss dialog
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });

  group('Adversarial Test 2: AccountCard ThreeDIconPuck Contrast Defect Analysis', () {
    testWidgets(
        'Inspect ThreeDIconPuck icon color when AccountCard is rendered in Light Mode',
        (tester) async {
      const account = Account(
        id: 'acc-1',
        householdId: 'hh1',
        ownerUserId: 'u1',
        name: 'Checking Account',
        accountType: AccountType.bank,
        balance: 5000.0,
      );

      await tester.pumpWidget(
        _wrapTestApp(
          child: const AccountCard(
            account: account,
            committedBudgets: 5000.0, // exactly 0 margin -> zeroBased
            householdId: 'hh1',
          ),
          theme: AppThemes.lightTheme,
        ),
      );
      await tester.pumpAndSettle();

      // Look at the ThreeDIconPuck inside AccountCard
      final puckFinder = find.byType(ThreeDIconPuck);
      expect(puckFinder, findsOneWidget);

      final puckWidget = tester.widget<ThreeDIconPuck>(puckFinder);
      // In light mode, puck icon is high-contrast Colors.white on dark maroon puck
      expect(puckWidget.iconColor, Colors.white);

      // The icon inside ThreeDIconPuck
      final iconFinder =
          find.descendant(of: puckFinder, matching: find.byType(Icon));
      final iconWidget = tester.widget<Icon>(iconFinder);
      expect(iconWidget.color, Colors.white);

      // On dark maroon puck background (0xFF4A0E1E), Colors.white has contrast > 7.0:1 (WCAG AAA)
      final contrastOnPuck =
          _contrast(iconWidget.color!, const Color(0xFF4A0E1E));
      expect(contrastOnPuck, greaterThan(7.0));

      // Meanwhile, the Status Pill text MUST have high contrast on white card surface:
      final pillTextFinder = find.textContaining('100% Allocated');
      final pillText = tester.widget<Text>(pillTextFinder);
      expect(pillText.style?.color, const Color(0xFF4A0E1E));
      final contrastOnCard = _contrast(pillText.style!.color!, Colors.white);
      expect(contrastOnCard, greaterThan(4.5));
    });
  });

  group('Adversarial Test 3: Extreme Accessibility & Text Scaling (1.5x - 2.0x)', () {
    testWidgets(
        'AccountsOverviewScreen buttons under 1.5x and 2.0x text scaling on compact viewport',
        (tester) async {
      final accountProvider = AccountProvider();
      final txProvider = TransactionProvider();
      final budgetProvider = BudgetProvider();
      final installmentProvider = InstallmentProvider();

      const account = Account(
        id: 'acc-1',
        householdId: 'hh1',
        ownerUserId: 'u1',
        name: 'Al Rajhi Bank',
        accountType: AccountType.bank,
        balance: 12500.0,
      );
      accountProvider.setAccountsForTesting([account]);

      // Stress test with textScaler 2.0 on narrow width (360px)
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AccountProvider>.value(
                value: accountProvider),
            ChangeNotifierProvider<TransactionProvider>.value(
                value: txProvider),
            ChangeNotifierProvider<BudgetProvider>.value(
                value: budgetProvider),
            ChangeNotifierProvider<InstallmentProvider>.value(
                value: installmentProvider),
          ],
          child: _wrapTestApp(
            child: const AccountsOverviewScreen(householdId: 'hh1'),
            textScaler: const TextScaler.linear(2.0),
            size: const Size(360, 800),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify no Flutter exceptions / overflows occurred
      expect(tester.takeException(), isNull);

      // Verify both buttons are present and clickable
      final recordIncomeBtn = find.text('Record Income');
      final transferFundsBtn = find.text('Transfer Funds');
      expect(recordIncomeBtn, findsOneWidget);
      expect(transferFundsBtn, findsOneWidget);

      // Also test with Arabic locale under 1.75x text scaling
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AccountProvider>.value(
                value: accountProvider),
            ChangeNotifierProvider<TransactionProvider>.value(
                value: txProvider),
            ChangeNotifierProvider<BudgetProvider>.value(
                value: budgetProvider),
            ChangeNotifierProvider<InstallmentProvider>.value(
                value: installmentProvider),
          ],
          child: _wrapTestApp(
            child: const AccountsOverviewScreen(householdId: 'hh1'),
            locale: const Locale('ar'),
            textScaler: const TextScaler.linear(1.75),
            size: const Size(360, 800),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('Adversarial Test 4: Trilingual & RTL Context (ar, ur, en)', () {
    testWidgets(
        'Arabic and Urdu RTL layout with swap_horiz and check_circle icons',
        (tester) async {
      for (final locale in [const Locale('ar'), const Locale('ur')]) {
        await tester.pumpWidget(
          _wrapTestApp(
            locale: locale,
            child: RolloverSettingsCard(
              initialRule: 'send_to_savings',
              accumulatedSavings: 1500.0,
              onSaveRule: (_) async => true,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // RolloverSettingsCard save/saved button has check_circle_outline_rounded icon
        final iconFinder =
            find.byIcon(Icons.check_circle_outline_rounded);
        expect(iconFinder, findsOneWidget);

        // Directionality in ar and ur is RTL
        final dir = Directionality.of(tester.element(iconFinder));
        expect(dir, TextDirection.rtl);

        // No rendering exception
        final arEx = tester.takeException();
      if (arEx != null && arEx is FlutterError) {
        // ignore: avoid_print
        print('ARABIC OVERFLOW:');
        for (final d in arEx.diagnostics) {
          // ignore: avoid_print
          print('${d.runtimeType} [${d.name}]: ${d.value}');
        }
      }
      expect(arEx, isNull);
      }
    });
  });

  group('Adversarial Test 5: Edge Cases & Boundary Conditions', () {
    testWidgets(
        'AccountCard boundary conditions: exactly 0.0 vs negative vs surplus balance',
        (tester) async {
      // 1. Exactly 0 margin (zeroBased)
      const accZero = Account(
        id: 'acc-zero',
        householdId: 'hh1',
        ownerUserId: 'u1',
        name: 'Zero Margin Account',
        accountType: AccountType.bank,
        balance: 1000.0,
      );

      await tester.pumpWidget(
        _wrapTestApp(
          child: const AccountCard(
            account: accZero,
            committedBudgets: 1000.0,
            householdId: 'hh1',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('100% Allocated'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline_rounded), findsOneWidget);

      // 2. Negative margin (deficit)
      const accDeficit = Account(
        id: 'acc-def',
        householdId: 'hh1',
        ownerUserId: 'u1',
        name: 'Shortfall Account',
        accountType: AccountType.bank,
        balance: 500.0,
      );

      await tester.pumpWidget(
        _wrapTestApp(
          child: const AccountCard(
            account: accDeficit,
            committedBudgets: 1000.0,
            householdId: 'hh1',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Deficit:'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      // Deficit action button should be rendered
      expect(find.byKey(const Key('account_cover_deficit')), findsOneWidget);

      // 3. Positive margin (surplus)
      const accSurplus = Account(
        id: 'acc-surplus',
        householdId: 'hh1',
        ownerUserId: 'u1',
        name: 'Surplus Account',
        accountType: AccountType.bank,
        balance: 2500.0,
      );

      await tester.pumpWidget(
        _wrapTestApp(
          child: const AccountCard(
            account: accSurplus,
            committedBudgets: 1000.0,
            householdId: 'hh1',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Surplus Buffer'), findsOneWidget);
      expect(find.byIcon(Icons.savings_outlined), findsOneWidget);
    });

    testWidgets(
        'Rapid consecutive taps on RecurringBill Pay button does not double-trigger',
        (tester) async {
      final billsProvider = RecurringBillsProvider();
      billsProvider.setSummaryForTesting(
        const RecurringBillsSummary(
          cycleKey: '2026-11',
          cycleLabel: 'November 2026',
          totalRecurringMonthly: 200.0,
          paidThisCycle: 0.0,
          reservedAmount: 200.0,
          bills: [
            RecurringBillItem(
              merchant: 'National Water',
              normalizedMerchant: 'water',
              categoryCode: 'OPEX-UTILITIES',
              subCode: 'water',
              averageAmount: 200.0,
              expectedDayOfMonth: 10,
              status: 'UPCOMING',
            ),
          ],
        ),
        householdId: 'hh_test',
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<RecurringBillsProvider>.value(
                value: billsProvider),
            ChangeNotifierProvider<TransactionProvider>(
                create: (_) => TransactionProvider()),
            ChangeNotifierProvider<BudgetProvider>(
                create: (_) => BudgetProvider()),
          ],
          child: _wrapTestApp(
            child: const RecurringBillsCard(householdId: 'hh_test'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final payFinder = find.text('Pay');
      expect(payFinder, findsOneWidget);

      // Simulate rapid double-tap
      await tester.tap(payFinder, warnIfMissed: false);
      await tester.tap(payFinder, warnIfMissed: false);
      await tester.pumpAndSettle();

      // Only a single Confirm Paid dialog should be open
      expect(find.text('Confirm Paid'), findsOneWidget);

      // Tap Confirm Paid
      await tester.tap(find.text('Confirm Paid'), warnIfMissed: false);
      await tester.pumpAndSettle();

      // Dialog is dismissed
      expect(find.text('Confirm Paid'), findsNothing);
      final arEx = tester.takeException();
      if (arEx != null && arEx is FlutterError) {
        // ignore: avoid_print
        print('ARABIC OVERFLOW:');
        for (final d in arEx.diagnostics) {
          // ignore: avoid_print
          print('${d.runtimeType} [${d.name}]: ${d.value}');
        }
      }
      expect(arEx, isNull);
    });
  });
}
