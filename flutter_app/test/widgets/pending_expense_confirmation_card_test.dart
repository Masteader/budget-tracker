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
              onConfirm: (store, cat, subCat, paidBy, beneficiary) {},
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
}
