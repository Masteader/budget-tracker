/// Payload of a receipt captured while offline (`receipt_offline_draft`).
///
/// The photo is stored as it is and read by the server when the device is
/// back online (the sync worker replays it through `/agent/scan-receipt`).
/// Nothing is guessed on the device: merchant and amount are included only
/// when the user typed them, and no category is assumed (R8).
library;

Map<String, dynamic> offlineReceiptDraftPayload({
  required List<String> imagesBase64,
  String? merchant,
  double? amount,
  String? qrCodeRaw,
  String? userId,
  Map<String, String> nafaqahFields = const {},
}) {
  final typedMerchant = merchant?.trim() ?? '';
  return {
    'images_base64': imagesBase64,
    if (typedMerchant.isNotEmpty) 'merchant': typedMerchant,
    if (amount != null && amount > 0) 'amount': amount,
    if (qrCodeRaw != null && qrCodeRaw.isNotEmpty) 'qr_code_raw': qrCodeRaw,
    if (userId != null) 'user_id': userId,
    'needs_cloud_enrichment': true,
    ...nafaqahFields,
  };
}
