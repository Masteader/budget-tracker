import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Velvet Burgundy Master Design System color tokens.
/// Supports both Light Mode (Ceramic Pure White on Blush-Alabaster)
/// and Dark Mode (Dark Plum-Charcoal on Obsidian Wine).
class VelvetBurgundyColors {
  VelvetBurgundyColors._();

  // ─── Light Mode Tokens ───────────────────────────────────────────────────────
  static const Color canvasLight = Color(0xFFF8F3F5); // Soft Blush-Alabaster
  static const Color surfaceLight = Color(0xFFFFFFFF); // Pure White 3D Ceramic Card
  static const Color primaryLight = Color(0xFF4A0E1E); // Velvet Burgundy
  static const Color primaryDarkMaroon = Color(0xFF2A050E); // Deep Maroon
  static const Color primaryLightGradient = Color(0xFF6C162F); // Top Highlight
  static const Color roseGold = Color(0xFFE598B0); // Glossy Rose Gold
  static const Color rosePillLight = Color(0xFFFCEEF2); // Subtle Rose Chip Fill
  static const Color roseBorderLight = Color(0xFFF2DCE2); // Rose Ceramic Border
  static const Color accentRose = Color(0xFFB83253);

  // ─── Dark Mode Tokens ────────────────────────────────────────────────────────
  static const Color canvasDark = Color(0xFF110509); // Obsidian Wine
  static const Color canvasDarkBg = Color(0xFF0A0205); // Void Canvas Edge
  static const Color surfaceDark = Color(0xFF1E0B12); // Dark Plum-Charcoal Card
  static const Color surfaceDarkGradientStart = Color(0xFF240E17);
  static const Color surfaceDarkGradientEnd = Color(0xFF17080E);
  static const Color primaryDark = Color(0xFF5E1327); // Luminous Burgundy for Dark
  static const Color primaryDarkGradientStart = Color(0xFF6B162C);
  static const Color primaryDarkGradientEnd = Color(0xFF380814);
  static const Color roseGoldGlow = Color(0xFFF0A3BC);
  static const Color roseBorderDark = Color(0x33FFD2E1); // rgba(255, 210, 225, 0.2)

  // ─── Semantic Status Tokens ──────────────────────────────────────────────────
  static const Color emeraldSafe = Color(0xFF10B981);
  static const Color emeraldSafeBgLight = Color(0xFFECFDF5);
  static const Color emeraldSafeTextLight = Color(0xFF065F46);

  static const Color amberCaution = Color(0xFFF59E0B);
  static const Color amberCautionBgLight = Color(0xFFFFFBEB);
  static const Color amberCautionTextLight = Color(0xFF92400E);

  static const Color coralDanger = Color(0xFFF43F5E);
  static const Color coralDangerBgLight = Color(0xFFFFF1F2);
  static const Color coralDangerTextLight = Color(0xFF9F1239);

  // ─── Text Ink Tokens ─────────────────────────────────────────────────────────
  static const Color textPrimaryLight = Color(0xFF1E040B);
  static const Color textSecondaryLight = Color(0xFF6F5E64);
  static const Color textPrimaryDark = Color(0xFFFDF8FA);
  static const Color textSecondaryDark = Color(0xFFC7AEB6);
}

/// Velvet Burgundy ThemeData generator conforming to strict RTL,
/// typography, and 3D elevation rules.
class VelvetBurgundyTheme {
  VelvetBurgundyTheme._();

  static const List<String> arabicFallback = ['Cairo', 'Tajawal'];

  static TextTheme _textTheme(Color color) =>
      GoogleFonts.outfitTextTheme().apply(
        bodyColor: color,
        displayColor: color,
        fontFamilyFallback: arabicFallback,
      );

