// Household type (chosen at creation, changed by an admin) and members'
// financial roles: the app side of the owner decisions, against the backend
// contract (create_household_and_claim(p_name, p_household_type),
// PUT /households/{id}/type, PUT .../members/{user_id}/financial-role).
import 'dart:convert';

import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/models/household_membership.dart';
import 'package:budget_tracker/models/nafaqah.dart';
import 'package:budget_tracker/services/api/base_api_client.dart';
import 'package:budget_tracker/services/api/household_roles_api_client.dart';
import 'package:budget_tracker/services/household_join.dart';
import 'package:budget_tracker/services/nafaqah_write_errors.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

void main() {
  group('createHouseholdAndClaim', () {
    test('sends the chosen type', () async {
      final calls = <Map<String, dynamic>>[];
      final hh = await createHouseholdAndClaim(
        name: 'Home',
        householdType: kHouseholdTypeRoommates,
        rpc: (fn, params) async {
          expect(fn, 'create_household_and_claim');
          calls.add(params);
          return {'id': 'hh-1', 'name': 'Home', 'invite_code': 'ABCD1234'};
        },
      );
      expect(hh['id'], 'hh-1');
      expect(calls, [
        {'p_name': 'Home', 'p_household_type': 'roommates'},
      ]);
    });

    test('an older database without p_household_type is called again without it', () async {
      final calls = <Map<String, dynamic>>[];
      final hh = await createHouseholdAndClaim(
        name: 'Home',
        householdType: kHouseholdTypeFamily,
        rpc: (fn, params) async {
          calls.add(params);
          if (params.containsKey('p_household_type')) {
            throw const PostgrestException(
              message: 'Could not find the function public.create_household_and_claim(p_household_type, p_name) in the schema cache',
              code: 'PGRST202',
            );
          }
          return {'id': 'hh-2', 'name': 'Home'};
        },
      );
      expect(hh['id'], 'hh-2');
      expect(calls.last, {'p_name': 'Home'});
    });

    test('other refusals are not retried', () async {
      var count = 0;
      await expectLater(
        createHouseholdAndClaim(
          name: 'Home',
          householdType: kHouseholdTypeFamily,
          rpc: (fn, params) async {
            count++;
            throw const PostgrestException(message: 'permission denied', code: '42501');
          },
        ),
        throwsA(isA<PostgrestException>()),
      );
      expect(count, 1);
    });

    test('a role mismatch from the join/claim RPCs is recognised', () {
      expect(
        () => checkHouseholdJoinResult({'success': false, 'error': 'x', 'code': 'invite_role_mismatch'}),
        throwsA(isA<HouseholdJoinException>().having((e) => e.isRoleMismatch, 'isRoleMismatch', isTrue)),
      );
    });
  });

  group('roster contract', () {
    test('parses household_type, permissions and assignable roles', () {
      final roster = HouseholdRoster.fromMap({
        'household_id': 'hh',
        'household_type': 'family',
        'caller_role': 'admin',
        'can_change_household_type': true,
        'can_set_financial_roles': true,
        'assignable_financial_roles': ['spouse', 'family_member', 'dependent'],
        'nafaqah_provider_user_id': 'h',
        'members': [
          {'user_id': 'h', 'financial_role': 'provider', 'is_nafaqah_provider': true},
          {'user_id': 's', 'financial_role': 'family_member'},
        ],
      });
      expect(roster.householdType, 'family');
      expect(roster.mayChangeHouseholdType, isTrue);
      expect(roster.maySetFinancialRoles, isTrue);
      expect(roster.financialRoleOptions(roster.members[1]), ['spouse', 'family_member', 'dependent']);
      expect(roster.financialRoleOptions(roster.members[0]), ['family_member', 'dependent'],
          reason: 'never offer "wife" for the Nafaqah provider');
    });

    test('a roommates household offers only roommate; the server flags win', () {
      final roster = HouseholdRoster.fromMap({
        'household_id': 'hh',
        'household_type': 'roommates',
        'caller_role': 'admin',
        'can_change_household_type': false,
        'members': [
          {'user_id': 'a', 'financial_role': 'peer'},
        ],
      });
      expect(roster.financialRoleOptions(roster.members.single), ['peer']);
      expect(roster.mayChangeHouseholdType, isFalse);
      expect(roster.maySetFinancialRoles, isTrue, reason: 'not sent: admins');
    });
  });

  group('HouseholdRolesApiClient', () {
    late http.Request last;
    HouseholdRolesApiClient client(int status, Object body) => HouseholdRolesApiClient(
          baseClient: BaseApiClient(
            authTokenProvider: () => 'jwt',
            client: MockClient((request) async {
              last = request;
              return http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});
            }),
          ),
        );

    test('PUT /households/{id}/type', () async {
      final stored = await client(200, {'status': 'success', 'household_id': 'hh', 'household_type': 'roommates'})
          .setHouseholdType('hh', 'roommates');
      expect(stored, 'roommates');
      expect(last.method, 'PUT');
      expect(last.url.path, '/households/hh/type');
      expect(jsonDecode(last.body), {'household_type': 'roommates'});
    });

    test('a blocked type change carries the server code and message', () async {
      await expectLater(
        client(409, {
          'detail': {'code': 'type_change_blocked', 'message': 'A wife is a member: remove her first.'},
        }).setHouseholdType('hh', 'roommates'),
        throwsA(isA<HouseholdRolesApiException>()
            .having((e) => e.code, 'code', 'type_change_blocked')
            .having((e) => e.serverMessage, 'serverMessage', 'A wife is a member: remove her first.')),
      );
    });

    test('PUT .../members/{user_id}/financial-role', () async {
      final stored = await client(200, {
        'status': 'success',
        'household_id': 'hh',
        'user_id': 'u1',
        'financial_role': 'dependent',
      }).setFinancialRole('hh', 'u1', 'dependent');
      expect(stored, 'dependent');
      expect(last.url.path, '/households/hh/members/u1/financial-role');
      expect(jsonDecode(last.body), {'financial_role': 'dependent'});
    });

    test('financial role refusals map to codes', () async {
      Future<String> codeOf(int status, Object body) async {
        try {
          await client(status, body).setFinancialRole('hh', 'u1', 'spouse');
        } on HouseholdRolesApiException catch (e) {
          return e.code;
        }
        return 'none';
      }

      expect(await codeOf(403, {'detail': 'Not an admin'}), 'forbidden');
      expect(await codeOf(404, {'detail': 'Not a member'}), 'not_found');
      expect(await codeOf(422, {'detail': {'code': 'financial_role_not_allowed'}}), 'invalid');
      expect(await codeOf(409, {'detail': {'code': 'provider_is_spouse'}}), 'provider_is_spouse');
      expect(await codeOf(409, {'detail': {'code': 'spouse_has_ledger'}}), 'spouse_has_ledger');
    });
  });

  group('classification refusals use the implemented codes', () {
    test('API 403 nafaqah_classification_forbidden and PostgREST hint nafaqah_class_not_allowed', () {
      expect(
        nafaqahWriteRefusalOf({
          'status': 'error',
          'status_code': 403,
          'detail': {'code': 'nafaqah_classification_forbidden', 'message': 'x'},
        }),
        NafaqahWriteRefusal.notClassifier,
      );
      expect(
        nafaqahWriteRefusalOf(const PostgrestException(message: 'x', code: '42501', hint: 'nafaqah_class_not_allowed')),
        NafaqahWriteRefusal.notClassifier,
      );
    });

    test('an installment refused by the ledger guard (ApiRequestException 409)', () {
      expect(
        nafaqahWriteRefusalOf(const ApiRequestException('x', statusCode: 409, code: 'ledger_would_be_overpaid')),
        NafaqahWriteRefusal.ledgerWouldBeOverpaid,
      );
    });

    testWidgets('oversized receipt photos (413) are explained', (tester) async {
      String? text;
      await tester.pumpWidget(Localizations(
        locale: const Locale('en'),
        delegates: const [AppLocalizationsDelegate(), DefaultWidgetsLocalizations.delegate],
        child: Builder(builder: (context) {
          text = expenseApiErrorText(context, {'status': 'error', 'status_code': 413, 'message': 'Payload Too Large'});
          return const SizedBox();
        }),
      ));
      await tester.pump();
      expect(text, contains('12 MP'));
    });
  });

  test('the Nafaqah summary carries household_type', () {
    expect(NafaqahSummary.fromMap({'mode': 'not_family', 'household_type': 'roommates'}).householdType, 'roommates');
  });
}
