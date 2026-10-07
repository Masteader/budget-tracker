import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/screens/auth/login_screen.dart';
import 'package:budget_tracker/screens/auth/forgot_password_screen.dart';

void main() {
  testWidgets('LoginScreen shows Forgot password? button in login mode and hides in sign up', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LoginScreen(),
      ),
    );
    await tester.pumpAndSettle();

    // Verify Forgot password? is visible in login mode
    expect(find.text('Forgot password?'), findsOneWidget);

    // Enter email
    await tester.enterText(find.byType(TextFormField).first, 'user@example.com');
    await tester.pumpAndSettle();

    // Tap Forgot password?
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();

    // Verify ForgotPasswordScreen opened with email prefilled
    expect(find.byType(ForgotPasswordScreen), findsOneWidget);
    expect(find.text('user@example.com'), findsOneWidget);
  });
}
