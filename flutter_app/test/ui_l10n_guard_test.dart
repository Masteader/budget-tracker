// Regression guards for localization (en / ar / ur) and hardcoded UI strings.
//
// 1. The three language maps in lib/l10n/app_localizations.dart must declare
//    exactly the same keys, with the same {placeholders}.
// 2. Arabic and Urdu values must actually be written in Arabic script
//    (catches English text pasted into the wrong map).
// 3. Screens and widgets must not pass string literals to user-facing text
//    parameters (Text(...), hintText:, labelText:, tooltip:, ...).
// 4. Every key referenced with tr('...') / trArgs('...') must exist.
import 'dart:io';

import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

final _l10nSource = File('lib/l10n/app_localizations.dart').readAsStringSync();

/// Parses `'lang': { 'key': 'value', ... }` blocks of `_localizedValues`.
Map<String, Map<String, String>> _parseMaps() {
  final start = _l10nSource.indexOf('_localizedValues = <String');
  if (start < 0) throw StateError('_localizedValues map not found');
  final lines = _l10nSource.substring(start).split('\n');
  final maps = <String, Map<String, String>>{};
  String? current;
  final header = RegExp(r"^\s*'(en|ar|ur)': \{\s*$");
  final entry = RegExp(r"^\s*'([a-z0-9_]+)'\s*:\s*'((?:[^'\\]|\\.)*)',\s*$");
  for (final line in lines.skip(1)) {
    if (RegExp(r'^  \};').hasMatch(line)) break;
    final h = header.firstMatch(line);
    if (h != null) {
      current = h.group(1);
      maps[current!] = {};
      continue;
    }
    final e = entry.firstMatch(line);
    if (current != null && e != null) {
      if (maps[current]!.containsKey(e.group(1))) {
        throw StateError('duplicate key ${e.group(1)} in $current');
      }
      maps[current]![e.group(1)!] = e.group(2)!;
    }
  }
  return maps;
}

Set<String> _placeholders(String s) =>
    RegExp(r'\{[a-zA-Z_]+\}').allMatches(s).map((m) => m.group(0)!).toSet();

/// Reads a Dart string literal whose opening quote is at [start], honouring
/// escapes and `${...}` interpolations (which may contain nested quotes).
/// Returns the literal body, or null if there is no single-line literal.
String? _readLiteral(String line, int start) {
  if (start >= line.length) return null;
  final quote = line[start];
  if (quote != "'" && quote != '"') return null;
  final buf = StringBuffer();
  var i = start + 1;
  while (i < line.length) {
    final c = line[i];
    if (c == r'\') {
      i += 2;
      continue;
    }
    if (c == r'$' && i + 1 < line.length && line[i + 1] == '{') {
      var depth = 0;
      while (i < line.length) {
        if (line[i] == '{') depth++;
        if (line[i] == '}' && --depth == 0) break;
        i++;
      }
      i++;
      continue; // interpolation content is not literal text
    }
    if (c == quote) return buf.toString();
    if (c == r'$') {
      // simple $identifier interpolation
      i++;
      while (i < line.length && RegExp(r'\w').hasMatch(line[i])) {
        i++;
      }
      continue;
    }
    buf.write(c);
    i++;
  }
  return null;
}

Iterable<File> _uiDartFiles() sync* {
  for (final dir in ['lib/screens', 'lib/widgets']) {
    yield* Directory(dir)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
  }
}

