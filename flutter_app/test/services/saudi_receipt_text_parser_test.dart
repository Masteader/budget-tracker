import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/services/ocr/saudi_receipt_text_parser.dart';

void main() {
  group('SaudiReceiptTextParser Tests', () {
    test('extracts total amount, vat, and merchant from Arabic grocery receipt', () {
      const sampleText = '''
أسواق عبدالله العثيم
Al Othaim Markets
الفرع: حي النرجس - الرياض
الرقم الضريبي: 300055555500003
التاريخ: 2026-10-18 14:22
حليب المراعي 2 لتر    14.50
أرز أبو كاس 5 كجم     42.00
دجاج ساديا 1000 جم    18.50
المجموع قبل الضريبة:  65.22
ضريبة القيمة المضافة 15%: 9.78
المجموع الكلي: 75.00 ر.س
شكراً لزيارتكم
''';

      final draft = SaudiReceiptTextParser.parse(sampleText);
      expect(draft.merchant.toLowerCase(), contains('othaim'));
      expect(draft.amount, 75.00);
      expect(draft.vatAmount, 9.78);
      expect(draft.confidence, greaterThanOrEqualTo(0.8));
    });

    test('extracts total from English dining receipt with SAR currency', () {
      const sampleText = '''
AL BAIK RESTAURANT
Branch: Al Tahlia St, Jeddah
Tax Invoice: 998822
Date: 18/10/2026
Chicken Meal 4 Pcs    21.00
Garlic Sauce           3.00
Soft Drink             4.50
SUBTOTAL:             24.78
VAT 15%:               3.72
TOTAL AMOUNT:      SAR 28.50
THANK YOU
''';

      final draft = SaudiReceiptTextParser.parse(sampleText);
      expect(draft.merchant.toLowerCase(), contains('al baik'));
      expect(draft.amount, 28.50);
      expect(draft.vatAmount, 3.72);
      expect(draft.confidence, greaterThanOrEqualTo(0.8));
    });

    test('handles Panda supermarket receipt with SR symbol', () {
      const sampleText = '''
شركة العزيزية بنده المتحدة
Panda Supermarket
Total: 120.40 SR
VAT: 15.70 SR
''';

      final draft = SaudiReceiptTextParser.parse(sampleText);
      expect(draft.merchant.toLowerCase(), contains('panda'));
      expect(draft.amount, 120.40);
      expect(draft.vatAmount, 15.70);
    });
  });
}
