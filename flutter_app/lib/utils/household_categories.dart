import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/models.dart';
import '../providers/budget_provider.dart';

final _customPrefix = RegExp(r'^custom[-_]', caseSensitive: false);

/// Display name for a category [code].
///
/// A household's own (non-system) category shows the name the household gave
/// it. System categories use the localized taxonomy name from [localize]. An
/// unknown custom code falls back to a readable form of the code, never the
/// raw code.
String resolveCategoryLabel(
  String code,
  Iterable<CategoryItem> householdCategories,
  String Function(String code) localize,
) {
  final key = _codeKey(code);
  for (final c in householdCategories) {
    if (_codeKey(c.code) == key) {
      final name = c.name.trim();
      // A name that is just the code (or another CUSTOM- code) is no name.
      if (!c.isSystem && name.isNotEmpty && _codeKey(name) != key && !_customPrefix.hasMatch(name)) {
        return name;
      }
      break;
    }
  }
  final localized = localize(code);
  if (localized != code.trim()) return localized;
  return _humanizeCustomCode(code.trim());
}

/// Codes compare trimmed and case-insensitively (`custom-car_transport` is `CUSTOM-CAR_TRANSPORT`).
String _codeKey(String code) => code.trim().toUpperCase();

/// `CUSTOM-CAR_TRANSPORT` -> `Car Transport`. Non-custom codes are returned as is.
String _humanizeCustomCode(String code) {
  final match = _customPrefix.firstMatch(code);
  if (match == null) return code;
  final words = code
      .substring(match.end)
      .split(RegExp(r'[_\-\s]+'))
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase());
  final label = words.join(' ');
  return label.isEmpty ? code : label;
}

/// The household category a new category would duplicate: the one with the
/// same [code] (Add Category builds the code from the typed name, so "Fuel"
/// is `OPEX-FUEL`), or the one whose stored or shown name is the typed [name].
/// [localize] is `trCat`; it maps a system category name typed in any app
/// language to the shown label. Active categories are checked first. Null
/// when nothing matches or [categories] has not loaded.
({CategoryItem category, bool isActive})? findExistingCategory(
  String code,
  String name,
  Map<String, List<CategoryItem>>? categories,
  String Function(String code) localize,
) {
  if (categories == null) return null;
  final key = _codeKey(code);
  final typed = {_nameKey(name), _nameKey(localize(name))}..remove('');
  for (final isActive in const [true, false]) {
    for (final c in categories[isActive ? 'active' : 'inactive'] ?? const <CategoryItem>[]) {
      final names = {_nameKey(c.name), _nameKey(resolveCategoryLabel(c.code, [c], localize))};
      if (_codeKey(c.code) == key || typed.any(names.contains)) {
        return (category: c, isActive: isActive);
      }
    }
  }
  return null;
}

/// Names compare trimmed, case-insensitively and with runs of spaces collapsed.
String _nameKey(String name) => name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// Codes of the categories the household has deactivated.
/// Codes are normalized (trimmed, upper case); compare with [isEmptyInactiveCategoryBudget].
Set<String> inactiveCategoryCodes(Map<String, List<CategoryItem>>? categories) =>
    {for (final c in categories?['inactive'] ?? const <CategoryItem>[]) _codeKey(c.code)};

/// True for a budget row whose category the household deactivated and that
/// holds no money. Such rows are hidden like the budget screen hides them; a
/// deactivated category that still has an allocation, spending or a rollover
/// from the previous cycle stays visible so money is never hidden.
/// [inactiveCodes] comes from [inactiveCategoryCodes].
bool isEmptyInactiveCategoryBudget(Budget budget, Set<String> inactiveCodes) =>
    inactiveCodes.contains(_codeKey(budget.categoryCode)) &&
    budget.allocatedAmount == 0 &&
    budget.spentAmount == 0 &&
    budget.previousCycleDelta == 0;

extension HouseholdCategoryLabels on BuildContext {
  /// Category display name honoring the household's custom category names.
  /// Call from `build` only: it subscribes to [BudgetProvider] so the label
  /// updates once categories load.
  String categoryLabel(String code) {
    Map<String, List<CategoryItem>>? categories;
    try {
      categories = Provider.of<BudgetProvider>(this, listen: true).cachedCategories;
    } catch (_) {}
    return resolveCategoryLabel(
      code,
      [...?categories?['active'], ...?categories?['inactive']],
      trCat,
    );
  }
}
