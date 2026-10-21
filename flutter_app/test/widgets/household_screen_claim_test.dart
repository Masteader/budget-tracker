import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:convert';
import 'dart:io' show SocketException;

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
              joinHandler: (code) async => {'id': 'hh-123', 'name': 'Household'},
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

  // FABLE-DB-01: an existing member cannot take an invite of their household;
  // the server's reason is shown instead of a generic failure.
  group('HouseholdScreen join refusals', () {
    Future<void> pumpJoin(
      WidgetTester tester, {
      required MockClient client,
      required Future<Map<String, dynamic>> Function(String code) joinHandler,
      String code = 'FATIMA01',
    }) async {
      final apiService = ApiService(budget: BudgetApiClient(baseClient: BaseApiClient(client: client)));
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<BudgetProvider>.value(value: BudgetProvider()),
            ChangeNotifierProvider<TransactionProvider>.value(value: TransactionProvider()),
          ],
          child: MaterialApp(
            localizationsDelegates: const [AppLocalizationsDelegate()],
            supportedLocales: const [Locale('en'), Locale('ar'), Locale('ur')],
            locale: const Locale('en'),
            home: HouseholdScreen(
              apiService: apiService,
              joinHandler: joinHandler,
              destinationBuilder: (_) => const Scaffold(body: Text('Joined Dashboard Test')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Tab).last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, code);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Join Household'));
      await tester.pumpAndSettle();
    }

    MockClient inviteClient({http.Response Function(http.Request request)? onClaim, bool targeted = true}) =>
        MockClient((request) async {
          if (request.url.path.contains('/claim') && request.method == 'POST') {
            return onClaim?.call(request) ?? http.Response(jsonEncode({'status': 'success'}), 200);
          }
          if (request.url.path.endsWith('/FATIMA01')) {
            return http.Response(
              jsonEncode({
                'invite_code': 'FATIMA01',
                'role': 'spouse',
                'target_member_id': targeted ? 'dep-fatima' : null,
                'target_member_name': targeted ? 'Fatima' : null,
                'is_valid': true,
              }),
              200,
            );
          }
          return http.Response('{"error": "not found"}', 404);
        });

    testWidgets('join_household_by_code already_member is shown, nothing is joined', (tester) async {
      await pumpJoin(
        tester,
        client: inviteClient(targeted: false),
        joinHandler: (_) async => {
          'success': false,
          'error': 'You are already a member of this household',
          'code': 'already_member',
        },
      );

      expect(find.text('You are already a member of this household.'), findsOneWidget);
      expect(find.text('Joined Dashboard Test'), findsNothing);
      expect(find.textContaining('Exception'), findsNothing);
    });

    testWidgets('a claim refused with 400 shows the server reason and stops before joining', (tester) async {
      var joinCalls = 0;
      await pumpJoin(
        tester,
        client: inviteClient(
          onClaim: (_) => http.Response(jsonEncode({'detail': 'Invalid, expired, or already used invite code'}), 400),
        ),
        joinHandler: (_) async {
          joinCalls++;
          return {'id': 'hh-123', 'name': 'Household'};
        },
      );

      expect(joinCalls, 0);
      expect(find.text('Invalid, expired, or already used invite code'), findsOneWidget);
      expect(find.text('Joined Dashboard Test'), findsNothing);
    });

    testWidgets('a claim refused because the user is already a member is localized', (tester) async {
      await pumpJoin(
        tester,
        client: inviteClient(
          onClaim: (_) => http.Response(jsonEncode({'detail': 'You are already a member of this household'}), 400),
        ),
        joinHandler: (_) async => {'id': 'hh-123', 'name': 'Household'},
      );

      expect(find.text('You are already a member of this household.'), findsOneWidget);
      expect(find.text('Joined Dashboard Test'), findsNothing);
    });

    testWidgets('a claim that never reached the server still lets the join decide', (tester) async {
      await pumpJoin(
        tester,
        client: inviteClient(onClaim: (_) => throw const SocketException('offline')),
        joinHandler: (_) async => {'id': 'hh-123', 'name': 'Household'},
      );

      expect(find.text('Joined Dashboard Test'), findsOneWidget);
    });
  });
}
