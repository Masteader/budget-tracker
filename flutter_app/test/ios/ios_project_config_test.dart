/// Structural checks of the iOS project files. Nothing can be compiled for iOS
/// on the Windows and Linux machines that run this suite, so this pins what a
/// wrong edit would silently break: the identifiers auth redirects depend on,
/// the permission strings that crash the app when missing, and the localized
/// app name. See docs/IOS_READINESS.md.
///
/// Parsed by structure: Info.plist and AndroidManifest.xml (XML, comments
/// ignored), project.pbxproj and InfoPlist.strings (Apple's old-style plist
/// format). Malformed files fail here, as they would fail the build.
///
/// Text-based, because no Swift or Ruby parser is available to a Dart test, and
/// only after stripping comments: AppDelegate.swift, SceneDelegate.swift and
/// the Podfile (pinned statement by statement), plus single values read from
/// build.gradle.kts, .metadata and supabase_config.dart.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

const _expectedBundleId = 'com.budgettracker';
const _usageKeys = {
  'NSCameraUsageDescription',
  'NSPhotoLibraryUsageDescription',
  'NSMicrophoneUsageDescription',
  'NSSpeechRecognitionUsageDescription',
};
const _localizedNames = {'en': 'Qawam Money', 'ar': 'قوام المال', 'ur': 'Qawam Money'};

String _read(String path) => File(path).readAsStringSync();

Map<String, Object?> _map(Object? value) => (value! as Map).cast<String, Object?>();
List<Object?> _list(Object? value) => value! as List<Object?>;

// ── Info.plist (XML) ─────────────────────────────────────────────────────────

Object? _plistValue(XmlElement element) {
  switch (element.name.local) {
    case 'string':
      return element.innerText;
    case 'true':
      return true;
    case 'false':
      return false;
    case 'array':
      return element.childElements.map(_plistValue).toList();
    case 'dict':
      final children = element.childElements.toList();
      if (children.length.isOdd) throw FormatException('dict with a key and no value: ${element.toString()}');
      final dict = <String, Object?>{};
      for (var i = 0; i < children.length; i += 2) {
        if (children[i].name.local != 'key') throw FormatException('expected <key>, got ${children[i]}');
        final key = children[i].innerText;
        if (dict.containsKey(key)) throw FormatException('duplicate key $key');
        dict[key] = _plistValue(children[i + 1]);
      }
      return dict;
    default:
      throw FormatException('unsupported plist element ${element.name}');
  }
}

Map<String, Object?> _parsePlist(String source) {
  final root = XmlDocument.parse(source).rootElement;
  if (root.name.local != 'plist') throw FormatException('root is <${root.name}>, not <plist>');
  return _map(_plistValue(root.childElements.single));
}

final Map<String, Object?> _info = _parsePlist(_read('ios/Runner/Info.plist'));

// ── Apple's old-style plist format (project.pbxproj, InfoPlist.strings) ──────

class _OldStylePlist {
  _OldStylePlist(this._s);

  final String _s;
  int _i = 0;

  static final _bare = RegExp(r'[A-Za-z0-9_$/:.\-+]+');

  void _skipSpaceAndComments() {
    while (_i < _s.length) {
      if (_s.startsWith('//', _i)) {
        final end = _s.indexOf('\n', _i);
        _i = end < 0 ? _s.length : end + 1;
      } else if (_s.startsWith('/*', _i)) {
        final end = _s.indexOf('*/', _i + 2);
        if (end < 0) throw FormatException('unterminated comment at $_i');
        _i = end + 2;
      } else if (_s[_i].trim().isEmpty) {
        _i++;
      } else {
        return;
      }
    }
  }

  void _expect(String token) {
    _skipSpaceAndComments();
    if (!_s.startsWith(token, _i)) {
      throw FormatException('expected "$token" at offset $_i: ${_s.substring(_i, (_i + 40).clamp(0, _s.length))}');
    }
    _i += token.length;
  }

  String _quoted() {
    _expect('"');
    final out = StringBuffer();
    while (true) {
      if (_i >= _s.length) throw const FormatException('unterminated string');
      final c = _s[_i++];
      if (c == '"') return out.toString();
      if (c == r'\') {
        if (_i >= _s.length) throw const FormatException('unterminated escape');
        final next = _s[_i++];
        out.write(next == 'n' ? '\n' : next);
      } else {
        out.write(c);
      }
    }
  }

