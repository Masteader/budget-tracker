import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/services/api/base_api_client.dart';
import 'package:budget_tracker/services/api/budget_api_client.dart';

void main() {
  group('Multi-Party Settlement & Role Invite Models', () {
    test('HouseholdInvite parses correctly from map', () {
      final map = {
        'id': 'inv-123',
        'household_id': 'hh-abc',
        'invite_code': 'WIFE2026',
        'role': 'spouse',
        'created_at': '2026-10-15T00:00:00Z',
        'expires_at': '2026-10-22T00:00:00Z',
      };

      final invite = HouseholdInvite.fromMap(map);
      expect(invite.id, equals('inv-123'));
      expect(invite.householdId, equals('hh-abc'));
      expect(invite.inviteCode, equals('WIFE2026'));
      expect(invite.role, equals('spouse'));
      expect(invite.isSpouse, isTrue);
      expect(invite.isPeer, isFalse);
    });

    test('HouseholdDependent parses relationship and monthlyAllowance', () {
      final map = {
        'id': 'dep-1',
        'household_id': 'hh-1',
        'name': 'Sarah',
        'avatar_icon': 'child',
        'relationship': 'daughter',
        'monthly_allowance': 250.0,
      };

      final dep = HouseholdDependent.fromMap(map);
      expect(dep.relationship, equals('daughter'));
      expect(dep.monthlyAllowance, equals(250.0));

      final serialized = dep.toMap();
      expect(serialized['relationship'], equals('daughter'));
      expect(serialized['monthly_allowance'], equals(250.0));
    });

    test('ReimbursementRecordRequest serializes correctly', () {
      const req = ReimbursementRecordRequest(
        householdId: 'hh-1',
        payerId: 'husband-1',
        recipientId: 'wife-1',
        amount: 350.0,
        paymentMethod: 'stc_pay',
        notes: 'Monthly panda reimbursement',
      );

      final jsonMap = req.toMap();
      expect(jsonMap['household_id'], equals('hh-1'));
      expect(jsonMap['payer_id'], equals('husband-1'));
      expect(jsonMap['recipient_id'], equals('wife-1'));
      expect(jsonMap['amount'], equals(350.0));
      expect(jsonMap['payment_method'], equals('stc_pay'));
      expect(jsonMap['notes'], equals('Monthly panda reimbursement'));
    });

    test('SettlementV2Summary parses Family Nafaqah payload', () {
      final data = {
        'mode': 'family_nafaqah',
        'family_summary': {
          'wife_reimbursement_owed': 350.0,
          'spent_on_wife': 120.0,
          'spent_on_children': 450.0,
          'family_general_total': 800.0,
        },
        'pairwise_debts': [],
        'simplified_debts': [],
        'roommate_balances': {},
      };

      final summary = SettlementV2Summary.fromMap(data);
      expect(summary.mode, equals('family_nafaqah'));
      expect(summary.isFamilyMode, isTrue);
      expect(summary.familySummary, isNotNull);
      expect(summary.familySummary!.wifeReimbursementOwed, equals(350.0));
      expect(summary.familySummary!.spentOnChildren, equals(450.0));
    });

    test('SettlementV2Summary parses Multi-Roommate pairwise and simplified debts', () {
      final data = {
        'mode': 'multi_roommate',
        'family_summary': null,
        'pairwise_debts': [
          {
            'from_id': 'omar',
            'to_id': 'ahmed',
            'from_name': 'Omar',
            'to_name': 'Ahmed',
            'amount': 100.0,
          },
          {
            'from_id': 'ibrahim',
            'to_id': 'ahmed',
            'from_name': 'Ibrahim',
            'to_name': 'Ahmed',
            'amount': 200.0,
          },
        ],
        'simplified_debts': [
          {
            'from_id': 'omar',
            'to_id': 'ahmed',
            'from_name': 'Omar',
            'to_name': 'Ahmed',
            'amount': 100.0,
          },
        ],
        'roommate_balances': {
          'ahmed': 300.0,
          'omar': -100.0,
          'ibrahim': -200.0,
        },
      };

      final summary = SettlementV2Summary.fromMap(data);
      expect(summary.mode, equals('multi_roommate'));
      expect(summary.isRoommateMode, isTrue);
      expect(summary.pairwiseDebts.length, equals(2));
      expect(summary.simplifiedDebts.length, equals(1));
      expect(summary.roommateBalances['ahmed'], equals(300.0));
    });
  });

  group('BudgetApiClient Multi-Party Endpoints', () {
    test('createRoleInvite issues POST /households/:id/invites', () async {
      final mockClient = MockClient((request) async {
        if (request.method == 'POST' && request.url.path.endsWith('/households/hh-1/invites')) {
          final body = jsonDecode(request.body);
          expect(body['role'], equals('spouse'));
          return http.Response(
            jsonEncode({
              'invite_code': 'ABCD1234',
              'role': 'spouse',
              'household_id': 'hh-1',
              'expires_at': '2026-10-22T00:00:00Z',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final base = BaseApiClient(client: mockClient);
      final client = BudgetApiClient(baseClient: base);

      final invite = await client.createRoleInvite(
        householdId: 'hh-1',
        role: 'spouse',
      );

      expect(invite.inviteCode, equals('ABCD1234'));
      expect(invite.role, equals('spouse'));
    });

    test('createRoleInvite throws instead of inventing a code when refused (FR-A-11)', () async {
      final mockClient = MockClient((request) async => http.Response(
            jsonEncode({'detail': 'Forbidden: Admin access required for this household.'}),
            403,
            headers: {'content-type': 'application/json'},
          ));
      final client = BudgetApiClient(baseClient: BaseApiClient(client: mockClient));

      await expectLater(
        client.createRoleInvite(householdId: 'hh-1', role: 'spouse'),
        throwsA(isA<ApiRequestException>().having((e) => e.statusCode, 'statusCode', 403)),
      );
    });

    test('inspectInviteCode issues GET /households/invites/:code', () async {
      final mockClient = MockClient((request) async {
        if (request.method == 'GET' && request.url.path.endsWith('/households/invites/ABCD1234')) {
          return http.Response(
            jsonEncode({
              'invite_code': 'ABCD1234',
              'role': 'peer',
              'household_id': 'hh-1',
              'is_valid': true,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final base = BaseApiClient(client: mockClient);
      final client = BudgetApiClient(baseClient: base);

      final invite = await client.inspectInviteCode(code: 'ABCD1234');
      expect(invite.inviteCode, equals('ABCD1234'));
      expect(invite.role, equals('peer'));
    });

    test('recordReimbursementPayment issues POST /households/:id/reimbursements', () async {
      final mockClient = MockClient((request) async {
        if (request.method == 'POST' && request.url.path.endsWith('/households/hh-1/reimbursements')) {
          final body = jsonDecode(request.body);
          expect(body['amount'], equals(250.0));
          expect(body['payment_method'], equals('stc_pay'));
          return http.Response(
            jsonEncode({
              'status': 'success',
              'transaction_id': 'tx-123',
              'amount': 250.0,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final base = BaseApiClient(client: mockClient);
      final client = BudgetApiClient(baseClient: base);

      final res = await client.recordReimbursementPayment(
        request: const ReimbursementRecordRequest(
          householdId: 'hh-1',
          payerId: 'husband-1',
          recipientId: 'wife-1',
          amount: 250.0,
          paymentMethod: 'stc_pay',
        ),
      );

      expect(res['status'], equals('success'));
      expect(res['transaction_id'], equals('tx-123'));
    });
  });
}
