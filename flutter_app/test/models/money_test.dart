import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/models/money.dart';

void main() {
  group('MOB-14 parseMoneyInput', () {
    const cases = <String, double?>{
      '150': 150.0,
      '150.5': 150.5,
      ' 1,250.75 ': 1250.75,
      '١٥٠': 150.0, // Arabic-Indic
      '١٥٠٫٥٠': 150.5, // Arabic decimal separator
      '١٬٢٥٠٫٧٥': 1250.75, // Arabic thousands separator
      '۱۵۰': 150.0, // Extended Arabic-Indic (Urdu/Persian keyboards)
      '‏١٥٠ ر.س': 150.0, // RTL mark + Saudi riyal symbol
      'SAR 99.99': 99.99,
      '12.346': 12.35, // rounded to halalas
      '0.1': 0.1,
      '.5': 0.5,
      '-20': -20.0,
      '': null,
      'abc': null,
      '1.2.3': null,
      '12abc': null,
    };
    cases.forEach((input, expected) {
      test('"$input" -> $expected', () {
        expect(parseMoneyInput(input), expected);
      });
    });

    test('legacy double.tryParse silently rejected Arabic digits (the bug)', () {
      expect(double.tryParse('١٥٠'), isNull);
    });

    test('normalizeDigits keeps non-digit text', () {
      expect(normalizeDigits('فاتورة ١٢'), 'فاتورة 12');
    });
  });
}
