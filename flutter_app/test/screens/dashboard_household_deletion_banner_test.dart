// The household deletion banner on the real dashboard, next to the payday banner.
import 'package:budget_tracker/models/account_deletion.dart';
import 'package:budget_tracker/providers/account_deletion_provider.dart';
import 'package:budget_tracker/providers/budget_provider.dart';
import 'package:budget_tracker/providers/installment_provider.dart';
import 'package:budget_tracker/providers/recurring_bills_provider.dart';
import 'package:budget_tracker/providers/transaction_provider.dart';
import 'package:budget_tracker/screens/home/dashboard_screen.dart';
import 'package:budget_tracker/services/account_deletion_service.dart';
import 'package:budget_tracker/services/api_service.dart';
import 'package:budget_tracker/services/local_account_data_cleaner.dart';
import 'package:budget_tracker/widgets/dashboard/household_deletion_banner.dart';
import 'package:budget_tracker/widgets/dashboard/payday_checkin_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_settings_supabase.dart';
import '../support/localized_app.dart';

final _http = FakeSettingsHttpClient();

class _FakeService extends AccountDeletionService {
  final Map<String, HouseholdDeletionMark> marks = {};

  @override
  Future<AccountDeletionStatus> getStatus() async => AccountDeletionStatus.none;

  @override
  Future<HouseholdDeletionMark> readHouseholdMark(String householdId) async =>
      marks[householdId] ?? const HouseholdDeletionMark(readable: true);
}

void main() {
  late _FakeService service;
  late AccountDeletionProvider provider;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    TestWidgetsFlutterBinding.ensureInitialized();
    await initFakeSettingsSupabase(_http);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _http.resetScenario();
    final originalApi = ApiService.instance;
    ApiService.instance = FakeSettingsApi();
    addTearDown(() => ApiService.instance = originalApi);
    service = _FakeService();
    provider = AccountDeletionProvider(
      service: service,
      cleaner: LocalAccountDataCleaner(cancelReminders: () async {}, deleteStatements: () async {}, clearSignedUrls: () {}),
      currentUserId: () => fakeSettingsUserId,
    );
  });

  Future<void> pumpDashboard(WidgetTester tester) async {
    tester.view.physicalSize = const Size(600, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<TransactionProvider>(create: (_) => TransactionProvider()),
        ChangeNotifierProvider<RecurringBillsProvider>(create: (_) => RecurringBillsProvider()),
        ChangeNotifierProvider<BudgetProvider>(create: (_) => BudgetProvider()),
        ChangeNotifierProvider<InstallmentProvider>(create: (_) => InstallmentProvider()),
        ChangeNotifierProvider<AccountDeletionProvider>.value(value: provider),
      ],
      child: localizedApp(
        BudgetDashboard(householdId: 'h-1', budgetStreamOverride: (_) => Stream.value(const [])),
        lang: 'en',
        scaffold: false,
      ),
    ));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  // The dashboard's providers leave retry timers running.
  Future<void> disposeDashboard(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 1));
  }

  testWidgets('a marked household shows it right before the payday banner', (tester) async {
    service.marks['h-1'] = HouseholdDeletionMark(readable: true, scheduledFor: DateTime.utc(2026, 12, 5, 10));
    await pumpDashboard(tester);

    expect(find.byKey(const ValueKey('household_deletion_banner')), findsOneWidget);
    expect(find.textContaining('5 December 2026'), findsOneWidget);

    final column = tester.widget<Column>(
      find.ancestor(of: find.byType(HouseholdDeletionBanner), matching: find.byType(Column)).first,
    );
    final banners = column.children.map((w) => w.runtimeType).toList();
    expect(banners.indexOf(HouseholdDeletionBanner), greaterThanOrEqualTo(0));
    expect(banners.indexOf(PaydayCheckinBanner), banners.indexOf(HouseholdDeletionBanner) + 1);
    await disposeDashboard(tester);
  });

  testWidgets('an unmarked household shows nothing', (tester) async {
    await pumpDashboard(tester);
    expect(find.byType(HouseholdDeletionBanner), findsOneWidget);
    expect(find.byKey(const ValueKey('household_deletion_banner')), findsNothing);
    await disposeDashboard(tester);
  });
}
