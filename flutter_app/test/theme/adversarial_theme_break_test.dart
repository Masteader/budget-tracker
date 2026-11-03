import 'dart:io';
import 'dart:math' as math;
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
import 'package:budget_tracker/screens/scanner/batch_receipt_scanner_screen.dart';
import 'package:budget_tracker/screens/settings/settings_screen.dart';
import 'package:budget_tracker/theme/app_themes.dart';
import 'package:budget_tracker/widgets/accounts/account_card.dart';
import 'package:budget_tracker/widgets/dashboard/family_reimbursement_card.dart';
import 'package:budget_tracker/widgets/nafaqah/wife_allowance_card.dart';
import 'package:budget_tracker/widgets/scanner/batch_item_review_sheet.dart';

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

Widget _wrapDynamicApp({
  required Widget Function(BuildContext) builder,
  required ThemeMode themeMode,
  Locale locale = const Locale('en'),
  TextScaler textScaler = TextScaler.noScaling,
  Size size = const Size(390, 844),
}) {
  return MediaQuery(
    data: MediaQueryData(size: size, textScaler: textScaler),
    child: MaterialApp(
      theme: AppThemes.lightTheme,
      darkTheme: AppThemes.darkTheme,
      themeMode: themeMode,
      locale: locale,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('ar'), Locale('ur')],
      home: Builder(builder: builder),
    ),
  );
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Vector 1: Dynamic Theme Switching & Contrast Invariants', () {
    testWidgets('Toggle Light <-> Dark at runtime maintains >= 4.5:1 contrast for all modified elements', (tester) async {
      ThemeMode currentMode = ThemeMode.dark;
      late StateSetter setDynamicState;

      const dummyAccount = Account(
        id: 'acc_adv_1',
        householdId: 'hh1',
        ownerUserId: 'u1',
        name: 'Alinma Bank',
        accountType: AccountType.bank,
        balance: 15000.0,
      );

      final dummyFile = File('test_assets/receipt_adv.jpg');

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => ThemeProvider()),
            ChangeNotifierProvider(create: (_) => LocaleProvider()),
          ],
          child: StatefulBuilder(
            builder: (context, setState) {
              setDynamicState = setState;
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
                supportedLocales: const [Locale('en'), Locale('ar'), Locale('ur')],
                locale: const Locale('en'),
                home: Scaffold(
                  body: SingleChildScrollView(
                    child: Column(
                      children: [
                        const AccountCard(
                          account: dummyAccount,
                          committedBudgets: 10000.0,
                          householdId: 'hh1',
                        ),
                        const WifeAllowanceCard(
                          householdId: 'hh1',
                          wife: NafaqahWife(
                            id: 'w1',
                            displayName: 'Noura',
                            allowance: AllowanceStatus(
                              cycleKey: '2026-11',
                              isSet: true,
                              allocated: 2000,
                              spent: 500,
                            ),
                          ),
                          cycleKey: '2026-11',
                          canSet: true,
                        ),
                        const FamilyReimbursementCard(
                          householdId: 'hh1',
                          summary: NafaqahSummary(
                            mode: 'family_nafaqah',
                            callerRole: 'husband',
                            callerUserId: 'u-h',
                            wives: [NafaqahWife(id: 'w1', reimbursement: ReimbursementBalance(grossAdvanced: 400, outstanding: 400))],
                            canRecordReimbursement: true,
                          ),
                        ),
                        BatchItemReviewSheet(
                          receiptImages: [dummyFile],
                          householdId: 'hh1',
                          previewReceipt: (_) async => {
                            'merchant': 'HyperPanda',
                            'amount': 85.0,
                            'vat_amount': 11.0,
                            'category_code': 'OPEX-GROCERIES',
                          },
                          saveReceipt: (_) async {},
                        ),
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

      // --- PHASE 1: DARK MODE INVARIANTS ---
      expect(Theme.of(tester.element(find.byType(AccountCard))).brightness, Brightness.dark);

      // 1. AccountCard "Transfer Out" text button contrast on dark card
      final transferOutFinder = find.widgetWithText(TextButton, 'Transfer Out');
      expect(transferOutFinder, findsOneWidget);
      final transferOutBtn = tester.widget<TextButton>(transferOutFinder);
      final transferOutFgDark = transferOutBtn.style?.foregroundColor?.resolve({}) ?? Colors.transparent;
      expect(_contrast(transferOutFgDark, VelvetBurgundyColors.surfaceDark), greaterThanOrEqualTo(4.5));

      // 2. FamilyReimbursementCard "Reimburse Wife" champagne gold button contrast
      final reimburseBtnFinder = find.widgetWithText(ElevatedButton, 'Reimburse Wife');
      expect(reimburseBtnFinder, findsOneWidget);
      final reimburseBtn = tester.widget<ElevatedButton>(reimburseBtnFinder);
      final reimburseFgDark = reimburseBtn.style?.foregroundColor?.resolve({}) ?? Colors.transparent;
      expect(_contrast(reimburseFgDark, AppThemes.champagneGold), greaterThanOrEqualTo(4.5));

      // 3. BatchItemReviewSheet "Save & Next" contrast
      final saveNextFinder = find.byKey(const Key('batch_save_next_button'));
      expect(saveNextFinder, findsOneWidget);
      final saveNextBtn = tester.widget<ElevatedButton>(saveNextFinder);
      final saveNextBgDark = saveNextBtn.style?.backgroundColor?.resolve({}) ?? Colors.transparent;
      final saveNextFgDark = saveNextBtn.style?.foregroundColor?.resolve({}) ?? Colors.transparent;
      expect(_contrast(saveNextFgDark, saveNextBgDark), greaterThanOrEqualTo(4.5));

      // --- PHASE 2: SWITCH RUNTIME TO LIGHT MODE ---
      setDynamicState(() {
        currentMode = ThemeMode.light;
      });
      await tester.pumpAndSettle();

      expect(Theme.of(tester.element(find.byType(AccountCard))).brightness, Brightness.light);

      // 1. AccountCard "Transfer Out" text button contrast on light card
      final transferOutBtnLight = tester.widget<TextButton>(transferOutFinder);
      final transferOutFgLight = transferOutBtnLight.style?.foregroundColor?.resolve({}) ?? Colors.transparent;
      expect(_contrast(transferOutFgLight, VelvetBurgundyColors.surfaceLight), greaterThanOrEqualTo(4.5));

      // 2. FamilyReimbursementCard "Reimburse Wife" button foreground on gold in light mode
      final reimburseBtnLight = tester.widget<ElevatedButton>(reimburseBtnFinder);
      final reimburseFgLight = reimburseBtnLight.style?.foregroundColor?.resolve({}) ?? Colors.transparent;
      expect(_contrast(reimburseFgLight, AppThemes.champagneGold), greaterThanOrEqualTo(4.5));

      // 3. BatchItemReviewSheet "Save & Next" contrast in light mode
      final saveNextBtnLight = tester.widget<ElevatedButton>(saveNextFinder);
      final saveNextBgLight = saveNextBtnLight.style?.backgroundColor?.resolve({}) ?? Colors.transparent;
      final saveNextFgLight = saveNextBtnLight.style?.foregroundColor?.resolve({}) ?? Colors.transparent;
      expect(_contrast(saveNextFgLight, saveNextBgLight), greaterThanOrEqualTo(4.5));
    });

    testWidgets('SettingsScreen Permissions NOT GRANTED badge & Grant Access button contrast in Light & Dark modes', (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final themeProvider = ThemeProvider();
      await themeProvider.setThemeMode(ThemeMode.light);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: themeProvider),
            ChangeNotifierProvider(create: (_) => LocaleProvider()),
          ],
          child: MaterialApp(
            theme: AppThemes.lightTheme,
            darkTheme: AppThemes.darkTheme,
            themeMode: ThemeMode.light,
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

      final permHeaderFinder = find.text('HARDWARE & APP PERMISSIONS');
      await tester.scrollUntilVisible(permHeaderFinder, 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(permHeaderFinder);
      await tester.pumpAndSettle();

      // --- LIGHT MODE CHECKS ---
      final grantFinder = find.widgetWithText(ElevatedButton, 'Grant Access').first;
      expect(grantFinder, findsOneWidget);
      var grantBtn = tester.widget<ElevatedButton>(grantFinder);
      var grantBg = grantBtn.style?.backgroundColor?.resolve({}) ?? Colors.transparent;
      var grantFg = grantBtn.style?.foregroundColor?.resolve({}) ?? Colors.transparent;
      expect(_contrast(grantFg, grantBg), greaterThanOrEqualTo(4.5),
          reason: 'Grant Access button contrast in Light mode must be >= 4.5:1');

      final notGrantedFinder = find.text('NOT GRANTED').first;
      expect(notGrantedFinder, findsOneWidget);
      var badgeText = tester.widget<Text>(notGrantedFinder);
      expect(_contrast(badgeText.style!.color!, VelvetBurgundyColors.surfaceLight), greaterThanOrEqualTo(4.5),
          reason: 'NOT GRANTED badge text contrast in Light mode must be >= 4.5:1');

      // --- DYNAMIC SWITCH TO DARK MODE ---
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: themeProvider),
            ChangeNotifierProvider(create: (_) => LocaleProvider()),
          ],
          child: MaterialApp(
            theme: AppThemes.lightTheme,
            darkTheme: AppThemes.darkTheme,
            themeMode: ThemeMode.dark,
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

      // Check expanded section still visible and dynamically repainted in dark mode
      expect(find.widgetWithText(ElevatedButton, 'Grant Access').first, findsOneWidget);
      grantBtn = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Grant Access').first);
      grantBg = grantBtn.style?.backgroundColor?.resolve({}) ?? Colors.transparent;
      grantFg = grantBtn.style?.foregroundColor?.resolve({}) ?? Colors.transparent;
      expect(_contrast(grantFg, grantBg), greaterThanOrEqualTo(4.5),
          reason: 'Grant Access button contrast in Dark mode must be >= 4.5:1');

      badgeText = tester.widget<Text>(find.text('NOT GRANTED').first);
      expect(_contrast(badgeText.style!.color!, VelvetBurgundyColors.surfaceDark), greaterThanOrEqualTo(4.5),
          reason: 'NOT GRANTED badge text contrast in Dark mode must be >= 4.5:1');
    });

    testWidgets('BatchReceiptScannerScreen Process Queue button contrast in Light & Dark modes', (tester) async {
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        await tester.pumpWidget(
          _wrapDynamicApp(
            themeMode: mode,
            builder: (context) => const BatchReceiptScannerScreen(householdId: 'hh1'),
          ),
        );
        await tester.pumpAndSettle();

        final processFinder = find.byKey(const Key('process_batch_queue_button'));
        expect(processFinder, findsOneWidget);
        final processBtn = tester.widget<ElevatedButton>(processFinder);
        final bg = processBtn.style?.backgroundColor?.resolve({}) ?? Colors.transparent;
        final fg = processBtn.style?.foregroundColor?.resolve({}) ?? Colors.transparent;

        expect(_contrast(fg, bg), greaterThanOrEqualTo(4.5),
            reason: 'Process Queue contrast in mode $mode must be >= 4.5:1');
      }
    });

    testWidgets('IncomeSpendingReportScreen savings action icon contrast on VelvetWaveHeader in Light & Dark modes', (tester) async {
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        await tester.pumpWidget(
          _wrapDynamicApp(
            themeMode: mode,
            builder: (context) => const IncomeSpendingReportScreen(householdId: 'hh1'),
          ),
        );
        await tester.pumpAndSettle();

        final iconFinder = find.byIcon(Icons.savings_outlined);
        expect(iconFinder, findsOneWidget);
        final iconWidget = tester.widget<Icon>(iconFinder);
        final iconColor = iconWidget.color ?? Colors.transparent;

        // VelvetWaveHeader dark burgundy gradient base color is ~0xFF4A0E1E
        const headerBurgundy = Color(0xFF4A0E1E);
        expect(_contrast(iconColor, headerBurgundy), greaterThanOrEqualTo(4.5),
            reason: 'Savings action icon contrast on header in mode $mode must be >= 4.5:1');
      }
    });
  });

  group('Vector 2: Extreme Text Scaling (1.75x & 2.0x) & Zero Overflow', () {
    for (final scale in [1.75, 2.0]) {
      testWidgets('SettingsScreen permissions card under textScaler: $scale does not overflow', (tester) async {
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider(create: (_) => ThemeProvider()),
              ChangeNotifierProvider(create: (_) => LocaleProvider()),
            ],
            child: _wrapDynamicApp(
              themeMode: ThemeMode.light,
              textScaler: TextScaler.linear(scale),
              size: const Size(360, 800),
              builder: (context) => const SettingsScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final permHeaderFinder = find.text('HARDWARE & APP PERMISSIONS');
        await tester.scrollUntilVisible(permHeaderFinder, 200, scrollable: find.byType(Scrollable).first);
        await tester.tap(permHeaderFinder);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });

      testWidgets('BatchItemReviewSheet under textScaler: $scale does not overflow', (tester) async {
        final dummyFile = File('test_assets/receipt_adv_scale.jpg');
        await tester.pumpWidget(
          _wrapDynamicApp(
            themeMode: ThemeMode.light,
            textScaler: TextScaler.linear(scale),
            size: const Size(360, 800),
            builder: (context) => Scaffold(
              body: SingleChildScrollView(
                child: BatchItemReviewSheet(
                  receiptImages: [dummyFile],
                  householdId: 'hh1',
                  previewReceipt: (_) async => {
                    'merchant': 'Panda Supermarket',
                    'amount': 250.75,
                    'vat_amount': 37.61,
                    'category_code': 'OPEX-GROCERIES',
                  },
                  saveReceipt: (_) async {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('batch_save_next_button')), findsOneWidget);
        expect(find.byKey(const Key('batch_skip_button')), findsOneWidget);
      });

      testWidgets('WifeAllowanceCard under textScaler: $scale does not overflow', (tester) async {
        await tester.pumpWidget(
          _wrapDynamicApp(
            themeMode: ThemeMode.light,
            textScaler: TextScaler.linear(scale),
            size: const Size(360, 800),
            builder: (context) => const Scaffold(
              body: SingleChildScrollView(
                child: WifeAllowanceCard(
                  householdId: 'hh1',
                  wife: NafaqahWife(
                    id: 'w1',
                    displayName: 'Amina',
                    allowance: AllowanceStatus(
                      cycleKey: '2026-11',
                      isSet: true,
                      allocated: 3500.0,
                      spent: 3800.0, // Overspent condition
                    ),
                  ),
                  cycleKey: '2026-11',
                  canSet: true,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('allowance_remaining_value')), findsOneWidget);
      });

      testWidgets('FamilyReimbursementCard under textScaler: $scale does not overflow', (tester) async {
        await tester.pumpWidget(
          _wrapDynamicApp(
            themeMode: ThemeMode.light,
            textScaler: TextScaler.linear(scale),
            size: const Size(360, 800),
            builder: (context) => const Scaffold(
              body: SingleChildScrollView(
                child: FamilyReimbursementCard(
                  householdId: 'hh1',
                  summary: NafaqahSummary(
                    mode: 'family_nafaqah',
                    callerRole: 'husband',
                    callerUserId: 'u-h',
                    wives: [
                      NafaqahWife(
                        id: 'w1',
                        displayName: 'Sara',
                        reimbursement: ReimbursementBalance(grossAdvanced: 1250.0, outstanding: 1250.0),
                      ),
                    ],
                    canRecordReimbursement: true,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Reimburse Wife'), findsOneWidget);
      });
    }
  });

  group('Vector 3: RTL / Trilingual Rendering (ar, ur, en)', () {
    for (final loc in [const Locale('ar'), const Locale('ur')]) {
      testWidgets('SettingsScreen permissions, WifeAllowanceCard, FamilyReimbursementCard in $loc RTL', (tester) async {
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider(create: (_) => ThemeProvider()),
              ChangeNotifierProvider(create: (_) => LocaleProvider()),
            ],
            child: _wrapDynamicApp(
              locale: loc,
              themeMode: ThemeMode.light,
              textScaler: const TextScaler.linear(1.5),
              size: const Size(360, 900),
              builder: (context) {
                // Verify Directionality is RTL
                expect(Directionality.of(context), TextDirection.rtl);

                return const Scaffold(
                  body: SingleChildScrollView(
                    child: Column(
                      children: [
                        WifeAllowanceCard(
                          householdId: 'hh1',
                          wife: NafaqahWife(
                            id: 'w1',
                            displayName: 'مريم',
                            allowance: AllowanceStatus(
                              cycleKey: '2026-11',
                              isSet: true,
                              allocated: 2500,
                              spent: 1200,
                            ),
                          ),
                          cycleKey: '2026-11',
                          canSet: true,
                        ),
                        FamilyReimbursementCard(
                          householdId: 'hh1',
                          summary: NafaqahSummary(
                            mode: 'family_nafaqah',
                            callerRole: 'husband',
                            callerUserId: 'u-h',
                            wives: [
                              NafaqahWife(
                                id: 'w1',
                                reimbursement: ReimbursementBalance(grossAdvanced: 850, outstanding: 850),
                              ),
                            ],
                            canRecordReimbursement: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });

      testWidgets('BatchItemReviewSheet in $loc RTL with 1.75x text scale', (tester) async {
        final dummyFile = File('test_assets/receipt_rtl.jpg');

        await tester.pumpWidget(
          _wrapDynamicApp(
            locale: loc,
            themeMode: ThemeMode.light,
            textScaler: const TextScaler.linear(1.75),
            size: const Size(360, 900),
            builder: (context) {
              expect(Directionality.of(context), TextDirection.rtl);

              return Scaffold(
                body: SingleChildScrollView(
                  child: BatchItemReviewSheet(
                    receiptImages: [dummyFile],
                    householdId: 'hh1',
                    previewReceipt: (_) async => {
                      'merchant': 'أسواق العثيم',
                      'amount': 320.0,
                      'vat_amount': 48.0,
                      'category_code': 'OPEX-GROCERIES',
                    },
                    saveReceipt: (_) async {},
                  ),
                ),
              );
            },
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('batch_save_next_button')), findsOneWidget);
        expect(find.byKey(const Key('batch_skip_button')), findsOneWidget);
      });
    }
  });
}
