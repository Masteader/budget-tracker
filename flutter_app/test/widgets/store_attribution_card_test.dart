import 'package:budget_tracker/widgets/store_attribution_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget card({
    bool showSpentBy = true,
    bool isFamily = false,
    String selectedSpentBy = 'both',
    String? selectedBeneficiary,
    String? nafaqahBadgeText,
  }) =>
      MaterialApp(
        home: Scaffold(
          body: StoreAttributionCard(
            merchantController: TextEditingController(text: 'Panda'),
            selectedSpentBy: selectedSpentBy,
            onSpentByChanged: (_) {},
            showSpentBy: showSpentBy,
            isFamily: isFamily,
            selectedBeneficiary: selectedBeneficiary,
            onBeneficiaryChanged: (_) {},
            nafaqahBadgeText: nafaqahBadgeText,
          ),
        ),
      );

  testWidgets('roommates: "spent by whom" offers Me, Partner, Both (Shared)', (tester) async {
    await tester.pumpWidget(card(isFamily: false));
    expect(find.text('SPENT BY WHOM?'), findsOneWidget);
    expect(find.byKey(const ValueKey('spent_by_me')), findsOneWidget);
    expect(find.byKey(const ValueKey('spent_by_partner')), findsOneWidget);
    expect(find.byKey(const ValueKey('spent_by_both')), findsOneWidget);
  });

  testWidgets('family: "who paid" offers only Me and Partner (never Both/Shared in family mode)', (tester) async {
    await tester.pumpWidget(card(isFamily: true, selectedSpentBy: 'me'));
    expect(find.byKey(const ValueKey('spent_by_both')), findsNothing);
    expect(find.byKey(const ValueKey('spent_by_me')), findsOneWidget);
    expect(find.byKey(const ValueKey('spent_by_partner')), findsOneWidget);
  });

  testWidgets('family: "for whom" offers Household/Shared, Me, Wife/Partner, Children', (tester) async {
    await tester.pumpWidget(card(isFamily: true, selectedSpentBy: 'me', selectedBeneficiary: 'both'));
    expect(find.byKey(const ValueKey('beneficiary_both')), findsOneWidget);
    expect(find.byKey(const ValueKey('beneficiary_me')), findsOneWidget);
    expect(find.byKey(const ValueKey('beneficiary_partner')), findsOneWidget);
    expect(find.byKey(const ValueKey('beneficiary_children')), findsOneWidget);
  });

  testWidgets('family: displays live nafaqah badge', (tester) async {
    await tester.pumpWidget(card(
      isFamily: true,
      selectedSpentBy: 'me',
      nafaqahBadgeText: 'Household Expense (Husband Nafaqah — 0 SAR owed by wife)',
    ));
    expect(find.text('Household Expense (Husband Nafaqah — 0 SAR owed by wife)'), findsOneWidget);
  });
}
