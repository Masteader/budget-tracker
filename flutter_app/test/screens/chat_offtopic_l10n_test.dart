import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/screens/chat/chat_entry_screen.dart';
import 'package:budget_tracker/services/api_service.dart';
import 'package:budget_tracker/l10n/app_localizations.dart';
import '../support/localized_app.dart';

class _FakeChatApiService extends ApiService {
  final Map<String, dynamic> responseToReturn;
  _FakeChatApiService(this.responseToReturn);

  @override
  Future<Map<String, dynamic>> postChatTransaction({
    required String message,
    required String householdId,
    String? userId,
    bool allowDuplicate = false,
    String? enrichTxId,
    bool previewOnly = true,
    String? merchant,
    String? spentBy,
    String? categoryCode,
    String? subCategory,
    String? paidBy,
    String? beneficiary,
    String? nafaqahClass,
    String? nafaqahSpouseId,
    String? idempotencyKey,
    DateTime? occurredAt,
    String? previewToken,
    double? amount,
    String? accountId,
  }) async {
    return responseToReturn;
  }
}

void main() {
  testWidgets('ChatEntryScreen: off-topic warning renders localized Urdu text and never echoes message/message_en', (tester) async {
    final originalApi = ApiService.instance;
    final fakeApi = _FakeChatApiService({
      'status': 'off_topic_warning',
      'strikes': 2,
      'max_strikes': 3,
      'message': 'عذراً',
      'message_en': 'Sorry',
    });
    ApiService.instance = fakeApi;
    addTearDown(() => ApiService.instance = originalApi);

    await tester.pumpWidget(localizedApp(
      const ChatEntryScreen(householdId: 'hh-test-123'),
      lang: 'ur',
      scaffold: false,
    ));
    await tester.pumpAndSettle();

    // Type a message and tap send
    final textField = find.byType(TextField);
    expect(textField, findsOneWidget);
    await tester.enterText(textField, 'Tell me a joke');

    final sendButton = find.byIcon(Icons.send_rounded);
    expect(sendButton, findsOneWidget);
    await tester.tap(sendButton);
    await tester.pumpAndSettle();

    final loc = AppLocalizations(const Locale('ur'));
    final expectedUrduWarning = loc.format('chat_offtopic_warning', {
      'current': '2',
      'max': '3',
    });

    expect(find.text(expectedUrduWarning), findsOneWidget);
    expect(find.text('Sorry'), findsNothing);
    expect(find.text('عذراً'), findsNothing);
  });
}
