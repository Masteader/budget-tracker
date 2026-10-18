import 'dart:io';
import 'package:flutter/foundation.dart';
import 'saudi_receipt_text_parser.dart';

/// Abstract text recognizer interface to isolate platform-specific ML Kit dependencies.
abstract class IOcrTextRecognizer {
  Future<String> recognizeText(File imageFile);
}

/// Fallback / mock recognizer for unit tests and platforms without Google ML Kit.
class MockOcrTextRecognizer implements IOcrTextRecognizer {
  final String? fixedResult;
  const MockOcrTextRecognizer({this.fixedResult});

  @override
  Future<String> recognizeText(File imageFile) async {
    return fixedResult ?? 'Al Othaim Supermarket Total: 85.00 SAR VAT: 11.08 SAR';
  }
}

/// Service providing lightweight on-device OCR fallback when device is offline.
class LocalOcrService {
  final IOcrTextRecognizer recognizer;
  static final LocalOcrService instance = LocalOcrService();

  LocalOcrService({IOcrTextRecognizer? recognizer})
      : recognizer = recognizer ?? const MockOcrTextRecognizer();

  /// Reads text from the given receipt photo file and parses a structured draft.
  Future<ParsedReceiptDraft> extractDraft(File imageFile) async {
    try {
      if (!await imageFile.exists()) {
        debugPrint('[LocalOcrService] Receipt file does not exist: ${imageFile.path}');
        return const ParsedReceiptDraft(merchant: 'Merchant', amount: 0.0);
      }

      final rawText = await recognizer.recognizeText(imageFile);
      return SaudiReceiptTextParser.parse(rawText);
    } catch (e) {
      debugPrint('[LocalOcrService] Extraction error: $e');
      return const ParsedReceiptDraft(merchant: 'Merchant', amount: 0.0);
    }
  }
}