  String _scalar() {
    _skipSpaceAndComments();
    if (_i < _s.length && _s[_i] == '"') return _quoted();
    final match = _bare.matchAsPrefix(_s, _i);
    if (match == null) throw FormatException('expected a value at offset $_i');
    _i = match.end;
    return match.group(0)!;
  }

  Object? _value() {
    _skipSpaceAndComments();
    if (_i >= _s.length) throw const FormatException('unexpected end of file');
    if (_s[_i] == '{') return _dict();
    if (_s[_i] == '(') return _array();
    return _scalar();
  }

  Map<String, Object?> _dict() {
    _expect('{');
    final dict = <String, Object?>{};
    while (true) {
      _skipSpaceAndComments();
      if (_i < _s.length && _s[_i] == '}') {
        _i++;
        return dict;
      }
      final key = _scalar();
      _expect('=');
      if (dict.containsKey(key)) throw FormatException('duplicate key $key');
      dict[key] = _value();
      _expect(';');
    }
  }

  List<Object?> _array() {
    _expect('(');
    final array = <Object?>[];
    while (true) {
      _skipSpaceAndComments();
      if (_i < _s.length && _s[_i] == ')') {
        _i++;
        return array;
      }
      array.add(_value());
      _skipSpaceAndComments();
      if (_i < _s.length && _s[_i] != ')') _expect(',');
    }
  }

  /// A whole document holding one value.
  Object? document() {
    final value = _value();
    _skipSpaceAndComments();
    if (_i != _s.length) throw FormatException('trailing content at offset $_i');
    return value;
  }

  /// A .strings table: `"key" = "value";` entries with no enclosing braces.
  Map<String, String> stringsTable() {
    final table = <String, String>{};
    while (true) {
      _skipSpaceAndComments();
      if (_i >= _s.length) return table;
      final key = _quoted();
      _expect('=');
      _skipSpaceAndComments();
      final value = _quoted();
      _expect(';');
      if (table.containsKey(key)) throw FormatException('duplicate key $key');
      table[key] = value;
    }
  }
}

Map<String, String> _strings(String lang) =>
    _OldStylePlist(_read('ios/Runner/$lang.lproj/InfoPlist.strings')).stringsTable();

/// The Xcode project as its object graph, so a setting is read from the target
/// and configuration that really owns it.
class _Project {
  _Project(String source) {
    final root = _map(_OldStylePlist(source).document());
    _objects = _map(root['objects']);
    project = _object(root['rootObject']);
  }

  late final Map<String, Object?> _objects;
  late final Map<String, Object?> project;

  Map<String, Object?> _object(Object? id) {
    final object = _objects[id];
    if (object == null) throw StateError('dangling reference to $id');
    return _map(object);
  }

  Map<String, Object?> target(String name) =>
      _list(project['targets']).map(_object).singleWhere((t) => t['name'] == name);

  /// Configuration name to its build settings, for a project or a target.
  Map<String, Map<String, Object?>> settings(Map<String, Object?> owner) => {
        for (final id in _list(_object(owner['buildConfigurationList'])['buildConfigurations']))
          _object(id)['name']! as String: _map(_object(id)['buildSettings']),
      };

  /// What the build phase of type [isa] in [target] actually includes.
  List<Map<String, Object?>> phaseFiles(Map<String, Object?> target, String isa) => [
        for (final phase in _list(target['buildPhases']).map(_object).where((p) => p['isa'] == isa))
          for (final file in _list(phase['files']).map(_object)) _object(file['fileRef']),
      ];

  /// Whether the group named [groupName] lists an object named [name].
  bool groupContains(String groupName, String name) => _objects.values
      .map(_map)
      .where((o) => o['isa'] == 'PBXGroup' && (o['path'] == groupName || o['name'] == groupName))
      .expand((g) => _list(g['children']).map(_object))
      .any((child) => child['name'] == name || child['path'] == name);

  /// `lang` to its path, from a variant group's children.
  Map<String, String> variants(Map<String, Object?> group) => {
        for (final child in _list(group['children']).map(_object))
          child['name']! as String: child['path']! as String,
      };
}

final _Project _xcode = _Project(_read('ios/Runner.xcodeproj/project.pbxproj'));

// ── Source with comments removed ─────────────────────────────────────────────

