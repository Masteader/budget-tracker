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

  // ─── Light-mode text tokens (UX-06: WCAG AA, ≥4.5:1 on white and the canvas) ─
  static const Color goldTextLight = Color(0xFF7A5C00);  // owed-to-wife amounts, gold badges
  static const Color infoTextLight = Color(0xFF0369A1);  // links and "ice cyan" text
  static const Color warnTextLight = Color(0xFF9A5B00);  // pending / amber text
  static const Color dangerTextLight = Color(0xFFB91C1C); // errors and deficits
  static const Color warnTextDark = Color(0xFFFBBF24);
  static const Color infoTextDark = Color(0xFF38BDF8);

  /// Ink for labels on a [success] (#00C896) fill: 8.8:1. White on it is 2.2:1.
  static const Color onSuccessFill = Color(0xFF0A0F1D);

  /// Outfit has no Arabic glyphs: Arabic and Urdu text falls back to the
  /// bundled Cairo (UX-20) instead of the phone's book face.
  static const List<String> arabicFallback = ['Cairo'];

  static TextTheme _textTheme(Color color) => GoogleFonts.outfitTextTheme().apply(
        bodyColor: color,
        displayColor: color,
        fontFamilyFallback: arabicFallback,
      );

  // ─── Sovereign Light Theme Tokens (Calm, Anti-Glare Sovereign Fintech) ─────
  static const Color brandLightPrimary = Color(0xFF0F766E);   // Deep Sovereign Coastal Teal (AAA contrast)
  static const Color brandLightSecondary = Color(0xFF0369A1); // Sovereign Ocean Azure (5.9:1 on white)
  static const Color brandLightBg = Color(0xFFF6F8FA);        // Soft Anti-Glare Canvas
  static const Color brandLightCard = Colors.white;
  static const Color brandLightInput = Color(0xFFEDF2F7);     // Balanced Input Fill
  static const Color brandLightBorder = Color(0xFFE2E8F0);    // Crisp Structural Border
  static const Color brandLightText = Color(0xFF0F172A);      // Deep Ink Primary Text
  static const Color brandLightSubtext = Color(0xFF475569);   // Slate Secondary Text (≥6.9:1 on light surfaces)

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
      textTheme: _textTheme(Colors.white),
      appBarTheme: AppBarTheme(
        backgroundColor: brandDarkBg,
        foregroundColor: Colors.white,
        elevation: 0,
        titleTextStyle: GoogleFonts.outfit(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ).copyWith(fontFamilyFallback: arabicFallback),
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
        ).copyWith(fontFamilyFallback: arabicFallback)),
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
      seedColor: brandLightPrimary,
      brightness: Brightness.light,
    ).copyWith(
      primary: brandLightPrimary,
      secondary: brandLightSecondary,
      surface: brandLightCard,
      surfaceContainerHighest: brandLightInput,
      outline: brandLightBorder,
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
      textTheme: _textTheme(brandLightText),
      appBarTheme: AppBarTheme(
        backgroundColor: brandLightCard,
        foregroundColor: brandLightText,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: GoogleFonts.outfit(
          color: brandLightText,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ).copyWith(fontFamilyFallback: arabicFallback),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: brandLightCard,
        indicatorColor: brandLightPrimary.withValues(alpha: 0.12),
        labelTextStyle: WidgetStateProperty.resolveWith((states) => GoogleFonts.outfit(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected) ? FontWeight.bold : FontWeight.normal,
          color: states.contains(WidgetState.selected) ? brandLightPrimary : brandLightSubtext,
        ).copyWith(fontFamilyFallback: arabicFallback)),
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? brandLightPrimary : brandLightSubtext,
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
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: brandLightPrimary, width: 2),
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
  Color get subtleCardBg => isDarkMode ? AppThemes.deepGlacial : const Color(0xFFF1F5F9);
  Color get inputBg => isDarkMode ? AppThemes.brandDarkInput : AppThemes.brandLightInput;
  Color get borderColor => isDarkMode ? AppThemes.brandDarkBorder : AppThemes.brandLightBorder;
  Color get textPrimary => isDarkMode ? Colors.white : AppThemes.brandLightText;
  Color get textSecondary => isDarkMode ? const Color(0xFF8B949E) : AppThemes.brandLightSubtext;
  Color get textMuted => isDarkMode ? const Color(0xFF8B949E) : AppThemes.brandLightSubtext;
  Color get chipBg => isDarkMode ? AppThemes.brandDarkInput : const Color(0xFFE2E8F0);
  Color get chipBorder => isDarkMode ? AppThemes.brandDarkBorder : const Color(0xFFCBD5E1);
  Color get dangerColor => isDarkMode ? const Color(0xFFFF5252) : AppThemes.dangerTextLight;
  Color get primaryAccent => isDarkMode ? AppThemes.electricTeal : AppThemes.brandLightPrimary;
  Color get electricTeal => isDarkMode ? AppThemes.electricTeal : AppThemes.brandLightPrimary;
  Color get iceCyan => isDarkMode ? AppThemes.iceCyan : AppThemes.infoTextLight;
  Color get mintNeon => isDarkMode ? AppThemes.mintNeon : AppThemes.successTextLight;

  /// Gold for text and icons: the brand gold in dark mode, a deep gold in
  /// light mode (the brand gold is 2.1:1 on white).
  Color get champagneGold => isDarkMode ? AppThemes.champagneGold : AppThemes.goldTextLight;
  Color get goldText => champagneGold;

  /// Link / informational blue for text.
  Color get infoText => isDarkMode ? AppThemes.infoTextDark : AppThemes.infoTextLight;

  /// Amber for pending / warning text.
  Color get warnText => isDarkMode ? AppThemes.warnTextDark : AppThemes.warnTextLight;

  /// Label colour on a filled [AppThemes.success] button, in both modes.
  Color get onAccentFill => AppThemes.onSuccessFill;

  /// Text drawn on [icedHeroGradient] (always a dark gradient).
  Color get heroText => Colors.white;
  Color get heroCaption => isDarkMode ? AppThemes.electricTeal : const Color(0xFFCCFBF1);

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
          colors: [Color(0xFF0F766E), Color(0xFF0369A1)],
        );

  LinearGradient get icedAccentGradient => isDarkMode
      ? const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppThemes.electricTeal, AppThemes.iceCyan],
        )
      : const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppThemes.brandLightPrimary, AppThemes.brandLightSecondary],
        );
}
