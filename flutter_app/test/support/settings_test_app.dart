// Shared helpers for the Settings theme, l10n and layout tests.
import 'dart:io';

import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/theme/app_themes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}

/// The surface a [ThreeDSurfaceCard] paints: its lightest gradient stop in dark.
Color surfaceCardBg(BuildContext context) =>
    context.isDark ? VelvetBurgundyColors.surfaceDarkGradientStart : VelvetBurgundyColors.surfaceLight;

/// The real scaler reaches routes (sheets, dialogs) through MaterialApp.builder.
Widget settingsTestApp(Widget child, {String lang = 'en', bool dark = false, double scale = 1.0, bool scaffold = true}) => MaterialApp(
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
      home: scaffold ? Scaffold(body: SingleChildScrollView(child: child)) : child,
    );

void useViewport(WidgetTester tester, {double width = 390, double height = 2400}) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Pumps until a sheet or dialog has finished opening, for pages with spinners
/// where pumpAndSettle would never return.
Future<void> settleFrames(WidgetTester tester, [int frames = 12]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// The default test font draws every glyph as a 1em square, so where a line
/// breaks says nothing about a phone. This registers the bundled Cairo under the
/// primary family names the theme and GoogleFonts ask for (a fallback family is
/// only used for glyphs the primary lacks, and the test font has them all), so
/// widths are realistic. Outfit itself is not in the repo; Cairo is close to it.
Future<void> loadRealFontMetrics() async {
  final regular = File('assets/fonts/cairo/Cairo-Regular.ttf').readAsBytesSync();
  final bold = File('assets/fonts/cairo/Cairo-Bold.ttf').readAsBytesSync();
  for (final family in [
    'Cairo',
    'Tajawal',
    'Outfit',
    'Outfit_regular',
    for (final weight in [100, 200, 300, 500, 600, 700, 800, 900]) 'Outfit_$weight',
  ]) {
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.sublistView(regular)))
      ..addFont(Future.value(ByteData.sublistView(bold)));
    await loader.load();
  }
}

/// The on-screen line of each character of [p], by the boxes it really painted.
List<int?> _lineOfEachChar(RenderParagraph p, String text) {
  final lines = <int?>[];
  TextBox? current;
  var line = 0;
  for (var i = 0; i < text.length; i++) {
    final boxes = p.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
    if (boxes.isEmpty) {
      lines.add(null);
      continue;
    }
    final box = boxes.first;
    // Runs in different fonts on one line differ in height, so a new line is a
    // box whose middle lies outside the previous box, not just a different top.
    final middle = (box.top + box.bottom) / 2;
    if (current != null && (middle < current.top || middle > current.bottom)) line++;
    current = box;
    lines.add(line);
  }
  return lines;
}

/// How many lines [p] painted.
int paintedLineCount(RenderParagraph p) {
  final text = p.text.toPlainText();
  final lines = _lineOfEachChar(p, text).whereType<int>();
  return lines.isEmpty ? 0 : lines.last + 1;
}

final _wordChar = RegExp(r'[\p{L}\p{N}\p{M}]', unicode: true);

/// The texts under [scope] that broke a line in the middle of a word, shown as
/// `start|rest`. A break after a space, hyphen or other punctuation is fine.
List<String> brokenWords(WidgetTester tester, Finder scope, {bool Function(String text)? ignore, Finder? excluding}) {
  final out = <String>[];
  final paragraphs = tester.renderObjectList<RenderParagraph>(
    find.descendant(of: scope, matching: find.byType(RichText)),
  );
  final skipped = excluding == null
      ? const <RenderParagraph>{}
      : tester.renderObjectList<RenderParagraph>(find.descendant(of: excluding, matching: find.byType(RichText))).toSet();
  for (final p in paragraphs) {
    if (skipped.contains(p)) continue;
    final text = p.text.toPlainText();
    if (text.trim().isEmpty || (ignore?.call(text) ?? false)) continue;
    final lines = _lineOfEachChar(p, text);
    int? lastIndex;
    for (var i = 0; i < text.length; i++) {
      if (lines[i] == null) continue;
      if (lastIndex != null && lines[i] != lines[lastIndex]) {
        final before = text[lastIndex];
        final after = text[i];
        if (i == lastIndex + 1 && _wordChar.hasMatch(before) && _wordChar.hasMatch(after)) {
          out.add('${text.substring(0, i)}|${text.substring(i)}');
        }
      }
      lastIndex = i;
    }
  }
  return out;
}
