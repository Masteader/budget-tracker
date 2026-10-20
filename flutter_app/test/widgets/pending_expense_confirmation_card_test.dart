import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/widgets/chat/pending_expense_confirmation_card.dart';

void main() {
  testWidgets('renders category, subcategory dropdown and for whom child chips', (tester) async {
    final pendingData = {
      'merchant': 'Beit Al Shawarma',
      'amount': 10.0,
      'category_code': 'OPEX-DINING',
      'sub_category': 'restaurants_dinners',
      'paid_by': 'me',
      'beneficiary': 'Sarah',
      'available_sub_categories': [
        {'sub_code': 'restaurants_dinners', 'name_en': 'Restaurants & Meals', 'name_ar': 'المطاعم والوجبات'},
        {'sub_code': 'coffee_bakeries', 'name_en': 'Coffee & Bakeries', 'name_ar': 'القهوة والمخابز'},
      ],
      'dependents': ['Sarah', 'Fahad'],
    };

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PendingExpenseConfirmationCard(
              pendingData: pendingData,
              onConfirm: (store, cat, subCat, paidBy, beneficiary, nafaqahClass, nafaqahSpouseId) {},
              onCancel: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Beit Al Shawarma'), findsOneWidget);
    expect(find.text('Restaurants & Meals'), findsOneWidget);
    expect(find.text('Sarah'), findsOneWidget);
  });

  testWidgets('defaults to first available subcategory and passes it on confirm when sub_category is null', (tester) async {
    String? confirmedStore;
    String? confirmedCat;
    String? confirmedSub;
    String? confirmedPaidBy;
    String? confirmedBeneficiary;

    final pendingData = {
      'merchant': 'Big Baik',
      'amount': 25.0,
      'category_code': 'OPEX-DINING',
      'sub_category': null, // null as reported in bug
      'paid_by': 'me',
      'beneficiary': 'both',
      'available_sub_categories': [
        {'sub_code': 'restaurants_dinners', 'name_en': 'Restaurants & Meals', 'name_ar': 'المطاعم والوجبات'},
        {'sub_code': 'coffee_bakeries', 'name_en': 'Coffee & Bakeries', 'name_ar': 'القهوة والمخابز'},
      ],
      'dependents': <String>[],
    };

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PendingExpenseConfirmationCard(
              pendingData: pendingData,
              onConfirm: (store, cat, subCat, paidBy, beneficiary, nafaqahClass, nafaqahSpouseId) {
                confirmedStore = store;
                confirmedCat = cat;
                confirmedSub = subCat;
                confirmedPaidBy = paidBy;
                confirmedBeneficiary = beneficiary;
              },
              onCancel: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Big Baik'), findsOneWidget);
    expect(find.text('Restaurants & Meals'), findsOneWidget);

    final confirmBtn = find.text('Confirm & Add Expense');
    expect(confirmBtn, findsOneWidget);
    await tester.tap(confirmBtn);
    await tester.pumpAndSettle();

    expect(confirmedStore, equals('Big Baik'));
    expect(confirmedCat, equals('OPEX-DINING'));
    expect(confirmedSub, equals('restaurants_dinners'));
    expect(confirmedPaidBy, equals('me'));
    expect(confirmedBeneficiary, equals('both'));
  });

  Map<String, dynamic> familyPreview({String role = 'wife', String paidBy = 'me', String beneficiary = 'both', String? cls}) => {
        'merchant': 'Panda',
        'amount': 180.0,
        'category_code': 'OPEX-GROCERY',
        'sub_category': 'pantry_staples',
        'paid_by': paidBy,
        'beneficiary': beneficiary,
        'available_sub_categories': [
          {'sub_code': 'pantry_staples', 'name_en': 'Pantry Staples', 'name_ar': 'المؤن'},
        ],
        'dependents': <String>[],
        'household_mode': 'family_nafaqah',
        'recorder_role': role,
        'nafaqah_class': cls,
      };

  Future<String?> confirmWith(WidgetTester tester, Map<String, dynamic> data, {Future<void> Function()? before}) async {
    String? confirmed = 'unset';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: PendingExpenseConfirmationCard(
            pendingData: data,
            onConfirm: (store, cat, subCat, paidBy, beneficiary, nafaqahClass, nafaqahSpouseId) => confirmed = nafaqahClass,
            onCancel: () {},
          ),
        ),
      ),
    ));
    if (before != null) await before();
    await tester.tap(find.text('Confirm & Add Expense'));
    await tester.pumpAndSettle();
    return confirmed;
  }

  testWidgets('family: wife-paid shared expense is confirmed as a husband debt, no split', (tester) async {
    final cls = await confirmWith(tester, familyPreview(cls: 'wife_reimbursable'));
    expect(find.text('Shared for family (husband reimburses)'), findsOneWidget);
    expect(find.text('Personal (from my allowance)'), findsOneWidget);
    expect(find.text('Husband paid (household expense)'), findsNothing);
    expect(find.textContaining('50/50'), findsNothing);
    expect(cls, 'wife_reimbursable');
  });

  testWidgets('family: the wife can mark it personal (charged to her allowance)', (tester) async {
    final cls = await confirmWith(tester, familyPreview(cls: 'wife_reimbursable'), before: () async {
      await tester.tap(find.text('Personal (from my allowance)'));
      await tester.pumpAndSettle();
    });
    expect(cls, 'wife_personal');
  });

  testWidgets('family: husband-paid expense needs no choice and is never a debt', (tester) async {
    final cls = await confirmWith(tester, familyPreview(role: 'husband', paidBy: 'me'));
    expect(find.text('Shared for family (husband reimburses)'), findsNothing);
    expect(cls, 'none');
  });

  testWidgets('family: husband records what his wife paid for herself', (tester) async {
    final cls = await confirmWith(tester, familyPreview(role: 'husband', paidBy: 'partner', beneficiary: 'partner'));
    expect(find.text('Personal (from her allowance)'), findsOneWidget);
    expect(cls, 'wife_personal');
  });

  testWidgets('roommates: no Nafaqah class is sent', (tester) async {
    final data = familyPreview()..['household_mode'] = 'not_family';
    final cls = await confirmWith(tester, data);
    expect(find.text('Shared for family (husband reimburses)'), findsNothing);
    expect(cls, isNull);
  });

  // External review (Gemini) HIGH 4: the class follows the edited chips, and a
  // husband with several wives says which wife paid.
  testWidgets('family: editing "who paid" after a debt suggestion sends no stale class', (tester) async {
    final cls = await confirmWith(tester, familyPreview(cls: 'wife_reimbursable'), before: () async {
      await tester.tap(find.text('Partner').first); // who paid: my husband
      await tester.pumpAndSettle();
    });
    expect(cls, 'none');
  });

  testWidgets('family: a husband with several wives must choose the wife', (tester) async {
    final data = familyPreview(role: 'husband', paidBy: 'partner', cls: 'wife_reimbursable')
      ..['wives'] = [
        {'id': 'wife-1', 'display_name': 'Sara'},
        {'id': 'wife-2', 'display_name': 'Mona'},
      ]
      ..['nafaqah_spouse_required'] = true;
    var calls = 0;
    String? spouse;
    String? cls;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: PendingExpenseConfirmationCard(
            pendingData: data,
            onConfirm: (store, cat, subCat, paidBy, beneficiary, nafaqahClass, nafaqahSpouseId) {
              calls++;
              cls = nafaqahClass;
              spouse = nafaqahSpouseId;
            },
            onCancel: () {},
          ),
        ),
      ),
    ));
    expect(find.text('Which wife paid?'), findsOneWidget);

    await tester.tap(find.text('Confirm & Add Expense'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.text('Choose which wife paid before saving.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nafaqah_wife_wife-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm & Add Expense'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(cls, 'wife_reimbursable');
    expect(spouse, 'wife-2');
  });

  testWidgets('family: a wife never sends a spouse id', (tester) async {
    String? spouse = 'unset';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: PendingExpenseConfirmationCard(
            pendingData: familyPreview(cls: 'wife_reimbursable'),
            onConfirm: (store, cat, subCat, paidBy, beneficiary, nafaqahClass, nafaqahSpouseId) => spouse = nafaqahSpouseId,
            onCancel: () {},
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Confirm & Add Expense'));
    await tester.pumpAndSettle();
    expect(spouse, isNull);
  });
}
