import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/services/api/base_api_client.dart';
import 'package:budget_tracker/services/api/chat_api_client.dart';
import 'package:budget_tracker/widgets/chat/pending_expense_confirmation_card.dart';

class MockBaseApiClient extends BaseApiClient {
  Map<String, dynamic> mockPostResponse = {'status': 'success'};
  String? lastPostPath;
  Map<String, dynamic>? lastPostBody;

  @override
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    bool shouldSign = true,
    Duration timeout = const Duration(seconds: 20),
    Map<String, String>? extraHeaders,
  }) async {
    lastPostPath = path;
    lastPostBody = body;
    return mockPostResponse;
  }
}

void main() {
  group('ChatApiClient account linkage tests', () {
    test('postChatTransaction includes account_id in payload when provided', () async {
      final mock = MockBaseApiClient();
      final client = ChatApiClient(baseClient: mock);

      final res = await client.postChatTransaction(
        message: 'Hunger Station AL-Baik Restaurant 34.4 SAR',
        householdId: 'h1111111-2222-3333-4444-555555555555',
        accountId: 'a1111111-2222-3333-4444-555555555555',
        amount: 34.40,
        merchant: 'Hunger Station AL-Baik Restaurant',
        previewOnly: false,
      );

      expect(res['status'], equals('success'));
      expect(mock.lastPostPath, equals('/agent/chat-transaction'));
      expect(mock.lastPostBody?['account_id'], equals('a1111111-2222-3333-4444-555555555555'));
      expect(mock.lastPostBody?['amount'], equals(34.40));
    });

    test('PendingExpenseEdits supports accountId parameter', () {
      const edits = PendingExpenseEdits(
        amount: 34.40,
        accountId: 'a1111111-2222-3333-4444-555555555555',
      );
      expect(edits.amount, equals(34.40));
      expect(edits.accountId, equals('a1111111-2222-3333-4444-555555555555'));
    });
  });
}
