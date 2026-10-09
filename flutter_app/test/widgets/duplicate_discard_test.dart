import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/widgets/scanner/duplicate_candidate_card.dart';
import 'package:budget_tracker/widgets/chat/duplicate_resolution_card.dart';

void main() {
  group('Duplicate Discard Action Widget Tests', () {
    testWidgets('DuplicateCandidateCard renders Discard button and triggers onDiscard', (tester) async {
      bool discarded = false;
      bool enriched = false;
      bool loggedSeparate = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DuplicateCandidateCard(
              message: 'Matching recent transaction found: SAR 150.00',
              itemCount: 3,
              onEnrich: () => enriched = true,
              onLogSeparate: () => loggedSeparate = true,
              onDiscard: () => discarded = true,
            ),
          ),
        ),
      );

      // Verify the Discard button exists
      final discardFinder = find.widgetWithText(OutlinedButton, 'Discard Duplicate');
      expect(discardFinder, findsOneWidget);

      // Tap Discard
      await tester.tap(discardFinder);
      await tester.pump();

      expect(discarded, isTrue);
      expect(enriched, isFalse);
      expect(loggedSeparate, isFalse);
    });

    testWidgets('DuplicateResolutionCard renders Discard button and triggers onDiscard', (tester) async {
      bool discarded = false;
      String? enrichedId;
      String? loggedNewMsg;

      final candidateData = {
        'candidate_transaction_id': 'tx_123',
        'parsed_data': {
          'merchant': 'Al Meera',
          'amount': 85.50,
        },
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DuplicateResolutionCard(
              candidateData: candidateData,
              onEnrich: (id) => enrichedId = id,
              onLogAsNew: (msg) => loggedNewMsg = msg,
              onDiscard: () => discarded = true,
            ),
          ),
        ),
      );

      // Verify Discard button exists
      final discardFinder = find.widgetWithText(OutlinedButton, 'Discard');
      expect(discardFinder, findsOneWidget);

      // Tap Discard
      await tester.tap(discardFinder);
      await tester.pump();

      expect(discarded, isTrue);
      expect(enrichedId, isNull);
      expect(loggedNewMsg, isNull);
    });
  });
}
