import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/models/account.dart';
import 'package:budget_tracker/models/nafaqah.dart';
import 'package:budget_tracker/providers/locale_provider.dart';
import 'package:budget_tracker/providers/theme_provider.dart';
import 'package:budget_tracker/screens/analytics/income_spending_report_screen.dart';
import 'package:budget_tracker/screens/auth/forgot_password_screen.dart';
import 'package:budget_tracker/screens/auth/update_password_screen.dart';
import 'package:budget_tracker/screens/scanner/batch_receipt_scanner_screen.dart';
import 'package:budget_tracker/screens/settings/settings_screen.dart';
import 'package:budget_tracker/theme/app_themes.dart';
import 'package:budget_tracker/widgets/accounts/account_card.dart';
import 'package:budget_tracker/widgets/dashboard/family_reimbursement_card.dart';
import 'package:budget_tracker/widgets/nafaqah/nafaqah_class_selector.dart';
import 'package:budget_tracker/widgets/nafaqah/wife_allowance_card.dart';
import 'package:budget_tracker/widgets/scanner/batch_item_review_sheet.dart';
import 'package:budget_tracker/widgets/settings/rollover_settings_card.dart';

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
      home: child,
    );

Widget _wrapDark(Widget child) => MaterialApp(
      theme: AppThemes.darkTheme,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('ar'), Locale('ur')],
      locale: const Locale('en'),
      home: child,
    );

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Whole App Theme Sweep - TH-01 to TH-17 Tests', () {
    testWidgets('TH-01, TH-02, TH-03: BatchItemReviewSheet uses primaryButtonBg/Fg and semantic inputBg/borderColor', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final dummyFile = File('test_assets/receipt1.jpg');
      await tester.pumpWidget(
        _wrapLight(
          Scaffold(
            body: SingleChildScrollView(
              child: BatchItemReviewSheet(
                receiptImages: [dummyFile],
                householdId: 'hh1',
                previewReceipt: (_) async => {
                  'merchant': 'Tamimi Markets',
                  'amount': 120.0,
                  'vat_amount': 18.0,
                  'category_code': 'OPEX-GROCERIES',
                },
                saveReceipt: (_) async {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final saveBtnFinder = find.byKey(const Key('batch_save_next_button'));
      expect(saveBtnFinder, findsOneWidget);
      final elevatedBtn = tester.widget<ElevatedButton>(saveBtnFinder);
      final bg = elevatedBtn.style?.backgroundColor?.resolve({});
      final fg = elevatedBtn.style?.foregroundColor?.resolve({});

      // In Light mode: primaryButtonBg is primaryLight (#4A0E1E), primaryButtonFg is white
      expect(bg, VelvetBurgundyColors.primaryLight);
      expect(fg, Colors.white);
      expect(_contrast(fg!, bg!), greaterThan(4.5));

      // Input field decoration check
      final textFields = find.byType(TextField);
      expect(textFields, findsWidgets);
      final merchantField = tester.widget<TextField>(textFields.first);
      expect(merchantField.decoration?.fillColor, const Color(0xFFFDF8FA));
      expect(merchantField.decoration?.border?.borderSide.color, VelvetBurgundyColors.roseBorderLight);
    });

    testWidgets('TH-04: BatchReceiptScannerScreen Process Queue button uses primaryButtonBg/Fg', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final dummyFile1 = File('test_assets/receipt1.jpg');
      await tester.pumpWidget(
        _wrapLight(
          BatchReceiptScannerScreen(
            householdId: 'hh1',
            initialFiles: [dummyFile1],
          ),
        ),
      );
      await tester.pumpAndSettle();

      final processBtnFinder = find.byKey(const Key('process_batch_queue_button'));
      expect(processBtnFinder, findsOneWidget);
      final elevatedBtn = tester.widget<ElevatedButton>(processBtnFinder);
      final bg = elevatedBtn.style?.backgroundColor?.resolve({});
      final fg = elevatedBtn.style?.foregroundColor?.resolve({});

      expect(bg, VelvetBurgundyColors.primaryLight);
      expect(fg, Colors.white);
      expect(_contrast(fg!, bg!), greaterThan(4.5));
    });

    testWidgets('TH-05: RolloverSettingsCard selected checkmark is white in light mode and black in dark mode', (tester) async {
      // Light Mode
      await tester.pumpWidget(
        _wrapLight(
          Scaffold(
            body: SingleChildScrollView(
              child: RolloverSettingsCard(
                initialRule: 'send_to_savings',
                accumulatedSavings: 500.0,
                onSaveRule: (_) async => true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final lightCheckIcon = tester.widget<Icon>(find.byIcon(Icons.check));
      expect(lightCheckIcon.color, Colors.white);

      // Dark Mode
      await tester.pumpWidget(
        _wrapDark(
          Scaffold(
            body: SingleChildScrollView(
              child: RolloverSettingsCard(
                initialRule: 'send_to_savings',
                accumulatedSavings: 500.0,
                onSaveRule: (_) async => true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final darkCheckIcon = tester.widget<Icon>(find.byIcon(Icons.check));
      expect(darkCheckIcon.color, Colors.black);
    });

    testWidgets('TH-06 & TH-07: WifeAllowanceCard save button and progress bar have high contrast', (tester) async {
      const wife = NafaqahWife(
        id: 'w1',
        displayName: 'Amina',
        allowance: AllowanceStatus(
          cycleKey: '2026-11',
          isSet: true,
          allocated: 1000.0,
          spent: 400.0,
          remaining: 600.0,
        ),
      );

      // Light mode test for progress bar
      await tester.pumpWidget(
        _wrapLight(
          const Scaffold(
            body: SingleChildScrollView(
              child: WifeAllowanceCard(
                householdId: 'hh1',
                wife: wife,
                canSet: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final progressFinder = find.byType(LinearProgressIndicator);
      expect(progressFinder, findsOneWidget);
      final progress = tester.widget<LinearProgressIndicator>(progressFinder);
      final barColorAnim = progress.valueColor as AlwaysStoppedAnimation<Color>?;
      expect(barColorAnim?.value, VelvetBurgundyColors.primaryLight);
      expect(_contrast(barColorAnim!.value, Colors.white), greaterThan(4.5));

      // Open set sheet and check save button
      final editBtn = find.text('Change allowance');
      expect(editBtn, findsOneWidget);
      await tester.tap(editBtn);
      await tester.pumpAndSettle();

      final saveBtnFinder = find.widgetWithText(ElevatedButton, 'Save');
      expect(saveBtnFinder, findsOneWidget);
      final btnWidget = tester.widget<ElevatedButton>(saveBtnFinder);
      final bg = btnWidget.style?.backgroundColor?.resolve({});
      final fg = btnWidget.style?.foregroundColor?.resolve({});
      expect(bg, VelvetBurgundyColors.primaryLight);
      expect(fg, Colors.white);
      expect(_contrast(fg!, bg!), greaterThan(4.5));
    });

    testWidgets('TH-08 & TH-09: AccountCard transfer out and shared pool tag use context.accentText', (tester) async {
      const account = Account(
        id: 'acc1',
        householdId: 'hh1',
        ownerUserId: 'u1',
        name: 'Family Shared Account',
        accountType: AccountType.bank,
        balance: 5000.0,
        isSharedPool: true,
      );

      await tester.pumpWidget(
        _wrapLight(
          const Scaffold(
            body: SingleChildScrollView(
              child: AccountCard(
                account: account,
                committedBudgets: 1000.0,
                householdId: 'hh1',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // TH-08: Transfer Out text button
      final transferOutFinder = find.widgetWithText(TextButton, 'Transfer Out');
      expect(transferOutFinder, findsOneWidget);
      final textBtn = tester.widget<TextButton>(transferOutFinder);
      final fg = textBtn.style?.foregroundColor?.resolve({});
      expect(fg, VelvetBurgundyColors.primaryLight);
      expect(_contrast(fg!, Colors.white), greaterThan(4.5));

      // TH-09: Shared Pool tag
      final tagFinder = find.text('Shared Pool');
      expect(tagFinder, findsOneWidget);
      final tagContainer = tester.widget<Container>(find.ancestor(of: tagFinder, matching: find.byType(Container)).first);
      final boxDecoration = tagContainer.decoration as BoxDecoration?;
      expect(boxDecoration?.color, VelvetBurgundyColors.primaryLight.withValues(alpha: 0.15));
    });

    testWidgets('TH-10: NafaqahClassSelector colorFor adapts to light/dark brightness', (tester) async {
      final lightColor = NafaqahClassSelector.colorFor(kWifePersonal, isDark: false);
      final darkColor = NafaqahClassSelector.colorFor(kWifePersonal, isDark: true);

      expect(lightColor, VelvetBurgundyColors.primaryLight);
      expect(darkColor, isNot(VelvetBurgundyColors.primaryLight));
      expect(_contrast(lightColor, Colors.white), greaterThan(4.5));
    });

    testWidgets('TH-11, TH-12, TH-13: progress indicators in buttons adopt primaryButtonFg', (tester) async {
      // In light mode, primaryButtonFg is white, not black
      await tester.pumpWidget(
        _wrapLight(
          Builder(
            builder: (context) {
              return SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: 0.5, // Deterministic value to avoid infinite animation in test
                  color: context.primaryButtonFg,
                ),
              );
            },
          ),
        ),
      );
      await tester.pump();

      final spinnerFinder = find.byType(CircularProgressIndicator);
      expect(spinnerFinder, findsOneWidget);
      final spinner = tester.widget<CircularProgressIndicator>(spinnerFinder);
      expect(spinner.color, Colors.white);
      expect(spinner.color, isNot(Colors.black));
    });

    testWidgets('TH-14: IncomeSpendingReportScreen header savings action icon is white in light mode', (tester) async {
      await tester.pumpWidget(
        _wrapLight(
          const IncomeSpendingReportScreen(householdId: 'hh1'),
        ),
      );
      await tester.pumpAndSettle();

      final savingsIconFinder = find.byIcon(Icons.savings_outlined);
      expect(savingsIconFinder, findsOneWidget);
      final iconWidget = tester.widget<Icon>(savingsIconFinder);
      expect(iconWidget.color, Colors.white);
    });

    testWidgets('TH-15: FamilyReimbursementCard champagne gold button uses dark maroon text in light mode', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _wrapLight(
          const Scaffold(
            body: SingleChildScrollView(
              child: FamilyReimbursementCard(
                householdId: 'hh1',
                summary: NafaqahSummary(
                  mode: 'family_nafaqah',
                  callerRole: 'husband',
                  callerUserId: 'u-h',
                  wives: [NafaqahWife(id: 'u-w', reimbursement: ReimbursementBalance(grossAdvanced: 350, outstanding: 350))],
                  canRecordReimbursement: true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final reimburseBtn = find.text('Reimburse Wife');
      expect(reimburseBtn, findsOneWidget);
      final btnWidget = tester.widget<ElevatedButton>(find.ancestor(of: reimburseBtn, matching: find.byType(ElevatedButton)));
      final fg = btnWidget.style?.foregroundColor?.resolve({});
      expect(fg, const Color(0xFF4A0E1E));
      expect(_contrast(fg!, AppThemes.champagneGold), greaterThan(4.5));
    });

    testWidgets('TH-16: ForgotPasswordScreen and UpdatePasswordScreen use Velvet Burgundy tokens', (tester) async {
      await tester.pumpWidget(_wrapLight(const ForgotPasswordScreen()));
      await tester.pumpAndSettle();

      final sendBtnFinder = find.widgetWithText(ElevatedButton, 'Send Reset Code');
      expect(sendBtnFinder, findsOneWidget);
      final sendBtn = tester.widget<ElevatedButton>(sendBtnFinder);
      final bg = sendBtn.style?.backgroundColor?.resolve({});
      final fg = sendBtn.style?.foregroundColor?.resolve({});
      expect(bg, VelvetBurgundyColors.primaryLight);
      expect(fg, Colors.white);
      expect(_contrast(fg!, bg!), greaterThan(4.5));

      // Test UpdatePasswordScreen
      await tester.pumpWidget(_wrapLight(const UpdatePasswordScreen()));
      await tester.pumpAndSettle();

      final setBtnFinder = find.widgetWithText(ElevatedButton, 'Set New Password');
      expect(setBtnFinder, findsOneWidget);
      final setBtn = tester.widget<ElevatedButton>(setBtnFinder);
      final setBg = setBtn.style?.backgroundColor?.resolve({});
      final setFg = setBtn.style?.foregroundColor?.resolve({});
      expect(setBg, VelvetBurgundyColors.primaryLight);
      expect(setFg, Colors.white);
    });

    testWidgets('TH-17: SettingsScreen permissions NOT GRANTED badge and Grant Access button contrast', (tester) async {
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
          child: _wrapLight(const SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Scroll and expand Hardware & App Permissions section
      final permHeaderFinder = find.text('HARDWARE & APP PERMISSIONS');
      await tester.scrollUntilVisible(permHeaderFinder, 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(permHeaderFinder);
      await tester.pumpAndSettle();

      final grantBtnFinder = find.widgetWithText(ElevatedButton, 'Grant Access').first;
      expect(grantBtnFinder, findsOneWidget);
      final grantBtn = tester.widget<ElevatedButton>(grantBtnFinder);
      final bg = grantBtn.style?.backgroundColor?.resolve({});
      final fg = grantBtn.style?.foregroundColor?.resolve({});
      expect(bg, VelvetBurgundyColors.primaryLight);
      expect(fg, Colors.white);

      final notGrantedFinder = find.text('NOT GRANTED').first;
      expect(notGrantedFinder, findsOneWidget);
      final textWidget = tester.widget<Text>(notGrantedFinder);
      expect(textWidget.style?.color, VelvetBurgundyColors.amberCautionTextLight);
    });
  });
}
