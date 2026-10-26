import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:budget_tracker/main.dart';
import 'package:budget_tracker/screens/auth/update_password_screen.dart';

void main() {
  group('UpdatePasswordScreen Widget Tests', () {
    testWidgets('Renders update password form with new and confirm password fields', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: UpdatePasswordScreen(),
        ),
      );

      expect(find.text('Set New Password'), findsNWidgets(2)); // Header title and button
      expect(find.byType(TextFormField), findsNWidgets(2));
      expect(find.text('Cancel and return to sign in'), findsOneWidget);
    });

    testWidgets('Validates min length and password mismatch', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: UpdatePasswordScreen(),
        ),
      );

      final textFields = find.byType(TextFormField);
      await tester.enterText(textFields.at(0), '123'); // short
      await tester.enterText(textFields.at(1), '123456');

      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();

      expect(find.text('Min 6 characters'), findsOneWidget);

      await tester.enterText(textFields.at(0), 'password123');
      await tester.enterText(textFields.at(1), 'mismatch456');

      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();

      expect(find.text('Passwords do not match'), findsOneWidget);
    });

    testWidgets('Submits new password successfully', (tester) async {
      String? submittedPassword;
      bool callbackFired = false;

      await tester.pumpWidget(
        MaterialApp(
          home: UpdatePasswordScreen(
            onUpdatePassword: (pass) async {
              submittedPassword = pass;
            },
            onPasswordUpdated: () {
              callbackFired = true;
            },
          ),
        ),
      );

      final textFields = find.byType(TextFormField);
      await tester.enterText(textFields.at(0), 'newValidPass2026');
      await tester.enterText(textFields.at(1), 'newValidPass2026');

      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();

      expect(submittedPassword, equals('newValidPass2026'));
      expect(callbackFired, isTrue);
    });

    testWidgets('Cancel button invokes onCancel callback', (tester) async {
      bool cancelFired = false;

      await tester.pumpWidget(
        MaterialApp(
          home: UpdatePasswordScreen(
            onCancel: () {
              cancelFired = true;
            },
          ),
        ),
      );

      await tester.tap(find.text('Cancel and return to sign in'));
      await tester.pumpAndSettle();

      expect(cancelFired, isTrue);
    });
  });

  group('AuthGate Recovery Routing Tests', () {
    testWidgets('AuthGate routes to recoveryBuilder when AuthChangeEvent.passwordRecovery fires', (tester) async {
      final authStreamController = StreamController<AuthState>.broadcast();

      await tester.pumpWidget(
        MaterialApp(
          home: AuthGate(
            authStates: authStreamController.stream,
            loginBuilder: (_) => const Text('Login Screen Mock'),
            homeBuilder: (_) => const Text('Dashboard Screen Mock'),
            recoveryBuilder: (_) => const Text('Password Recovery Screen Mock'),
          ),
        ),
      );

      // Initial state: signed out
      authStreamController.add(const AuthState(AuthChangeEvent.signedOut, null));
      await tester.pumpAndSettle();
      expect(find.text('Login Screen Mock'), findsOneWidget);

      // Password recovery link tapped: recovery event emitted
      authStreamController.add(
        AuthState(
          AuthChangeEvent.passwordRecovery,
          Session(
            accessToken: 'token-xyz',
            tokenType: 'bearer',
            user: const User(
              id: 'u-recovery',
              appMetadata: {},
              userMetadata: {},
              aud: 'authenticated',
              createdAt: '2026-01-01',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verified: AuthGate intercepts passwordRecovery and routes to recovery screen
      expect(find.text('Password Recovery Screen Mock'), findsOneWidget);
      expect(find.text('Dashboard Screen Mock'), findsNothing);

      await authStreamController.close();
    });
  });
}
