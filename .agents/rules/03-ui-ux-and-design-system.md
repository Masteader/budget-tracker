# UI/UX & Design System Rules

## 1. Sovereign OS & Iced Ocean Mobile Design Language

- **Visual Concept:** Deep, premium, oceanic tactical interface reminiscent of modern aerospace glass-cockpits and high-end fintech.
- **Core Color Palette:**
  - Background (Dark): `#0A0F1D` (Deep Abyssal Midnight)
  - Surface & Card (Dark): `#111827` / `#1E293B` (Glacial Slate Glass)
  - Background (Light): `#F0FDF4` / `#F8FAFC` (Crisp Iced Arctic White)
  - Primary Accent: `#00E5BF` (Electric Glacial Turquoise / Mint Cyan)
  - Secondary Accent: `#38BDF8` (Sky Blue Ice)
  - Warning / Deficit: `#F43F5E` (Vibrant Coral Rose)
  - Surplus / Safe: `#10B981` (Emerald Glow)
- **Typography:**
  - Modern sans-serif via Google Fonts (`Outfit`, `Cairo`, or `Tajawal` for Arabic text).
- **Glassmorphism & Elevation:**
  - Thin 1px borders with subtle opacity (`Colors.white.withValues(alpha: 0.08)` in dark mode, `Color(0x15000000)` in light mode; `withOpacity` is deprecated).
  - Smooth rounded corners (16px to 24px).
  - Avoid heavy flat drop-shadows; use soft atmospheric glows.

## 2. Daylight Coastal Exploding Flow (Web Landing Page)

- The web app and marketing portal follow the **Daylight Coastal Exploding Flow** aesthetic:
  - Light morning coastal palette (teal on white), one subtle hero visual, no decorative canvas or looping effects.
  - An illustrative payday countdown card (household payday → real cycle dates, sample amounts, labelled as an example).
  - Plain, true copy: no invented metrics or claims the code does not back (product review 2026-10-21).

## 3. Strict Trilingual & RTL Guidelines

- **Primary Orientation:** Arabic is the primary language (`ar`) with RTL (Right-to-Left) directional flow.
- **Supported Locales:**
  1. `ar` - Arabic (العربية - Default)
  2. `en` - English
  3. `ur` - Urdu (اردو)
- **Zero Hardcoding Rule:**
  - NEVER hardcode user-facing strings in English, Arabic, or Urdu.
  - All labels, dialog titles, placeholders, toast notifications, and button text MUST be declared for `en`, `ar` and `ur` in `flutter_app/lib/l10n/app_localizations.dart` and accessed via `context.tr('key')` / `context.trArgs('key', {...})` (or `AppLocalizations.of(context).get('key')`).
  - In the React web app, translations live in `web_app/src/i18n/translations.ts`.
- **RTL Integrity:**
  - Avoid directional hardcoded paddings (e.g., use `EdgeInsetsDirectional` instead of `EdgeInsets.only(left: ...)`).
  - Use `Directionality.of(context)` or `isRTL` helpers to ensure arrows, icons, and progress bars mirror correctly.

## 4. Interaction Patterns & Micro-Animations

- **Privacy Eye Toggles:** Total Net Worth and account balances must support instant hide/reveal toggles for discreet public usage.
- **Speed Dial FAB:** Quick access menu for 3 primary financial actions (Add Expense, Record Income, Transfer Funds).
- **Capacity Status Indicators:** Immediate color-coded status badges on account cards and budget categories.
- **Haptic Feedback:** Provide subtle tactile feedback on key actions (scanning receipt, logging salary, transferring funds).
