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

  group('FABLE-LOGIC-09 exact halala rounding (no binary doubles)', () {
    const halalas = <String, int?>{
      '1.005': 101, // 1.005 is 1.00499999... as a double: must still round up
      '0.285': 29, // 0.28499999... as a double
      '2.675': 268,
      '1.004': 100,
      '1.0049': 100, // only the 3rd decimal decides (half-up), no double rounding
      '0.995': 100,
      '٠٫٢٨٥': 29,
      '١٥٠٫٥': 15050,
      '١٬٢٥٠٫٧٥': 125075,
      '1,234,567.891': 123456789,
      '10.': 1000,
      '.005': 1,
      '-1.005': -101,
      '999999999999.99': 99999999999999,
      '1234567890123456': null, // beyond numeric(14,2): rejected, never wrapped
      '1e3': null,
      'NaN': null,
      'Infinity': null,
    };
    halalas.forEach((input, expected) {
      test('"$input" -> $expected halalas', () {
        expect(parseMoneyToHalalas(input), expected);
      });
    });

    test('parseMoneyInput returns the rounded SAR value', () {
      expect(parseMoneyInput('1.005'), 1.01);
      expect(parseMoneyInput('0.285'), 0.29);
      expect(parseMoneyInput('١٥٠٫٥'), 150.50);
      expect(parseMoneyInput('1,250.755'), 1250.76);
    });

    test('negatives are rejected where a positive amount is required', () {
      expect(parseMoneyInput('-20', allowNegative: false), isNull);
      expect(parseMoneyToHalalas('-0.01', allowNegative: false), isNull);
      expect(parseMoneyInput('20', allowNegative: false), 20.0);
      expect(parseMoneyInput('-20'), -20.0, reason: 'balances may be negative');
    });

    test('formatHalalas shows the rounded value with two decimals', () {
      expect(formatHalalas(101), '1.01');
      expect(formatHalalas(29), '0.29');
      expect(formatHalalas(-101), '-1.01');
      expect(formatHalalas(15050), '150.50');
      expect(roundedMoneyText('1.005'), '1.01');
      expect(roundedMoneyText('abc'), isNull);
      expect(roundedMoneyTextIfRounded('1.005'), '1.01');
      expect(roundedMoneyTextIfRounded('٠٫٢٨٥'), '0.29');
      expect(roundedMoneyTextIfRounded('150.5'), isNull, reason: 'nothing rounded away: keep what was typed');
      expect(roundedMoneyTextIfRounded('150'), isNull);
      expect(roundedMoneyTextIfRounded('abc'), isNull);
    });
  });

  // FABLE2-APP-04: "0,5" was read as 5 SAR (the comma dropped as a grouping
  // mark), and "999999999999.995" passed the digit check but rounds to an
  // amount numeric(14,2) cannot hold.
  group('FABLE2-APP-04 decimal comma, strict grouping, cap after rounding', () {
    const cases = <String, double?>{
      '0,5': 0.50,
      '1,5': 1.50,
      '12,5': 12.50,
      '12,50': 12.50,
      '١,٥': 1.50,
      '١٢،٥': 12.50, // Arabic comma as the decimal mark
      ',5': 0.50,
      '1,234': 1234.0,
      '12,345': 12345.0,
      '1,234,567.8': 1234567.80,
      '1,234.56': 1234.56,
      '١٬٢٣٤٫٥٦': 1234.56,
      '١٬٥': null, // the Arabic thousands mark is never a decimal mark
      '1,,2': null,
      '1,2,3': null,
      '12,5.3': null,
      '1234,567': null, // a first group has at most three digits
      ',500': null,
      '1,2345': null,
      '١٢٣٬٫٥': null,
      '999999999999.99': 999999999999.99,
      '999999999999.995': null,
      '999,999,999,999.994': 999999999999.99,
    };
    cases.forEach((input, expected) {
      test('"$input" -> $expected', () {
        expect(parseMoneyInput(input), expected);
      });
    });

    test('a decimal comma is shown back rounded like a decimal point', () {
      expect(roundedMoneyTextIfRounded('1,5'), isNull);
      expect(roundedMoneyTextIfRounded('1,234'), isNull, reason: 'thousands group, nothing rounded');
      expect(roundedMoneyText('0,5'), '0.50');
    });
  });
}
