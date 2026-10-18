/// Representation of an offline parsed receipt draft.
class ParsedReceiptDraft {
  final String merchant;
  final double amount;
  final double vatAmount;
  final DateTime? date;
  final double confidence;
  final String? rawText;

  const ParsedReceiptDraft({
    required this.merchant,
    required this.amount,
    this.vatAmount = 0.0,
    this.date,
    this.confidence = 0.5,
    this.rawText,
  });

  Map<String, dynamic> toMap() {
    return {
      'merchant': merchant,
      'amount': amount,
      'vat_amount': vatAmount,
      'date': date?.toIso8601String(),
      'confidence': confidence,
      if (rawText != null) 'raw_text': rawText,
    };
  }

  factory ParsedReceiptDraft.fromMap(Map<String, dynamic> map) {
    return ParsedReceiptDraft(
      merchant: map['merchant'] as String? ?? 'Merchant',
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      vatAmount: (map['vat_amount'] as num?)?.toDouble() ?? 0.0,
      date: map['date'] != null ? DateTime.tryParse(map['date'].toString()) : null,
      confidence: (map['confidence'] as num?)?.toDouble() ?? 0.5,
      rawText: map['raw_text'] as String?,
    );
  }
}

/// Offline parser extracting Saudi merchant name, total SAR, and VAT from raw OCR text.
class SaudiReceiptTextParser {
  SaudiReceiptTextParser._();

  static const List<Map<String, String>> knownMerchants = [
    {'key': 'othaim', 'name': 'Al Othaim Markets'},
    {'key': 'عثيم', 'name': 'أسواق عبدالله العثيم'},
    {'key': 'panda', 'name': 'Panda Supermarket'},
    {'key': 'بنده', 'name': 'بنده'},
    {'key': 'danube', 'name': 'Danube'},
    {'key': 'الدانوب', 'name': 'الدانوب'},
    {'key': 'carrefour', 'name': 'Carrefour'},
    {'key': 'كارفور', 'name': 'كارفور'},
    {'key': 'lulu', 'name': 'LuLu Hypermarket'},
    {'key': 'لولو', 'name': 'لولو هايبر ماركت'},
    {'key': 'tamimi', 'name': 'Tamimi Markets'},
    {'key': 'التميمي', 'name': 'أسواق التميمي'},
    {'key': 'al baik', 'name': 'Al Baik'},
    {'key': 'البيك', 'name': 'البيك'},
    {'key': 'barns', 'name': "Barn's Coffee"},
    {'key': 'بارنز', 'name': 'بارنز كافيه'},
    {'key': 'dunkin', 'name': 'Dunkin'},
    {'key': 'دانكن', 'name': 'دانكن'},
    {'key': 'starbucks', 'name': 'Starbucks'},
    {'key': 'ستاربكس', 'name': 'ستاربكس'},
    {'key': 'nahdi', 'name': 'Al Nahdi Pharmacy'},
    {'key': 'النهدي', 'name': 'صيدلية النهدي'},
    {'key': 'sasco', 'name': 'SASCO Fuel'},
    {'key': 'ساسكو', 'name': 'ساسكو'},
    {'key': 'aldrees', 'name': 'Aldrees Petroleum'},
    {'key': 'الدريس', 'name': 'الدريس'},
    {'key': 'jarir', 'name': 'Jarir Bookstore'},
    {'key': 'جرير', 'name': 'مكتبة جرير'},
    {'key': 'extra', 'name': 'eXtra Electronics'},
    {'key': 'اكسترا', 'name': 'إكسترا'},
  ];

  static ParsedReceiptDraft parse(String text) {
    if (text.trim().isEmpty) {
      return const ParsedReceiptDraft(merchant: 'Merchant', amount: 0.0);
    }

    final lower = text.toLowerCase();

    // 1. Merchant Detection
    String merchant = 'Merchant';
    bool merchantFound = false;
    for (final m in knownMerchants) {
      if (lower.contains(m['key']!)) {
        merchant = m['name']!;
        merchantFound = true;
        break;
      }
    }

    // 2. Total Amount Extraction
    double amount = 0.0;
    final totalPatterns = [
      RegExp(r'(?:المجموع\s*الكلي|المجموع|الإجمالي|صافي\s*القيمة|total\s*amount|total|net\s*amount)[\s:]*([0-9]+(?:\.[0-9]{1,2})?)', caseSensitive: false),
      RegExp(r'(?:sar|ر\.س|sr)[\s:]*([0-9]+(?:\.[0-9]{1,2})?)', caseSensitive: false),
      RegExp(r'([0-9]+(?:\.[0-9]{1,2})?)[\s]*(?:sar|ر\.س|sr)', caseSensitive: false),
    ];

    for (final pattern in totalPatterns) {
      final matches = pattern.allMatches(text);
      for (final match in matches) {
        if (match.group(1) != null) {
          final val = double.tryParse(match.group(1)!);
          if (val != null && val > amount) {
            amount = val;
          }
        }
      }
    }

    // 3. 15% VAT Extraction
    double vatAmount = 0.0;
    for (final line in text.split(RegExp(r'[\r\n]+'))) {
      final l = line.toLowerCase();
      if (l.contains('قبل الضريبة') || l.contains('before vat') || l.contains('excluding vat')) {
        continue;
      }
      if (l.contains('vat') || l.contains('ضريبة') || l.contains('الضريبة')) {
        final cleanedLine = line.replaceAll(RegExp(r'(?:15|١٥)\s*[%٪]'), '');
        final numMatch = RegExp(r'(\d+(?:\.\d{1,2})?)').firstMatch(cleanedLine);
        if (numMatch != null) {
          final val = double.tryParse(numMatch.group(1)!);
          if (val != null && val > 0) {
            vatAmount = val;
            break;
          }
        }
      }
    }

    // Fallback: If amount found but no VAT, calculate standard 15% Saudi VAT component
    if (vatAmount == 0.0 && amount > 0) {
      vatAmount = double.parse(((amount / 1.15) * 0.15).toStringAsFixed(2));
    }

    // Confidence Calculation
    double confidence = 0.3;
    if (merchantFound) confidence += 0.35;
    if (amount > 0) confidence += 0.35;

    return ParsedReceiptDraft(
      merchant: merchant,
      amount: amount,
      vatAmount: vatAmount,
      date: DateTime.now(),
      confidence: confidence,
      rawText: text,
    );
  }
}
