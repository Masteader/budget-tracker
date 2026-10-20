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