void main() {
  late Map<String, Map<String, String>> maps;
  setUpAll(() => maps = _parseMaps());

  test('en, ar and ur maps exist and have identical key sets', () {
    expect(maps.keys.toSet(), {'en', 'ar', 'ur'});
    final en = maps['en']!.keys.toSet();
    for (final lang in ['ar', 'ur']) {
      final other = maps[lang]!.keys.toSet();
      expect(en.difference(other), isEmpty, reason: 'keys missing in $lang');
      expect(other.difference(en), isEmpty, reason: 'keys only in $lang');
    }
    expect(en.length, greaterThan(1000));
  });

  test('placeholders match across languages', () {
    final mismatches = <String>[];
    maps['en']!.forEach((key, enValue) {
      for (final lang in ['ar', 'ur']) {
        final other = maps[lang]![key]!;
        if (!_placeholders(enValue).containsAll(_placeholders(other)) ||
            !_placeholders(other).containsAll(_placeholders(enValue))) {
          mismatches.add('$lang:$key');
        }
      }
    });
    expect(mismatches, isEmpty);
  });

  test('Arabic and Urdu values are written in Arabic script', () {
    // Brand names / abbreviations that are legitimately Latin in ar/ur.
    const allowLatin = {'pay_method_stc_pay', 'language_en', 'tib_total_vat', 'bir_vat'};
    final arabicScript = RegExp('[؀-ۿ]');
    final offenders = <String>[];
    for (final lang in ['ar', 'ur']) {
      maps[lang]!.forEach((key, value) {
        if (!allowLatin.contains(key) && !arabicScript.hasMatch(value)) {
          offenders.add('$lang:$key=$value');
        }
      });
    }
    expect(offenders, isEmpty);
  });

  test('Urdu currency is riyal, never rupees', () {
    for (final value in maps['ur']!.values) {
      expect(RegExp('روپ(ے|یہ|ئے)').hasMatch(value), isFalse, reason: value);
    }
  });

  test('every tr()/trArgs() key used in lib/ is defined', () {
    final used = <String>{};
    final keyRef = RegExp(r'''\btr(?:Args)?\(\s*['"]([a-z0-9_]+)['"]''');
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      for (final m in keyRef.allMatches(f.readAsStringSync())) {
        used.add(m.group(1)!);
      }
    }
    final missing = used.difference(maps['en']!.keys.toSet());
    expect(missing, isEmpty);
  });

  test('screens and widgets contain no hardcoded user-facing literals', () {
    // A string literal containing letters passed straight to a user-facing
    // text parameter. Interpolations of tr() results are fine because the
    // literal itself then contains no letters outside `${...}`.
    final prefixes = [
      RegExp(r'\b(?:Text|SelectableText|Tooltip)\(\s*'),
      RegExp(r'\b(?:hintText|labelText|helperText|errorText|tooltip|semanticLabel|semanticsLabel|suffixText|prefixText)\s*:\s*'),
      RegExp(r'\bTab\(\s*(?:icon:[^,]*,\s*)?text:\s*'),
      RegExp(r'\btitle:\s*'),
    ];
    // Endonyms (language names shown in their own script) and sample data.
    const allowed = {'English', 'AQ5UYW1pbWkgTWFya2V0cw...'};
    final letters = RegExp('[A-Za-z؀-ۿ]{2,}');
    final snakeCaseKey = RegExp(r'^[a-z0-9_]+$');
    final offenders = <String>[];
    for (final file in _uiDartFiles()) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//')) continue;
        for (final p in prefixes) {
          for (final m in p.allMatches(line)) {
            final literal = _readLiteral(line, m.end);
            if (literal == null || allowed.contains(literal.trim())) continue;
            // Sample ZATCA Base64 payloads shown as input hints are data.
            if (RegExp(r'^[A-Za-z0-9+/=]{24,}\.*$').hasMatch(literal.trim())) continue;
            // Translation keys (snake_case) used as data are fine.
            if (snakeCaseKey.hasMatch(literal)) continue;
            if (letters.hasMatch(literal)) offenders.add('${file.path}:${i + 1}: $literal');
          }
        }
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  group('AppLocalizations helpers', () {
    test('format substitutes placeholders', () {
      final en = AppLocalizations(const Locale('en'));
      expect(en.format('across_accounts', {'count': 3}), 'across 3 accounts');
    });

    test('sar puts the unit on the locale-appropriate side', () {
      expect(AppLocalizations(const Locale('en')).sar(1250), 'SAR 1,250.00');
      expect(AppLocalizations(const Locale('ar')).sar(1250), '1,250.00 ر.س');
      expect(AppLocalizations(const Locale('ur')).sar(1250.5, decimals: 0), '1,251 ریال');
    });

    test('cycleMonth formats cycle keys and falls back gracefully', () {
      final en = AppLocalizations(const Locale('en'));
      expect(en.cycleMonth('2026-11'), 'November 2026');
      expect(en.cycleMonth('bad', fallback: 'Fallback'), 'Fallback');
    });

    test('missing keys fall back to English, then to the key', () {
      expect(AppLocalizations(const Locale('ur')).get('nav_dashboard'), isNot('nav_dashboard'));
      expect(AppLocalizations(const Locale('ar')).get('no_such_key_xyz'), 'no_such_key_xyz');
    });
  });
}