  // ─── Light Theme ────────────────────────────────────────────────────────────
  static ThemeData get lightTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: VelvetBurgundyColors.primaryLight,
      brightness: Brightness.light,
    ).copyWith(
      primary: VelvetBurgundyColors.primaryLight,
      secondary: VelvetBurgundyColors.roseGold,
      surface: VelvetBurgundyColors.surfaceLight,
      surfaceContainerHighest: VelvetBurgundyColors.rosePillLight,
      outline: VelvetBurgundyColors.roseBorderLight,
      onPrimary: Colors.white,
      onSurface: VelvetBurgundyColors.textPrimaryLight,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      brightness: Brightness.light,
      scaffoldBackgroundColor: VelvetBurgundyColors.canvasLight,
      textTheme: _textTheme(VelvetBurgundyColors.textPrimaryLight),
      appBarTheme: AppBarTheme(
        backgroundColor: VelvetBurgundyColors.primaryLight,
        foregroundColor: Colors.white,
        elevation: 0,
        titleTextStyle: GoogleFonts.outfit(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ).copyWith(fontFamilyFallback: arabicFallback),
      ),
      cardTheme: CardThemeData(
        color: VelvetBurgundyColors.surfaceLight,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(
            color: Color(0xC0F2DCE2),
            width: 1.0,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: VelvetBurgundyColors.surfaceLight,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(
            color: VelvetBurgundyColors.roseBorderLight,
            width: 1.2,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(
            color: VelvetBurgundyColors.roseBorderLight,
            width: 1.2,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(
            color: VelvetBurgundyColors.primaryLight,
            width: 1.8,
          ),
        ),
        hintStyle: TextStyle(
          color: VelvetBurgundyColors.textSecondaryLight.withValues(alpha: 0.8),
          fontFamilyFallback: arabicFallback,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: VelvetBurgundyColors.surfaceLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: VelvetBurgundyColors.roseBorderLight),
        ),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: VelvetBurgundyColors.surfaceLight,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: VelvetBurgundyColors.roseBorderLight),
        ),
        headerBackgroundColor: VelvetBurgundyColors.primaryLight,
        headerForegroundColor: Colors.white,
        headerHeadlineStyle: GoogleFonts.outfit(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ).copyWith(fontFamilyFallback: arabicFallback),
        headerHelpStyle: GoogleFonts.outfit(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: VelvetBurgundyColors.roseGold,
        ).copyWith(fontFamilyFallback: arabicFallback),
        weekdayStyle: GoogleFonts.outfit(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: VelvetBurgundyColors.textSecondaryLight,
        ).copyWith(fontFamilyFallback: arabicFallback),
        dayStyle: GoogleFonts.outfit(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: VelvetBurgundyColors.textPrimaryLight,
        ).copyWith(fontFamilyFallback: arabicFallback),
        dayForegroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return VelvetBurgundyColors.textSecondaryLight.withValues(alpha: 0.38);
          }
          if (states.contains(WidgetState.selected)) {
            return Colors.white;
          }
          return VelvetBurgundyColors.textPrimaryLight;
        }),
        dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return VelvetBurgundyColors.primaryLight;
          }
          return Colors.transparent;
        }),
        todayForegroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.white;
          }
          return VelvetBurgundyColors.primaryLight;
        }),
        todayBorder: const BorderSide(color: VelvetBurgundyColors.primaryLight, width: 1.5),
        yearForegroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return VelvetBurgundyColors.textSecondaryLight.withValues(alpha: 0.38);
          }
          if (states.contains(WidgetState.selected)) {
            return Colors.white;
          }
          return VelvetBurgundyColors.textPrimaryLight;
        }),
        yearBackgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return VelvetBurgundyColors.primaryLight;
          }
          return Colors.transparent;
        }),
        dividerColor: VelvetBurgundyColors.roseBorderLight,
        cancelButtonStyle: TextButton.styleFrom(
          foregroundColor: VelvetBurgundyColors.primaryLight,
          textStyle: GoogleFonts.outfit(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ).copyWith(fontFamilyFallback: arabicFallback),
        ),
        confirmButtonStyle: TextButton.styleFrom(
          foregroundColor: VelvetBurgundyColors.primaryLight,
          textStyle: GoogleFonts.outfit(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ).copyWith(fontFamilyFallback: arabicFallback),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: VelvetBurgundyColors.canvasLight,
        modalBackgroundColor: VelvetBurgundyColors.canvasLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: VelvetBurgundyColors.surfaceLight,
        indicatorColor: VelvetBurgundyColors.rosePillLight,
        labelTextStyle: WidgetStateProperty.resolveWith((states) => GoogleFonts.outfit(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected) ? FontWeight.bold : FontWeight.normal,
          color: states.contains(WidgetState.selected)
              ? VelvetBurgundyColors.primaryLight
              : VelvetBurgundyColors.textSecondaryLight,
        ).copyWith(fontFamilyFallback: arabicFallback)),
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? VelvetBurgundyColors.primaryLight
              : VelvetBurgundyColors.textSecondaryLight,
        )),
      ),
      dividerColor: VelvetBurgundyColors.roseBorderLight,
    );
  }

  // ─── Dark Theme ─────────────────────────────────────────────────────────────
  static ThemeData get darkTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: VelvetBurgundyColors.primaryDark,
      brightness: Brightness.dark,
    ).copyWith(
      primary: VelvetBurgundyColors.primaryDark,
      secondary: VelvetBurgundyColors.roseGoldGlow,
      surface: VelvetBurgundyColors.surfaceDark,
      surfaceContainerHighest: const Color(0xFF2A0F1B),
      outline: VelvetBurgundyColors.roseBorderDark,
      onPrimary: Colors.white,
      onSurface: VelvetBurgundyColors.textPrimaryDark,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: VelvetBurgundyColors.canvasDark,
      textTheme: _textTheme(VelvetBurgundyColors.textPrimaryDark),
      appBarTheme: AppBarTheme(
        backgroundColor: VelvetBurgundyColors.primaryDarkMaroon,
        foregroundColor: Colors.white,
        elevation: 0,
        titleTextStyle: GoogleFonts.outfit(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ).copyWith(fontFamilyFallback: arabicFallback),
      ),
      cardTheme: CardThemeData(
        color: VelvetBurgundyColors.surfaceDark,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(
            color: VelvetBurgundyColors.roseBorderDark,
            width: 1.0,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF240E17),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(
            color: VelvetBurgundyColors.roseBorderDark,
            width: 1.2,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(
            color: VelvetBurgundyColors.roseBorderDark,
            width: 1.2,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(
            color: VelvetBurgundyColors.roseGoldGlow,
            width: 1.8,
          ),
        ),
        hintStyle: TextStyle(
          color: VelvetBurgundyColors.textSecondaryDark.withValues(alpha: 0.7),
          fontFamilyFallback: arabicFallback,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: VelvetBurgundyColors.surfaceDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: VelvetBurgundyColors.roseBorderDark),
        ),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: VelvetBurgundyColors.surfaceDark,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: VelvetBurgundyColors.roseBorderDark),
        ),
        headerBackgroundColor: VelvetBurgundyColors.primaryDarkMaroon,
        headerForegroundColor: VelvetBurgundyColors.textPrimaryDark,
        headerHeadlineStyle: GoogleFonts.outfit(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: VelvetBurgundyColors.textPrimaryDark,
        ).copyWith(fontFamilyFallback: arabicFallback),
        headerHelpStyle: GoogleFonts.outfit(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: VelvetBurgundyColors.roseGoldGlow,
        ).copyWith(fontFamilyFallback: arabicFallback),
        weekdayStyle: GoogleFonts.outfit(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: VelvetBurgundyColors.textSecondaryDark,
        ).copyWith(fontFamilyFallback: arabicFallback),
        dayStyle: GoogleFonts.outfit(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: VelvetBurgundyColors.textPrimaryDark,
        ).copyWith(fontFamilyFallback: arabicFallback),
        dayForegroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return VelvetBurgundyColors.textSecondaryDark.withValues(alpha: 0.38);
          }
          if (states.contains(WidgetState.selected)) {
            return Colors.white;
          }
          return VelvetBurgundyColors.textPrimaryDark;
        }),
        dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return VelvetBurgundyColors.accentRose;
          }
          return Colors.transparent;
        }),
        dayOverlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered) || states.contains(WidgetState.focused)) {
            return VelvetBurgundyColors.roseGoldGlow.withValues(alpha: 0.12);
          }
          return null;
        }),
        todayForegroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.white;
          }
          return VelvetBurgundyColors.roseGoldGlow;
        }),
        todayBorder: const BorderSide(color: VelvetBurgundyColors.roseGoldGlow, width: 1.5),
        yearForegroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return VelvetBurgundyColors.textSecondaryDark.withValues(alpha: 0.38);
          }
          if (states.contains(WidgetState.selected)) {
            return Colors.white;
          }
          return VelvetBurgundyColors.textPrimaryDark;
        }),
        yearBackgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return VelvetBurgundyColors.accentRose;
          }
          return Colors.transparent;
        }),
        dividerColor: VelvetBurgundyColors.roseBorderDark,
        cancelButtonStyle: TextButton.styleFrom(
          foregroundColor: VelvetBurgundyColors.roseGoldGlow,
          textStyle: GoogleFonts.outfit(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ).copyWith(fontFamilyFallback: arabicFallback),
        ),
        confirmButtonStyle: TextButton.styleFrom(
          foregroundColor: VelvetBurgundyColors.roseGoldGlow,
          textStyle: GoogleFonts.outfit(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ).copyWith(fontFamilyFallback: arabicFallback),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: VelvetBurgundyColors.canvasDark,
        modalBackgroundColor: VelvetBurgundyColors.canvasDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: VelvetBurgundyColors.surfaceDark,
        indicatorColor: VelvetBurgundyColors.primaryDark.withValues(alpha: 0.35),
        labelTextStyle: WidgetStateProperty.resolveWith((states) => GoogleFonts.outfit(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected) ? FontWeight.bold : FontWeight.normal,
          color: states.contains(WidgetState.selected)
              ? VelvetBurgundyColors.roseGoldGlow
              : VelvetBurgundyColors.textSecondaryDark,
        ).copyWith(fontFamilyFallback: arabicFallback)),
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? VelvetBurgundyColors.roseGoldGlow
              : VelvetBurgundyColors.textSecondaryDark,
        )),
      ),
      dividerColor: VelvetBurgundyColors.roseBorderDark,
    );
  }
}
