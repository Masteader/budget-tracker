// Who the app shows a wife's allowance to, and who it offers to set it (owner
// decision 2026-11-06): she herself, her husband, an admin who is not a wife.
// The dashboard's shortcut names a figure only the caller reads.
import 'package:budget_tracker/models/nafaqah.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _wife(String id, double allocated) => {
      'id': id,
      'display_name': id,
      'allowance': {'cycle_key': '2026-11', 'is_set': true, 'allocated': allocated, 'spent': 0, 'remaining': allocated},
    };

NafaqahSummary _summary(String role, String me, {bool canSet = false, List<String> wives = const [], List<String> allowanceOnly = const []}) =>
    NafaqahSummary.fromMap({
      'mode': 'family_nafaqah',
      'caller_role': role,
      'caller_user_id': me,
      'wives': [for (final w in wives) _wife(w, 700)],
      'allowance_wives': [for (final w in allowanceOnly) _wife(w, 700)],
      'can_set_allowance': canSet,
    });

void main() {
  const sara = NafaqahWife(id: 'sara', displayName: 'Sara');
  const huda = NafaqahWife(id: 'huda', displayName: 'Huda');

  test('a wife sees her own only and never sets one', () {
    final s = _summary('wife', 'sara', canSet: true, wives: ['sara']);
    expect(s.canSeeAllowanceOf(sara), isTrue);
    expect(s.canSeeAllowanceOf(huda), isFalse);
    expect(s.canSetAllowanceFor(sara), isFalse);
    expect(s.canSetAllowanceFor(huda), isFalse);
    expect(s.primaryWifeAllowance, 700);
  });

  test('the husband sees and sets every wife\'s', () {
    final s = _summary('husband', 'ahmed', canSet: true, wives: ['sara', 'huda']);
    expect(s.canSeeAllowanceOf(sara) && s.canSeeAllowanceOf(huda), isTrue);
    expect(s.canSetAllowanceFor(sara) && s.canSetAllowanceFor(huda), isTrue);
    expect(s.primaryWifeAllowance, 700);
  });

  test('an admin who is not a wife sees and sets every wife\'s', () {
    final s = _summary('member', 'nora', canSet: true, allowanceOnly: ['sara']);
    expect(s.canSeeAllowanceOf(sara), isTrue);
    expect(s.canSetAllowanceFor(sara), isTrue);
    expect(s.primaryWifeAllowance, 700);
  });

  test('she is never offered her own, even under a role a server got wrong', () {
    final s = _summary('member', 'sara', canSet: true, wives: ['sara']);
    expect(s.canSetAllowanceFor(sara), isFalse);
    expect(s.canSetAllowanceFor(huda), isTrue);
  });

  test('an ordinary member sees no figure, whatever a server sends', () {
    final s = _summary('member', 'fahad', wives: ['sara'], allowanceOnly: ['huda']);
    expect(s.canSeeAllowanceOf(sara), isFalse);
    expect(s.canSeeAllowanceOf(huda), isFalse);
    expect(s.canSetAllowanceFor(sara), isFalse);
    expect(s.primaryWifeAllowance, isNull);
  });
}
