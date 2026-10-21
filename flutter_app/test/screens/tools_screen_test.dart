import 'dart:async';
import 'dart:io';

import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/models/account.dart';
import 'package:budget_tracker/screens/tools/tools_screen.dart';
import 'package:budget_tracker/services/account_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAccountService extends AccountService {
  final controller = StreamController<List<Account>>.broadcast();

  @override
  Stream<List<Account>> streamAccounts(String householdId) => controller.stream;

  @override
  Future<List<Account>> getAccounts(String householdId) async => [];
}

void main() {
  late _FakeAccountService fake;
  setUp(() {
    fake = _FakeAccountService();
    AccountService.instance = fake;
  });
  tearDown(() {
    fake.controller.close();
    AccountService.instance = AccountService();
  });

  testWidgets('Tools lists every secondary feature once (R3)', (tester) async {
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(
      localizationsDelegates: [AppLocalizationsDelegate()],
      supportedLocales: [Locale('en'), Locale('ar'), Locale('ur')],
      locale: Locale('en'),
      home: ToolsScreen(householdId: 'hh'),
    ));
    await tester.pumpAndSettle();

    for (final key in [
      'tool_affordability',
      'tool_price_tracker',
      'tool_smart_basket',
      'tool_batch_scan',
      'tool_record_income',
      'tool_transfer',
      'tool_accounts',
    ]) {
      expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
    }
    expect(find.text('Can I Afford This?'), findsOneWidget);
    expect(find.text('Price Tracker'), findsOneWidget);
  });

  testWidgets('Tools renders right-to-left in Arabic', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      localizationsDelegates: [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: [Locale('en'), Locale('ar'), Locale('ur')],
      locale: Locale('ar'),
      home: ToolsScreen(householdId: 'hh'),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tool_affordability')), findsOneWidget);
    expect(find.text('الأدوات'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_left_rounded), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  test('dashboard keeps one entry per feature (R3)', () {
    final src = File('lib/screens/home/dashboard_screen.dart').readAsStringSync();
    expect(src, isNot(contains('SalaryCycleWidget')));
    expect(src, isNot(contains('GroceryPriceIntelligenceScreen')));
    expect(src, isNot(contains('AffordabilitySimulatorSheet')));
    expect(src, isNot(contains('_QuickActionButton')));
    expect(src, contains('ToolsScreen'));
    expect(src, contains('minAccounts: 2'));
    expect(File('lib/widgets/salary_cycle_widget.dart').existsSync(), isFalse);
  });
}
