import 'dart:convert';

import 'package:budget_tracker/screens/settings/help_support_screen.dart';
import 'package:budget_tracker/services/api/base_api_client.dart';
import 'package:budget_tracker/services/api/support_api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Recorder {
  final List<http.Request> requests = [];
  http.Response response = http.Response(jsonEncode({'status': 'sent', 'reference': 'ref42abc'}), 200);

  SupportApiClient client() => SupportApiClient(
        baseClient: BaseApiClient(
          client: MockClient((request) async {
            requests.add(request);
            return response;
          }),
          authTokenProvider: () => 'user-jwt',
          sessionRefresher: () async => null,
        ),
      );
}

Future<void> _openComposer(WidgetTester tester, _Recorder recorder) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: HelpSupportScreen(householdId: '00000000-0000-4000-8000-000000000001', supportClient: recorder.client()),
  ));
  final button = find.widgetWithText(OutlinedButton, 'Send to Developer');
  await tester.scrollUntilVisible(button, 300, scrollable: find.byType(Scrollable).first);
  await tester.tap(button);
  await tester.pumpAndSettle();
  expect(find.text('Message the Developer'), findsOneWidget);
}

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

  group('Contact developer', () {
    testWidgets('sends the message through /support/inquiries and confirms only after delivery', (tester) async {
      final recorder = _Recorder();
      await _openComposer(tester, recorder);

      await tester.enterText(find.byKey(const ValueKey('support-inquiry-message')), 'Bills tab crashes on open');
      await tester.tap(find.byKey(const ValueKey('support-inquiry-send')));
      await tester.pumpAndSettle();

      expect(recorder.requests, hasLength(1));
      final request = recorder.requests.single;
      expect(request.url.path, endsWith('/support/inquiries'));
      expect(request.headers['Authorization'], 'Bearer user-jwt');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['message'], 'Bills tab crashes on open');
      expect(body['locale'], 'en');
      expect(body['household_id'], '00000000-0000-4000-8000-000000000001');

      expect(find.text('Message the Developer'), findsNothing);
      expect(find.text('Message sent'), findsOneWidget);
      expect(find.textContaining('ref42abc'), findsOneWidget);
    });

    testWidgets('shows an honest error and the manual fallback when delivery fails', (tester) async {
      final recorder = _Recorder()
        ..response = http.Response(jsonEncode({'detail': 'Email delivery is not configured'}), 503);
      await _openComposer(tester, recorder);

      await tester.enterText(find.byKey(const ValueKey('support-inquiry-message')), 'Need help');
      await tester.tap(find.byKey(const ValueKey('support-inquiry-send')));
      await tester.pumpAndSettle();

      expect(recorder.requests, hasLength(1));
      expect(find.text('Message the Developer'), findsOneWidget, reason: 'dialog stays open');
      expect(find.textContaining('could not be sent'), findsOneWidget);
      expect(find.textContaining('abedmowafaq@gmail.com'), findsOneWidget);
      expect(find.text('Copy Full Diagnostic Info'), findsOneWidget);
      expect(find.text('Message sent'), findsNothing);
      // The typed message is kept for a retry.
      expect(find.text('Need help'), findsOneWidget);
    });

    testWidgets('asks to sign in again when the session is rejected', (tester) async {
      final recorder = _Recorder()..response = http.Response(jsonEncode({'detail': 'expired'}), 401);
      await _openComposer(tester, recorder);

      await tester.enterText(find.byKey(const ValueKey('support-inquiry-message')), 'Need help');
      await tester.tap(find.byKey(const ValueKey('support-inquiry-send')));
      await tester.pumpAndSettle();

      expect(find.textContaining('sign in again'), findsOneWidget);
      expect(find.text('Message sent'), findsNothing);
    });

    testWidgets('an empty message is not sent', (tester) async {
      final recorder = _Recorder();
      await _openComposer(tester, recorder);

      await tester.tap(find.byKey(const ValueKey('support-inquiry-send')));
      await tester.pumpAndSettle();

      expect(recorder.requests, isEmpty);
      expect(find.text('Please write your message first.'), findsOneWidget);
    });
  });
}
