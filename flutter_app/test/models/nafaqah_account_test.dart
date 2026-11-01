import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/models/nafaqah_account.dart';

void main() {
  group('accountForNafaqahClass tests', () {
    test('wife_personal returns null regardless of accountId', () {
      expect(accountForNafaqahClass('wife_personal', 'acc-123'), isNull);
    });

    test('wife_reimbursable returns null regardless of accountId', () {
      expect(accountForNafaqahClass('wife_reimbursable', 'acc-456'), isNull);
    });

    test('null nafaqahClass returns the given accountId', () {
      expect(accountForNafaqahClass(null, 'acc-789'), equals('acc-789'));
      expect(accountForNafaqahClass(null, null), isNull);
    });

    test('any other nafaqahClass or standard expense returns given accountId', () {
      expect(accountForNafaqahClass('standard', 'acc-999'), equals('acc-999'));
    });
  });
}

