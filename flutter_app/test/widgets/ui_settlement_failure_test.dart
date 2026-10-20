import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/models/nafaqah.dart';
import 'package:budget_tracker/widgets/dashboard/family_reimbursement_card.dart';
import 'package:budget_tracker/widgets/dashboard/multi_roommate_settlement_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('ar'), Locale('ur')],
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  // Regression: both settlement sheets swallowed API errors and still showed
  // "Settlement Recorded" and fired the confirmation callback.
  testWidgets('family reimbursement failure is reported, sheet stays open', (tester) async {
    var confirmed = false;
    await tester.pumpWidget(_app(FamilyReimbursementCard(
      householdId: 'hh-1',
      summary: const NafaqahSummary(
        mode: 'family_nafaqah',
        callerRole: 'husband',
        callerUserId: 'u-h',
        wives: [NafaqahWife(id: 'u-w', reimbursement: ReimbursementBalance(grossAdvanced: 350, outstanding: 350))],
        canRecordReimbursement: true,
      ),
      onReimbursed: () => confirmed = true,
      recordReimbursement: ({required double amount, required String paymentMethod, required String wifeUserId}) async =>
          throw Exception('HTTP 500'),
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Reimburse Wife'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Record Settlement Payment'));
    await tester.pumpAndSettle();

    expect(confirmed, isFalse);
    expect(find.text('Settlement Failed'), findsOneWidget);
    expect(find.text('Settlement Recorded'), findsNothing);
    expect(find.text('Settle Wife Reimbursement'), findsOneWidget);
  });

  testWidgets('roommate settlement failure is reported, callback not fired', (tester) async {
    var settled = false;
    await tester.pumpWidget(_app(MultiRoommateSettlementCard(
      householdId: 'hh-2',
      summary: const SettlementV2Summary(
        mode: 'multi_roommate',
        pairwiseDebts: [],
        simplifiedDebts: [
          SimplifiedDebt(fromId: 'a', toId: 'b', fromName: 'Omar', toName: 'Ahmed', amount: 120.0),
        ],
        roommateBalances: {'a': -120.0, 'b': 120.0},
      ),
      onSettled: () => settled = true,
      recordPayment: (_) async => throw Exception('offline'),
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Settle').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Record Settlement Payment'));
    await tester.pumpAndSettle();

    expect(settled, isFalse);
    expect(find.text('Settlement Failed'), findsOneWidget);
    expect(find.text('Record Roommate Settlement'), findsOneWidget);
  });

  testWidgets('roommate card renders Arabic labels and riyal amounts in RTL', (tester) async {
    await tester.pumpWidget(_app(
      const MultiRoommateSettlementCard(
        householdId: 'hh-3',
        summary: SettlementV2Summary(
          mode: 'multi_roommate',
          pairwiseDebts: [],
          simplifiedDebts: [
            SimplifiedDebt(fromId: 'a', toId: 'b', fromName: 'عمر', toName: 'أحمد', amount: 50.0),
          ],
          roommateBalances: {'a': -50.0, 'b': 50.0},
        ),
      ),
      locale: const Locale('ar'),
    ));
    await tester.pumpAndSettle();

    final dir = Directionality.of(tester.element(find.byType(MultiRoommateSettlementCard)));
    expect(dir, TextDirection.rtl);
    expect(find.text('عمر عليه لـ أحمد'), findsOneWidget);
    expect(find.text('50.00 ر.س'), findsOneWidget);
    expect(find.textContaining('SAR'), findsNothing);
  });
}
