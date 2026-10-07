import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/screens/auth/forgot_password_screen.dart';

void main() {
  group('ForgotPasswordScreen Widget Tests', () {
    testWidgets('Renders initial email step and prefilled email', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ForgotPasswordScreen(initialEmail: 'user@example.com'),
        ),
      );

      expect(find.text('Reset Password'), findsOneWidget);
      expect(find.text('Send Reset Code'), findsOneWidget);
      expect(find.text('user@example.com'), findsOneWidget);
    });

    testWidgets('Validates invalid email format', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ForgotPasswordScreen(),
        ),
      );

      final emailField = find.byType(TextFormField);
      await tester.enterText(emailField, 'not-an-email');
      await tester.tap(find.text('Send Reset Code'));
      await tester.pump();

      expect(find.text('Enter a valid email'), findsOneWidget);
    });

    testWidgets('Transitions to Step 2 upon sending code successfully', (tester) async {
      String? sentEmail;

      await tester.pumpWidget(
        MaterialApp(
          home: ForgotPasswordScreen(
            initialEmail: 'test@domain.com',
            onSendResetCode: (email) async {
              sentEmail = email;
            },
          ),
        ),
      );

      await tester.tap(find.text('Send Reset Code'));
      await tester.pumpAndSettle();

      expect(sentEmail, equals('test@domain.com'));
      expect(find.text('Enter Verification Code'), findsOneWidget);
      expect(find.text('Set New Password'), findsOneWidget);
    });

    testWidgets('Validates password mismatch and min length in Step 2', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ForgotPasswordScreen(
            initialEmail: 'test@domain.com',
            onSendResetCode: (email) async {},
          ),
        ),
      );

      // Transition to Step 2
      await tester.tap(find.text('Send Reset Code'));
      await tester.pumpAndSettle();

      // Enter OTP
      final textFields = find.byType(TextFormField);
      // OTP field is first
      await tester.enterText(textFields.at(0), '123456');
      // New password
      await tester.enterText(textFields.at(1), '12345');
      // Confirm password
      await tester.enterText(textFields.at(2), 'mismatch');

      await tester.tap(find.text('Set New Password'));
      await tester.pump();

      expect(find.text('Min 6 characters'), findsOneWidget);
    });

    testWidgets('Submits OTP and new password successfully', (tester) async {
      String? verifiedEmail;
      String? verifiedToken;
      String? verifiedPass;

      await tester.pumpWidget(
        MaterialApp(
          home: ForgotPasswordScreen(
            initialEmail: 'test@domain.com',
            onSendResetCode: (email) async {},
            onVerifyAndResetPassword: (email, token, pass) async {
              verifiedEmail = email;
              verifiedToken = token;
              verifiedPass = pass;
            },
          ),
        ),
      );

      // Go to Step 2
      await tester.tap(find.text('Send Reset Code'));
      await tester.pumpAndSettle();

      final textFields = find.byType(TextFormField);
      await tester.enterText(textFields.at(0), '654321');
      await tester.enterText(textFields.at(1), 'newpassword123');
      await tester.enterText(textFields.at(2), 'newpassword123');

      await tester.tap(find.text('Set New Password'));
      await tester.pumpAndSettle();

      expect(verifiedEmail, equals('test@domain.com'));
      expect(verifiedToken, equals('654321'));
      expect(verifiedPass, equals('newpassword123'));
    });
  });
}
