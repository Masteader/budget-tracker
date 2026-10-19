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
final RegExp _plainNumber = RegExp(r'^[+-]?(\d+\.?\d*|\.\d+)$');

/// Parses a typed money amount, rounded to halalas (2 decimals).
/// Returns null when the text is not a number.
double? parseMoneyInput(String? input) {
  if (input == null) return null;
  final cleaned = normalizeDigits(input).replaceAll(_currencyTokens, '').replaceAll(_ignorable, '');
  if (cleaned.isEmpty || !_plainNumber.hasMatch(cleaned)) return null;
  final value = double.tryParse(cleaned);
  if (value == null || !value.isFinite) return null;
  return (value * 100).roundToDouble() / 100;
}
