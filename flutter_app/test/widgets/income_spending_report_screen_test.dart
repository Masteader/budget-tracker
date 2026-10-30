import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/screens/analytics/income_spending_report_screen.dart';

Widget _buildTestApp(Widget child, {Locale locale = const Locale('en')}) {
  return MaterialApp(
    locale: locale,
    supportedLocales: const [Locale('en'), Locale('ar'), Locale('ur')],
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: child,
  );
}

void main() {
  group('IncomeSpendingReportScreen Widget Tests', () {
    testWidgets('Renders header, cycle selector, and hero card structure in English', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          const IncomeSpendingReportScreen(householdId: 'hh_test_report_1'),
          locale: const Locale('en'),
        ),
      );

      await tester.pumpAndSettle();

      // Header and title
      expect(find.text('Income & Cash Flow Report'), findsOneWidget);

      // Metric hero cards
      expect(find.text('Net Cash Flow'), findsOneWidget);
      expect(find.text('Total Inflow'), findsOneWidget);
      expect(find.text('Total Outflow'), findsOneWidget);
      expect(find.text('Income Records Ledger'), findsOneWidget);
      expect(find.text('Spending by Category'), findsOneWidget);
    });

    testWidgets('Renders in Arabic with native localized labels', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          const IncomeSpendingReportScreen(householdId: 'hh_test_report_ar'),
          locale: const Locale('ar'),
        ),
      );

      await tester.pumpAndSettle();

      // Arabic localized labels
      expect(find.text('تقرير الدخل والتدفق النقدي'), findsOneWidget);
      expect(find.text('صافي التدفق النقدي'), findsOneWidget);
      expect(find.text('إجمالي الدخل الوارد'), findsOneWidget);
      expect(find.text('إجمالي المصروفات'), findsOneWidget);
      expect(find.text('سجل مقبوضات الدخل'), findsOneWidget);
      expect(find.text('توزيع المصروفات حسب التصنيف'), findsOneWidget);
    });
  });
}
