// Renders key screens under the Arabic (primary, RTL), Urdu (RTL) and English
// locales and checks direction, translated text and absence of English UI text.
import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/screens/auth/login_screen.dart';
import 'package:budget_tracker/widgets/settings/payday_settings_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _localized(Widget home, String lang) => MaterialApp(
      locale: Locale(lang),
      supportedLocales: const [Locale('en'), Locale('ar'), Locale('ur')],
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: home,
    );

void main() {
  testWidgets('login screen is RTL and fully Arabic in ar', (tester) async {
    await tester.pumpWidget(_localized(const LoginScreen(), 'ar'));
    await tester.pumpAndSettle();

    final ctx = tester.element(find.byType(LoginScreen));
    expect(Directionality.of(ctx), TextDirection.rtl);
    expect(find.text('تسجيل الدخول'), findsOneWidget);
    expect(find.text('نسيت كلمة المرور؟'), findsOneWidget);
    for (final english in ['Sign In', 'Welcome back', 'Forgot password?', 'Password']) {
      expect(find.text(english), findsNothing, reason: english);
    }
    // "Forgot password?" sits at the logical end (left edge in RTL).
    final forgot = tester.getRect(find.text('نسيت كلمة المرور؟'));
    final signIn = tester.getRect(find.text('تسجيل الدخول'));
    expect(forgot.center.dx, lessThan(signIn.center.dx));
  });

  testWidgets('login screen is RTL and Urdu in ur', (tester) async {
    await tester.pumpWidget(_localized(const LoginScreen(), 'ur'));
    await tester.pumpAndSettle();

    final ctx = tester.element(find.byType(LoginScreen));
    expect(Directionality.of(ctx), TextDirection.rtl);
    expect(find.text('سائن ان'), findsOneWidget);
    expect(find.text('Sign In'), findsNothing);
  });

  testWidgets('login screen stays LTR English in en', (tester) async {
    await tester.pumpWidget(_localized(const LoginScreen(), 'en'));
    await tester.pumpAndSettle();

    final ctx = tester.element(find.byType(LoginScreen));
    expect(Directionality.of(ctx), TextDirection.ltr);
    expect(find.text('Sign In'), findsOneWidget);
  });

  testWidgets('payday settings uses plain day numbers (no English ordinals) in ar', (tester) async {
    await tester.pumpWidget(_localized(
      Scaffold(
        body: SingleChildScrollView(
          child: PaydaySettingsCard(initialPayday: 27, onSavePayday: (_) async => true),
        ),
      ),
      'ar',
    ));
    await tester.pumpAndSettle();

    expect(find.text('يوم 27 من الشهر'), findsOneWidget);
    expect(find.textContaining('27th'), findsNothing);
    expect(find.text('الراتب ودورة الصرف'), findsOneWidget);
  });

  testWidgets('login screen survives 2x text scale on a 360dp phone', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 740 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(size: Size(360, 740), textScaler: TextScaler.linear(2)),
      child: _localized(const LoginScreen(), 'ar'),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
