import 'package:flutter/material.dart';
import '../core/theme/velvet_burgundy_theme.dart';

class AppThemes {
  AppThemes._();

  // ─── Legacy Sovereign Palette Tokens (Mapped to Velvet Burgundy) ────────────
  static const Color brandEmerald = VelvetBurgundyColors.emeraldSafe;
  static const Color brandDarkBg = VelvetBurgundyColors.canvasDark;
  static const Color brandDarkCard = VelvetBurgundyColors.surfaceDark;
  static const Color brandDarkInput = Color(0xFF240E17);
  static const Color brandDarkBorder = VelvetBurgundyColors.roseBorderDark;
  static const Color brandLightBg = VelvetBurgundyColors.canvasLight;
  static const Color brandLightCard = VelvetBurgundyColors.surfaceLight;
  static const Color brandLightText = VelvetBurgundyColors.textPrimaryLight;

  // ─── Highlights & Accents ───────────────────────────────────────────────────
  static const Color iceCyan = VelvetBurgundyColors.roseGold;
  static const Color electricTeal = VelvetBurgundyColors.roseGoldGlow;
  static const Color mintNeon = VelvetBurgundyColors.emeraldSafe;
  static const Color champagneGold = Color(0xFFE598B0);
  static const Color success = VelvetBurgundyColors.emeraldSafe;
  static const Color accentTextLight = VelvetBurgundyColors.primaryLight;
  static const Color successTextLight = Color(0xFF065F46);
  static const Color deepGlacial = Color(0xFF1E0B12);

  // ─── Text & Status Tokens ───────────────────────────────────────────────────
  static const Color goldTextLight = Color(0xFF92400E);
  static const Color infoTextLight = VelvetBurgundyColors.primaryLight;
  static const Color warnTextLight = VelvetBurgundyColors.amberCautionTextLight;
  static const Color dangerTextLight = Color(0xFF9F1239);
  static const Color warnTextDark = VelvetBurgundyColors.amberCaution;
  static const Color infoTextDark = VelvetBurgundyColors.roseGoldGlow;

  static const Color onSuccessFill = Color(0xFF0A0F1D);
  static const List<String> arabicFallback = ['Cairo'];

  // ─── Master Theme Getters delegating to Velvet Burgundy ─────────────────────
  static ThemeData get darkTheme => VelvetBurgundyTheme.darkTheme;
  static ThemeData get lightTheme => VelvetBurgundyTheme.lightTheme;
}

extension ThemeContextExtension on BuildContext {
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;
  bool get isDark => isDarkMode;
  Color get scaffoldBg => Theme.of(this).scaffoldBackgroundColor;
  Color get cardBg => isDarkMode ? VelvetBurgundyColors.surfaceDark : VelvetBurgundyColors.surfaceLight;
  Color get cardSurfaceBg => isDarkMode ? VelvetBurgundyColors.surfaceDark : VelvetBurgundyColors.surfaceLight;
  Color get subtleCardBg => isDarkMode ? const Color(0xFF240E17) : VelvetBurgundyColors.rosePillLight;
  Color get inputBg => isDarkMode ? const Color(0xFF240E17) : const Color(0xFFFDF8FA);
  Color get borderColor => isDarkMode ? VelvetBurgundyColors.roseBorderDark : VelvetBurgundyColors.roseBorderLight;
  Color get textPrimary => isDarkMode ? VelvetBurgundyColors.textPrimaryDark : VelvetBurgundyColors.textPrimaryLight;
  Color get textSecondary => isDarkMode ? VelvetBurgundyColors.textSecondaryDark : VelvetBurgundyColors.textSecondaryLight;
  Color get textMuted => isDarkMode ? VelvetBurgundyColors.textSecondaryDark : VelvetBurgundyColors.textSecondaryLight;
  Color get chipBg => isDarkMode ? const Color(0xFF240E17) : VelvetBurgundyColors.rosePillLight;
  Color get chipBorder => isDarkMode ? VelvetBurgundyColors.roseBorderDark : VelvetBurgundyColors.roseBorderLight;
  Color get dangerColor => isDarkMode ? VelvetBurgundyColors.coralDanger : VelvetBurgundyColors.coralDangerTextLight;
  Color get primaryAccent => isDarkMode ? VelvetBurgundyColors.roseGoldGlow : VelvetBurgundyColors.primaryLight;
  Color get electricTeal => isDarkMode ? VelvetBurgundyColors.roseGoldGlow : VelvetBurgundyColors.primaryLight;
  Color get iceCyan => isDarkMode ? VelvetBurgundyColors.roseGold : VelvetBurgundyColors.primaryLightGradient;
  Color get mintNeon => isDarkMode ? VelvetBurgundyColors.emeraldSafe : const Color(0xFF065F46);

  Color get champagneGold => isDarkMode ? const Color(0xFFE598B0) : const Color(0xFF92400E);
  Color get goldText => champagneGold;

  Color get infoText => isDarkMode ? VelvetBurgundyColors.roseGoldGlow : VelvetBurgundyColors.primaryLight;
  Color get warnText => isDarkMode ? VelvetBurgundyColors.amberCaution : VelvetBurgundyColors.amberCautionTextLight;
  Color get onAccentFill => AppThemes.onSuccessFill;

  Color get heroText => Colors.white;
  Color get heroCaption => isDarkMode ? VelvetBurgundyColors.roseGoldGlow : VelvetBurgundyColors.rosePillLight;

  Color get accentText => isDarkMode ? VelvetBurgundyColors.roseGoldGlow : VelvetBurgundyColors.primaryLight;
  Color get successText => isDarkMode ? VelvetBurgundyColors.emeraldSafe : const Color(0xFF065F46);

  LinearGradient get icedHeroGradient => isDarkMode
      ? const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4A0E1E), Color(0xFF2A050E)],
        )
      : const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6C162F), Color(0xFF4A0E1E)],
        );

  LinearGradient get icedAccentGradient => isDarkMode
      ? const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE598B0), Color(0xFFB83253)],
        )
      : const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFB83253), Color(0xFF4A0E1E)],
        );
}
