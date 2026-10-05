import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/models/installment_plan.dart';
import 'package:budget_tracker/widgets/dashboard/installment_plans_card.dart';

void main() {
  group('InstallmentPlansCard Widget Tests', () {
    testWidgets('Renders installment plans with provider and progress', (tester) async {
      bool payTapped = false;

      final testPlans = [
        InstallmentPlan(
          id: 'plan_1',
          householdId: 'hh_1',
          merchant: 'United Electronics Co. eXtra',
          provider: 'Tamara',
          totalAmount: 7408.0,
          installmentCount: 4,
          monthlyAmount: 1852.0,
          paidInstallments: 1,
          dayOfMonth: 27,
          startDate: '2026-10-01',
          status: 'ACTIVE',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: InstallmentPlansCard(
                plans: testPlans,
                onPayInstallment: (planId) => payTapped = true,
              ),
            ),
          ),
        ),
      );

      // Verify title and provider
      expect(find.text('Installments & BNPL'), findsOneWidget);
      expect(find.text('Tamara'), findsOneWidget);
      expect(find.text('United Electronics Co. eXtra'), findsOneWidget);

      // Verify payment details
      expect(find.text('SAR 1852.00 / mo'), findsOneWidget);
      expect(find.text('Installment 1 of 4 paid'), findsOneWidget);

      // Verify Pay button
      final payBtn = find.widgetWithText(OutlinedButton, 'Record Payment');
      expect(payBtn, findsOneWidget);
      await tester.tap(payBtn);
      await tester.pump();
      expect(payTapped, isTrue);
    });
  });
}
