import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/widgets/chat/chat_message_bubble.dart';

import '../support/localized_app.dart';

void main() {
  testWidgets('renders contextual action pills when guidanceActions are present and fires onActionTap', (tester) async {
    String? tappedAction;
    final msg = ChatMessage(
      isUser: false,
      text: 'To configure your payday, follow these steps.',
      guidanceActions: [
        {
          'id': 'open_tutor',
          'label_en': 'Launch Setup Tutor',
          'label_ar': 'بدء جولة الإعداد',
          'route': 'open_tutor',
        },
        {
          'id': 'open_payday',
          'label_en': 'Set Payday',
          'label_ar': 'تحديد يوم الراتب',
          'route': 'edit_payday',
        },
      ],
    );

    await tester.pumpWidget(localizedApp(
      ChatMessageBubble(
        message: msg,
        onActionTap: (actionId) => tappedAction = actionId,
      ),
      lang: 'en',
    ));
    await tester.pumpAndSettle();

    expect(find.text('Launch Setup Tutor'), findsOneWidget);
    expect(find.text('Set Payday'), findsOneWidget);

    await tester.tap(find.text('Set Payday'));
    await tester.pumpAndSettle();
    expect(tappedAction, 'open_payday');
  });

  testWidgets('renders action pills in Arabic correctly', (tester) async {
    final msg = ChatMessage(
      isUser: false,
      text: 'يمكنك تحديد يوم الراتب من خلال الخيارات أدناه.',
      guidanceActions: [
        {
          'id': 'open_tutor',
          'label_en': 'Launch Setup Tutor',
          'label_ar': 'بدء جولة الإعداد',
          'route': 'open_tutor',
        },
      ],
    );

    await tester.pumpWidget(localizedApp(
      ChatMessageBubble(
        message: msg,
      ),
      lang: 'ar',
    ));
    await tester.pumpAndSettle();

    expect(find.text('بدء جولة الإعداد'), findsOneWidget);
  });
}
