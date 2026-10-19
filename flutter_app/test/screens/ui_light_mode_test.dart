// Light-mode regressions: text that was hardcoded white rendered invisibly on
// the light canvas/cards.
import 'package:budget_tracker/screens/auth/forgot_password_screen.dart';
import 'package:budget_tracker/theme/app_themes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('forgot-password verification step is readable in light mode', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppThemes.lightTheme,
      home: ForgotPasswordScreen(
        initialEmail: 'user@example.com',
        onSendResetCode: (_) async {},
        onVerifyAndResetPassword: (_, __, ___) async {},
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send Reset Code'));
    await tester.pumpAndSettle();

    final title = tester.widget<Text>(find.text('Enter Verification Code'));
    expect(title.style?.color, AppThemes.brandLightText);
    expect(title.style?.color, isNot(Colors.white));
  });

  test('light-mode text tokens meet WCAG AA (4.5:1) on the light canvas', () {
    double contrast(Color a, Color b) {
      final la = a.computeLuminance();
      final lb = b.computeLuminance();
      final hi = la > lb ? la : lb;
      final lo = la > lb ? lb : la;
      return (hi + 0.05) / (lo + 0.05);
    }

    for (final bg in [AppThemes.brandLightBg, AppThemes.brandLightCard]) {
      expect(contrast(AppThemes.accentTextLight, bg), greaterThanOrEqualTo(4.5));
      expect(contrast(AppThemes.successTextLight, bg), greaterThanOrEqualTo(4.5));
      // The raw brand colours are what the tokens replace for text:
      expect(contrast(AppThemes.electricTeal, bg), lessThan(3));
      expect(contrast(AppThemes.success, bg), lessThan(3));
    }
  });
}
