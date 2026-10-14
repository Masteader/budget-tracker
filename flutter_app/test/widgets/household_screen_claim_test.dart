import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:convert';

import 'package:budget_tracker/screens/onboarding/household_screen.dart';
import 'package:budget_tracker/providers/budget_provider.dart';
import 'package:budget_tracker/providers/transaction_provider.dart';
import 'package:budget_tracker/services/api_service.dart';
import 'package:budget_tracker/services/api/base_api_client.dart';
import 'package:budget_tracker/services/api/budget_api_client.dart';
import 'package:budget_tracker/l10n/app_localizations.dart';

void main() {
  group('HouseholdScreen Targeted Claim-on-Join Tests', () {
    testWidgets('shows personalized welcome banner when code with targetMemberId is entered', (tester) async {
      // Mock API inspecting targeted code FATIMA01
      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/FATIMA01')) {
          return http.Response(
            jsonEncode({
              'household_id': 'hh-123',
              'invite_code': 'FATIMA01',
              'role': 'spouse',
              'target_member_id': 'dep-fatima',
              'target_member_name': 'Fatima',
              'is_valid': true,
            }),
            200,
          );
        }
        return http.Response('{"error": "not found"}', 404);
      });

      final baseClient = BaseApiClient(client: mockClient);
      final budgetClient = BudgetApiClient(baseClient: baseClient);
      final apiService = ApiService(budget: budgetClient);

      final budgetProvider = BudgetProvider();
      final txProvider = TransactionProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<BudgetProvider>.value(value: budgetProvider),
            ChangeNotifierProvider<TransactionProvider>.value(value: txProvider),
          ],
          child: MaterialApp(
            localizationsDelegates: const [AppLocalizationsDelegate()],
            supportedLocales: const [Locale('en'), Locale('ar'), Locale('ur')],
            locale: const Locale('en'),
            home: HouseholdScreen(apiService: apiService),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Join tab
      await tester.tap(find.byType(Tab).last);
      await tester.pumpAndSettle();

      // Enter 8-character invite code
      final codeInput = find.byType(TextField).last;
      await tester.enterText(codeInput, 'FATIMA01');
      await tester.pumpAndSettle();

      // Verify personalized banner appears
      expect(find.byKey(const Key('targeted_claim_banner')), findsOneWidget);
      expect(find.textContaining('Welcome Fatima!'), findsOneWidget);
      expect(find.textContaining('Wife / Spouse'), findsOneWidget);
    });

    testWidgets('tapping Join Household invokes claimMemberProfile and links user', (tester) async {
      bool claimCalled = false;
      String? claimedCode;
      String? claimedUid;

      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/FATIMA01')) {
          return http.Response(
            jsonEncode({
              'household_id': 'hh-123',
              'invite_code': 'FATIMA01',
              'role': 'spouse',
              'target_member_id': 'dep-fatima',
              'target_member_name': 'Fatima',
              'is_valid': true,
            }),
            200,
          );
        }
        if (request.url.path.contains('/claim') && request.method == 'POST') {
          claimCalled = true;
          claimedCode = request.url.pathSegments[2];
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          claimedUid = body['user_id'] as String?;
          return http.Response(
            jsonEncode({
              'status': 'success',
              'household_id': 'hh-123',
              'user_id': claimedUid,
              'linked_member_id': 'dep-fatima',
            }),
            200,
          );
        }
        return http.Response('{"error": "not found"}', 404);
      });

      final baseClient = BaseApiClient(client: mockClient);
      final budgetClient = BudgetApiClient(baseClient: baseClient);
      final apiService = ApiService(budget: budgetClient);

      final budgetProvider = BudgetProvider();
      final txProvider = TransactionProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<BudgetProvider>.value(value: budgetProvider),
            ChangeNotifierProvider<TransactionProvider>.value(value: txProvider),
          ],
          child: MaterialApp(
            localizationsDelegates: const [AppLocalizationsDelegate()],
            supportedLocales: const [Locale('en'), Locale('ar'), Locale('ur')],
            locale: const Locale('en'),
            home: HouseholdScreen(
              apiService: apiService,
              destinationBuilder: (_) => const Scaffold(body: Text('Joined Dashboard Test')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Join tab
      await tester.tap(find.byType(Tab).last);
      await tester.pumpAndSettle();

      // Enter 8-character invite code
      final codeInput = find.byType(TextField).last;
      await tester.enterText(codeInput, 'FATIMA01');
      await tester.pumpAndSettle();

      // Tap Join Household button
      final joinBtn = find.widgetWithText(ElevatedButton, 'Join Household');
      await tester.tap(joinBtn);
      await tester.pumpAndSettle();

      expect(claimCalled, isTrue);
      expect(claimedCode, equals('FATIMA01'));
      expect(claimedUid, isNotNull);
      expect(find.text('Joined Dashboard Test'), findsOneWidget);
    });
  });
}
