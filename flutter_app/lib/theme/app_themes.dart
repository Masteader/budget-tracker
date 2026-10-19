import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppThemes {
  AppThemes._();

  // ─── Iced Ocean Sovereign Palette Tokens ─────────────────────────────────────
  static const Color brandEmerald = Color(0xFF00E5BF); // Electric Teal
  static const Color brandDarkBg = Color(0xFF051424);  // Arctic Void Canvas
  static const Color brandDarkCard = Color(0xFF0B192C);// Glacial Elevate Card
  static const Color brandDarkInput = Color(0xFF0F223B);// Sub-surface Input / Field
  static const Color brandDarkBorder = Color(0xFF1B3150);// Deep Glacial Rim Border

  // ─── Sovereign Highlights ───────────────────────────────────────────────────
  static const Color iceCyan = Color(0xFF4DE6F7);       // Ice Cyan Accent
  static const Color electricTeal = Color(0xFF00E5BF);  // Sovereign Electric Teal
  static const Color mintNeon = Color(0xFF73FBC4);      // Mint Neon Status
  static const Color champagneGold = Color(0xFFD4AF37); // Sovereign Gold Accent
  static const Color success = Color(0xFF00C896);       // Surplus / Safe Emerald
  static const Color accentTextLight = Color(0xFF00796B); // AA-contrast teal on light canvas
  static const Color successTextLight = Color(0xFF047857); // AA-contrast emerald on light canvas
  static const Color deepGlacial = Color(0xFF071C33);   // Nav & Elevated HUD

  static const Color brandLightBg = Color(0xFFF8FAFC);
  static const Color brandLightCard = Colors.white;
  static const Color brandLightInput = Color(0xFFF1F5F9);
  static const Color brandLightBorder = Color(0xFFE2E8F0);
  static const Color brandLightText = Color(0xFF0F172A);
  static const Color brandLightSubtext = Color(0xFF64748B);

  // ─── Dark Theme ─────────────────────────────────────────────────────────────
  static ThemeData get darkTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: electricTeal,
      brightness: Brightness.dark,
    ).copyWith(
      primary: electricTeal,
      secondary: iceCyan,
      surface: brandDarkCard,
      surfaceContainerHighest: brandDarkInput,
      outline: brandDarkBorder,
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
        backgroundColor: deepGlacial,
        indicatorColor: iceCyan.withValues(alpha: 0.18),
        labelTextStyle: WidgetStateProperty.resolveWith((states) => GoogleFonts.outfit(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected) ? FontWeight.bold : FontWeight.normal,
          color: states.contains(WidgetState.selected) ? iceCyan : const Color(0xFF8B949E),
        )),
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? iceCyan : const Color(0xFF8B949E),
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
  Color get subtleCardBg => isDarkMode ? AppThemes.deepGlacial : const Color(0xFFF8FAFC);
  Color get inputBg => isDarkMode ? AppThemes.brandDarkInput : AppThemes.brandLightInput;
  Color get borderColor => isDarkMode ? AppThemes.brandDarkBorder : AppThemes.brandLightBorder;
  Color get textPrimary => isDarkMode ? Colors.white : AppThemes.brandLightText;
  Color get textSecondary => isDarkMode ? const Color(0xFF8B949E) : AppThemes.brandLightSubtext;
  Color get textMuted => isDarkMode ? const Color(0xFF8B949E) : const Color(0xFF64748B);
  Color get chipBg => isDarkMode ? AppThemes.brandDarkInput : const Color(0xFFF1F5F9);
  Color get chipBorder => isDarkMode ? AppThemes.brandDarkBorder : const Color(0xFFCBD5E1);
  Color get dangerColor => isDarkMode ? const Color(0xFFFF5252) : const Color(0xFFDC2626);
  Color get primaryAccent => AppThemes.electricTeal;
  Color get electricTeal => AppThemes.electricTeal;
  Color get iceCyan => AppThemes.iceCyan;
  Color get mintNeon => AppThemes.mintNeon;
  Color get champagneGold => AppThemes.champagneGold;

  /// Teal accent for *text and icons*. The electric teal brand colour only
  /// reaches ~1.6:1 contrast on the light canvas, so light mode uses a deeper
  /// teal that meets WCAG AA (≥4.5:1) for body-size text.
  Color get accentText => isDarkMode ? AppThemes.electricTeal : AppThemes.accentTextLight;

  /// Success/surplus green for *text and icons*, contrast-safe in light mode.
  Color get successText => isDarkMode ? AppThemes.success : AppThemes.successTextLight;

  LinearGradient get icedHeroGradient => isDarkMode
      ? const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0E233D), Color(0xFF051424)],
        )
      : const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF00E5BF), Color(0xFF0284C7)],
        );

  LinearGradient get icedAccentGradient => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppThemes.electricTeal, AppThemes.iceCyan],
      );
}
