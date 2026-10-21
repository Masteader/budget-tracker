// UX-20: Arabic and Urdu text falls back to the bundled Cairo (OFL), not to
// the phone's book face, in both themes.
import 'dart:io';

import 'package:budget_tracker/theme/app_themes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Cairo 400/600/700 and its licence are bundled and declared', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('family: Cairo'));
    for (final f in ['Cairo-Regular.ttf', 'Cairo-SemiBold.ttf', 'Cairo-Bold.ttf']) {
      expect(pubspec, contains('assets/fonts/cairo/$f'));
      expect(File('assets/fonts/cairo/$f').lengthSync(), greaterThan(50000), reason: f);
    }
    expect(File('assets/fonts/cairo/OFL.txt').readAsStringSync(), contains('SIL Open Font License'));
  });

  for (final mode in ['light', 'dark']) {
    testWidgets('$mode theme: every text style falls back to Cairo', (tester) async {
      final theme = mode == 'light' ? AppThemes.lightTheme : AppThemes.darkTheme;
      final t = theme.textTheme;
      for (final style in [t.bodySmall, t.bodyMedium, t.bodyLarge, t.titleMedium, t.labelLarge, t.headlineSmall]) {
        expect(style?.fontFamilyFallback, contains('Cairo'));
      }
      expect(theme.appBarTheme.titleTextStyle?.fontFamilyFallback, contains('Cairo'));
      expect(theme.navigationBarTheme.labelTextStyle?.resolve(<WidgetState>{})?.fontFamilyFallback, contains('Cairo'));
    });
  }
}
