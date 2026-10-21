/// Preview → commit binding for chat and receipt expenses.
///
/// The API may return a `preview_token` with a chat or receipt preview. The
/// app sends it back unchanged in the commit request (chat: with the same
/// message text; receipt: with the same photos) so the server can commit what
/// the user reviewed instead of parsing again. Duplicate-candidate responses
/// carry a token too. A token the server no longer accepts is refused with
/// 422 `{"detail": {"code": "invalid_preview_token"}}` (or
/// `preview_token_expired` for a receipt sent without photos): the preview is
/// then run once more and the commit retried with the fresh token. Servers that send no token keep
/// working: the commit simply carries none.
library;

const String previewTokenField = 'preview_token';

/// The token of a preview response, or null when the server sent none.
String? previewTokenOf(Map<String, dynamic>? preview) {
  final token = preview?[previewTokenField];
  return token is String && token.isNotEmpty ? token : null;
}

/// Whether [res] is the server refusing the preview token: tampered, for
/// another user / household / endpoint (`invalid_preview_token`), or a
/// receipt preview whose photos the server no longer holds
/// (`preview_token_expired`). Either way the preview is run again and the
/// commit resent (with the photos, which the app always sends).
bool isInvalidPreviewToken(Map<String, dynamic> res) {
  if ((res['status_code'] as num?)?.toInt() != 422) return false;
  final detail = res['detail'];
  final code = detail is Map ? detail['code'] : res['code'];
  return code == 'invalid_preview_token' || code == 'preview_token_expired';
}

/// Commits with [token]; on an invalid-token refusal re-runs the preview once
/// ([rePreview]) and commits again with its token. Never retries twice.
Future<Map<String, dynamic>> commitWithPreviewToken({
  required String? token,
  required Future<Map<String, dynamic>> Function(String? token) commit,
  required Future<Map<String, dynamic>> Function() rePreview,
}) async {
  final first = await commit(token);
  if (!isInvalidPreviewToken(first)) return first;
  final fresh = await rePreview();
  if (fresh['status'] == 'error') return first;
  return commit(previewTokenOf(fresh));
}
