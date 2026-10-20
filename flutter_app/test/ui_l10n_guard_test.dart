// Regression guards for localization (en / ar / ur) and hardcoded UI strings.
//
// 1. The three language maps in lib/l10n/app_localizations.dart must declare
//    exactly the same keys, with the same {placeholders}.
// 2. Arabic and Urdu values must actually be written in Arabic script
//    (catches English text pasted into the wrong map).
// 3. Screens and widgets must not pass string literals to user-facing text
//    parameters (Text(...), hintText:, labelText:, tooltip:, ...).
// 4. Every key referenced with tr('...') / trArgs('...') / trPlural('...')
//    must exist.
// 5. Urdu values must not contain Arabic-only letters (ي ك ى ة).
// 6. The plural table has every CLDR form each language needs.
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

  test('Urdu values contain no Arabic-only letters (ي ك ى ة)', () {
    // Deliberate exceptions: the Arabic endonym and the Arabic sample sentence.
    const allowArabic = {'language_ar', 'chat_welcome'};
    final arabicOnly = RegExp('[يكىة]');
    final offenders = <String>[];
    maps['ur']!.forEach((key, value) {
      if (!allowArabic.contains(key) && arabicOnly.hasMatch(value)) {
        offenders.add('ur:$key=$value');
      }
    });
    AppLocalizations.pluralTable.forEach((key, langs) {
      langs['ur']!.forEach((form, value) {
        if (arabicOnly.hasMatch(value)) offenders.add('ur:$key.$form=$value');
      });
    });
    expect(offenders, isEmpty, reason: offenders.join('\n'));
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

  test('every trPlural() key used in lib/ is in the plural table', () {
    final used = <String>{};
    final keyRef = RegExp(r'''\btrPlural\(\s*['"]([a-z0-9_]+)['"]''');
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      for (final m in keyRef.allMatches(f.readAsStringSync())) {
        used.add(m.group(1)!);
      }
    }
    expect(used, isNotEmpty);
    expect(used.difference(AppLocalizations.pluralTable.keys.toSet()), isEmpty);
  });

  test('plural table: every key has the CLDR forms each language needs', () {
    const required = {
      'en': {'one', 'other'},
      'ur': {'one', 'other'},
      'ar': {'zero', 'one', 'two', 'few', 'many', 'other'},
    };
    final problems = <String>[];
    AppLocalizations.pluralTable.forEach((key, langs) {
      if (maps['en']!.containsKey(key)) problems.add('$key is also a plain key');
      if (!langs.keys.toSet().containsAll(required.keys)) problems.add('$key lacks a language');
      // Placeholders other than {count} must be the same in every form.
      final extra = _placeholders(langs['en']!['other']!)..remove('{count}');
      langs.forEach((lang, forms) {
        final need = required[lang]!;
        if (!forms.keys.toSet().containsAll(need)) {
          problems.add('$lang:$key is missing forms ${need.difference(forms.keys.toSet())}');
        }
        if (!{...need, 'zero'}.containsAll(forms.keys)) problems.add('$lang:$key has unknown forms');
        forms.forEach((form, value) {
          final ph = _placeholders(value)..remove('{count}');
          if (!ph.containsAll(extra) || !extra.containsAll(ph)) {
            problems.add('$lang:$key.$form placeholders $ph != $extra');
          }
          if (lang != 'en' && !RegExp('[؀-ۿ]').hasMatch(value)) {
            problems.add('$lang:$key.$form is not in Arabic script');
          }
        });
        if (!(forms['other'] ?? '').contains('{count}')) problems.add('$lang:$key.other has no {count}');
      });
    });
    expect(problems, isEmpty, reason: problems.join('\n'));
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
      expect(en.format('take_shot_n', {'n': 3}), 'Take Shot 3');
      expect(en.format('no_allocations_for_cycle', {'cycle': 'November 2026'}), 'No allocations for November 2026');
    });

    test('Arabic plural categories follow CLDR (0 / 1 / 2 / 3-10 / 11-99 / 100+)', () {
      String ar(num n) => AppLocalizations.pluralCategory('ar', n);
      expect(ar(0), 'zero');
      expect(ar(1), 'one');
      expect(ar(2), 'two');
      for (final n in [3, 7, 10, 103, 110, 1005]) {
        expect(ar(n), 'few', reason: '$n');
      }
      for (final n in [11, 25, 99, 111, 1099]) {
        expect(ar(n), 'many', reason: '$n');
      }
      for (final n in [100, 101, 102, 200, 1000]) {
        expect(ar(n), 'other', reason: '$n');
      }
      expect(ar(2.5), 'other');
    });

    test('English and Urdu plural categories are one / other', () {
      for (final lang in ['en', 'ur']) {
        expect(AppLocalizations.pluralCategory(lang, 1), 'one');
        for (final n in [0, 2, 3, 11, 100]) {
          expect(AppLocalizations.pluralCategory(lang, n), 'other', reason: '$lang $n');
        }
      }
    });

    test('plural picks the right Arabic noun form for each count', () {
      final ar = AppLocalizations(const Locale('ar'));
      expect(ar.plural('items_count', 0), 'لا توجد بنود');
      expect(ar.plural('items_count', 1), 'بند واحد');
      expect(ar.plural('items_count', 2), 'بندان');
      expect(ar.plural('items_count', 3), '3 بنود');
      expect(ar.plural('items_count', 10), '10 بنود');
      expect(ar.plural('items_count', 11), '11 بنداً');
      expect(ar.plural('items_count', 100), '100 بند');
      expect(ar.plural('days_to_payday_badge', 5), '5 أيام على الراتب');
      expect(ar.plural('days_to_payday_badge', 12), '12 يوماً على الراتب');
      expect(ar.plural('n_months', 2), 'شهران');
      expect(ar.plural('n_months', 12), '12 شهراً');
      expect(
        ar.plural('scan_items_logged', 4, {'merchant': 'بنده', 'amount': '20.00 ر.س'}),
        'تم تسجيل 4 بنود لدى بنده (20.00 ر.س)',
      );
    });

    test('plural works for English and Urdu, including optional zero forms', () {
      final en = AppLocalizations(const Locale('en'));
      expect(en.plural('across_accounts', 1), 'across 1 account');
      expect(en.plural('across_accounts', 3), 'across 3 accounts');
      expect(en.plural('across_accounts', 0), 'across 0 accounts');
      expect(en.plural('days_to_payday_badge', 0), 'PAYDAY TODAY');
      expect(en.plural('transactions_count', 1), '1 transaction');
      expect(en.plural('transactions_count', 4), '4 transactions');
      final ur = AppLocalizations(const Locale('ur'));
      expect(ur.plural('queued_offline', 1), '1 لین دین آف لائن محفوظ ہے');
      expect(ur.plural('queued_offline', 5), '5 لین دین آف لائن محفوظ ہیں');
      expect(ur.plural('no_such_plural_key', 2), 'no_such_plural_key');
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
