import 'package:budget_tracker/errors/config_error_app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ConfigErrorApp Widget Tests', () {
    testWidgets('renders configuration problems and error badge', (tester) async {
      final problems = [
        'Missing --dart-define=SUPABASE_URL',
        'Missing --dart-define=SUPABASE_PUBLISHABLE_KEY',
      ];

      await tester.pumpWidget(
        ConfigErrorApp(
          problems: problems,
          error: StateError('Invalid Budget Tracker build configuration'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Budget Tracker Diagnostic'), findsOneWidget);
      expect(find.text('Configuration Error'), findsOneWidget);
      expect(find.text('Application Startup Stopped'), findsOneWidget);
      expect(find.text('Identified Issues'), findsOneWidget);
      expect(find.text('Missing --dart-define=SUPABASE_URL'), findsOneWidget);
      expect(find.text('Missing --dart-define=SUPABASE_PUBLISHABLE_KEY'), findsOneWidget);
      expect(find.text('Copy Report', skipOffstage: false), findsOneWidget);
    });

    testWidgets('renders initialization failure badge when problems list is empty', (tester) async {
      await tester.pumpWidget(
        ConfigErrorApp(
          error: Exception('Supabase connection timed out'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Initialization Failure'), findsOneWidget);
      expect(find.textContaining('Supabase connection timed out'), findsOneWidget);
      expect(find.text('View Stack Trace'), findsNothing);
    });

    testWidgets('toggles stack trace display when trace is provided', (tester) async {
      final trace = StackTrace.fromString('main.dart:45:10\nmain.dart:12:3');

      await tester.pumpWidget(
        ConfigErrorApp(
          error: Exception('Failed'),
          stackTrace: trace,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('View Stack Trace'), findsOneWidget);
      expect(find.textContaining('main.dart:45:10'), findsNothing);

      await tester.tap(find.text('View Stack Trace'));
      await tester.pumpAndSettle();

      expect(find.text('Hide Stack Trace'), findsOneWidget);
      expect(find.textContaining('main.dart:45:10'), findsOneWidget);
    });

    testWidgets('calls onRetry callback when retry button is tapped', (tester) async {
      var retryCalled = false;

      await tester.pumpWidget(
        ConfigErrorApp(
          error: Exception('Initial failed'),
          onRetry: () => retryCalled = true,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Retry Startup'), findsOneWidget);
      await tester.tap(find.text('Retry Startup'));
      await tester.pumpAndSettle();

      expect(retryCalled, isTrue);
    });
  });
}
