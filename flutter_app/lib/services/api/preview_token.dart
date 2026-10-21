/// Preview → commit binding for chat and receipt expenses.
///
/// The API may return a `preview_token` with a chat or receipt preview. The
/// app sends it back unchanged in the commit request so the server can commit
/// what the user reviewed instead of parsing again. A token the server no
/// longer accepts is refused with 422 `{"detail": {"code":
/// "invalid_preview_token"}}`: the preview is then run once more and the
/// commit retried with the fresh token. Servers that send no token keep
/// working: the commit simply carries none.
library;

const String previewTokenField = 'preview_token';

/// The token of a preview response, or null when the server sent none.
String? previewTokenOf(Map<String, dynamic>? preview) {
  final token = preview?[previewTokenField];
  return token is String && token.isNotEmpty ? token : null;
}

/// Whether [res] is the server refusing an expired or foreign preview token.
bool isInvalidPreviewToken(Map<String, dynamic> res) {
  if ((res['status_code'] as num?)?.toInt() != 422) return false;
  final detail = res['detail'];
  final code = detail is Map ? detail['code'] : res['code'];
  return code == 'invalid_preview_token';
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
