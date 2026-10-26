import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/widgets/chat/chat_message_bubble.dart';

import '../support/localized_app.dart';

void main() {
  testWidgets('renders warning message bubble with warning styling and icon', (tester) async {
    final msg = ChatMessage(
      isUser: false,
      text: 'Notice: This assistant is strictly reserved for financial tracking.',
      isOffTopicWarning: true,
    );

    await tester.pumpWidget(localizedApp(
      ChatMessageBubble(message: msg),
      lang: 'en',
    ));
    await tester.pumpAndSettle();

    expect(find.text('Notice: This assistant is strictly reserved for financial tracking.'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
  });
}
