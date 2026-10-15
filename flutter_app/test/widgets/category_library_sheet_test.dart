import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/widgets/categories/category_library_sheet.dart';

void main() {
  testWidgets('CategoryLibrarySheet displays Active and Library tabs with categories', (tester) async {
    final active = [
      const CategoryItem(code: 'OPEX-DINING', name: 'Dining', isActive: true, isSystem: true),
    ];
    final inactive = [
      const CategoryItem(code: 'OPEX-PETS', name: 'Pets', isActive: false, isSystem: true),
    ];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CategoryLibrarySheet(
          activeCategories: active,
          inactiveCategories: inactive,
          onToggle: (cat, active) {},
          onAddCustom: () {},
        ),
      ),
    ));

    expect(find.textContaining('Active (1)'), findsOneWidget);
    expect(find.textContaining('Library / Inactive (1)'), findsOneWidget);
    expect(find.text('Dining'), findsOneWidget);

    // Switch to Library (Inactive) tab
    await tester.tap(find.textContaining('Library / Inactive'));
    await tester.pumpAndSettle();

    expect(find.text('Pets'), findsOneWidget);
    expect(find.text('Activate'), findsOneWidget);
  });
}
