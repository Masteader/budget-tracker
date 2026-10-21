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
  testWidgets('a section shows its title, hides its body until opened', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SettingsSection(
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

  testWidgets('settings: permissions and reports are folded; help stays open', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
      ],
      child: const MaterialApp(home: SettingsScreen()),
    ));
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
}
