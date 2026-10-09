import '../../supabase_config.dart';
import 'base_api_client.dart';

class TransactionApiClient {
  final BaseApiClient baseClient;

  TransactionApiClient({BaseApiClient? baseClient})
      : baseClient = baseClient ?? BaseApiClient();
}
