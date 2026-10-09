import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/widgets/analytics/smart_shopping_basket_sheet.dart';

void main() {
  group('SmartShoppingBasketSheet Widget Tests', () {
    testWidgets('Renders header, quick suggestions, and initial basket items', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SmartShoppingBasketSheet(householdId: 'test-household-123'),
          ),
        ),
      );

      // Verify header
      expect(find.text('Smart Basket Optimizer'), findsOneWidget);
      expect(find.textContaining('Compare totals across Panda'), findsOneWidget);

      // Verify popular suggestion chips
      expect(find.text('Milk'), findsWidgets);
      expect(find.text('Chicken'), findsWidgets);
      expect(find.text('Cheese'), findsOneWidget);
      expect(find.text('Rice'), findsOneWidget);

      // Verify initial checklist items
      expect(find.textContaining('Shopping Checklist'), findsOneWidget);
      expect(find.byType(Checkbox), findsNWidgets(4));
    });

    testWidgets('Toggles checklist item strike-through state', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SmartShoppingBasketSheet(householdId: 'test-household-123'),
          ),
        ),
      );

      // Find first checkbox and tap it
      final firstCheckbox = find.byType(Checkbox).first;
      await tester.tap(firstCheckbox);
      await tester.pump();

      expect(find.text('Shopping Checklist (1/4)'), findsOneWidget);
    });
  });
}
