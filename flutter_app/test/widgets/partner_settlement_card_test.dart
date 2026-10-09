import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/widgets/partner_settlement_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PartnerSettlementCard Widget Tests', () {
    testWidgets('Renders 2D attribution settlement when partner owes me', (tester) async {
      final sampleData = {
        'total_shared_expenses': 400.0,
        'i_paid_for_partner_100': 150.0,
        'partner_paid_for_me_100': 0.0,
        'shared_paid_by_me': 300.0,
        'shared_paid_by_partner': 100.0,
        'net_balance': 250.0,
        'settlement_amount': 250.0,
        'who_owes': 'partner_owes_me',
        'recommendation_en': 'Partner owes you SAR 250.00.',
        'recommendation_ar': 'الشريك مدين لك بمبلغ 250.00 ريال.',
        'stc_pay_note': 'Settlement to Me',
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PartnerSettlementCard(
                householdId: 'hh_123',
                initialData: sampleData,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Header & Status
      expect(find.text('Partner Settlement'), findsOneWidget);
      expect(find.text('Partner Owes You'), findsOneWidget);

      // Amount & Recommendation
      expect(find.text('SAR 250.00'), findsOneWidget);
      expect(find.text('Partner owes you SAR 250.00.'), findsOneWidget);

      // 2D Attribution chips
      expect(find.text('Shared 50/50: SAR 400.00'), findsOneWidget);
      expect(find.text('Paid for partner: SAR 150.00'), findsOneWidget);

      // Settle Button
      final settleBtn = find.widgetWithText(
        ElevatedButton,
        'Settle SAR 250.00 via STC Pay / IBAN',
      );
      expect(settleBtn, findsOneWidget);

      // Tap settle button
      await tester.tap(settleBtn);
      await tester.pump();
    });

    testWidgets('Renders 2D attribution settlement when me owes partner', (tester) async {
      final sampleData = {
        'total_shared_expenses': 200.0,
        'i_paid_for_partner_100': 0.0,
        'partner_paid_for_me_100': 120.0,
        'shared_paid_by_me': 50.0,
        'shared_paid_by_partner': 150.0,
        'net_balance': -170.0,
        'settlement_amount': 170.0,
        'who_owes': 'me_owes_partner',
        'recommendation_en': 'You owe partner SAR 170.00.',
        'recommendation_ar': 'أنت مدين للشريك بمبلغ 170.00 ريال.',
        'stc_pay_note': 'Settlement to Partner',
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PartnerSettlementCard(
                householdId: 'hh_123',
                initialData: sampleData,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('You Owe Partner'), findsOneWidget);
      expect(find.text('SAR 170.00'), findsOneWidget);
      expect(find.text('Partner paid for me: SAR 120.00'), findsOneWidget);
      expect(
        find.widgetWithText(ElevatedButton, 'Settle SAR 170.00 via STC Pay / IBAN'),
        findsOneWidget,
      );
    });

    testWidgets('Renders all square when expenses are balanced', (tester) async {
      final sampleData = {
        'total_shared_expenses': 200.0,
        'i_paid_for_partner_100': 0.0,
        'partner_paid_for_me_100': 0.0,
        'shared_paid_by_me': 100.0,
        'shared_paid_by_partner': 100.0,
        'net_balance': 0.0,
        'settlement_amount': 0.0,
        'who_owes': 'settled',
        'recommendation_en': 'All expenses are balanced.',
        'recommendation_ar': 'المصاريف متوازنة تماماً.',
        'stc_pay_note': 'Settled',
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PartnerSettlementCard(
                householdId: 'hh_123',
                initialData: sampleData,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Expenses Balanced'), findsOneWidget);
      expect(find.text('All square'), findsOneWidget);
      expect(find.text('SAR 0.00'), findsOneWidget);
      expect(find.byType(ElevatedButton), findsNothing);
    });
  });
}
