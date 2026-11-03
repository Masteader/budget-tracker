import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:budget_tracker/core/widgets/three_d_icon_puck.dart';
import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/screens/tools/tools_screen.dart';
import 'package:budget_tracker/theme/app_themes.dart';
import 'package:budget_tracker/widgets/settings/household_type_chooser.dart';

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
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('Deep Theme Semantic & Component Contrast Audit (DEF-01 to DEF-07)', () {
    // -------------------------------------------------------------------------
    // DEF-01: ToolsScreen ThreeDIconPuck Contrast
    // -------------------------------------------------------------------------
    testWidgets('DEF-01: ToolsScreen tool pucks reach >= 4.5:1 contrast in Light and Dark modes', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // Light Mode
      await tester.pumpWidget(_wrapLight(const ToolsScreen(householdId: 'hh1')));
      await tester.pumpAndSettle();

      final pucksLight = tester.widgetList<ThreeDIconPuck>(find.byType(ThreeDIconPuck)).toList();
      expect(pucksLight, isNotEmpty);

      // Maroon puck background in Light Mode: VelvetBurgundyColors.primaryLight (#4A0E1E)
      const maroonPuckBg = VelvetBurgundyColors.primaryLight;

      for (final puck in pucksLight) {
        expect(puck.iconColor, Colors.white,
            reason: 'In Light Mode, tool puck icons must be Colors.white on dark maroon puck');
        expect(_contrast(puck.iconColor!, maroonPuckBg), greaterThanOrEqualTo(4.5),
            reason: 'Light Mode tool puck icon contrast >= 4.5:1');
      }

      // Dark Mode
      await tester.pumpWidget(_wrapDark(const ToolsScreen(householdId: 'hh1')));
      await tester.pumpAndSettle();

      final pucksDark = tester.widgetList<ThreeDIconPuck>(find.byType(ThreeDIconPuck)).toList();
      expect(pucksDark, isNotEmpty);

      // Dark puck background in Dark Mode: VelvetBurgundyColors.primaryDark (#5E1327)
      const darkPuckBg = VelvetBurgundyColors.primaryDark;

      for (final puck in pucksDark) {
        expect(puck.iconColor, isNot(Colors.white),
            reason: 'In Dark Mode, tool puck icons use tool.color (gold/rose/teal)');
        expect(_contrast(puck.iconColor!, darkPuckBg), greaterThanOrEqualTo(4.5),
            reason: 'Dark Mode tool puck icon contrast >= 4.5:1');
      }
    });

    // -------------------------------------------------------------------------
    // DEF-02: HouseholdTypeChooser ThreeDIconPuck Contrast
    // -------------------------------------------------------------------------
    testWidgets('DEF-02: HouseholdTypeChooser pucks reach >= 4.5:1 in Light & Dark modes (selected & unselected)', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // Light Mode: family selected, roommates unselected
      await tester.pumpWidget(_wrapLight(
        Scaffold(
          body: HouseholdTypeChooser(
            value: 'family',
            onChanged: (_) {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final pucksLight = tester.widgetList<ThreeDIconPuck>(find.byType(ThreeDIconPuck)).toList();
      expect(pucksLight.length, 2);

      const maroonPuckBg = VelvetBurgundyColors.primaryLight;

      // Selected puck: Colors.white
      final selectedPuck = pucksLight[0];
      expect(selectedPuck.iconColor, Colors.white);
      expect(_contrast(selectedPuck.iconColor!, maroonPuckBg), greaterThanOrEqualTo(4.5));

      // Unselected puck: Colors.white.withValues(alpha: 0.7)
      final unselectedPuck = pucksLight[1];
      expect(unselectedPuck.iconColor, Colors.white.withValues(alpha: 0.7));
      expect(_contrast(unselectedPuck.iconColor!, maroonPuckBg), greaterThanOrEqualTo(4.5));

      // Dark Mode: family selected, roommates unselected
      await tester.pumpWidget(_wrapDark(
        Scaffold(
          body: HouseholdTypeChooser(
            value: 'family',
            onChanged: (_) {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final pucksDark = tester.widgetList<ThreeDIconPuck>(find.byType(ThreeDIconPuck)).toList();
      expect(pucksDark.length, 2);

      const darkPuckBg = VelvetBurgundyColors.primaryDark;

      // In Dark Mode, selected and unselected use color and context.textSecondary
      final selectedPuckDark = pucksDark[0];
      expect(_contrast(selectedPuckDark.iconColor!, darkPuckBg), greaterThanOrEqualTo(4.5));

      final unselectedPuckDark = pucksDark[1];
      expect(_contrast(unselectedPuckDark.iconColor!, darkPuckBg), greaterThanOrEqualTo(4.5));
    });

    // -------------------------------------------------------------------------
    // DEF-03: BudgetManagementScreen Prior Spend Dialog Button
    // -------------------------------------------------------------------------
    test('DEF-03: BudgetManagementScreen prior spend dialog uses primaryButtonBg/Fg and reaches >= 4.5:1', () {
      final src = File('lib/screens/home/budget_management_screen.dart').readAsStringSync();
      // Ensure electricTeal / Colors.black is replaced
      expect(
        src.contains('backgroundColor: context.electricTeal'),
        isFalse,
        reason: 'budget_management_screen prior spend dialog must not use context.electricTeal for button background',
      );
      expect(
        src.contains('foregroundColor: Colors.black'),
        isFalse,
        reason: 'budget_management_screen prior spend dialog must not use Colors.black for button foreground',
      );
      expect(
        src.contains('backgroundColor: context.primaryButtonBg'),
        isTrue,
        reason: 'budget_management_screen prior spend dialog must use context.primaryButtonBg',
      );
      expect(
        src.contains('foregroundColor: context.primaryButtonFg'),
        isTrue,
        reason: 'budget_management_screen prior spend dialog must use context.primaryButtonFg',
      );

      // Contrast verification of primaryButtonFg on primaryButtonBg
      // Light Mode:
      const lightBg = VelvetBurgundyColors.primaryLight;
      const lightFg = Colors.white;
      expect(_contrast(lightFg, lightBg), greaterThanOrEqualTo(4.5));

      // Dark Mode:
      const darkBg = VelvetBurgundyColors.primaryDark;
      const darkFg = VelvetBurgundyColors.roseGoldGlow;
      expect(_contrast(darkFg, darkBg), greaterThanOrEqualTo(4.5));
    });

    // -------------------------------------------------------------------------
    // DEF-04: ReceiptScannerSheet Camera Permission Try Again Button
    // -------------------------------------------------------------------------
    test('DEF-04: ReceiptScannerSheet camera permission Try Again button uses context.textPrimary', () {
      final src = File('lib/screens/scanner/receipt_scanner_sheet.dart').readAsStringSync();
      // Locate the Try Again button section
      final tryAgainIdx = src.indexOf("context.tr('try_again')");
      expect(tryAgainIdx, isNot(-1));
      final tryAgainSection = src.substring(tryAgainIdx - 600, tryAgainIdx + 100);

      // Verify no OutlinedButton with foregroundColor: Colors.white in retry button
      expect(
        tryAgainSection.contains('foregroundColor: Colors.white'),
        isFalse,
        reason: 'receipt_scanner_sheet camera banner Try Again button must not use Colors.white',
      );
      expect(
        tryAgainSection.contains('foregroundColor: context.textPrimary'),
        isTrue,
        reason: 'receipt_scanner_sheet camera banner Try Again button must use context.textPrimary',
      );

      // In Light Mode, textPrimary (#1E040B) on card/scaffold surface (> 12:1)
      const lightSurface = Color(0xFFFFFFFF);
      const lightText = VelvetBurgundyColors.textPrimaryLight;
      expect(_contrast(lightText, lightSurface), greaterThanOrEqualTo(4.5));
    });

    // -------------------------------------------------------------------------
    // DEF-05: AffordabilitySimulatorSheet Record Expense Button
    // -------------------------------------------------------------------------
    test('DEF-05: AffordabilitySimulatorSheet Record Expense button uses context.successText', () {
      final src = File('lib/widgets/simulator/affordability_simulator_sheet.dart').readAsStringSync();
      expect(
        src.contains('foregroundColor: AppThemes.success'),
        isFalse,
        reason: 'affordability_simulator_sheet Record Expense button must not use static AppThemes.success',
      );
      expect(
        src.contains('foregroundColor: context.successText'),
        isTrue,
        reason: 'affordability_simulator_sheet Record Expense button must use context.successText',
      );
      expect(
        src.contains('side: BorderSide(color: context.successText)'),
        isTrue,
        reason: 'affordability_simulator_sheet Record Expense button border must use context.successText',
      );

      // Contrast verification: successText on cardBg in Light mode
      const lightCard = Color(0xFFFFFFFF);
      const lightSuccess = VelvetBurgundyColors.emeraldSafeTextLight; // #065F46
      expect(_contrast(lightSuccess, lightCard), greaterThanOrEqualTo(4.5));
    });

    // -------------------------------------------------------------------------
    // DEF-06: GroceryPriceIntelligenceScreen Basket Icon & Cheapest Price Label
    // -------------------------------------------------------------------------
    testWidgets('DEF-06: GroceryPriceIntelligenceScreen basket icon and cheapest tag use context.successText', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final src = File('lib/screens/analytics/grocery_price_intelligence_screen.dart').readAsStringSync();
      expect(
        src.contains('Icons.shopping_basket_outlined, color: AppThemes.success'),
        isFalse,
        reason: 'Basket icon must not use static AppThemes.success',
      );
      expect(
        src.contains('Icons.shopping_basket_outlined, color: context.successText'),
        isTrue,
        reason: 'Basket icon must use context.successText',
      );
      expect(
        src.contains('Icons.star_rounded, size: 14, color: AppThemes.success'),
        isFalse,
        reason: 'Cheapest star icon must not use static AppThemes.success',
      );
      expect(
        src.contains('color: isCheapest ? AppThemes.success : context.textPrimary'),
        isFalse,
        reason: 'Cheapest price text must not use static AppThemes.success',
      );

      // Light mode AppBar & card surface contrast
      const lightSurface = Color(0xFFFFFFFF);
      const lightSuccess = VelvetBurgundyColors.emeraldSafeTextLight;
      expect(_contrast(lightSuccess, lightSurface), greaterThanOrEqualTo(4.5));
    });

    // -------------------------------------------------------------------------
    // DEF-07: Static AppThemes.success replacement across Scanner and Chat headers
    // -------------------------------------------------------------------------
    test('DEF-07: ZATCA dialog, receipt scanner header, multi-page scanner, and chat entry icons use context.successText', () {
      final receiptSheetSrc = File('lib/screens/scanner/receipt_scanner_sheet.dart').readAsStringSync();
      expect(
        receiptSheetSrc.contains('Icons.qr_code_2_rounded, color: AppThemes.success'),
        isFalse,
        reason: 'receipt_scanner_sheet ZATCA dialog icon must not use AppThemes.success',
      );
      expect(
        receiptSheetSrc.contains('Icons.document_scanner_outlined, color: AppThemes.success'),
        isFalse,
        reason: 'receipt_scanner_sheet scan header icon must not use AppThemes.success',
      );
      expect(
        receiptSheetSrc.contains('Icons.qr_code_2_rounded, color: context.successText'),
        isTrue,
        reason: 'receipt_scanner_sheet ZATCA dialog icon must use context.successText',
      );
      expect(
        receiptSheetSrc.contains('Icons.document_scanner_outlined, color: context.successText'),
        isTrue,
        reason: 'receipt_scanner_sheet scan header icon must use context.successText',
      );

      final multiPageSrc = File('lib/screens/scanner/multi_page_receipt_scanner_screen.dart').readAsStringSync();
      expect(
        multiPageSrc.contains('Icons.qr_code_scanner, color: AppThemes.success'),
        isFalse,
        reason: 'multi_page_receipt_scanner_screen QR action icon must not use AppThemes.success',
      );
      expect(
        multiPageSrc.contains('Icons.qr_code_scanner, color: context.successText'),
        isTrue,
        reason: 'multi_page_receipt_scanner_screen QR action icon must use context.successText',
      );

      final chatSrc = File('lib/screens/chat/chat_entry_screen.dart').readAsStringSync();
      expect(
        chatSrc.contains('Icons.auto_awesome, color: AppThemes.success'),
        isFalse,
        reason: 'chat_entry_screen AI header icon must not use AppThemes.success',
      );
      expect(
        chatSrc.contains('Icons.auto_awesome, color: context.successText'),
        isTrue,
        reason: 'chat_entry_screen AI header icon must use context.successText',
      );
    });
  });
}
