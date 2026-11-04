// UX-15: Settings is grouped into sections; the rarely used ones start
// collapsed (nothing is removed, only folded away).
import 'package:budget_tracker/providers/locale_provider.dart';
import 'package:budget_tracker/providers/theme_provider.dart';
import 'package:budget_tracker/screens/settings/settings_screen.dart';
import 'package:budget_tracker/widgets/settings/settings_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Widget page() => MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider(create: (_) => LocaleProvider()),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      );

  testWidgets('a section shows its title, hides its body until opened', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SettingsSection(
          id: 'section',
          title: 'SECTION',
          subtitle: 'Summary line',
          icon: Icons.tune,
          children: [Text('Body')],
        ),
      ),
    ));
    expect(find.text('SECTION'), findsOneWidget);
    expect(find.text('Summary line'), findsOneWidget);
    expect(find.text('Body'), findsNothing);
    await tester.tap(find.text('SECTION'));
    await tester.pumpAndSettle();
    expect(find.text('Body'), findsOneWidget);
    expect(tester.getSize(find.byType(ListTile)).height, greaterThanOrEqualTo(48));
  });

  testWidgets('a list inside a section survives opening and closing it', (tester) async {
    // The tile stores a bool under its PageStorageKey; a list inside reads its
    // scroll offset as a double from whatever slot its ancestors' keys name.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SettingsSection(
          id: 'section',
          title: 'SECTION',
          icon: Icons.tune,
          children: [
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 1,
              itemBuilder: (_, __) => const Text('Row'),
            ),
          ],
        ),
      ),
    ));
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('SECTION'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    expect(find.text('Row'), findsOneWidget);
  });

  testWidgets('settings: permissions and reports are folded; help stays open', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();

    expect(find.byType(SettingsSection), findsWidgets);
    final permissions = find.text('HARDWARE & APP PERMISSIONS');
    await tester.scrollUntilVisible(permissions, 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('Camera Access'), findsNothing);
    await tester.tap(permissions);
    await tester.pumpAndSettle();
    expect(find.text('Camera Access'), findsOneWidget);

    final reports = find.text('REPORTS & OFFLINE QUEUE');
    await tester.scrollUntilVisible(reports, 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('Export Monthly Report'), findsNothing);

    final help = find.text('App Guide & Tutorial');
    await tester.scrollUntilVisible(help, 200, scrollable: find.byType(Scrollable).first);
    expect(help, findsOneWidget);
  });

  testWidgets('without a household: the page order, open and folded, money hidden', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 6000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();

    final sections = tester.widgetList<SettingsSection>(find.byType(SettingsSection)).toList();
    expect(sections.map((s) => s.title).toList(), [
      'HOUSEHOLD & MEMBERSHIP',
      'APPEARANCE & LANGUAGE',
      'REMINDERS',
      'HARDWARE & APP PERMISSIONS',
      'REPORTS & OFFLINE QUEUE',
      'HELP & SUPPORT',
      'ACCOUNT',
    ]);
    expect(sections.map((s) => s.initiallyExpanded).toList(), [true, true, false, false, false, true, true]);
    // Nothing removed: signing out is still reachable.
    expect(find.text('Sign Out'), findsOneWidget);
    expect(find.text('HOUSEHOLD & ACCOUNT'), findsNothing);
  });

  testWidgets('the page ends with one bottom gap, not two stacked', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 6000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();

    final list = tester.widget<ListView>(find.byType(ListView).first);
    expect((list.padding! as EdgeInsets).bottom, 110);
    // The last child of the page is the account section itself.
    final childrenDelegate = list.childrenDelegate as SliverChildListDelegate;
    expect(childrenDelegate.children.last, isA<SettingsSection>());
  });
}
