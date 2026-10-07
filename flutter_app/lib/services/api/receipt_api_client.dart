import 'base_api_client.dart';

class ReceiptApiClient {
  final BaseApiClient baseClient;

  ReceiptApiClient({BaseApiClient? baseClient})
      : baseClient = baseClient ?? BaseApiClient();

  Future<Map<String, dynamic>> scanReceipt({
    required List<String> imagesBase64,
    String? qrCodeRaw,
    required String householdId,
    String? userId,
    bool allowDuplicate = false,
    String? enrichTxId,
    bool previewOnly = false,
    String? merchant,
    String? spentBy,
    String? receiptUrl,
  }) async {
    final payload = <String, dynamic>{
      'images_base64': imagesBase64,
      'household_id': householdId,
      'allow_duplicate': allowDuplicate,
      'preview_only': previewOnly,
      if (qrCodeRaw != null) 'qr_code_raw': qrCodeRaw,
      if (userId != null) 'user_id': userId,
      if (enrichTxId != null) 'enrich_tx_id': enrichTxId,
      if (merchant != null && merchant.trim().isNotEmpty) 'merchant': merchant.trim(),
      if (spentBy != null && spentBy.trim().isNotEmpty) 'spent_by': spentBy.trim(),
      if (receiptUrl != null && receiptUrl.trim().isNotEmpty) 'receipt_url': receiptUrl.trim(),
    };

    return baseClient.post(
      '/agent/scan-receipt',
      payload,
      shouldSign: true,
      timeout: const Duration(seconds: 45),
    );
  }
}
