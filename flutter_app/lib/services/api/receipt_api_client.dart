import 'base_api_client.dart';
import 'preview_token.dart';

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
    String? paidBy,
    String? beneficiary,
    String? nafaqahClass,
    String? nafaqahSpouseId,
    String? idempotencyKey,
    DateTime? occurredAt,
    String? previewToken,
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
      // Family Nafaqah (same contract as chat): who paid for whom and the confirmed class.
      if (paidBy != null && paidBy.trim().isNotEmpty) 'paid_by': paidBy.trim(),
      if (beneficiary != null && beneficiary.trim().isNotEmpty) 'beneficiary': beneficiary.trim(),
      if (nafaqahClass != null && nafaqahClass.isNotEmpty) 'nafaqah_class': nafaqahClass,
      if (nafaqahSpouseId != null && nafaqahSpouseId.isNotEmpty) 'nafaqah_spouse_id': nafaqahSpouseId,
      if (occurredAt != null) 'client_occurred_at': occurredAt.toUtc().toIso8601String(),
      // Sent back unchanged from the preview (see preview_token.dart).
      if (previewToken != null && previewToken.isNotEmpty) previewTokenField: previewToken,
    };

    return baseClient.post(
      '/agent/scan-receipt',
      payload,
      shouldSign: true,
      timeout: const Duration(seconds: 45),
      extraHeaders: idempotencyKey == null ? null : {'Idempotency-Key': idempotencyKey},
    );
  }
}
