import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/widgets/chat/pending_expense_confirmation_card.dart';
import '../support/localized_app.dart';

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

  Map<String, dynamic> familyPreview({
    String role = 'wife',
    String paidBy = 'me',
    String beneficiary = 'both',
    String? cls,
    List<String> dependents = const [],
  }) =>
      {
        'merchant': 'Panda',
        'amount': 180.0,
        'category_code': 'OPEX-GROCERY',
        'sub_category': 'pantry_staples',
        'paid_by': paidBy,
        'beneficiary': beneficiary,
        'available_sub_categories': [
          {'sub_code': 'pantry_staples', 'name_en': 'Pantry Staples', 'name_ar': 'المؤن'},
        ],
        'dependents': dependents,
        'household_mode': 'family_nafaqah',
        'recorder_role': role,
        'nafaqah_class': cls,
        'wives': [
          {'id': 'wife-1', 'display_name': 'Sara'},
        ],
      };

  /// Everything the card confirmed.
  Future<Map<String, String?>> confirmAll(WidgetTester tester, Map<String, dynamic> data,
      {Future<void> Function()? before, String lang = 'en'}) async {
    final out = <String, String?>{'called': 'no'};
    await tester.pumpWidget(localizedApp(
      PendingExpenseConfirmationCard(
        pendingData: data,
        onConfirm: (store, cat, subCat, paidBy, beneficiary, nafaqahClass, nafaqahSpouseId) {
          out
            ..['called'] = 'yes'
            ..['paid_by'] = paidBy
            ..['beneficiary'] = beneficiary
            ..['class'] = nafaqahClass
            ..['spouse'] = nafaqahSpouseId;
        },
        onCancel: () {},
      ),
      lang: lang,
    ));
    await tester.pumpAndSettle();
    if (before != null) await before();
    final confirm = find.byKey(const ValueKey('pec_confirm'));
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    return out;
  }

  Future<void> tapOption(WidgetTester tester, String cls) async {
    final option = find.byKey(ValueKey('nafaqah_option_$cls'));
    await tester.ensureVisible(option);
    await tester.tap(option);
    await tester.pumpAndSettle();
  }

  // UX-03: one Nafaqah question in family mode, worded with real names.
  testWidgets('family (wife): one question from her point of view, no "who paid / for whom" chips', (tester) async {
    final r = await confirmAll(tester, familyPreview(cls: 'wife_reimbursable'));
    expect(find.text('Who paid, and for whom?'), findsOneWidget);
    expect(find.text('My husband paid'), findsOneWidget);
    expect(find.text('I paid for the home — he pays me back'), findsOneWidget);
    expect(find.text('For me personally — from my allowance'), findsOneWidget);
    expect(find.text('WHO PAID?'), findsNothing);
    expect(find.text('FOR WHOM?'), findsNothing);
    expect(find.text('Partner'), findsNothing);
    expect(find.textContaining('50/50'), findsNothing);
    expect(r['class'], 'wife_reimbursable');
    expect(r['paid_by'], 'me');
    expect(r['beneficiary'], 'both');
    expect(r['spouse'], isNull);
  });

  testWidgets('family (wife): the personal option charges her allowance', (tester) async {
    final r = await confirmAll(tester, familyPreview(cls: 'wife_reimbursable'),
        before: () => tapOption(tester, 'wife_personal'));
    expect(r['class'], 'wife_personal');
    expect(r['paid_by'], 'me');
    expect(r['beneficiary'], 'me');
  });

  testWidgets('family (wife): "my husband paid" is an ordinary household expense', (tester) async {
    final r = await confirmAll(tester, familyPreview(cls: 'wife_reimbursable'),
        before: () => tapOption(tester, 'husband'));
    expect(r['class'], 'none');
    expect(r['paid_by'], 'partner');
  });

  testWidgets('family (husband): options name the wife; default is his household expense', (tester) async {
    final r = await confirmAll(tester, familyPreview(role: 'husband', paidBy: 'me'));
    expect(find.text('I paid (household expense)'), findsOneWidget);
    expect(find.text('Sara paid for the home — I pay her back'), findsOneWidget);
    expect(find.text("Sara's personal purchase — from her allowance"), findsOneWidget);
    expect(find.text('Partner'), findsNothing);
    expect(r['class'], 'none');
    expect(r['paid_by'], 'me');
  });

  testWidgets('family (husband): records what Sara paid for herself', (tester) async {
    final r = await confirmAll(tester, familyPreview(role: 'husband', paidBy: 'me'),
        before: () => tapOption(tester, 'wife_personal'));
    expect(r['class'], 'wife_personal');
    expect(r['paid_by'], 'partner');
    expect(r['beneficiary'], 'partner');
    expect(r['spouse'], 'wife-1');
  });

  testWidgets('family (husband, Arabic): real names, never "الشريك"', (tester) async {
    await confirmAll(tester, familyPreview(role: 'husband', paidBy: 'partner', cls: 'wife_reimbursable'), lang: 'ar');
    expect(find.text('مين دفع، ولمين؟'), findsOneWidget);
    expect(find.text('Sara دفعت للبيت — أردّها لها'), findsOneWidget);
    expect(find.textContaining('الشريك'), findsNothing);
    expect(find.text('للشريك'), findsNothing);
  });

  testWidgets('family: an optional child chip keeps the class and names the child', (tester) async {
    final r = await confirmAll(tester, familyPreview(cls: 'wife_reimbursable', dependents: ['Fahad']), before: () async {
      await tester.ensureVisible(find.text('Fahad'));
      await tester.tap(find.text('Fahad'));
      await tester.pumpAndSettle();
    });
    expect(r['class'], 'wife_reimbursable');
    expect(r['beneficiary'], 'fahad');
  });

  testWidgets('roommates: "who paid / for whom" chips stay, the payer chip is a payer label', (tester) async {
    final data = familyPreview()..['household_mode'] = 'not_family';
    final r = await confirmAll(tester, data, before: () async {
      await tester.tap(find.text('The other person paid'));
      await tester.pumpAndSettle();
    });
    expect(find.text('WHO PAID?'), findsOneWidget);
    expect(find.text('Who paid, and for whom?'), findsNothing);
    expect(r['class'], isNull);
    expect(r['paid_by'], 'partner');
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

    await tester.tap(find.byKey(const ValueKey('pec_confirm')));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.text('Choose which wife paid before saving.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nafaqah_wife_wife-2')));
    await tester.pumpAndSettle();
    expect(find.text('Mona paid for the home — I pay her back'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pec_confirm')));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(cls, 'wife_reimbursable');
    expect(spouse, 'wife-2');
  });

  testWidgets('family: a wife never sends a spouse id', (tester) async {
    final r = await confirmAll(tester, familyPreview(cls: 'wife_reimbursable'));
    expect(r['spouse'], isNull);
  });

}
