import 'package:budget_tracker/models/nafaqah.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('classifyNafaqah (no spousal split; only the wife\'s own money is classified)', () {
    final cases = <(String?, String, String, String?)>[
      ('wife', 'me', 'me', kWifePersonal),
      ('wife', 'me', 'both', kWifeReimbursable),
      ('wife', 'me', 'sarah', kWifeReimbursable),
      ('wife', 'me', 'partner', kWifeReimbursable),
      ('wife', 'partner', 'both', null),
      ('wife', 'partner', 'me', null),
      ('husband', 'me', 'both', null),
      ('husband', 'me', 'partner', null),
      ('husband', 'partner', 'both', kWifeReimbursable),
      ('husband', 'partner', 'partner', kWifePersonal),
      ('member', 'me', 'both', null),
      (null, 'me', 'me', null),
    ];
    for (final c in cases) {
      test('${c.$1}/${c.$2}/${c.$3} -> ${c.$4}', () {
        expect(classifyNafaqah(c.$1, c.$2, c.$3), c.$4);
      });
    }
  });

  test('NafaqahSummary parses the family summary', () {
    final s = NafaqahSummary.fromMap({
      'mode': 'family_nafaqah',
      'caller_role': 'wife',
      'caller_user_id': 'w2',
      'cycle_key': '2026-11',
      'husband': {'id': 'h', 'display_name': 'Ahmed'},
      'wives': [
        {'id': 'w1', 'reimbursement': {'outstanding': 10}, 'allowance': {'allocated': 100, 'spent': 150, 'remaining': -50}},
        {'id': 'w2', 'reimbursement': {'outstanding': 20.5}, 'allowance': {'is_set': true, 'allocated': 300}},
      ],
      'can_set_allowance': false,
      'can_record_reimbursement': true,
    });
    expect(s.isFamily, isTrue);
    expect(s.husbandName, 'Ahmed');
    expect(s.primaryWife!.id, 'w2');
    expect(s.primaryWife!.reimbursement.outstanding, 20.5);
    expect(s.wives.first.allowance.isOverspent, isTrue);
    expect(s.wives.first.allowance.usedFraction, 1.0);
  });

  test('a household without wives is not family mode', () {
    expect(NafaqahSummary.fromMap({'mode': 'not_family', 'wives': []}).isFamily, isFalse);
    expect(const NafaqahSummary().primaryWife, isNull);
  });

  test('NafaqahApiException maps API errors', () {
    expect(
      NafaqahApiException.fromResponse({
        'status': 'error',
        'status_code': 409,
        'detail': {'code': 'overpayment', 'message': 'x'},
      }).code,
      'overpayment',
    );
    expect(NafaqahApiException.fromResponse({'status': 'error', 'status_code': 403}).code, 'forbidden');
    expect(NafaqahApiException.fromResponse({'status': 'error', 'status_code': 422}).code, 'invalid');
    expect(NafaqahApiException.fromResponse({'status': 'error', 'message': 'offline'}).code, 'network');
  });

  test('NafaqahSummary parses the explicit provider fields', () {
    final s = NafaqahSummary.fromMap({
      'mode': 'family_nafaqah',
      'caller_role': 'member',
      'husband': null,
      'wives': [
        {'id': 'w1'},
      ],
      'provider_user_id': null,
      'needs_provider': true,
      'can_set_provider': true,
    });
    expect(s.providerUserId, isNull);
    expect(s.needsProvider, isTrue);
    expect(s.canSetProvider, isTrue);
    expect(s.isFamily, isTrue, reason: 'still a family: the card explains the missing provider');

    final legacy = NafaqahSummary.fromMap({'mode': 'family_nafaqah', 'wives': [{'id': 'w1'}]});
    expect(legacy.needsProvider, isFalse);
    expect(legacy.canSetProvider, isFalse);

    final set = NafaqahSummary.fromMap({
      'mode': 'family_nafaqah',
      'husband': {'id': 'h'},
      'wives': [{'id': 'w1'}],
      'provider_user_id': 'h',
      'needs_provider': false,
    });
    expect(set.providerUserId, 'h');
  });

  test('ReimbursementBalance parses overpaid (repaid more than advanced)', () {
    final b = ReimbursementBalance.fromMap({'gross_advanced': 100, 'reimbursed': 200, 'outstanding': 0, 'overpaid': 100});
    expect(b.overpaid, 100);
    expect(b.isOverpaid, isTrue);
    expect(b.isSettled, isTrue);
    final ok = ReimbursementBalance.fromMap({'gross_advanced': 300, 'reimbursed': 100, 'outstanding': 200});
    expect(ok.overpaid, 0);
    expect(ok.isOverpaid, isFalse);
  });

  test('NafaqahApiException maps the ledger guard and missing provider refusals', () {
    expect(
      NafaqahApiException.fromResponse({
        'status': 'error',
        'status_code': 409,
        'detail': {'code': 'ledger_would_be_overpaid', 'message': 'x'},
      }).code,
      'ledger_would_be_overpaid',
    );
    expect(
      NafaqahApiException.fromResponse({
        'status': 'error',
        'status_code': 409,
        'detail': {'code': 'no_provider', 'message': 'x'},
      }).code,
      'no_provider',
    );
  });

  test('NafaqahProviderChange parses the PUT provider response', () {
    final c = NafaqahProviderChange.fromMap({
      'status': 'success',
      'household_id': 'hh',
      'provider_user_id': 'u2',
      'previous_provider_user_id': 'u1',
      'summary': {
        'mode': 'family_nafaqah',
        'husband': {'id': 'u2'},
        'wives': [{'id': 'w'}],
        'provider_user_id': 'u2',
        'needs_provider': false,
      },
    });
    expect(c.providerUserId, 'u2');
    expect(c.previousProviderUserId, 'u1');
    expect(c.summary!.husbandId, 'u2');
    expect(NafaqahProviderChange.fromMap({'provider_user_id': 'u2'}).summary, isNull);
  });

  test('NafaqahLedger parses history', () {
    final l = NafaqahLedger.fromMap({
      'balance': {'gross_advanced': 300, 'reimbursed': 100, 'outstanding': 200},
      'history': [
        {'type': 'advance', 'id': 't1', 'amount': 300, 'merchant': 'Panda', 'timestamp': '2026-11-10T09:00:00Z'},
        {'type': 'reimbursement', 'id': 'r1', 'amount': 100, 'payment_method': 'cash'},
      ],
    });
    expect(l.balance.outstanding, 200);
    expect(l.history.first.isAdvance, isTrue);
    expect(l.history.last.paymentMethod, 'cash');
    expect(l.history.last.timestamp, isNull);
  });
}
