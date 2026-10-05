import '../../supabase_config.dart';
import 'base_api_client.dart';

class TransactionApiClient {
  final BaseApiClient baseClient;

  TransactionApiClient({BaseApiClient? baseClient})
      : baseClient = baseClient ?? BaseApiClient();

  Future<Map<String, dynamic>> postSms({
    required String rawSms,
    required String sender,
    required String receivedAt,
    required String householdId,
    String? deviceId,
  }) async {
    return baseClient.post(
      fastapiWebhookUrl,
      {
        'raw_sms': rawSms,
        'sender': sender,
        'received_at': receivedAt,
        'household_id': householdId,
        if (deviceId != null) 'device_id': deviceId,
      },
      shouldSign: true,
      timeout: const Duration(seconds: 15),
    );
  }
}