/// Removes `//` and nested `/* */` comments, leaving double-quoted strings alone.
String _stripSwiftComments(String source) {
  final out = StringBuffer();
  var i = 0;
  var depth = 0;
  var inString = false;
  while (i < source.length) {
    if (depth > 0) {
      if (source.startsWith('/*', i)) {
        depth++;
        i += 2;
      } else if (source.startsWith('*/', i)) {
        depth--;
        i += 2;
      } else {
        i++;
      }
    } else if (inString) {
      if (source[i] == r'\' && i + 1 < source.length) {
        out.write(source.substring(i, i + 2));
        i += 2;
      } else {
        if (source[i] == '"') inString = false;
        out.write(source[i++]);
      }
    } else if (source.startsWith('//', i)) {
      final end = source.indexOf('\n', i);
      i = end < 0 ? source.length : end;
    } else if (source.startsWith('/*', i)) {
      depth = 1;
      i += 2;
    } else {
      if (source[i] == '"') inString = true;
      out.write(source[i++]);
    }
  }
  return out.toString();
}

/// The statements inside the `{ }` that follows [anchor].
List<String> _swiftBody(String source, String anchor) {
  final start = source.indexOf('{', source.indexOf(anchor));
  var depth = 0;
  for (var i = start; i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}' && --depth == 0) {
      return source
          .substring(start + 1, i)
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
    }
  }
  throw FormatException('unbalanced braces after $anchor');
}

/// Podfile lines, trimmed, with `#` comments and `=begin` blocks removed.
List<String> _rubyLines(String source) {
  final lines = <String>[];
  var inBlockComment = false;
  for (final raw in source.split('\n')) {
    if (raw.startsWith('=begin')) inBlockComment = true;
    if (inBlockComment) {
      if (raw.startsWith('=end')) inBlockComment = false;
      continue;
    }
    String? quote;
    var end = raw.length;
    for (var i = 0; i < raw.length; i++) {
      final c = raw[i];
      if (quote != null) {
        if (c == r'\') {
          i++;
        } else if (c == quote) {
          quote = null;
        }
      } else if (c == '"' || c == "'") {
        quote = c;
      } else if (c == '#') {
        end = i;
        break;
      }
    }
    final line = raw.substring(0, end).trim();
    if (line.isNotEmpty) lines.add(line);
  }
  return lines;
}

/// The `Permission.x` groups `lib/` uses, ignoring comment lines.
Set<String> _permissionGroupsUsed() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((file) => file.path.endsWith('.dart'))
    .expand((file) => file.readAsLinesSync())
    .where((line) => !line.trimLeft().startsWith('//'))
    .expand((line) => RegExp(r'\bPermission\.(\w+)').allMatches(line))
    .map((match) => match.group(1)!)
    .toSet();

