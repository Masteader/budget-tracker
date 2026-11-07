import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/providers/budget_provider.dart';
import 'package:budget_tracker/services/api_service.dart';
import 'package:budget_tracker/utils/household_categories.dart';

class _CategoriesApi extends ApiService {
  @override
  Future<Map<String, List<CategoryItem>>> fetchHouseholdCategories(String householdId) async => {
        'active': const [
          CategoryItem(code: 'CUSTOM-CAR_TRANSPORT', name: 'Car & Transport', isSystem: false),
          CategoryItem(code: 'OPEX-GROCERY', name: 'Groceries', isSystem: true),
        ],
        'inactive': const [
          CategoryItem(code: 'OPEX-FUEL', name: 'Fuel & Transport', isSystem: true, isActive: false),
        ],
      };
}

Budget _budget(String code, {double allocated = 0, double spent = 0, double delta = 0}) => Budget(
      id: 'b-$code',
      householdId: 'h1',
      month: '2026-11-01',
      categoryCode: code,
      allocatedAmount: allocated,
      spentAmount: spent,
      remainingAmount: allocated - spent,
      cycleKey: '2026-11',
      previousCycleDelta: delta,
    );

void main() {
  String localize(String code) => code == 'OPEX-GROCERY' ? 'Groceries (localized)' : code;

  group('resolveCategoryLabel', () {
    const cats = [
      CategoryItem(code: 'CUSTOM-CAR_TRANSPORT', name: 'Car & Transport', isSystem: false),
      CategoryItem(code: 'OPEX-GROCERY', name: 'Groceries', isSystem: true),
    ];

    test('custom category shows the name the household gave it', () {
      expect(resolveCategoryLabel('CUSTOM-CAR_TRANSPORT', cats, localize), 'Car & Transport');
    });

    test('system category uses the localized taxonomy name, not the stored English name', () {
      expect(resolveCategoryLabel('OPEX-GROCERY', cats, localize), 'Groceries (localized)');
    });

    test('matches codes regardless of case and padding', () {
      expect(resolveCategoryLabel(' custom-car_transport ', cats, localize), 'Car & Transport');
    });

    test('a custom name that is just the code is not used as a label', () {
      const raw = [CategoryItem(code: 'CUSTOM-HOME_OFFICE', name: 'CUSTOM-HOME_OFFICE', isSystem: false)];
      expect(resolveCategoryLabel('CUSTOM-HOME_OFFICE', raw, localize), 'Home Office');
    });

    test('unknown custom code never shows the raw code', () {
      expect(resolveCategoryLabel('custom-car_transport', const [], localize), 'Car Transport');
      expect(resolveCategoryLabel('CUSTOM-HOME_OFFICE', const [], localize), 'Home Office');
    });
  });

  group('isEmptyInactiveCategoryBudget', () {
    const inactive = {'OPEX-FUEL'};

    test('hides an empty budget whose category the household deactivated', () {
      expect(isEmptyInactiveCategoryBudget(_budget('OPEX-FUEL'), inactive), isTrue);
    });

    test('never hides a deactivated category that still holds money', () {
      expect(isEmptyInactiveCategoryBudget(_budget('OPEX-FUEL', allocated: 100), inactive), isFalse);
      expect(isEmptyInactiveCategoryBudget(_budget('OPEX-FUEL', spent: 20), inactive), isFalse);
    });

    test('never hides a deactivated category that carries a rollover', () {
      expect(isEmptyInactiveCategoryBudget(_budget('OPEX-FUEL', delta: -40), inactive), isFalse);
    });

    test('matches the inactive code regardless of case', () {
      expect(isEmptyInactiveCategoryBudget(_budget('opex-fuel'), inactive), isTrue);
    });

    test('keeps active categories even when empty', () {
      expect(isEmptyInactiveCategoryBudget(_budget('OPEX-GROCERY'), inactive), isFalse);
    });
  });

  testWidgets('context.categoryLabel reads custom names from BudgetProvider', (tester) async {
    final provider = BudgetProvider(api: _CategoriesApi());
    await provider.getHouseholdCategories('h1');

    await tester.pumpWidget(
      ChangeNotifierProvider<BudgetProvider>.value(
        value: provider,
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          locale: const Locale('en'),
          home: Builder(builder: (ctx) {
            return Text(ctx.categoryLabel('CUSTOM-CAR_TRANSPORT'));
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Car & Transport'), findsOneWidget);
    expect(inactiveCategoryCodes(provider.cachedCategories), {'OPEX-FUEL'});
  });

  group('findExistingCategory', () {
    const cats = {
      'active': [
        CategoryItem(code: 'CUSTOM-CAR_TRANSPORT', name: 'Car & Transport', isSystem: false),
        CategoryItem(code: 'OPEX-GROCERY', name: 'Groceries & Supermarkets', isSystem: true),
      ],
      'inactive': [
        CategoryItem(code: 'OPEX-FUEL', name: 'Fuel & Transport', isSystem: true, isActive: false),
      ],
    };
    // Stands in for trCat: system codes and their names in any language map to the shown label.
    String trCat(String s) => switch (s.trim()) {
          'OPEX-FUEL' || 'الوقود' || 'Fuel' => 'Fuel',
          'OPEX-GROCERY' => 'Groceries & Supermarkets',
          _ => s.trim(),
        };

    test('the generated code of an inactive category finds it as inactive', () {
      final hit = findExistingCategory('OPEX-FUEL', 'Fuel', cats, trCat);
      expect(hit?.category.code, 'OPEX-FUEL');
      expect(hit?.isActive, isFalse);
    });

    test('codes compare case-insensitively', () {
      expect(findExistingCategory('opex-grocery', 'x', cats, trCat)?.category.code, 'OPEX-GROCERY');
    });

    test('a typed name equal to a custom category name finds it under another code', () {
      final hit = findExistingCategory('OPEX-CARTRANSPORT', '  car &  transport ', cats, trCat);
      expect(hit?.category.code, 'CUSTOM-CAR_TRANSPORT');
      expect(hit?.isActive, isTrue);
    });

    test('a typed name equal to the stored or shown name of a system category finds it', () {
      expect(findExistingCategory('OPEX-FUELTRANSPORT', 'Fuel & Transport', cats, trCat)?.category.code, 'OPEX-FUEL');
      expect(findExistingCategory('OPEX-GROCERIESSUPERMARKETS', 'groceries & supermarkets', cats, trCat)?.category.code,
          'OPEX-GROCERY');
    });

    test('a system category name typed in another language finds it', () {
      expect(findExistingCategory('OPEX-CUSTOMABC', 'الوقود', cats, trCat)?.category.code, 'OPEX-FUEL');
    });

    test('Arabic names match without the article, hamza forms, taa marbuta or diacritics', () {
      const arabic = {
        'active': [CategoryItem(code: 'CUSTOM-HEALTH', name: 'الصحة والأدوية')],
        'inactive': <CategoryItem>[],
      };
      String same(String s) => s.trim();
      expect(findExistingCategory('OPEX-CUSTOMA', 'صحه وادوية', arabic, same)?.category.code, 'CUSTOM-HEALTH');
      expect(findExistingCategory('OPEX-CUSTOMB', 'الصِّحة والأدوية', arabic, same)?.category.code, 'CUSTOM-HEALTH');
      expect(findExistingCategory('OPEX-CUSTOMC', 'الرياضة', arabic, same), isNull);
      // App in Arabic: the system category shows as "الوقود".
      String trCatAr(String s) => s.trim() == 'OPEX-FUEL' ? 'الوقود' : s.trim();
      expect(findExistingCategory('OPEX-CUSTOMD', 'وقود', cats, trCatAr)?.category.code, 'OPEX-FUEL');
    });

    test('a new name finds nothing, and nothing is found without categories', () {
      expect(findExistingCategory('OPEX-GYM', 'Gym', cats, trCat), isNull);
      expect(findExistingCategory('OPEX-FUEL', 'Fuel', null, trCat), isNull);
    });
  });

  for (final (lang, fuel) in [('ar', 'الوقود'), ('ur', 'ایندھن')]) {
    testWidgets('context.categoryLabel in $lang: system name localized, custom name as given', (tester) async {
      final provider = BudgetProvider(api: _CategoriesApi());
      await provider.getHouseholdCategories('h1');

      await tester.pumpWidget(
        ChangeNotifierProvider<BudgetProvider>.value(
          value: provider,
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizationsDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('en'), Locale('ar'), Locale('ur')],
            locale: Locale(lang),
            home: Builder(builder: (ctx) {
              return Column(children: [
                Text(ctx.categoryLabel('CUSTOM-CAR_TRANSPORT')),
                Text(ctx.categoryLabel('OPEX-FUEL')),
              ]);
            }),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Car & Transport'), findsOneWidget);
      expect(find.text(fuel), findsOneWidget);
      expect(find.textContaining('CUSTOM'), findsNothing);
    });
  }
}
