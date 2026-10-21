// Join/claim refusals keep the server's reason (FABLE-DB-01: an existing
// member cannot take an invite of their own household).
import 'package:budget_tracker/services/household_join.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('checkHouseholdJoinResult returns the household or throws the refusal', () {
    expect(checkHouseholdJoinResult({'id': 'hh', 'name': 'Home', 'success': true})['id'], 'hh');

    expect(
      () => checkHouseholdJoinResult({
        'success': false,
        'error': 'You are already a member of this household',
        'code': 'already_member',
      }),
      throwsA(isA<HouseholdJoinException>()
          .having((e) => e.code, 'code', 'already_member')
          .having((e) => e.isAlreadyMember, 'isAlreadyMember', isTrue)
          .having((e) => e.message, 'message', 'You are already a member of this household')),
    );
    expect(
      () => checkHouseholdJoinResult({'success': false, 'error': 'Invite code has expired'}),
      throwsA(isA<HouseholdJoinException>().having((e) => e.isAlreadyMember, 'isAlreadyMember', isFalse)),
    );
    expect(() => checkHouseholdJoinResult(null), throwsA(isA<HouseholdJoinException>()));
  });

  test('checkInviteClaimResponse throws only for a 400 refusal', () {
    expect(
      () => checkInviteClaimResponse({
        'status': 'error',
        'status_code': 400,
        'detail': 'You are already a member of this household',
        'message': 'You are already a member of this household',
      }),
      throwsA(isA<HouseholdJoinException>().having((e) => e.isAlreadyMember, 'isAlreadyMember', isTrue)),
    );
    // Network failures and server errors fall through to the join call.
    checkInviteClaimResponse({'status': 'error', 'message': 'offline', 'network_error': true});
    checkInviteClaimResponse({'status': 'error', 'status_code': 500, 'message': 'boom'});
    checkInviteClaimResponse({'status': 'success'});
  });
}
