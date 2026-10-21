/// System expense categories: the codes the pickers offer and how each one
/// looks (emoji used in chip labels, an icon and an accent colour).
///
/// Names live in `AppLocalizations.category` (en / ar / ur); this file only
/// holds the visual side so every picker and card shows the same thing.
library;

import 'package:flutter/material.dart';

class CategoryVisual {
  final String emoji;
  final IconData icon;
  final Color color;

  const CategoryVisual(this.emoji, this.icon, this.color);
}

class CategoryCatalog {
  CategoryCatalog._();

  /// Codes offered when the user picks a category, most common first.
  static const List<String> pickerCodes = [
    'OPEX-GROCERY',
    'OPEX-DINING',
    'OPEX-HOUSING',
    'OPEX-UTILITIES',
    'OPEX-TRANSPORT',
    'OPEX-FUEL',
    'OPEX-EDUCATION',
    'OPEX-HEALTH',
    'OPEX-SHOPPING',
    'OPEX-ENTERTAINMENT',
    'OPEX-DOMESTIC-HELP',
    'OPEX-FAMILY-SUPPORT',
    'OPEX-CHARITY',
    'OPEX-INSURANCE',
    'OPEX-REMITTANCE',
    'OPEX-GOV',
    'OPEX-MISC',
  ];

  static const CategoryVisual _fallback = CategoryVisual('📦 ', Icons.category_outlined, Color(0xFF94A3B8));

  static const Map<String, CategoryVisual> _visuals = {
    'OPEX-GROCERY': CategoryVisual('🛒 ', Icons.shopping_cart_outlined, Color(0xFF10B981)),
    'OPEX-DINING': CategoryVisual('☕ ', Icons.local_cafe_outlined, Color(0xFFF59E0B)),
    'OPEX-HOUSING': CategoryVisual('🏠 ', Icons.home_outlined, Color(0xFF6366F1)),
    'OPEX-UTILITIES': CategoryVisual('⚡ ', Icons.bolt_outlined, Color(0xFFEAB308)),
    'OPEX-TRANSPORT': CategoryVisual('🚗 ', Icons.directions_car_outlined, Color(0xFF0EA5E9)),
    'OPEX-FUEL': CategoryVisual('⛽ ', Icons.local_gas_station_outlined, Color(0xFF38BDF8)),
    'OPEX-EDUCATION': CategoryVisual('🎒 ', Icons.school_outlined, Color(0xFF8B5CF6)),
    'CAPEX-EDUCATION': CategoryVisual('🎓 ', Icons.history_edu_outlined, Color(0xFFA78BFA)),
    'OPEX-HEALTH': CategoryVisual('💊 ', Icons.medication_outlined, Color(0xFFF43F5E)),
    'OPEX-SHOPPING': CategoryVisual('🛍️ ', Icons.shopping_bag_outlined, Color(0xFFEC4899)),
    'OPEX-ENTERTAINMENT': CategoryVisual('🎮 ', Icons.sports_esports_outlined, Color(0xFFD946EF)),
    'OPEX-DOMESTIC-HELP': CategoryVisual('🧹 ', Icons.cleaning_services_outlined, Color(0xFF14B8A6)),
    'OPEX-FAMILY-SUPPORT': CategoryVisual('👪 ', Icons.family_restroom, Color(0xFFFB923C)),
    'OPEX-CHARITY': CategoryVisual('🤲 ', Icons.volunteer_activism_outlined, Color(0xFF22C55E)),
    'OPEX-INSURANCE': CategoryVisual('🛡️ ', Icons.shield_outlined, Color(0xFF64748B)),
    'OPEX-REMITTANCE': CategoryVisual('💸 ', Icons.currency_exchange, Color(0xFF00E5BF)),
    'OPEX-GOV': CategoryVisual('🏛️ ', Icons.account_balance_outlined, Color(0xFF78716C)),
    'OPEX-MISC': _fallback,
  };

  static const Map<String, String> _aliases = {
    'OPEX-GROCERIES': 'OPEX-GROCERY',
    'OPEX-HEALTHCARE': 'OPEX-HEALTH',
    'OPEX-DOMESTIC_HELP': 'OPEX-DOMESTIC-HELP',
    'OPEX-FAMILY_SUPPORT': 'OPEX-FAMILY-SUPPORT',
  };

  /// Upper-cased code with known aliases resolved; null/blank → OPEX-MISC.
  static String normalize(String? code) {
    final c = (code ?? '').trim().toUpperCase();
    if (c.isEmpty) return 'OPEX-MISC';
    return _aliases[c] ?? c;
  }

  static CategoryVisual visual(String? code) => _visuals[normalize(code)] ?? _fallback;

  static String emoji(String? code) => visual(code).emoji;

  /// [pickerCodes] plus [current] when it is a valid code the list does not
  /// offer (a legacy or household category), so a dropdown never silently
  /// swaps an existing transaction's category.
  static List<String> pickerCodesIncluding(String? current) {
    if (current == null || current.trim().isEmpty) return pickerCodes;
    final code = normalize(current);
    if (pickerCodes.contains(code)) return pickerCodes;
    return [...pickerCodes, code];
  }
}
