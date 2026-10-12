import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppThemes {
  AppThemes._();

  static const Color brandEmerald = Color(0xFF00C896);
  static const Color brandDarkBg = Color(0xFF0D1117);
  static const Color brandDarkCard = Color(0xFF161B22);
  static const Color brandDarkInput = Color(0xFF21262D);
  static const Color brandDarkBorder = Color(0xFF30363D);

  static const Color brandLightBg = Color(0xFFF8FAFC);
  static const Color brandLightCard = Colors.white;
  static const Color brandLightInput = Color(0xFFF1F5F9);
  static const Color brandLightBorder = Color(0xFFE2E8F0);
  static const Color brandLightText = Color(0xFF0F172A);
  static const Color brandLightSubtext = Color(0xFF64748B);

  // ─── Dark Theme ─────────────────────────────────────────────────────────────
  static ThemeData get darkTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: brandEmerald,
      brightness: Brightness.dark,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: brandDarkBg,
      textTheme: GoogleFonts.outfitTextTheme().apply(
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: brandDarkBg,
        foregroundColor: Colors.white,
        elevation: 0,
        titleTextStyle: GoogleFonts.outfit(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: brandDarkCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: brandDarkBorder),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: brandDarkInput,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        hintStyle: const TextStyle(color: Color(0xFF8B949E)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: brandDarkCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: brandDarkBorder),
        ),
      ),
      cardColor: brandDarkCard,
      canvasColor: brandDarkCard,
      dialogBackgroundColor: brandDarkCard,
      popupMenuTheme: const PopupMenuThemeData(
        color: brandDarkCard,
        textStyle: TextStyle(color: Colors.white),
      ),
      dropdownMenuTheme: const DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(brandDarkCard),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: brandDarkCard,
        indicatorColor: brandEmerald.withValues(alpha: 0.2),
        labelTextStyle: WidgetStateProperty.resolveWith((states) => GoogleFonts.outfit(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected) ? FontWeight.bold : FontWeight.normal,
          color: states.contains(WidgetState.selected) ? brandEmerald : const Color(0xFF8B949E),
        )),
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? brandEmerald : const Color(0xFF8B949E),
        )),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: brandDarkCard,
        modalBackgroundColor: brandDarkCard,
      ),
    );
  }

  // ─── Light Theme ────────────────────────────────────────────────────────────
  static ThemeData get lightTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: brandEmerald,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      brightness: Brightness.light,
      scaffoldBackgroundColor: brandLightBg,
      cardColor: brandLightCard,
      canvasColor: brandLightCard,
      dialogBackgroundColor: brandLightCard,
      popupMenuTheme: const PopupMenuThemeData(
        color: brandLightCard,
        textStyle: TextStyle(color: brandLightText),
      ),
      dropdownMenuTheme: const DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(brandLightCard),
        ),
      ),
      textTheme: GoogleFonts.outfitTextTheme().apply(
        bodyColor: brandLightText,
        displayColor: brandLightText,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: brandLightCard,
        foregroundColor: brandLightText,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: GoogleFonts.outfit(
          color: brandLightText,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: brandLightCard,
        indicatorColor: brandEmerald.withValues(alpha: 0.15),
        labelTextStyle: WidgetStateProperty.resolveWith((states) => GoogleFonts.outfit(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected) ? FontWeight.bold : FontWeight.normal,
          color: states.contains(WidgetState.selected) ? brandEmerald : brandLightSubtext,
        )),
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? brandEmerald : brandLightSubtext,
        )),
      ),
      cardTheme: CardThemeData(
        color: brandLightCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: brandLightBorder),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: brandLightInput,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: brandLightBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: brandEmerald, width: 2),
        ),
        hintStyle: const TextStyle(color: brandLightSubtext),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: brandLightCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: brandLightBorder),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: brandLightCard,
        modalBackgroundColor: brandLightCard,
      ),
    );
  }
}

extension ThemeContextExtension on BuildContext {
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;
  bool get isDark => isDarkMode;
  Color get scaffoldBg => Theme.of(this).scaffoldBackgroundColor;
  Color get cardBg => isDarkMode ? AppThemes.brandDarkCard : AppThemes.brandLightCard;
  Color get cardSurfaceBg => isDarkMode ? AppThemes.brandDarkCard : AppThemes.brandLightCard;
  Color get subtleCardBg => isDarkMode ? const Color(0xFF0D1117) : const Color(0xFFF8FAFC);
  Color get inputBg => isDarkMode ? AppThemes.brandDarkInput : AppThemes.brandLightInput;
  Color get borderColor => isDarkMode ? AppThemes.brandDarkBorder : AppThemes.brandLightBorder;
  Color get textPrimary => isDarkMode ? Colors.white : AppThemes.brandLightText;
  Color get textSecondary => isDarkMode ? const Color(0xFF8B949E) : AppThemes.brandLightSubtext;
  Color get textMuted => isDarkMode ? const Color(0xFF8B949E) : const Color(0xFF64748B);
  Color get chipBg => isDarkMode ? AppThemes.brandDarkInput : const Color(0xFFF1F5F9);
  Color get chipBorder => isDarkMode ? AppThemes.brandDarkBorder : const Color(0xFFCBD5E1);
  Color get dangerColor => isDarkMode ? const Color(0xFFFF5252) : const Color(0xFFDC2626);
  Color get primaryAccent => AppThemes.brandEmerald;
}
