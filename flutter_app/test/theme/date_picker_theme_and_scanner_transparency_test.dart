import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/core/theme/velvet_burgundy_theme.dart';
import 'package:budget_tracker/screens/scanner/receipt_scanner_sheet.dart';
import 'package:budget_tracker/widgets/transactions/expense_date_chips.dart';
import '../support/localized_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DatePickerTheme and Visibility Tests', () {
    testWidgets('Dark theme configures high-contrast datePickerTheme', (tester) async {
      final theme = VelvetBurgundyTheme.darkTheme;
      final dpTheme = theme.datePickerTheme;
      expect(dpTheme, isNotNull);
      expect(dpTheme.backgroundColor, equals(VelvetBurgundyColors.surfaceDark));
      expect(dpTheme.headerBackgroundColor, equals(VelvetBurgundyColors.primaryDarkMaroon));
      expect(dpTheme.headerForegroundColor, equals(VelvetBurgundyColors.textPrimaryDark));
      
      // Action buttons must have visible roseGoldGlow foreground against dark burgundy
      final cancelFg = dpTheme.cancelButtonStyle?.foregroundColor?.resolve({});
      final confirmFg = dpTheme.confirmButtonStyle?.foregroundColor?.resolve({});
      expect(cancelFg, equals(VelvetBurgundyColors.roseGoldGlow));
      expect(confirmFg, equals(VelvetBurgundyColors.roseGoldGlow));

      // Selected day background should be prominent accent rose
      final selectedBg = dpTheme.dayBackgroundColor?.resolve({WidgetState.selected});
      expect(selectedBg, equals(VelvetBurgundyColors.accentRose));
    });

    testWidgets('Light theme configures proper datePickerTheme', (tester) async {
      final theme = VelvetBurgundyTheme.lightTheme;
      final dpTheme = theme.datePickerTheme;
      expect(dpTheme, isNotNull);
      expect(dpTheme.backgroundColor, equals(VelvetBurgundyColors.surfaceLight));
      expect(dpTheme.headerBackgroundColor, equals(VelvetBurgundyColors.primaryLight));
      expect(dpTheme.headerForegroundColor, equals(Colors.white));

      final cancelFg = dpTheme.cancelButtonStyle?.foregroundColor?.resolve({});
      final confirmFg = dpTheme.confirmButtonStyle?.foregroundColor?.resolve({});
      expect(cancelFg, equals(VelvetBurgundyColors.primaryLight));
      expect(confirmFg, equals(VelvetBurgundyColors.primaryLight));
    });

    testWidgets('ExpenseDateChips renders properly under dark theme', (tester) async {
      DateTime selectedDate = DateTime(2026, 10, 25);
      await tester.pumpWidget(
        MaterialApp(
          theme: VelvetBurgundyTheme.darkTheme,
          home: Scaffold(
            body: ExpenseDateChips(
              value: selectedDate,
              now: () => DateTime(2026, 10, 29, 12, 0),
              onChanged: (d) => selectedDate = d,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ExpenseDateChips), findsOneWidget);
      expect(find.byKey(const ValueKey('expense_date_pick')), findsOneWidget);
    });
  });

  group('ReceiptScannerSheet Transparency Fix Tests', () {
    testWidgets('ReceiptScannerSheet root has solid opaque cardBg Container', (tester) async {
      await tester.pumpWidget(
        localizedApp(
          const ReceiptScannerSheet(householdId: '00000000-0000-0000-0000-000000000001'),
          scaffold: true,
        ),
      );
      await tester.pumpAndSettle();

      // Find Container which is the root of ReceiptScannerSheet
      final containerFinder = find.descendant(
        of: find.byType(ReceiptScannerSheet),
        matching: find.byType(Container),
      );
      expect(containerFinder, findsWidgets);

      final rootContainer = tester.widget<Container>(containerFinder.first);
      final decoration = rootContainer.decoration as BoxDecoration?;
      expect(decoration, isNotNull);
      expect(decoration!.color, isNotNull);
      // Ensure the background is NOT transparent
      expect(decoration.color, isNot(equals(Colors.transparent)));
    });
  });
}
