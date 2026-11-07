// Closing the setup tutor never pops the screen underneath it, even when the
// barrier or the back button closes it while its "seen" flag is still being
// written; and the flag is written on every way it can close (review R2-1).
// The member list is requested once per tutor (review R2-3).
import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/models/household_membership.dart';
import 'package:budget_tracker/widgets/onboarding/app_setup_tutor_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

/// A store whose writes take [delay], like a slow disk.
class _SlowStore extends InMemorySharedPreferencesStore {
  _SlowStore() : super.empty();
  Duration delay = const Duration(milliseconds: 40);

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    await Future<void>.delayed(delay);
    return super.setValue(valueType, key, value);
  }
}

class _RecordingNavigator extends TutorNavigator {
  final opened = <TutorAction>[];

  @override
  Future<void> open(BuildContext context, TutorAction action, String householdId, {int? paydayDay}) async =>
      opened.add(action);
}

/// Counts the routes popped.
class _PopRecorder extends NavigatorObserver {
  List<String?> pops = [];

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => pops.add(route.settings.name);
}

Widget _app(Widget home, {ThemeMode mode = ThemeMode.light}) => MaterialApp(
      navigatorObservers: [_PopRecorder()],
      locale: const Locale('en'),
      themeMode: mode,
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      supportedLocales: const [Locale('en'), Locale('ar'), Locale('ur')],
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: home,
    );

/// Home → "UNDER" (the screen that opens the tutor).
Widget _home(_RecordingNavigator navigator) => Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            key: const ValueKey('push'),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (ctx) => Scaffold(
                body: Column(
                  children: [
                    const Text('UNDER'),
                    TextButton(
                      key: const ValueKey('open'),
                      onPressed: () => AppSetupTutorDialog.show(
                        ctx,
                        householdId: 'h1',
                        fallbackIsAdmin: true,
                        navigator: navigator,
                        loadRoster: (_) async => throw StateError('offline'),
                      ),
                      child: const SizedBox(width: 40, height: 40),
                    ),
                  ],
                ),
              ),
            )),
            child: const SizedBox(width: 40, height: 40),
          ),
        ),
      ),
    );

Future<_SlowStore> _openTutor(WidgetTester tester, _RecordingNavigator navigator) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final store = _SlowStore();
  SharedPreferencesStorePlatform.instance = store;
  await tester.pumpWidget(_app(_home(navigator)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('push')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('open')));
  await tester.pumpAndSettle();
  expect(find.byType(AppSetupTutorDialog), findsOneWidget);
  return store;
}

Future<bool?> _seen() async => (await SharedPreferences.getInstance()).getBool(AppSetupTutorDialog.prefKey);

void main() {
  final closers = <String, Finder Function()>{
    'skip': () => find.byKey(const ValueKey('tutor_skip')),
    'close icon': () => find.byTooltip('Close'),
    'an action button': () => find.byKey(const ValueKey('tutor_action_payday')),
  };
  final interrupts = <String, Future<void> Function(WidgetTester)>{
    'the barrier': (tester) => tester.tapAt(const Offset(4, 4)),
    'back': (tester) async {
      await tester.binding.handlePopRoute();
    },
  };

  for (final closer in closers.entries) {
    testWidgets('${closer.key}, then a tap on the barrier: the screen underneath stays', (tester) async {
      final navigator = _RecordingNavigator();
      await _openTutor(tester, navigator);

      await tester.tap(closer.value());
      await tester.pump(const Duration(milliseconds: 5));
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();

      expect(find.byType(AppSetupTutorDialog), findsNothing);
      expect(find.text('UNDER'), findsOneWidget, reason: 'the route under the tutor must not be popped');
      expect(await _seen(), isTrue);
    });

    testWidgets('${closer.key}, then back: back goes back one screen, not two', (tester) async {
      final navigator = _RecordingNavigator();
      await _openTutor(tester, navigator);
      final pops = <String?>[];
      final nav = tester.state<NavigatorState>(find.byType(Navigator));
      nav.widget.observers.whereType<_PopRecorder>().forEach((o) => o.pops = pops);

      await tester.tap(closer.value());
      await tester.pump(const Duration(milliseconds: 5));
      // The tutor is already closed: this back is the person's next step.
      expect(find.byType(AppSetupTutorDialog).hitTestable(), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('UNDER'), findsNothing);
      expect(find.byKey(const ValueKey('push')), findsOneWidget, reason: 'the home screen stays');
      expect(pops.length, 2, reason: 'one pop for the tutor, one for the back press');
      expect(await _seen(), isTrue);
    });
  }

  for (final interrupt in interrupts.entries) {
    testWidgets('closed by ${interrupt.key} alone: marked seen, nothing opens', (tester) async {
      final navigator = _RecordingNavigator();
      await _openTutor(tester, navigator);
      await interrupt.value(tester);
      await tester.pumpAndSettle();

      expect(find.byType(AppSetupTutorDialog), findsNothing);
      expect(find.text('UNDER'), findsOneWidget);
      expect(navigator.opened, isEmpty);
      expect(await _seen(), isTrue);
    });
  }

  testWidgets('a rebuild above the navigator does not load the member list again', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    var loads = 0;
    late StateSetter setOuter;
    var mode = ThemeMode.light;
    await tester.pumpWidget(StatefulBuilder(
      builder: (context, setState) {
        setOuter = setState;
        return _app(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                key: const ValueKey('open'),
                onPressed: () => AppSetupTutorDialog.show(
                  context,
                  householdId: 'h1',
                  fallbackIsAdmin: false,
                  navigator: _RecordingNavigator(),
                  loadRoster: (_) async {
                    loads++;
                    return const HouseholdRoster(
                      householdId: 'h1',
                      householdType: kHouseholdTypeFamily,
                      callerRole: 'member',
                      nafaqahProviderUserId: 'h',
                      members: [
                        HouseholdMember(userId: 'h', role: 'admin', isNafaqahProvider: true),
                        HouseholdMember(userId: 'w', financialRole: 'spouse', isSelf: true),
                      ],
                    );
                  },
                ),
                child: const SizedBox(width: 40, height: 40),
              ),
            ),
          ),
          mode: mode,
        );
      },
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pumpAndSettle();
    expect(loads, 1);
    expect(find.text('Step 1 of 6'), findsOneWidget);

    setOuter(() => mode = ThemeMode.dark);
    await tester.pumpAndSettle();
    setOuter(() => mode = ThemeMode.light);
    await tester.pumpAndSettle();

    expect(loads, 1);
    expect(find.text('Step 1 of 6'), findsOneWidget);
  });
}
