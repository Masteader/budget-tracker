// UX-16: the roommates flow is centred on "me": what I owe / am owed first.
import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/models/household_dues.dart';
import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/widgets/dashboard/multi_roommate_settlement_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _summary = SettlementV2Summary(
  mode: 'multi_roommate',
  pairwiseDebts: [
    PairwiseDebt(fromId: 'omar', toId: 'ahmed', fromName: 'Omar', toName: 'Ahmed', amount: 100),
    PairwiseDebt(fromId: 'ibrahim', toId: 'ahmed', fromName: 'Ibrahim', toName: 'Ahmed', amount: 200),
    PairwiseDebt(fromId: 'tariq', toId: 'omar', fromName: 'Tariq', toName: 'Omar', amount: 200),
  ],
  simplifiedDebts: [
    SimplifiedDebt(fromId: 'tariq', toId: 'omar', fromName: 'Tariq', toName: 'Omar', amount: 100),
    SimplifiedDebt(fromId: 'tariq', toId: 'ahmed', fromName: 'Tariq', toName: 'Ahmed', amount: 100),
    SimplifiedDebt(fromId: 'ibrahim', toId: 'ahmed', fromName: 'Ibrahim', toName: 'Ahmed', amount: 200),
  ],
);

Widget _app(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('ar'), Locale('ur')],
      locale: locale,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

List<String?> _rowTitles(WidgetTester tester) =>
    tester.widgetList<Text>(find.byKey(const Key('roommate_debt_title'))).map((t) => t.data).toList();

void main() {
  test('dues for the hero: my net per roommate', () {
    final mine = roommateDueLines(_summary, 'tariq');
    expect(mine.map((d) => (d.kind, d.name, d.amount)), [
      (DueKind.iOwe, 'Omar', 100.0),
      (DueKind.iOwe, 'Ahmed', 100.0),
    ]);
    final ahmed = roommateDueLines(_summary, 'ahmed');
    expect(ahmed.map((d) => (d.kind, d.name, d.amount)), [
      (DueKind.owedByRoommate, 'Ibrahim', 200.0),
      (DueKind.owedByRoommate, 'Tariq', 100.0),
    ]);
    expect(roommateDueLines(_summary, 'nobody'), isEmpty);
    expect(roommateDueLines(_summary, null), isEmpty);
  });

  testWidgets('my debts first, in my words, with my net balance on top', (tester) async {
    await tester.pumpWidget(_app(const MultiRoommateSettlementCard(
      householdId: 'hh',
      summary: _summary,
      currentUserId: 'tariq',
    )));
    await tester.pumpAndSettle();
    expect(find.text('Your balance: you owe SAR 200.00'), findsOneWidget);
    expect(_rowTitles(tester), ['You owe Omar', 'You owe Ahmed', 'Ibrahim owes Ahmed']);
  });

  testWidgets('money owed to me reads "owes you"', (tester) async {
    await tester.pumpWidget(_app(const MultiRoommateSettlementCard(
      householdId: 'hh',
      summary: _summary,
      currentUserId: 'ahmed',
    )));
    await tester.pumpAndSettle();
    expect(find.text('Your balance: you are owed SAR 300.00'), findsOneWidget);
    expect(_rowTitles(tester), ['Ibrahim owes you', 'Tariq owes you', 'Tariq owes Omar']);
  });

  testWidgets('Arabic: "أنت مدين لـعمر", no stray space after لـ, plain toggle name', (tester) async {
    await tester.pumpWidget(_app(
      const MultiRoommateSettlementCard(householdId: 'hh', summary: _summary, currentUserId: 'tariq'),
      locale: const Locale('ar'),
    ));
    await tester.pumpAndSettle();
    expect(find.text('أنت مدين لـOmar'), findsOneWidget);
    expect(find.text('Ibrahim مدين لـAhmed'), findsOneWidget);
    expect(find.text('أقل عدد تحويلات'), findsOneWidget);
    expect(find.text('تبسيط الديون'), findsNothing);
  });

  testWidgets('the toggle has a one-line hint', (tester) async {
    await tester.pumpWidget(_app(const MultiRoommateSettlementCard(householdId: 'hh', summary: _summary)));
    await tester.pumpAndSettle();
    expect(find.text('Fewest transfers'), findsOneWidget);
    expect(find.text('Combines debts so fewer payments are needed.'), findsOneWidget);
  });
}
