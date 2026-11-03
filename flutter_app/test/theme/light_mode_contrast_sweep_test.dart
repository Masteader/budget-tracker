import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/models/account.dart';
import 'package:budget_tracker/models/nafaqah.dart';
import 'package:budget_tracker/models/recurring_bill.dart';
import 'package:budget_tracker/providers/budget_provider.dart';
import 'package:budget_tracker/providers/locale_provider.dart';
import 'package:budget_tracker/providers/recurring_bills_provider.dart';
import 'package:budget_tracker/providers/theme_provider.dart';
import 'package:budget_tracker/providers/transaction_provider.dart';
import 'package:budget_tracker/screens/settings/settings_screen.dart';
import 'package:budget_tracker/theme/app_themes.dart';
import 'package:budget_tracker/widgets/accounts/account_card.dart';
import 'package:budget_tracker/widgets/dashboard/recurring_bills_card.dart';
import 'package:budget_tracker/widgets/nafaqah/wife_allowance_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

Widget _wrapLight(Widget child) => MaterialApp(
      theme: AppThemes.lightTheme,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('ar'), Locale('ur')],
      locale: const Locale('en'),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  group('Light Mode Contrast Sweep Tests', () {
    testWidgets(
        'AccountCard surplus status uses context.successText (#065F46) with > 4.5:1 contrast',
        (tester) async {
      const account = Account(
        id: 'acc-1',
        householdId: 'hh1',
        ownerUserId: 'u1',
        name: 'Salary Account',
        accountType: AccountType.bank,
        balance: 10000.0,
      );

      await tester.pumpWidget(
        _wrapLight(
          const AccountCard(
            account: account,
            committedBudgets: 6000.0,
            householdId: 'hh1',
          ),
        ),
      );
      await tester.pumpAndSettle();

      final surplusFinder = find.textContaining('Surplus Buffer');
      expect(surplusFinder, findsOneWidget);

      final text = tester.widget<Text>(surplusFinder);
      expect(text.style?.color, const Color(0xFF065F46));
      expect(text.style?.color, isNot(AppThemes.iceCyan));

      // Assert high contrast on white card surface
      final ratio = _contrast(text.style!.color!, Colors.white);
      expect(ratio, greaterThan(4.5));
    });

    testWidgets(
        'AccountCard zero-based status uses context.electricTeal (#4A0E1E) with > 4.5:1 contrast',
        (tester) async {
      const account = Account(
        id: 'acc-2',
        householdId: 'hh1',
        ownerUserId: 'u1',
        name: 'Balanced Account',
        accountType: AccountType.bank,
        balance: 8000.0,
      );

      await tester.pumpWidget(
        _wrapLight(
          const AccountCard(
            account: account,
            committedBudgets: 8000.0,
            householdId: 'hh1',
          ),
        ),
      );
      await tester.pumpAndSettle();

      final zeroBasedFinder = find.textContaining('100% Allocated');
      expect(zeroBasedFinder, findsOneWidget);

      final text = tester.widget<Text>(zeroBasedFinder);
      expect(text.style?.color, const Color(0xFF4A0E1E));
      expect(text.style?.color, isNot(AppThemes.electricTeal));

      // Assert high contrast on white card surface
      final ratio = _contrast(text.style!.color!, Colors.white);
      expect(ratio, greaterThan(4.5));
    });

    testWidgets(
        'WifeAllowanceCard button uses context.accentText in light mode',
        (tester) async {
      await tester.pumpWidget(
        _wrapLight(
          const WifeAllowanceCard(
            householdId: 'hh1',
            wife: NafaqahWife(
              id: 'w1',
              displayName: 'Sara',
              allowance: AllowanceStatus(cycleKey: '2026-11', isSet: false),
            ),
            cycleKey: '2026-11',
            canSet: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final buttonFinder = find.widgetWithText(OutlinedButton, 'Set allowance');
      expect(buttonFinder, findsOneWidget);

      final button = tester.widget<OutlinedButton>(buttonFinder);
      final fgColor = button.style?.foregroundColor?.resolve({});
      expect(fgColor, const Color(0xFF4A0E1E));
      expect(fgColor, isNot(AppThemes.iceCyan));
    });

    testWidgets(
        'RecurringBillsCard Confirm Paid dialog does not have black text',
        (tester) async {
      final billsProvider = RecurringBillsProvider();
      final txProvider = TransactionProvider();
      final budgetProvider = BudgetProvider();

      const summary = RecurringBillsSummary(
        cycleKey: '2026-11',
        cycleLabel: 'November 2026',
        totalRecurringMonthly: 500.0,
        paidThisCycle: 0.0,
        reservedAmount: 500.0,
        bills: [
          RecurringBillItem(
            merchant: 'Electricity',
            normalizedMerchant: 'electricity',
            categoryCode: 'OPEX-UTILITIES',
            subCode: 'electricity',
            averageAmount: 500.0,
            expectedDayOfMonth: 15,
            status: 'UPCOMING',
          ),
        ],
      );
      billsProvider.setSummaryForTesting(summary, householdId: 'hh_test');

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<RecurringBillsProvider>.value(
                value: billsProvider),
            ChangeNotifierProvider<TransactionProvider>.value(
                value: txProvider),
            ChangeNotifierProvider<BudgetProvider>.value(value: budgetProvider),
          ],
          child: _wrapLight(const RecurringBillsCard(householdId: 'hh_test')),
        ),
      );
      await tester.pumpAndSettle();

      // Tap 'Pay'
      final payFinder = find.text('Pay');
      expect(payFinder, findsOneWidget);
      await tester.tap(payFinder);
      await tester.pumpAndSettle();

      // Verify dialog is shown
      final confirmBtn = find.widgetWithText(FilledButton, 'Confirm Paid');
      expect(confirmBtn, findsOneWidget);

      final btnWidget = tester.widget<FilledButton>(confirmBtn);
      final fg = btnWidget.style?.foregroundColor?.resolve({});
      // In light mode, primaryButtonFg is Colors.white
      expect(fg, Colors.white);

      final text = tester.widget<Text>(find.text('Confirm Paid'));
      expect(text.style?.color, isNot(Colors.black));
    });

    testWidgets(
        'SettingsScreen language switcher selected option has white text in light mode',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => ThemeProvider()),
            ChangeNotifierProvider(create: (_) => LocaleProvider()),
          ],
          child: MaterialApp(
            theme: AppThemes.lightTheme,
            localizationsDelegates: const [
              AppLocalizationsDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('en'), Locale('ar'), Locale('ur')],
            locale: const Locale('en'),
            home: const SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // English is the default selected language
      final enFinder = find.text('🇺🇸 English');
      expect(enFinder, findsOneWidget);
      final enText = tester.widget<Text>(enFinder);
      expect(enText.style?.color, Colors.white);

      // Tap Arabic option
      final arFinder = find.text('🇸🇦 العربية');
      expect(arFinder, findsOneWidget);
      await tester.tap(arFinder);
      await tester.pumpAndSettle();

      final arText = tester.widget<Text>(find.text('🇸🇦 العربية'));
      expect(arText.style?.color, Colors.white);
    });
  });
}
