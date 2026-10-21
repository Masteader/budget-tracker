import 'dart:io';

import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/models/installment_plan.dart';
import 'package:budget_tracker/models/recurring_bill.dart';
import 'package:budget_tracker/providers/installment_provider.dart';
import 'package:budget_tracker/providers/locale_provider.dart';
import 'package:budget_tracker/providers/recurring_bills_provider.dart';
import 'package:budget_tracker/services/notifications/reminder_notification_backend.dart';
import 'package:budget_tracker/services/notifications/reminder_planner.dart';
import 'package:budget_tracker/services/notifications/reminder_preferences.dart';
import 'package:budget_tracker/services/notifications/reminder_service.dart';
import 'package:budget_tracker/services/salary_cycle_service.dart';
import 'package:budget_tracker/widgets/reminder_sync.dart';
import 'package:budget_tracker/widgets/settings/reminder_settings_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records what would reach flutter_local_notifications.
class FakeBackend implements ReminderNotificationBackend {
  int initializeCalls = 0;
  int cancelAllCalls = 0;
  final scheduled = <PlannedReminder>[];
  String? channelName;

  @override
  Future<void> initialize() async => initializeCalls++;

  @override
  Future<void> cancelAll() async {
    cancelAllCalls++;
    scheduled.clear();
  }

  @override
  Future<void> schedule(PlannedReminder reminder, {required String channelName, required String channelDescription}) async {
    this.channelName = channelName;
    scheduled.add(reminder);
  }
}

RecurringBillItem _bill(String merchant, int day) => RecurringBillItem(
      merchant: merchant,
      normalizedMerchant: merchant,
      categoryCode: 'OPEX-UTILITIES',
      averageAmount: 99,
      expectedDayOfMonth: day,
      status: 'UPCOMING',
    );

RecurringBillsSummary _summary(List<RecurringBillItem> bills) => RecurringBillsSummary(
      cycleKey: '2026-11',
      cycleLabel: '',
      totalRecurringMonthly: 0,
      paidThisCycle: 0,
      reservedAmount: 0,
      bills: bills,
    );