void main() {
  group('identifiers', () {
    test('the Android applicationId is unchanged', () {
      final gradle = _read('android/app/build.gradle.kts');
      expect(RegExp(r'^\s*applicationId = "([^"]+)"', multiLine: true).firstMatch(gradle)?.group(1), _expectedBundleId);
    });

    test('the project has exactly the Runner and RunnerTests targets', () {
      final names = _list(_xcode.project['targets']).map((id) => _xcode._object(id)['name']).toList();
      expect(names, ['Runner', 'RunnerTests']);
    });

    for (final config in ['Debug', 'Release', 'Profile']) {
      test('Runner $config uses the Android applicationId and the real Info.plist', () {
        final settings = _xcode.settings(_xcode.target('Runner'))[config]!;
        expect(settings['PRODUCT_BUNDLE_IDENTIFIER'], _expectedBundleId);
        expect(settings['INFOPLIST_FILE'], 'Runner/Info.plist');
      });

      test('RunnerTests $config has its own ID', () {
        final settings = _xcode.settings(_xcode.target('RunnerTests'))[config]!;
        expect(settings['PRODUCT_BUNDLE_IDENTIFIER'], '$_expectedBundleId.RunnerTests');
      });
    }

    test('Info.plist takes its bundle ID from the build settings', () {
      expect(_info['CFBundleIdentifier'], r'$(PRODUCT_BUNDLE_IDENTIFIER)');
    });

    test('.metadata keeps android alongside ios', () {
      final platforms = RegExp(r'^\s*- platform: (\w+)', multiLine: true)
          .allMatches(_read('.metadata'))
          .map((m) => m.group(1))
          .toList();
      expect(platforms, ['root', 'android', 'ios']);
    });
  });

  group('auth redirect URL schemes', () {
    Set<String> iosSchemes() => {
          for (final type in _list(_info['CFBundleURLTypes']).map(_map))
            ..._list(type['CFBundleURLSchemes']).cast<String>(),
        };

    Iterable<XmlElement> androidDeepLinks() =>
        XmlDocument.parse(_read('android/app/src/main/AndroidManifest.xml')).findAllElements('data');

    test('registers exactly the two auth schemes', () {
      expect(iosSchemes(), {'budgettracker', 'io.supabase.budgettracker'});
    });

    test('every URL type has a name', () {
      final names = _list(_info['CFBundleURLTypes']).map(_map).map((type) => type['CFBundleURLName']).toList();
      expect(names, everyElement(startsWith('$_expectedBundleId.')));
      expect(names.toSet(), hasLength(names.length));
    });

    test('every scheme in the Android manifest is registered on iOS', () {
      final androidSchemes = androidDeepLinks().map((e) => e.getAttribute('android:scheme')).whereType<String>().toSet();
      expect(androidSchemes, isNotEmpty);
      expect(iosSchemes(), containsAll(androidSchemes));
    });

    test('the default password reset redirect uses a registered scheme and an Android host', () {
      // Read from source: the compiled constant changes with --dart-define.
      final match = RegExp(r"'AUTH_RESET_REDIRECT_URL',\s*defaultValue:\s*'([^']+)'")
          .firstMatch(_read('lib/supabase_config.dart'));
      final redirect = Uri.parse(match!.group(1)!);
      expect(iosSchemes(), contains(redirect.scheme));
      expect(androidDeepLinks().map((e) => e.getAttribute('android:host')), contains(redirect.host));
    });

    test('Flutter deep linking is off so the auth link reaches app_links only', () {
      // Left on, the link is also pushed as a named route. MaterialApp has only
      // `home` here, so a route carrying the auth code is an unknown route.
      expect(_info['FlutterDeepLinkingEnabled'], isFalse);
    });
  });

  group('Info.plist', () {
    test('the default display name is the English app name', () {
      expect(_info['CFBundleDisplayName'], 'Qawam Money');
      expect(_info['CFBundleName'], 'Qawam Money');
    });

    test('declares exactly the usage descriptions the plugins need', () {
      final declared = _info.keys.where((key) => key.endsWith('UsageDescription')).toSet();
      expect(declared, _usageKeys);
      for (final key in _usageKeys) {
        expect((_info[key]! as String).trim(), isNotEmpty, reason: key);
      }
    });

    test('declares the three app languages', () {
      expect(_list(_info['CFBundleLocalizations']), unorderedEquals(_localizedNames.keys));
    });

    test('share_plus: mixed localizations stay on', () {
      expect(_info['CFBundleAllowMixedLocalizations'], isTrue);
    });

    test('the scene configuration points at the real SceneDelegate', () {
      final manifest = _map(_info['UIApplicationSceneManifest']);
      final roles = _map(manifest['UISceneConfigurations']);
      final scene = _map(_list(roles['UIWindowSceneSessionRoleApplication']).single);
      expect(scene['UISceneDelegateClassName'], r'$(PRODUCT_MODULE_NAME).SceneDelegate');
      expect(scene['UISceneClassName'], 'UIWindowScene');
      expect(scene['UISceneStoryboardFile'], 'Main');

      final source = _stripSwiftComments(_read('ios/Runner/SceneDelegate.swift'));
      expect(source, matches(RegExp(r'class\s+SceneDelegate\s*:\s*FlutterSceneDelegate\b')));
      final compiled = _xcode.phaseFiles(_xcode.target('Runner'), 'PBXSourcesBuildPhase').map((f) => f['path']);
      expect(compiled, contains('SceneDelegate.swift'));
    });
  });

  group('InfoPlist.strings', () {
    for (final entry in _localizedNames.entries) {
      final lang = entry.key;

      test('$lang localizes the name and every permission', () {
        final table = _strings(lang);
        expect(table.keys.toSet(), {'CFBundleDisplayName', 'CFBundleName', ..._usageKeys});
        expect(table['CFBundleDisplayName'], entry.value);
        expect(table['CFBundleName'], entry.value);
        for (final key in _usageKeys) {
          expect(table[key]!.trim(), isNotEmpty, reason: key);
        }
      });

      test('$lang has no withdrawn names', () {
        final withdrawn = RegExp('wafeer|budget tracker', caseSensitive: false);
        expect(_strings(lang).values.where(withdrawn.hasMatch), isEmpty);
      });
    }

    test('English matches the Info.plist defaults', () {
      _strings('en').forEach((key, value) => expect(_info[key], value, reason: key));
    });

    test('Arabic and Urdu permission text is translated, not the English copy', () {
      final en = _strings('en');
      final arabicScript = RegExp(r'[؀-ۿ]');
      for (final lang in ['ar', 'ur']) {
        final table = _strings(lang);
        for (final key in _usageKeys) {
          expect(table[key], isNot(en[key]), reason: '$lang $key');
          expect(table[key], matches(arabicScript), reason: '$lang $key');
        }
      }
    });

    test('Urdu uses the Latin app name, with no Urdu-script form', () {
      final table = _strings('ur');
      for (final key in _usageKeys) {
        expect(table[key], contains('Qawam Money'), reason: key);
        expect(table[key], isNot(contains('قوام')), reason: key);
      }
    });

    Map<String, Object?> variantGroup(String targetName) =>
        _xcode.phaseFiles(_xcode.target(targetName), 'PBXResourcesBuildPhase').singleWhere(
              (file) => file['name'] == 'InfoPlist.strings',
              orElse: () => const {},
            );

    test('the Runner target ships all three languages from real files', () {
      final group = variantGroup('Runner');
      expect(group['isa'], 'PBXVariantGroup');
      final variants = _xcode.variants(group);
      expect(variants, {for (final lang in _localizedNames.keys) lang: '$lang.lproj/InfoPlist.strings'});
      for (final path in variants.values) {
        expect(File('ios/Runner/$path').existsSync(), isTrue, reason: path);
      }
      expect(_xcode.groupContains('Runner', 'InfoPlist.strings'), isTrue);
    });

    test('the RunnerTests target does not take the strings file', () {
      expect(variantGroup('RunnerTests'), isEmpty);
    });

    test('the project knows every language region', () {
      expect(_list(_xcode.project['knownRegions']), containsAll([..._localizedNames.keys, 'Base']));
      expect(_xcode.project['developmentRegion'], 'en');
    });
  });

  group('plugin setup', () {
    final podfile = _rubyLines(_read('ios/Podfile'));
    const macroFor = {'camera': 'CAMERA', 'microphone': 'MICROPHONE', 'notification': 'NOTIFICATIONS'};

    test('Runner builds for iOS 15.0 in every configuration, as the Podfile says', () {
      final project = _xcode.settings(_xcode.project);
      final runner = _xcode.settings(_xcode.target('Runner'));
      expect(runner.keys.toSet(), {'Debug', 'Release', 'Profile'});
      for (final config in runner.keys) {
        final effective = runner[config]!['IPHONEOS_DEPLOYMENT_TARGET'] ?? project[config]!['IPHONEOS_DEPLOYMENT_TARGET'];
        expect(effective, '15.0', reason: config);
      }
      expect(podfile, contains("platform :ios, '15.0'"));
    });

    test('the Podfile applies the macros to every pod target, unconditionally', () {
      // Pinned statement by statement: a `next`, `if` or `return` anywhere in
      // this block would silently leave the macros unset.
      expect(podfile.sublist(podfile.indexOf('post_install do |installer|')), [
        'post_install do |installer|',
        'installer.pods_project.targets.each do |target|',
        'flutter_additional_ios_build_settings(target)',
        'target.build_configurations.each do |config|',
        "config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= [",
        "'\$(inherited)',",
        "'PERMISSION_CAMERA=1',",
        "'PERMISSION_MICROPHONE=1',",
        "'PERMISSION_NOTIFICATIONS=1',",
        ']',
        'end',
        'end',
        'end',
      ]);
    });

    test('the Podfile enables exactly the permission groups lib/ uses', () {
      final enabled = podfile
          .expand((line) => RegExp(r"^'PERMISSION_(\w+)=1',?$").allMatches(line))
          .map((match) => match.group(1))
          .toSet();
      final used = _permissionGroupsUsed();
      expect(macroFor.keys, containsAll(used));
      expect(enabled, {for (final group in used) macroFor[group]});
    });

    test('AppDelegate sets the notification delegate before launch finishes', () {
      final source = _stripSwiftComments(_read('ios/Runner/AppDelegate.swift'));
      expect(_swiftBody(source, 'didFinishLaunchingWithOptions launchOptions'), [
        'UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate',
        'return super.application(application, didFinishLaunchingWithOptions: launchOptions)',
      ]);
    });

    test('AppDelegate registers plugins on the implicit engine', () {
      final source = _stripSwiftComments(_read('ios/Runner/AppDelegate.swift'));
      expect(source, contains('class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate'));
      expect(_swiftBody(source, 'func didInitializeImplicitFlutterEngine'), [
        'GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)',
      ]);
    });
  });
}
