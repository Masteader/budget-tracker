import 'package:budget_tracker/widgets/store_attribution_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget card({bool showSpentBy = true}) => MaterialApp(
        home: Scaffold(
          body: StoreAttributionCard(
            merchantController: TextEditingController(text: 'Panda'),
            selectedSpentBy: 'both',
            onSpentByChanged: (_) {},
            showSpentBy: showSpentBy,
          ),
        ),
      );

  testWidgets('roommates: "spent by whom" is asked', (tester) async {
    await tester.pumpWidget(card());
    expect(find.text('SPENT BY WHOM?'), findsOneWidget);
  });

  // UX-03: a family receipt answers the one Nafaqah question instead.
  testWidgets('family: no "spent by whom" row next to the Nafaqah question', (tester) async {
    await tester.pumpWidget(card(showSpentBy: false));
    expect(find.text('SPENT BY WHOM?'), findsNothing);
    expect(find.text('Partner'), findsNothing);
    expect(find.text('Panda'), findsOneWidget);
  });
}