void main() {
  // 21 Oct 2026, 10:00 Riyadh.
  DateTime clock() => DateTime.utc(2026, 10, 21, 7);

  group('ReminderService', () {
    test('schedules the plan once and skips identical reschedules', () async {
      final backend = FakeBackend();
      final service = ReminderService(backend: backend, clock: clock);
      Future<int> run() => service.reschedule(
            householdId: 'h1',
            paydayDay: 27,
            bills: [_bill('SEC', 25)],
            plans: const [],
            enabled: {...ReminderType.values},
            locale: const Locale('en'),
          );

      final n = await run();
      expect(n, greaterThan(0));
      expect(backend.scheduled.length, n);
      expect(backend.cancelAllCalls, 1);
      expect(backend.channelName, 'Reminders');
      expect(backend.scheduled.map((r) => r.type).toSet(), {...ReminderType.values}..remove(ReminderType.installment));

      await run();
      expect(backend.cancelAllCalls, 1, reason: 'same plan: platform untouched');
    });

    test('a household switch, payday change or language change reschedules', () async {
      final backend = FakeBackend();
      final service = ReminderService(backend: backend, clock: clock);
      Future<void> run({String hid = 'h1', int payday = 27, String lang = 'en'}) => service.reschedule(
            householdId: hid,
            paydayDay: payday,
            bills: const [],
            plans: const [],
            enabled: {ReminderType.payday},
            locale: Locale(lang),
          );
      await run();
      await run(hid: 'h2');
      await run(hid: 'h2', payday: 25);
      expect(backend.scheduled.first.fireAtUtc, DateTime.utc(2026, 10, 25, 6));
      await run(hid: 'h2', payday: 25, lang: 'ar');
      expect(backend.cancelAllCalls, 4);
      expect(backend.scheduled.first.title, AppLocalizations(const Locale('ar')).get('notif_payday_title'));
    });

    test('cancelAll clears everything and forgets the last plan', () async {
      final backend = FakeBackend();
      final service = ReminderService(backend: backend, clock: clock);
      Future<void> run() => service.reschedule(
            householdId: 'h1',
            paydayDay: 27,
            bills: const [],
            plans: const [],
            enabled: {ReminderType.payday},
            locale: const Locale('en'),
          );
      await run();
      await service.cancelAll();
      expect(backend.scheduled, isEmpty);
      expect(service.scheduled, isEmpty);
      await run();
      expect(backend.scheduled, isNotEmpty, reason: 'next login schedules again');
    });

    test('a failing plugin never throws to the caller', () async {
      final service = ReminderService(backend: _ThrowingBackend(), clock: clock);
      final n = await service.reschedule(
        householdId: 'h1',
        paydayDay: 27,
        bills: const [],
        plans: const [],
        enabled: {ReminderType.payday},
        locale: const Locale('en'),
      );
      expect(n, 0);
      await service.cancelAll();
    });
  });

  group('ReminderPreferences', () {
    test('all types default on; a switch is persisted locally', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = ReminderPreferences();
      await prefs.load();
      expect(prefs.enabledTypes, {...ReminderType.values});
      await prefs.setEnabled(ReminderType.bill, false);
      final reloaded = ReminderPreferences();
      await reloaded.load();
      expect(reloaded.isEnabled(ReminderType.bill), isFalse);
      expect(reloaded.isEnabled(ReminderType.payday), isTrue);
      final raw = await SharedPreferences.getInstance();
      expect(raw.getBool('reminder_bill_enabled'), isFalse);
    });
  });

  group('ReminderSync', () {
    late FakeBackend backend;
    late ReminderService service;
    late ReminderPreferences prefs;
    late RecurringBillsProvider bills;
    late InstallmentProvider installments;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      SalaryCycleService.paydayDay = 27;
      backend = FakeBackend();
      service = ReminderService(backend: backend, clock: clock);
      prefs = ReminderPreferences();
      bills = RecurringBillsProvider();
      installments = InstallmentProvider();
    });

    Widget host({PaydayFetcher? fetchPayday}) => MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: bills),
            ChangeNotifierProvider.value(value: installments),
            ChangeNotifierProvider(create: (_) => LocaleProvider()),
          ],
          child: MaterialApp(
            home: ReminderSync(
              service: service,
              preferences: prefs,
              fetchPayday: fetchPayday ?? (_) async => 27,
              debounce: const Duration(milliseconds: 10),
              child: const SizedBox(),
            ),
          ),
        );

    testWidgets('schedules on login and again when bills or plans change', (tester) async {
      installments.setPlansForTesting(const [], householdId: 'h1');
      await tester.pumpWidget(host());
      await _settle(tester);
      expect(backend.scheduled.where((r) => r.type == ReminderType.payday), isNotEmpty);
      expect(backend.scheduled.where((r) => r.type == ReminderType.bill), isEmpty);

      bills.setSummaryForTesting(_summary([_bill('SEC', 25)]), householdId: 'h1');
      await _settle(tester);
      expect(backend.scheduled.where((r) => r.type == ReminderType.bill), isNotEmpty);

      installments.setPlansForTesting([
        InstallmentPlan.fromJson({
          'id': 'p',
          'household_id': 'h1',
          'merchant': 'Jarir',
          'provider': 'Tabby',
          'total_amount': 400,
          'installment_count': 4,
          'monthly_amount': 100,
          'paid_installments': 1,
          'start_date': '2026-10-15',
          'status': 'ACTIVE',
          'frequency': 'biweekly',
          'next_due_at': '2026-10-29',
        }),
      ], householdId: 'h1');
      await _settle(tester);
      expect(backend.scheduled.where((r) => r.type == ReminderType.installment).length, 3);
    });

    testWidgets("ignores another household's bills and follows the household payday", (tester) async {
      installments.setPlansForTesting(const [], householdId: 'h2');
      bills.setSummaryForTesting(_summary([_bill('SEC', 25)]), householdId: 'h1');
      await tester.pumpWidget(host(fetchPayday: (_) async => 25));
      await _settle(tester);
      await _settle(tester);
      expect(SalaryCycleService.paydayDay, 25);
      expect(backend.scheduled.where((r) => r.type == ReminderType.bill), isEmpty);
      expect(backend.scheduled.firstWhere((r) => r.type == ReminderType.payday).fireAtUtc, DateTime.utc(2026, 10, 25, 6));
      SalaryCycleService.paydayDay = 27;
    });

    testWidgets('switching every type off cancels all reminders', (tester) async {
      installments.setPlansForTesting(const [], householdId: 'h1');
      await tester.pumpWidget(host());
      await _settle(tester);
      expect(backend.scheduled, isNotEmpty);
      for (final t in ReminderType.values) {
        await prefs.setEnabled(t, false);
      }
      await _settle(tester);
      expect(backend.scheduled, isEmpty);
    });
  });

  testWidgets('settings card: one switch per type, persisted, permission asked when turned on', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = ReminderPreferences();
    await prefs.load();
    var asked = 0;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: const [AppLocalizationsDelegate()],
      supportedLocales: const [Locale('en')],
      home: Scaffold(
        body: SingleChildScrollView(
          child: ReminderSettingsCard(
            preferences: prefs,
            requestPermission: () async {
              asked++;
              return true;
            },
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    for (final t in ReminderType.values) {
      expect(find.byKey(ValueKey('reminder_switch_${t.name}')), findsOneWidget);
    }
    expect(find.text('Payday check-in'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('reminder_switch_bill')));
    await tester.pumpAndSettle();
    expect(prefs.isEnabled(ReminderType.bill), isFalse);
    expect(asked, 0);

    await tester.tap(find.byKey(const ValueKey('reminder_switch_bill')));
    await tester.pumpAndSettle();
    expect(prefs.isEnabled(ReminderType.bill), isTrue);
    expect(asked, 1);
  });

  test('Android: small icon, boot receivers and no exact-alarm permission', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('android.permission.POST_NOTIFICATIONS'));
    expect(manifest, contains('android.permission.RECEIVE_BOOT_COMPLETED'));
    expect(manifest, contains('ScheduledNotificationReceiver'));
    expect(manifest, contains('ScheduledNotificationBootReceiver'));
    expect(manifest, isNot(contains('SCHEDULE_EXACT_ALARM')));
    expect(manifest, isNot(contains('USE_EXACT_ALARM')));
    expect(File('android/app/src/main/res/drawable/ic_stat_reminder.xml').existsSync(), isTrue);
    final backendSrc = File('lib/services/notifications/reminder_notification_backend.dart').readAsStringSync();
    expect(backendSrc, contains('AndroidScheduleMode.inexactAllowWhileIdle'));
    expect(backendSrc, contains("'Asia/Riyadh'"));
  });
}

/// Rebuild (timers start during the frame), then let the debounce fire.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
}

class _ThrowingBackend implements ReminderNotificationBackend {
  @override
  Future<void> initialize() async => throw StateError('no plugin');

  @override
  Future<void> cancelAll() async => throw StateError('no plugin');

  @override
  Future<void> schedule(PlannedReminder reminder, {required String channelName, required String channelDescription}) async =>
      throw StateError('no plugin');
}
