import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/models/category_catalog.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _newCodes = [
  'OPEX-HOUSING',
  'OPEX-EDUCATION',
  'OPEX-DOMESTIC-HELP',
  'OPEX-FAMILY-SUPPORT',
  'OPEX-CHARITY',
  'OPEX-TRANSPORT',
  'OPEX-INSURANCE',
  'OPEX-REMITTANCE',
];

void main() {
  group('CategoryCatalog (R4 taxonomy refresh)', () {
    test('every new system code has its own icon, colour and emoji', () {
      final fallback = CategoryCatalog.visual('NOT-A-CODE');
      final icons = <IconData>{};
      for (final code in _newCodes) {
        final v = CategoryCatalog.visual(code);
        expect(v.icon, isNot(fallback.icon), reason: code);
        expect(v.emoji.trim(), isNotEmpty, reason: code);
        icons.add(v.icon);
      }
      expect(icons.length, _newCodes.length, reason: 'icons are distinct');
    });

    test('pickers offer the new codes and keep a current legacy code selectable', () {
      for (final code in _newCodes) {
        expect(CategoryCatalog.pickerCodes, contains(code));
      }
      expect(CategoryCatalog.pickerCodes.toSet().length, CategoryCatalog.pickerCodes.length);
      expect(CategoryCatalog.pickerCodesIncluding('CAPEX-EDUCATION'), contains('CAPEX-EDUCATION'));
      expect(CategoryCatalog.pickerCodesIncluding('OPEX-MISC'), CategoryCatalog.pickerCodes);
      expect(CategoryCatalog.pickerCodesIncluding(null), CategoryCatalog.pickerCodes);
    });

    test('normalize maps known aliases and underscore spellings', () {
      expect(CategoryCatalog.normalize('opex-groceries'), 'OPEX-GROCERY');
      expect(CategoryCatalog.normalize('OPEX-HEALTHCARE'), 'OPEX-HEALTH');
      expect(CategoryCatalog.normalize('OPEX-DOMESTIC_HELP'), 'OPEX-DOMESTIC-HELP');
      expect(CategoryCatalog.normalize('OPEX-FAMILY_SUPPORT'), 'OPEX-FAMILY-SUPPORT');
      expect(CategoryCatalog.normalize(' OPEX-HOUSING '), 'OPEX-HOUSING');
      expect(CategoryCatalog.normalize(null), 'OPEX-MISC');
    });
  });

  group('category names', () {
    test('new codes have en / ar / ur names (no code-like fallback)', () {
      for (final lang in ['en', 'ar', 'ur']) {
        final l = AppLocalizations(Locale(lang));
        for (final code in _newCodes) {
          final name = l.category(code);
          expect(name, isNot(code), reason: '$lang $code');
          expect(name.contains('-'), isFalse, reason: '$lang $code -> $name');
          if (lang != 'en') expect(RegExp('[؀-ۿ]').hasMatch(name), isTrue, reason: '$lang $code');
          if (lang == 'ur') expect(RegExp('[يكىة]').hasMatch(name), isFalse, reason: 'ur $code');
        }
      }
    });

    test('fuel no longer claims transport now that transport is its own category', () {
      final en = AppLocalizations(const Locale('en'));
      expect(en.category('OPEX-FUEL'), isNot(en.category('OPEX-TRANSPORT')));
      expect(en.category('OPEX-FUEL').toLowerCase().contains('transport'), isFalse);
    });
  });
}
