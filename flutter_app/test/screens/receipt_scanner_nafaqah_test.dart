import 'package:budget_tracker/screens/scanner/receipt_scanner_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/localized_app.dart';

void main() {
  Widget testSheet({
    Map<String, dynamic>? initialScanResult,
    String lang = 'en',
  }) {
    return localizedApp(
      Scaffold(
        body: ReceiptScannerSheet(
          householdId: 'hh-test-family',
          initialScanResult: initialScanResult ??
              {
                'status': 'preview',
                'merchant': 'Tamimi Markets',
                'amount': 250.0,
                'category_code': 'OPEX-GROCERY',
                'household_mode': 'family_nafaqah',
                'is_family': true,
                'recorder_role': 'husband',
                'caller_role': 'husband',
                'items': [
                  {'name': 'Groceries', 'quantity': 1.0, 'price': 250.0}
                ],
              },
        ),
      ),
      lang: lang,
      scaffold: false,
    );
  }

  testWidgets('ReceiptScannerSheet in Family mode: payer has Me and Partner, never Both (Shared)', (tester) async {
    await tester.pumpWidget(testSheet());
    await tester.pumpAndSettle();

    // Verify "Who Paid?" section
    expect(find.byKey(const ValueKey('spent_by_me')), findsOneWidget);
    expect(find.byKey(const ValueKey('spent_by_partner')), findsOneWidget);
    // Rule 02.3: Both (Shared) is NEVER an option for who paid the cashier in Family mode
    expect(find.byKey(const ValueKey('spent_by_both')), findsNothing);
  });

  testWidgets('ReceiptScannerSheet in Family mode: For Whom selector has all beneficiary chips', (tester) async {
    await tester.pumpWidget(testSheet());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('beneficiary_both')), findsOneWidget);
    expect(find.byKey(const ValueKey('beneficiary_me')), findsOneWidget);
    expect(find.byKey(const ValueKey('beneficiary_partner')), findsOneWidget);
    expect(find.byKey(const ValueKey('beneficiary_children')), findsOneWidget);
  });

  testWidgets('ReceiptScannerSheet live Nafaqah preview: dynamically updates badge based on payer and beneficiary', (tester) async {
    await tester.pumpWidget(testSheet(lang: 'en'));
    await tester.pumpAndSettle();

    // Default: Paid by Me, For Whom = Household -> Paid by Husband
    expect(find.textContaining('Paid by husband — household expense'), findsOneWidget);

    // Tap Paid by Partner (Wife)
    await tester.tap(find.byKey(const ValueKey('spent_by_partner')));
    await tester.pumpAndSettle();

    // Now Paid by Partner, For Whom = Household -> Reimbursable Wife Advance
    expect(find.textContaining('Owed to wife:'), findsOneWidget);
    expect(find.textContaining('100%'), findsNothing);
    expect(find.descendant(of: find.byKey(const ValueKey('nafaqah_badge_text')), matching: find.textContaining('%')), findsNothing);

    // Tap For Whom = Wife / Partner
    await tester.tap(find.byKey(const ValueKey('beneficiary_partner')));
    await tester.pumpAndSettle();

    // Now Paid by Partner, For Whom = Wife -> Wife Personal Allowance
    expect(find.textContaining('From wife\'s personal allowance'), findsOneWidget);
  });

  testWidgets('ReceiptScannerSheet: switching back to Me clears wife nafaqah class without resurrecting stale state', (tester) async {
    await tester.pumpWidget(testSheet(lang: 'en'));
    await tester.pumpAndSettle();

    // Tap Paid by Partner (Wife) + Beneficiary Partner
    await tester.tap(find.byKey(const ValueKey('spent_by_partner')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('beneficiary_partner')));
    await tester.pumpAndSettle();
    expect(find.textContaining('From wife\'s personal allowance'), findsOneWidget);

    // Switch back to Paid by Me
    await tester.tap(find.byKey(const ValueKey('spent_by_me')));
    await tester.pumpAndSettle();

    // Must show Paid by Husband and NOT resurrect wife_personal!
    expect(find.textContaining('Paid by husband — household expense'), findsOneWidget);
    expect(find.textContaining('From wife\'s personal allowance'), findsNothing);
  });

  testWidgets('ReceiptScannerSheet: Arabic-locale renders dignified Arabic copy', (tester) async {
    await tester.pumpWidget(testSheet(lang: 'ar'));
    await tester.pumpAndSettle();

    // Default: Paid by husband in Arabic
    expect(find.textContaining('دفعه الزوج — مصاريف المنزل'), findsOneWidget);

    // Tap Paid by Partner (Wife)
    await tester.tap(find.byKey(const ValueKey('spent_by_partner')));
    await tester.pumpAndSettle();

    // Reimbursable wife advance in Arabic
    expect(find.textContaining('مستحقات للزوجة:'), findsOneWidget);
    expect(find.textContaining('100%'), findsNothing);
    expect(find.descendant(of: find.byKey(const ValueKey('nafaqah_badge_text')), matching: find.textContaining('%')), findsNothing);
  });
}
