import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/services/api/base_api_client.dart';
import 'package:budget_tracker/services/api/budget_api_client.dart';
import 'package:budget_tracker/services/api_service.dart';

void main() {
  group('Manual Household Members & Claim Models', () {
    test('HouseholdDependent parses linkedUserId, isClaimed, isSpouse, isPeer, isChild', () {
      final unlinkedWife = HouseholdDependent.fromMap({
        'id': 'dep-wife-1',
        'household_id': 'hh-1',
        'name': 'Fatima',
        'relationship': 'spouse',
        'avatar_icon': 'wife',
        'monthly_allowance': 1500.0,
        'linked_user_id': null,
      });

      expect(unlinkedWife.name, equals('Fatima'));
      expect(unlinkedWife.isClaimed, isFalse);
      expect(unlinkedWife.isSpouse, isTrue);
      expect(unlinkedWife.isPeer, isFalse);
      expect(unlinkedWife.isChild, isFalse);
      expect(unlinkedWife.monthlyAllowance, equals(1500.0));

      final linkedRoommate = HouseholdDependent.fromMap({
        'id': 'dep-peer-2',
        'household_id': 'hh-1',
        'name': 'Tariq',
        'relationship': 'roommate',
        'avatar_icon': 'roommate',
        'monthly_allowance': 0.0,
        'linked_user_id': 'usr-tariq-live',
      });

      expect(linkedRoommate.isClaimed, isTrue);
      expect(linkedRoommate.linkedUserId, equals('usr-tariq-live'));
      expect(linkedRoommate.isPeer, isTrue);
      expect(linkedRoommate.isSpouse, isFalse);
      expect(linkedRoommate.isChild, isFalse);

      final child = HouseholdDependent.fromMap({
        'id': 'dep-child-3',
        'household_id': 'hh-1',
        'name': 'Zaid',
        'relationship': 'child',
        'avatar_icon': 'child',
        'monthly_allowance': 100.0,
      });

      expect(child.isChild, isTrue);
      expect(child.isSpouse, isFalse);
      expect(child.isPeer, isFalse);
      expect(child.isClaimed, isFalse);

      // Verify serialization retains linked_user_id
      final serialized = linkedRoommate.toMap();
      expect(serialized['linked_user_id'], equals('usr-tariq-live'));
      expect(serialized['relationship'], equals('roommate'));
    });

    test('HouseholdInvite parses targetMemberId and targetMemberName', () {
      final invite = HouseholdInvite.fromMap({
        'id': 'inv-1',
        'household_id': 'hh-1',
        'invite_code': 'WIFECLAIM',
        'role': 'spouse',
        'target_member_id': 'dep-wife-1',
        'target_member_name': 'Fatima',
      });

      expect(invite.targetMemberId, equals('dep-wife-1'));
      expect(invite.targetMemberName, equals('Fatima'));
      expect(invite.isSpouse, isTrue);

      final map = invite.toMap();
      expect(map['target_member_id'], equals('dep-wife-1'));
      expect(map['target_member_name'], equals('Fatima'));
    });
  });

  group('BudgetApiClient Manual Members & Claim Endpoints', () {
    test('createHouseholdDependent sends relationship and monthlyAllowance', () async {
      String? requestBody;
      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/dependents') && request.method == 'POST') {
          requestBody = request.body;
          return http.Response(
            jsonEncode({
              'status': 'success',
              'dependent': {
                'id': 'dep-new-1',
                'household_id': 'hh-100',
                'name': 'Fatima',
                'avatar_icon': 'wife',
                'relationship': 'spouse',
                'monthly_allowance': 2000.0,
                'linked_user_id': null,
              }
            }),
            200,
          );
        }
        return http.Response('{"error": "not found"}', 404);
      });

      final baseClient = BaseApiClient(client: mockClient);
      final apiClient = BudgetApiClient(baseClient: baseClient);

      final created = await apiClient.createHouseholdDependent(
        householdId: 'hh-100',
        name: 'Fatima',
        avatarIcon: 'wife',
        relationship: 'spouse',
        monthlyAllowance: 2000.0,
      );

      expect(created, isNotNull);
      expect(created!.name, equals('Fatima'));
      expect(created.relationship, equals('spouse'));
      expect(created.monthlyAllowance, equals(2000.0));
      expect(created.isClaimed, isFalse);

      final decodedReq = jsonDecode(requestBody!) as Map<String, dynamic>;
      expect(decodedReq['name'], equals('Fatima'));
      expect(decodedReq['relationship'], equals('spouse'));
      expect(decodedReq['monthly_allowance'], equals(2000.0));
    });

    test('createRoleInvite with targetMemberId sends target_member_id in payload', () async {
      String? requestBody;
      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/invites') && request.method == 'POST') {
          requestBody = request.body;
          return http.Response(
            jsonEncode({
              'household_id': 'hh-100',
              'invite_code': 'CLAIM99',
              'role': 'spouse',
              'target_member_id': 'dep-fatima',
            }),
            200,
          );
        }
        return http.Response('{"error": "not found"}', 404);
      });

      final baseClient = BaseApiClient(client: mockClient);
      final apiClient = BudgetApiClient(baseClient: baseClient);

      final invite = await apiClient.createRoleInvite(
        householdId: 'hh-100',
        role: 'spouse',
        targetMemberId: 'dep-fatima',
      );

      expect(invite.inviteCode, equals('CLAIM99'));
      expect(invite.targetMemberId, equals('dep-fatima'));

      final decodedReq = jsonDecode(requestBody!) as Map<String, dynamic>;
      expect(decodedReq['target_member_id'], equals('dep-fatima'));
      expect(decodedReq['role'], equals('spouse'));
    });

    test('claimMemberProfile posts user_id to claim endpoint', () async {
      String? requestBody;
      final mockClient = MockClient((request) async {
        if (request.url.path == '/households/invites/CLAIM99/claim' && request.method == 'POST') {
          requestBody = request.body;
          return http.Response(
            jsonEncode({
              'status': 'success',
              'household_id': 'hh-100',
              'user_id': 'usr-fatima-live',
              'linked_member_id': 'dep-fatima',
              'financial_role': 'spouse',
            }),
            200,
          );
        }
        return http.Response('{"error": "not found"}', 404);
      });

      final baseClient = BaseApiClient(client: mockClient);
      final apiClient = BudgetApiClient(baseClient: baseClient);

      final claimRes = await apiClient.claimMemberProfile(
        inviteCode: 'CLAIM99',
        userId: 'usr-fatima-live',
      );

      expect(claimRes['status'], equals('success'));
      expect(claimRes['linked_member_id'], equals('dep-fatima'));
      expect(claimRes['financial_role'], equals('spouse'));

      final decodedReq = jsonDecode(requestBody!) as Map<String, dynamic>;
      expect(decodedReq['user_id'], equals('usr-fatima-live'));
    });

    test('ApiService forwards createDependent and claimMemberProfile', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/claim')) {
          return http.Response(
            jsonEncode({
              'status': 'success',
              'linked_member_id': 'dep-123',
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'status': 'success',
            'dependent': {
              'id': 'dep-123',
              'household_id': 'hh-1',
              'name': 'Huda',
              'relationship': 'spouse',
              'monthly_allowance': 1200.0,
            }
          }),
          200,
        );
      });

      final baseClient = BaseApiClient(client: mockClient);
      final budgetClient = BudgetApiClient(baseClient: baseClient);
      final apiService = ApiService(budget: budgetClient);

      final dep = await apiService.createDependent(
        'hh-1',
        'Huda',
        relationship: 'spouse',
        monthlyAllowance: 1200.0,
      );
      expect(dep?.name, equals('Huda'));

      final claim = await apiService.claimMemberProfile('CLAIM123', 'usr-huda');
      expect(claim['status'], equals('success'));
    });
  });
}
