// The setup tutor never navigates itself: it closes with the chosen action and
// the screen opens from the caller's context once the dialog has gone. Before
// this fix the dialog pushed a screen and then popped it again while closing.
import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/widgets/onboarding/app_setup_tutor_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeNavigator extends TutorNavigator {
  final calls = <(TutorAction, String)>[];
  bool? seenAtOpen;
  int? paydayAtOpen;

  @override
  Future<void> open(BuildContext context, TutorAction action, String householdId, {int? paydayDay}) async {
    calls.add((action, householdId));
    paydayAtOpen = paydayDay;
    final prefs = await SharedPreferences.getInstance();
    seenAtOpen = prefs.getBool(AppSetupTutorDialog.prefKey);
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(body: Text('OPENED ${action.name}')),
    ));
  }
}

final _done = <TutorAction>[];

Widget _app({required String? householdId, required _FakeNavigator navigator}) => MaterialApp(
      locale: const Locale('en'),
      supportedLocales: const [Locale('en'), Locale('ar'), Locale('ur')],
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => AppSetupTutorDialog.show(
                context,
                householdId: householdId,
                navigator: navigator,
                fallbackIsAdmin: true,
                paydayDay: 25,
                loadRoster: (_) async => throw StateError('offline'),
                onActionDone: _done.add,
              ),
              child: const Text('OPEN TUTOR'),
            ),
          ),
        ),
      ),
    );

Future<void> _openTutor(WidgetTester tester, {String? householdId = 'h1', required _FakeNavigator navigator}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(householdId: householdId, navigator: navigator));
  await tester.pumpAndSettle();
  await tester.tap(find.text('OPEN TUTOR'));
  await tester.pumpAndSettle();
  expect(find.byType(AppSetupTutorDialog), findsOneWidget);
}

/// Pages forward with "Next Step" until [finder] is on screen.
Future<void> _pageTo(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 8 && finder.evaluate().isEmpty; i++) {
    await tester.tap(find.byKey(const ValueKey('tutor_next')));
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  expect(finder.hitTestable(), findsOneWidget);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _done.clear();
  });

  for (final action in TutorAction.values) {
    testWidgets('the ${action.name} button closes the tutor and its screen stays open', (tester) async {
      final navigator = _FakeNavigator();
      await _openTutor(tester, navigator: navigator);

      final button = find.byKey(ValueKey('tutor_action_${action.name}'));
      await _pageTo(tester, button);
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(find.byType(AppSetupTutorDialog), findsNothing);
      expect(find.text('OPENED ${action.name}'), findsOneWidget);
      expect(navigator.calls, [(action, 'h1')]);
      expect(navigator.seenAtOpen, isTrue, reason: 'the tutor is marked seen before the screen opens');
      expect(navigator.paydayAtOpen, 25, reason: "the household's payday is passed on (review R2-2)");
      expect(_done, isEmpty, reason: 'reported once the opened screen is closed');

      Navigator.of(tester.element(find.text('OPENED ${action.name}'))).pop();
      await tester.pumpAndSettle();
      expect(_done, [action], reason: 'the caller is told an action ran, to refresh what it shows');
    });
  }

  testWidgets('close, skip and finish open nothing', (tester) async {
    final navigator = _FakeNavigator();
    await _openTutor(tester, navigator: navigator);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(AppSetupTutorDialog), findsNothing);

    await tester.tap(find.text('OPEN TUTOR'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tutor_skip')));
    await tester.pumpAndSettle();
    expect(find.byType(AppSetupTutorDialog), findsNothing);

    await tester.tap(find.text('OPEN TUTOR'));
    await tester.pumpAndSettle();
    final finish = find.byKey(const ValueKey('tutor_action_finish'));
    await _pageTo(tester, finish);
    await tester.tap(finish);
    await tester.pumpAndSettle();
    expect(find.byType(AppSetupTutorDialog), findsNothing);

    expect(navigator.calls, isEmpty);
    expect(_done, isEmpty);
    expect(find.text('OPEN TUTOR'), findsOneWidget);
  });

  testWidgets('without a household, only the buttons that need none are offered', (tester) async {
    final navigator = _FakeNavigator();
    await _openTutor(tester, householdId: null, navigator: navigator);

    final seen = <String>{};
    for (var i = 0; i < 8; i++) {
      for (final a in TutorAction.values) {
        if (find.byKey(ValueKey('tutor_action_${a.name}')).evaluate().isNotEmpty) seen.add(a.name);
      }
      final next = find.byKey(const ValueKey('tutor_next'));
      if (find.byKey(const ValueKey('tutor_action_finish')).evaluate().isNotEmpty) break;
      await tester.tap(next);
      await tester.pumpAndSettle();
    }
    expect(seen, {'budgets'});
  });
}
