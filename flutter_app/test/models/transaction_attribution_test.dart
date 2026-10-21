// FABLE2-APP-01: the app writes and reads attribution exactly like the
// settlement engine. Expected values were produced by running
// ai_service/settlement_engine.py (structured_attribution and
// transaction_attribution) on the same inputs.
import 'package:budget_tracker/models/transaction_attribution.dart';
import 'package:flutter_test/flutter_test.dart';

const _a = 'aaaaaaaa-2222-3333-4444-555555555555';
const _b = '11111111-2222-3333-4444-555555555555';

void main() {
  group('attributionColumns mirrors structured_attribution (no roster)', () {
    final cases = <List<String>, List<String>>{
      ['me', 'both']: ['me', 'household', 'household'],
      ['me', 'me']: ['me', 'individual', _a],
      ['partner', 'partner']: ['partner', 'individual', 'partner'],
      ['me', 'Sarah']: ['me', 'dependent', 'Sarah'],
      ['me', 'children']: ['me', 'dependent', 'children'],
      ['partner', _b]: ['partner', 'individual', _b],
      ['me', 'household']: ['me', 'household', 'household'],
      ['me', 'all_peers']: ['me', 'household', 'household'],
    };
    cases.forEach((input, expected) {
      test('${input[0]} / ${input[1]}', () {
        final cols = attributionColumns(payer: input[0], beneficiary: input[1], creatorId: _a);
        expect([cols.spentBy, cols.beneficiaryType, cols.beneficiaryId], expected);
      });
    });

    test('a known partner is stored as the member id', () {
      final cols = attributionColumns(payer: 'me', beneficiary: 'partner', creatorId: _a, partnerId: _b);
      expect(cols.beneficiaryId, _b);
    });

    test('spent_by is never both or a name', () {
      expect(() => attributionColumns(payer: 'both', beneficiary: 'both'), throwsArgumentError);
      expect(() => attributionColumns(payer: 'Sarah', beneficiary: 'both'), throwsArgumentError);
    });
  });

  group('storedPayerRef mirrors transaction_attribution', () {
    final rows = <String, (Map<String, dynamic>, String)>{
      'manual structured row: payer from the tail': ({
        'source': 'manual', 'spent_by': 'partner', 'beneficiary_type': 'household', 'beneficiary_id': 'household',
        'user_id': _a, 'raw_sms': 'Manual: Dinner | PaidBy: $_b | Beneficiary: household | SpentBy: partner',
      }, _b),
      'manual dependent row': ({
        'source': 'manual', 'spent_by': 'me', 'beneficiary_type': 'dependent', 'beneficiary_id': 'Sarah',
        'user_id': _a, 'raw_sms': 'Manual: Jarir | PaidBy: me | Beneficiary: Sarah | SpentBy: me',
      }, 'me'),
      'chat structured row: payer from spent_by': ({
        'source': 'chat', 'spent_by': 'partner', 'beneficiary_type': 'individual', 'beneficiary_id': _a,
        'raw_sms': 'Chat: X | PaidBy: me | Beneficiary: me',
      }, 'partner'),
      'legacy chat row: the server-authored tag': ({
        'source': 'chat', 'spent_by': 'me', 'beneficiary_id': null,
        'raw_sms': 'Chat: Jarir | PaidBy: me | Beneficiary: me | Items: [1x Jarir (50 SAR)]',
      }, 'me'),
      'legacy chat row naming a member: me': ({
        'source': 'chat', 'spent_by': 'me', 'beneficiary_id': null, 'raw_sms': 'Chat: X | PaidBy: $_b | Beneficiary: both',
      }, 'me'),
      'untagged legacy row: spent_by': ({
        'source': 'manual', 'spent_by': 'partner', 'beneficiary_id': null, 'raw_sms': '',
      }, 'partner'),
    };
    rows.forEach((name, c) {
      test(name, () => expect(storedPayerRef(c.$1), c.$2));
    });
  });

  test('manualAuditNote ends with the tail the server parses, right-anchored', () {
    final note = manualAuditNote(head: 'Manual: A | PaidBy: x | Beneficiary: y | SpentBy: z', payer: _b, beneficiaryId: 'household', spentBy: 'partner');
    final tail = manualTailPattern.firstMatch(note)!;
    expect(tail.group(1), _b);
    expect(tail.group(2), 'household');
    expect(tail.group(3), 'partner');
    // A separator in a dependent name cannot shift the tail.
    final forged = manualAuditNote(head: 'Manual: A', payer: 'me', beneficiaryId: 'Sa|rah', spentBy: 'me');
    expect(manualTailPattern.firstMatch(forged)!.group(2), 'Sa rah');
  });

  test('auditNoteHead drops every attribution tag of an older note', () {
    expect(
      auditNoteHead('Manual: Dinner | PaidBy: $_b | PaidBy: me | Beneficiary: both | SubCategory:  | SpentBy: both', fallback: 'x'),
      'Manual: Dinner',
    );
    expect(auditNoteHead(null, fallback: 'Manual: Panda'), 'Manual: Panda');
  });

  test('HouseholdRelations mirrors counterpart_id', () {
    final pair = HouseholdRelations(memberIds: [_a, _b], rosterComplete: true);
    expect(pair.counterpartOf(_a), _b);
    final three = HouseholdRelations(memberIds: [_a, _b, 'c'], rosterComplete: true);
    expect(three.counterpartOf(_a), isNull);
    final family = HouseholdRelations(memberIds: ['h', 'w', 'son'], husbandId: 'h', wifeIds: ['w'], rosterComplete: true);
    expect(family.counterpartOf('h'), 'w');
    expect(family.counterpartOf('w'), 'h');
    expect(family.counterpartOf('son'), isNull);
    final twoWives = HouseholdRelations(husbandId: 'h', wifeIds: ['w1', 'w2']);
    expect(twoWives.counterpartOf('h'), isNull);
    expect(twoWives.counterpartOf('w2'), 'h');
  });
}
