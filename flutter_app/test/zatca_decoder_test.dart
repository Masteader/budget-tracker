import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/services/zatca_decoder.dart';

void main() {
  group('ZatcaDecoder Tests', () {
    test('Correctly decodes valid ZATCA TLV Base64 payload', () {
      // Build a standard TLV payload manually:
      // Tag 1 (Seller): "Tamimi Markets"
      // Tag 2 (VAT Number): "300000000000003"
      // Tag 3 (Timestamp): "2026-10-05T01:00:00Z"
      // Tag 4 (Total): "115.00"
      // Tag 5 (VAT): "15.00"

      final sellerBytes = utf8.encode("Tamimi Markets");
      final vatNumBytes = utf8.encode("300000000000003");
      final timestampBytes = utf8.encode("2026-10-05T01:00:00Z");
      final totalBytes = utf8.encode("115.00");
      final vatBytes = utf8.encode("15.00");

      final List<int> tlvBytes = [];

      void addTag(int tag, List<int> val) {
        tlvBytes.add(tag);
        tlvBytes.add(val.length);
        tlvBytes.addAll(val);
      }

      addTag(1, sellerBytes);
      addTag(2, vatNumBytes);
      addTag(3, timestampBytes);
      addTag(4, totalBytes);
      addTag(5, vatBytes);

      final base64Payload = base64Encode(tlvBytes);

      final decoded = ZatcaDecoder.decodeTlv(base64Payload);

      expect(decoded, isNotNull);
      expect(decoded!['seller'], equals("Tamimi Markets"));
      expect(decoded['vat_number'], equals("300000000000003"));
      expect(decoded['timestamp'], equals("2026-10-05T01:00:00Z"));
      expect(decoded['total'], equals(115.00));
      expect(decoded['vat'], equals(15.00));
    });

    test('Returns null gracefully for invalid or malformed payload', () {
      expect(ZatcaDecoder.decodeTlv('not-a-valid-base64'), isNull);
      expect(ZatcaDecoder.decodeTlv(''), isNull);
      expect(ZatcaDecoder.decodeTlv('AQIDBAU='), isNull);
    });
  });
}
