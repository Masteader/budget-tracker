import '../../supabase_config.dart';
import 'base_api_client.dart';

class SupportApiClient {
  final BaseApiClient baseClient;

  SupportApiClient({BaseApiClient? baseClient})
      : baseClient = baseClient ?? BaseApiClient();

  Future<Map<String, dynamic>> postSupportChat({
    required String message,
    String? householdId,
    String? userId,
    List<Map<String, String>>? history,
  }) async {
    final url = '$fastapiBaseUrl/support/chat';
    return baseClient.post(
      url,
      {
        'message': message,
        if (householdId != null) 'household_id': householdId,
        if (userId != null) 'user_id': userId,
        if (history != null) 'history': history,
      },
      shouldSign: false,
      timeout: const Duration(seconds: 20),
    );
  }
}
