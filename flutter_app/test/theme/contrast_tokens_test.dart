// UX-06 / UX-27: every text colour the theme hands out must reach WCAG AA
// (4.5:1) on the surfaces it is drawn on, in light mode and in dark mode.
import 'dart:io';

import 'package:budget_tracker/theme/app_themes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

Future<BuildContext> _contextFor(WidgetTester tester, ThemeData theme) async {
  late BuildContext captured;
  await tester.pumpWidget(MaterialApp(
    theme: theme,
    home: Builder(builder: (context) {
      captured = context;
      return const SizedBox.shrink();
    }),
  ));
  return captured;
}

void main() {
  for (final mode in ['light', 'dark']) {
    testWidgets('$mode mode: text tokens reach 4.5:1 on card, canvas and subtle surfaces', (tester) async {
      final context = await _contextFor(tester, mode == 'light' ? AppThemes.lightTheme : AppThemes.darkTheme);
      final surfaces = <String, Color>{
        'card': context.cardBg,
        'canvas': context.scaffoldBg,
        'subtle': context.subtleCardBg,
      };
      final texts = <String, Color>{
        'textPrimary': context.textPrimary,
        'textSecondary': context.textSecondary,
        'textMuted': context.textMuted,
        'accentText': context.accentText,
        'successText': context.successText,
        'goldText': context.goldText,
        'infoText': context.infoText,
        'warnText': context.warnText,
        'dangerColor': context.dangerColor,
        // Getters that many widgets still use for text.
        'champagneGold': context.champagneGold,
        'iceCyan': context.iceCyan,
        'mintNeon': context.mintNeon,
        'electricTeal': context.electricTeal,
        'primaryAccent': context.primaryAccent,
      };
      final failures = <String>[];
      texts.forEach((name, fg) {
        surfaces.forEach((surface, bg) {
          final ratio = contrast(fg, bg);
          if (ratio < 4.5) failures.add('$name on $surface: ${ratio.toStringAsFixed(2)}');
        });
      });
      expect(failures, isEmpty);
    });

    testWidgets('$mode mode: ink on the green fill and text on the hero gradient reach 4.5:1', (tester) async {
      final context = await _contextFor(tester, mode == 'light' ? AppThemes.lightTheme : AppThemes.darkTheme);
      expect(contrast(context.onAccentFill, AppThemes.success), greaterThanOrEqualTo(4.5));
      for (final stop in context.icedHeroGradient.colors) {
        expect(contrast(context.heroText, stop), greaterThanOrEqualTo(4.5), reason: 'hero text on $stop');
        expect(contrast(context.heroCaption, stop), greaterThanOrEqualTo(4.5), reason: 'hero caption on $stop');
      }
    });

    testWidgets('$mode mode: selected bottom-navigation labels reach 4.5:1', (tester) async {
      final theme = mode == 'light' ? AppThemes.lightTheme : AppThemes.darkTheme;
      final style = theme.navigationBarTheme.labelTextStyle!.resolve({WidgetState.selected})!;
      final idle = theme.navigationBarTheme.labelTextStyle!.resolve(<WidgetState>{})!;
      final bg = theme.navigationBarTheme.backgroundColor!;
      expect(contrast(style.color!, bg), greaterThanOrEqualTo(4.5));
      expect(contrast(idle.color!, bg), greaterThanOrEqualTo(4.5));
    });
  }

  test('no filled green button paints white text (2.2:1 on #00C896)', () {
    final offenders = <String>[];
    final pattern = RegExp(
      r'backgroundColor:\s*AppThemes\.success,\s*\n\s*foregroundColor:\s*Colors\.white',
    );
    for (final dir in ['lib/screens', 'lib/widgets']) {
      for (final f in Directory(dir).listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        if (pattern.hasMatch(f.readAsStringSync())) offenders.add(f.path);
      }
    }
    expect(offenders, isEmpty);
  });

  test('the bottom navigation does not hard-code the 4.0:1 teal', () {
    final src = File('lib/screens/home/dashboard_screen.dart').readAsStringSync();
    expect(src.contains('0xFF008F7A'), isFalse);
  });
}
