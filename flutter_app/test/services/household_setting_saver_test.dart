// MOB-27: a household setting (payday, income, rollover) must only change
// locally after the server confirmed it; a rejection must surface as a failure.
import 'dart:io';

import 'package:budget_tracker/services/household_setting_saver.dart';
import 'package:budget_tracker/widgets/settings/payday_settings_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('saveHouseholdSetting', () {
    test('applies the value locally after the server confirmed it', () async {
      int? local;
      String? sentFor;
      await saveHouseholdSetting<int>(
        householdId: 'h1',
        value: 25,
        saveRemote: (hid, day) async {
          sentFor = hid;
          return true;
        },
        applyLocal: (day) async => local = day,
      );
      expect(sentFor, 'h1');
      expect(local, 25);
    });

    test('a server rejection throws and leaves the local value untouched', () async {
      int? local;
      await expectLater(
        saveHouseholdSetting<int>(
          householdId: 'h1',
          value: 25,
          saveRemote: (_, __) async => false,
          applyLocal: (day) async => local = day,
        ),
        throwsA(isA<HouseholdSettingNotSavedException>()),
      );
      expect(local, isNull);
    });

    test('a network error propagates and leaves the local value untouched', () async {
      int? local;
      await expectLater(
        saveHouseholdSetting<int>(
          householdId: 'h1',
          value: 25,
          saveRemote: (_, __) async => throw const SocketException('offline'),
          applyLocal: (day) async => local = day,
        ),
        throwsA(isA<SocketException>()),
      );
      expect(local, isNull);
    });

    test('without a household nothing is saved', () async {
      var remoteCalled = false;
      await expectLater(
        saveHouseholdSetting<int>(
          householdId: null,
          value: 25,
          saveRemote: (_, __) async => remoteCalled = true,
          applyLocal: (_) async {},
        ),
        throwsA(isA<HouseholdSettingNotSavedException>()),
      );
      expect(remoteCalled, isFalse);
    });
  });

  testWidgets('PaydaySettingsCard reverts to the payday in effect when the save is rejected', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PaydaySettingsCard(initialPayday: 27, onSavePayday: (_) async => false),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('1st (Calendar Month)'));
    await tester.pumpAndSettle();
    expect(find.text('1st of month'), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Save Payday'));
    await tester.pumpAndSettle();

    expect(find.text('27th of month'), findsOneWidget);
    expect(find.text('Payday Saved'), findsNothing, reason: 'no success toast on failure');
  });

  test('settings screen saves payday/income/rollover server-first', () {
    final src = File('lib/screens/settings/settings_screen.dart').readAsStringSync();
    for (final setting in ['saveHouseholdSetting<int>', 'saveHouseholdSetting<double>', 'saveHouseholdSetting<String>']) {
      expect(src, contains(setting));
    }
    // The old code wrote the cache before the server call.
    final savePayday = src.substring(src.indexOf('Future<bool> _savePayday'), src.indexOf('Future<bool> _saveIncome'));
    expect(savePayday.indexOf('setState(() => _paydayDay'), greaterThan(savePayday.indexOf('saveHouseholdSetting')));
  });
}
