import '../../supabase_config.dart';
import 'base_api_client.dart';

/// Outcome of [SupportApiClient.sendSupportInquiry].
enum SupportInquiryOutcome {
  /// The backend's email provider accepted the message.
  sent,

  /// The message was rejected as invalid (empty or too long).
  invalid,

  /// The session is missing or expired; the user must sign in again.
  unauthorized,

  /// Too many messages from this account in the last hour.
  rateLimited,

  /// The server could not deliver it (no email provider, provider failure, ...).
  unavailable,

  /// The server could not be reached at all.
  network,
}

class SupportInquiryResult {
  final SupportInquiryOutcome outcome;

  /// Server reference id of a delivered (or failed, when reported) message.
  final String? reference;

  const SupportInquiryResult(this.outcome, {this.reference});

  bool get isSent => outcome == SupportInquiryOutcome.sent;
}

class SupportApiClient {
  final BaseApiClient baseClient;

  SupportApiClient({BaseApiClient? baseClient})
      : baseClient = baseClient ?? BaseApiClient();

  /// Longest message the backend accepts (POST /support/inquiries).
  static const int maxInquiryLength = 4000;

  Future<Map<String, dynamic>> postSupportChat({
    required String message,
    String? householdId,
    String? userId,
    List<Map<String, String>>? history,
    String? language,
  }) async {
    const url = '$fastapiBaseUrl/support/chat';
    return baseClient.post(
      url,
      {
        'message': message,
        if (householdId != null) 'household_id': householdId,
        if (userId != null) 'user_id': userId,
        if (history != null) 'history': history,
        if (language != null) 'language': language,
      },
      shouldSign: false,
      timeout: const Duration(seconds: 20),
    );
  }

  /// Emails [message] to the developer through POST /support/inquiries.
  ///
  /// The sender is identified by the server from the caller's Supabase JWT
  /// (user id and account email, used as Reply-To); the body cannot name a
  /// user. Reports [SupportInquiryOutcome.sent] only when the server answered
  /// `{"status": "sent"}`, i.e. after the email provider accepted the message.
  Future<SupportInquiryResult> sendSupportInquiry({
    required String message,
    String? locale,
    String? householdId,
  }) async {
    final trimmed = message.trim();
    if (trimmed.isEmpty || trimmed.length > maxInquiryLength) {
      return const SupportInquiryResult(SupportInquiryOutcome.invalid);
    }
    const url = '$fastapiBaseUrl/support/inquiries';
    final res = await baseClient.post(
      url,
      {
        'message': trimmed,
        if (locale != null && locale.isNotEmpty) 'locale': locale,
        if (householdId != null && householdId.isNotEmpty) 'household_id': householdId,
      },
      shouldSign: false,
      timeout: const Duration(seconds: 30),
    );
    final reference = res['reference'] is String ? res['reference'] as String : null;
    if (res['status'] == 'sent') {
      return SupportInquiryResult(SupportInquiryOutcome.sent, reference: reference);
    }
    final code = res['status_code'];
    if (code is! int) {
      // BaseApiClient reports transport failures (timeout, no connection) as an
      // error without a status code; any other unexpected answer is not a send.
      return SupportInquiryResult(res['status'] == 'error'
          ? SupportInquiryOutcome.network
          : SupportInquiryOutcome.unavailable);
    }
    if (code == 401 || code == 403) {
      return const SupportInquiryResult(SupportInquiryOutcome.unauthorized);
    }
    if (code == 422) {
      return const SupportInquiryResult(SupportInquiryOutcome.invalid);
    }
    if (code == 429) {
      return const SupportInquiryResult(SupportInquiryOutcome.rateLimited);
    }
    return SupportInquiryResult(SupportInquiryOutcome.unavailable, reference: reference);
  }
}
