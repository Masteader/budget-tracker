/// Parsing of user-typed SAR amounts.
///
/// Arabic and Urdu keyboards (and iOS/Android numeric pads under an Arabic
/// locale) emit Arabic-Indic digits `٠١٢٣٤٥٦٧٨٩`, Extended Arabic-Indic
/// (Persian/Urdu) digits `۰۱۲۳۴۵۶۷۸۹`, the Arabic decimal separator `٫` and
/// the Arabic thousands separator `٬`. `double.tryParse` rejects all of them,
/// which silently turned an entered "١٥٠" into 0 (or "keep old balance").
library;

const int _arabicIndicZero = 0x0660;
const int _extendedArabicIndicZero = 0x06F0;

/// Converts Arabic-Indic / Extended Arabic-Indic digits to ASCII digits and
/// the Arabic decimal separator to '.'. Other characters are kept.
String normalizeDigits(String input) {
  final out = StringBuffer();
  for (final rune in input.runes) {
    if (rune >= _arabicIndicZero && rune <= _arabicIndicZero + 9) {
      out.writeCharCode(0x30 + rune - _arabicIndicZero);
    } else if (rune >= _extendedArabicIndicZero && rune <= _extendedArabicIndicZero + 9) {
      out.writeCharCode(0x30 + rune - _extendedArabicIndicZero);
    } else if (rune == 0x066B) {
      out.write('.');
    } else {
      out.writeCharCode(rune);
    }
  }
  return out.toString();
}

final RegExp _currencyTokens = RegExp(r'(sar|ر\.س\.?|ريال|﷼|riyals?)', caseSensitive: false);
// Grouping separators (',' '٬' '،' and spaces incl. NBSP / narrow NBSP) and
// bidi control marks that Arabic text fields insert around numbers.
final RegExp _ignorable = RegExp('[,٬،\\s  ‎‏؜]');
final RegExp _plainNumber = RegExp(r'^([+-]?)(\d*)(?:\.(\d*))?$');

/// Largest integer part accepted: the database stores amounts as numeric(14,2).
const int _maxIntegerDigits = 12;

/// Parses a typed money amount into integer halalas (1 SAR = 100 halalas),
/// working on the decimal string itself: the third decimal decides, half-up
/// (away from zero), so "1.005" is 101 and "0.285" is 29. Going through a
/// binary double made them 1.00 and 0.28 (FABLE-LOGIC-09).
///
/// Accepts Arabic-Indic / Urdu digits, the Arabic decimal and thousands
/// separators, grouping commas and spaces, and a currency token. Returns null
/// when the text is not a plain number, exceeds numeric(14,2), or is negative
/// while [allowNegative] is false.
int? parseMoneyToHalalas(String? input, {bool allowNegative = true}) {
  if (input == null) return null;
  final cleaned = normalizeDigits(input).replaceAll(_currencyTokens, '').replaceAll(_ignorable, '');
  final match = _plainNumber.firstMatch(cleaned);
  if (match == null) return null;
  final sign = match.group(1) ?? '';
  final whole = match.group(2) ?? '';
  final fraction = match.group(3) ?? '';
  if (whole.isEmpty && fraction.isEmpty) return null;

  final integerDigits = whole.replaceFirst(RegExp(r'^0+'), '');
  if (integerDigits.length > _maxIntegerDigits) return null;

  final padded = fraction.padRight(3, '0');
  var halalas = int.parse(integerDigits.isEmpty ? '0' : integerDigits) * 100 + int.parse(padded.substring(0, 2));
  if (padded.codeUnitAt(2) >= 0x35) halalas += 1; // third decimal >= 5: half-up
  if (halalas == 0) return 0;
  final negative = sign == '-';
  if (negative && !allowNegative) return null;
  return negative ? -halalas : halalas;
}

/// Parses a typed money amount, rounded half-up to halalas (2 decimals) from
/// the decimal string (see [parseMoneyToHalalas]). Returns null when the text
/// is not a number (or is negative while [allowNegative] is false).
double? parseMoneyInput(String? input, {bool allowNegative = true}) {
  final halalas = parseMoneyToHalalas(input, allowNegative: allowNegative);
  return halalas == null ? null : halalas / 100;
}

/// Halalas as a plain two-decimal SAR string ("1.01", "-0.29").
String formatHalalas(int halalas) {
  final negative = halalas < 0;
  final abs = halalas.abs();
  final text = '${abs ~/ 100}.${(abs % 100).toString().padLeft(2, '0')}';
  return negative ? '-$text' : text;
}

/// The value [input] is actually stored as, to show the rounded amount back
/// to the user ("1.005" → "1.01"); null when it is not a number.
String? roundedMoneyText(String? input, {bool allowNegative = true}) {
  final halalas = parseMoneyToHalalas(input, allowNegative: allowNegative);
  return halalas == null ? null : formatHalalas(halalas);
}

/// The rounded value to show in place of [input] when the user typed more
/// than two decimals ("1.005" → "1.01"); null when nothing was rounded away
/// or the text is not a number, so the field is left as typed.
String? roundedMoneyTextIfRounded(String? input) {
  if (input == null) return null;
  final cleaned = normalizeDigits(input).replaceAll(_currencyTokens, '').replaceAll(_ignorable, '');
  final fraction = _plainNumber.firstMatch(cleaned)?.group(3) ?? '';
  if (fraction.length <= 2) return null;
  return roundedMoneyText(input);
}
