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
                now: DateTime.utc(2026, 10, 21, 9),
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
      expect(find.text('SAR 1,852.00 / mo'), findsOneWidget);
      // No next_due_at from the API: monthly on day 27 → next 27 Oct.
      expect(find.text('Installment 1 of 4 paid · next 27 Oct'), findsOneWidget);
      // The 21 Oct cycle ends on 26 Oct: nothing of this plan is due before payday.
      expect(find.text('Nothing due before payday'), findsOneWidget);

      // Verify Pay button
      final payBtn = find.widgetWithText(OutlinedButton, 'Record Payment');
      expect(payBtn, findsOneWidget);
      await tester.tap(payBtn);
      await tester.pump();
      expect(payTapped, isTrue);
    });

    testWidgets('Renders actionable empty state when no plans exist', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: InstallmentPlansCard(
                plans: [],
              ),
            ),
          ),
        ),
      );

      expect(find.text('Installments & BNPL'), findsOneWidget);
      expect(find.text('No Active BNPL Installments'), findsOneWidget);
      expect(find.text('Add Installment Plan'), findsOneWidget);
    });

    testWidgets('bi-weekly Tabby plan: no "/month", shows the frequency and next due date', (tester) async {
      final plan = InstallmentPlan.fromJson({
        'id': 'p2',
        'household_id': 'hh_1',
        'merchant': 'Jarir',
        'provider': 'Tabby',
        'total_amount': 400,
        'installment_count': 4,
        'monthly_amount': 100,
        'paid_installments': 1,
        'start_date': '2026-10-15',
        'status': 'ACTIVE',
        'frequency': 'biweekly',
        'next_due_at': '2026-10-29',
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: InstallmentPlansCard(plans: [plan], now: DateTime.utc(2026, 10, 28, 9)),
            ),
          ),
        ),
      );
      expect(find.text('SAR 100.00 / 2 wks'), findsOneWidget);
      expect(find.textContaining('/ mo'), findsNothing);
      expect(find.text('Installment 1 of 4 paid · next 29 Oct'), findsOneWidget);
      // 29 Oct, 12 Nov and 26 Nov all fall before the 27 Nov payday.
      expect(find.text('SAR 300.00 due before payday'), findsOneWidget);
    });

    testWidgets('Ongoing plan with 0 paid displays First of N due text', (tester) async {
      final plan = InstallmentPlan.fromJson({
        'id': 'p3',
        'household_id': 'hh_1',
        'merchant': 'Panda Store',
        'provider': 'Tamara',
        'total_amount': 600,
        'installment_count': 2,
        'monthly_amount': 300,
        'paid_installments': 0,
        'start_date': '2026-10-15',
        'status': 'ACTIVE',
        'frequency': 'monthly',
        'next_due_at': '2026-10-29',
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: InstallmentPlansCard(plans: [plan], now: DateTime.utc(2026, 10, 28, 9)),
            ),
          ),
        ),
      );
      expect(find.text('SAR 300.00 / mo'), findsOneWidget);
      expect(find.text('First of 2 due 29 Oct'), findsOneWidget);
    });

    testWidgets('Add dialog renders New Purchase and Ongoing Plan tabs and custom options', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: InstallmentPlansCard(plans: []),
            ),
          ),
        ),
      );

      final addBtn = find.text('Add Installment Plan');
      expect(addBtn, findsOneWidget);
      await tester.tap(addBtn);
      await tester.pumpAndSettle();

      // Check modal title and tabs
      expect(find.text('New Installment Plan'), findsOneWidget);
      expect(find.text('New Purchase'), findsOneWidget);
      expect(find.text('Ongoing Plan (In Progress)'), findsOneWidget);

      // Check preset count chips
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      expect(find.text('6'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      expect(find.text('Custom'), findsOneWidget);

      // Switch to Ongoing Plan
      await tester.tap(find.text('Ongoing Plan (In Progress)'));
      await tester.pumpAndSettle();

      // Verify ongoing fields
      expect(find.text('Remaining Amount (SAR)'), findsOneWidget);
      expect(find.text('Monthly Payment (SAR)'), findsOneWidget);
      expect(find.text('Remaining installments'), findsOneWidget);
    });
  });
}
