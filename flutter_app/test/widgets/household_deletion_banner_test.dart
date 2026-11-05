// The banner a household's members see while it is marked for deletion: on the
// dashboard next to the payday banner, with the date and an export hint, and gone
// once the mark is.
import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/models/account_deletion.dart';
import 'package:budget_tracker/providers/account_deletion_provider.dart';
import 'package:budget_tracker/services/account_deletion_service.dart';
import 'package:budget_tracker/services/local_account_data_cleaner.dart';
import 'package:budget_tracker/theme/app_themes.dart';
import 'package:budget_tracker/widgets/dashboard/household_deletion_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _date = DateTime.utc(2026, 12, 5, 10);

class _FakeService extends AccountDeletionService {
  AccountDeletionStatus status = AccountDeletionStatus.none;
  final Map<String, HouseholdDeletionMark> marks = {};
  final reads = <String>[];

  @override
  Future<AccountDeletionStatus> getStatus() async => status;

  @override
  Future<AccountDeletionPreflight> getPreflight() async => const AccountDeletionPreflight(deletion: AccountDeletionStatus.none);

  @override
  Future<HouseholdDeletionMark> readHouseholdMark(String householdId) async {
    reads.add(householdId);
    return marks[householdId] ?? const HouseholdDeletionMark(readable: true);
  }

  @override
  Future<void> cancel() async {
    status = AccountDeletionStatus.none;
  }
}

Widget _app(Widget child, AccountDeletionProvider? provider, {String lang = 'en', bool dark = false, double scale = 1.0}) {
  final app = MaterialApp(
    locale: Locale(lang),
    theme: dark ? AppThemes.darkTheme : AppThemes.lightTheme,
    supportedLocales: const [Locale('en'), Locale('ar'), Locale('ur')],
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    builder: (context, page) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
      child: page!,
    ),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
  return provider == null ? app : ChangeNotifierProvider<AccountDeletionProvider>.value(value: provider, child: app);
}

Finder get _banner => find.byKey(const ValueKey('household_deletion_banner'));

void main() {
  late _FakeService service;
  late AccountDeletionProvider provider;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    service = _FakeService();
    provider = AccountDeletionProvider(
      service: service,
      cleaner: LocalAccountDataCleaner(cancelReminders: () async {}, deleteStatements: () async {}, clearSignedUrls: () {}),
      currentUserId: () => 'user-me',
    );
  });

  for (final lang in const ['en', 'ar', 'ur']) {
    testWidgets('$lang: a marked household shows the date and the export hint', (tester) async {
      service.marks['h-1'] = HouseholdDeletionMark(readable: true, scheduledFor: _date);
      await tester.pumpWidget(_app(const HouseholdDeletionBanner(householdId: 'h-1'), provider, lang: lang));
      await tester.pump();
      await tester.pump();

      final l = AppLocalizations(Locale(lang));
      expect(_banner, findsOneWidget);
      expect(find.text(l.get('del_banner_title')), findsOneWidget);
      final date = l.date(_date.toLocal(), 'd MMMM yyyy');
      expect(find.textContaining(date), findsOneWidget);
      expect(find.text(l.get('del_banner_export')), findsOneWidget);
      expect(Directionality.of(tester.element(_banner)), lang == 'en' ? TextDirection.ltr : TextDirection.rtl);
    });
  }

  testWidgets('it reads the mark of the household on screen', (tester) async {
    await tester.pumpWidget(_app(const HouseholdDeletionBanner(householdId: 'h-1'), provider));
    await tester.pump();
    expect(service.reads, ['h-1']);
  });

  testWidgets('a household with no mark shows nothing', (tester) async {
    await tester.pumpWidget(_app(const HouseholdDeletionBanner(householdId: 'h-1'), provider));
    await tester.pump();
    await tester.pump();
    expect(_banner, findsNothing);
  });

  testWidgets('another household\'s mark does not show here', (tester) async {
    service.marks['h-2'] = HouseholdDeletionMark(readable: true, scheduledFor: _date);
    await provider.loadHouseholdMark('h-2');
    await tester.pumpWidget(_app(const HouseholdDeletionBanner(householdId: 'h-1'), provider));
    await tester.pump();
    await tester.pump();
    expect(_banner, findsNothing);
  });

  testWidgets('it disappears at once when the requester cancels', (tester) async {
    service.status = AccountDeletionStatus(
      state: AccountDeletionState.scheduled,
      scheduledFor: _date,
      canCancel: true,
      markedHouseholds: [MarkedHousehold(id: 'h-1', name: 'Home', scheduledFor: _date)],
    );
    service.marks['h-1'] = HouseholdDeletionMark(readable: true, scheduledFor: _date);
    await provider.load();
    await tester.pumpWidget(_app(const HouseholdDeletionBanner(householdId: 'h-1'), provider));
    await tester.pump();
    await tester.pump();
    expect(_banner, findsOneWidget);

    service.marks.remove('h-1');
    await provider.cancelDeletion();
    await tester.pump();
    expect(_banner, findsNothing);
  });

  testWidgets('a member\'s banner disappears on the next resume after someone else cancels', (tester) async {
    service.marks['h-1'] = HouseholdDeletionMark(readable: true, scheduledFor: _date);
    await tester.pumpWidget(_app(const HouseholdDeletionBanner(householdId: 'h-1'), provider));
    await tester.pump();
    await tester.pump();
    expect(_banner, findsOneWidget);

    service.marks.remove('h-1');
    await provider.refreshOnResume();
    await tester.pump();
    expect(_banner, findsNothing);
  });

  testWidgets('it follows a switch to another household', (tester) async {
    service.marks['h-2'] = HouseholdDeletionMark(readable: true, scheduledFor: _date);
    await tester.pumpWidget(_app(const HouseholdDeletionBanner(householdId: 'h-1'), provider));
    await tester.pump();
    await tester.pump();
    expect(_banner, findsNothing);

    await tester.pumpWidget(_app(const HouseholdDeletionBanner(householdId: 'h-2'), provider));
    await tester.pump();
    await tester.pump();
    expect(service.reads, ['h-1', 'h-2']);
    expect(_banner, findsOneWidget);
  });

  testWidgets('without the provider it shows nothing and does not throw', (tester) async {
    await tester.pumpWidget(_app(const HouseholdDeletionBanner(householdId: 'h-1'), null));
    await tester.pump();
    expect(_banner, findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final lang in const ['en', 'ar', 'ur']) {
    for (final dark in const [false, true]) {
      testWidgets('$lang ${dark ? 'dark' : 'light'}: fits at 320px and x2.0 text', (tester) async {
        service.marks['h-1'] = HouseholdDeletionMark(readable: true, scheduledFor: _date);
        tester.view.physicalSize = const Size(320, 1800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(_app(const HouseholdDeletionBanner(householdId: 'h-1'), provider, lang: lang, dark: dark, scale: 2.0));
        await tester.pump();
        await tester.pump();
        expect(_banner, findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
