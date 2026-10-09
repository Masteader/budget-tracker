import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/screens/settings/help_support_screen.dart';

void main() {
  testWidgets('HelpSupportScreen renders FAQ tab and AI Chat tab', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: HelpSupportScreen(),
      ),
    );

    expect(find.text('Help & Support'), findsOneWidget);
    expect(find.text('FAQs & Guide'), findsOneWidget);
    expect(find.text('AI Assistant'), findsOneWidget);

    // Verify FAQ items appear
    expect(find.textContaining('Salary Cycle'), findsWidgets);
  });
}
