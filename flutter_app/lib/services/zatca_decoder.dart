import 'dart:convert';

/// Decoded data from Saudi ZATCA e-invoicing Phase 1 & 2 TLV Base64 QR code.
class ZatcaDecodedData {
  final String seller;
  final String? vatNumber;
  final String? timestamp;
  final double total;
  final double vat;

  const ZatcaDecodedData({
    required this.seller,
    this.vatNumber,
    this.timestamp,
    required this.total,
    required this.vat,
  });

  Map<String, dynamic> toMap() {
    return {
      'seller': seller,
      'vat_number': vatNumber,
      'timestamp': timestamp,
      'total': total,
      'vat': vat,
    };
  }

  factory ZatcaDecodedData.fromMap(Map<String, dynamic> map) {
    return ZatcaDecodedData(
      seller: map['seller'] as String? ?? 'Merchant',
      vatNumber: map['vat_number'] as String?,
      timestamp: map['timestamp'] as String?,
      total: (map['total'] as num?)?.toDouble() ?? 0.0,
      vat: (map['vat'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Decodes standard Saudi ZATCA Tag-Length-Value (TLV) QR codes from base64 strings.
class ZatcaDecoder {
  ZatcaDecoder._();

  /// Parses a base64 encoded TLV string into seller, VAT number, timestamp, total, and VAT amount.
  static Map<String, dynamic>? decodeTlv(String base64Str) {
    try {
      final bytes = base64Decode(base64Str.trim());
      final tags = <int, String>{};
      int idx = 0;
      while (idx < bytes.length) {
        if (idx + 1 >= bytes.length) break;
        final tag = bytes[idx];
        final len = bytes[idx + 1];
        if (idx + 2 + len > bytes.length) break;
        final val = utf8.decode(bytes.sublist(idx + 2, idx + 2 + len), allowMalformed: true);
        tags[tag] = val;
        idx += 2 + len;
      }
      final totalVal = double.tryParse(tags[4] ?? '');
      final vatVal = double.tryParse(tags[5] ?? '');
      if (tags[1] != null && totalVal != null) {
        return {
          'seller': tags[1],
          'vat_number': tags[2],
          'timestamp': tags[3],
          'total': totalVal,
          'vat': vatVal ?? 0.0,
        };
      }
    } catch (_) {}
    return null;
  }
}
