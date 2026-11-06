// The Android launcher icon is adaptive: minSdk is 26, so every supported
// device masks a 108 dp icon to its own shape. Only the central 66 dp circle is
// guaranteed to show, and a circular mask cuts at 72 dp. Legacy icons are
// shrunk onto a plate instead, which made the coin look small.
//
// The XML files are parsed, so a commented-out layer cannot satisfy these
// tests. The layer PNGs are decoded and checked pixel by pixel.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

const _res = 'android/app/src/main/res';
const _adaptiveIcon = '$_res/mipmap-anydpi-v26/ic_launcher.xml';
const _master = '../docs/brand/qawam_money_logo.svg';

/// 108 dp in pixels at each density.
const _layerSizes = {'mdpi': 108, 'hdpi': 162, 'xhdpi': 216, 'xxhdpi': 324, 'xxxhdpi': 432};

/// The legacy icons stay byte for byte: older launchers and stores still use them.
const _legacySha256 = {
  'mdpi': '50209f885de7c456e593f3b6565cda6c9c0f52c55128452cb2bd526e6e8b6d57',
  'hdpi': '301b7a6cac433ecba0a488a0c9f1f3d070f121a66ac92b8ddc0440a22e0d3ac7',
  'xhdpi': 'a4715a7c800c4e7d8ce0ad06327e53597c9e0b2ee95d443d9e10b09d0362b379',
  'xxhdpi': 'b7c18af6b30b5b30e49b84db16e0a83649606586c60493f88bc2c83b7d8ad9c5',
  'xxxhdpi': '3109729573fc14c3663a85bd49e24b25891f02a3d0e58256b8445ebe65bc7cc8',
};

const _android = 'http://schemas.android.com/apk/res/android';

/// Opaque enough to be part of the mark rather than its soft drop shadow.
const _opaque = 128;

/// Faint enough that a mask cutting through it would not show.
const _visible = 8;

XmlElement _root(String path) => XmlDocument.parse(File(path).readAsStringSync()).rootElement;

/// The `android:drawable` of each layer of an adaptive icon, by layer name.
Map<String, String> _layers(XmlElement icon) => {
      for (final layer in icon.childElements) layer.name.local: layer.getAttribute('drawable', namespaceUri: _android) ?? '',
    };

/// The files a `@type/name` reference resolves to, in any qualifier folder.
List<File> _resolve(String reference) {
  final match = RegExp(r'^@(drawable|mipmap|color)/(\w+)$').firstMatch(reference);
  if (match == null) return const [];
  final type = match.group(1)!, name = match.group(2)!;
  if (type == 'color') {
    return [
      for (final dir in Directory(_res).listSync().whereType<Directory>())
        if (RegExp(r'[\\/]values(-[\w-]+)?$').hasMatch(dir.path))
          for (final f in dir.listSync().whereType<File>())
            if (f.path.endsWith('.xml') && f.readAsStringSync().contains('<color name="$name">')) f,
    ];
  }
  return [
    for (final dir in Directory(_res).listSync().whereType<Directory>())
      if (RegExp('[\\\\/]$type(-[\\w-]+)?\$').hasMatch(dir.path))
        for (final f in dir.listSync().whereType<File>())
          if (_resourceName(f) == name) f,
  ];
}

/// A resource's name: its file name up to the first dot (`x.png`, `x.9.png`, `x.xml`, ...).
String _resourceName(File f) => f.uri.pathSegments.last.split('.').first;

/// `folder/file` under res, with forward slashes.
String _inRes(File f) => f.uri.pathSegments.reversed.take(2).toList().reversed.join('/');

/// Every file named [name] in any res folder, whatever its type, qualifiers or extension.
List<String> _filesNamed(String name) => [
      for (final dir in Directory(_res).listSync().whereType<Directory>())
        for (final f in dir.listSync().whereType<File>())
          if (_resourceName(f) == name) _inRes(f),
    ]..sort();

/// The PNG of a mipmap layer at every density, as `folder/file` under res.
List<String> _layerPngs(String name) => [for (final d in _layerSizes.keys) 'mipmap-$d/$name.png']..sort();

/// The corners of a single path built only from straight segments (M, L, H and V
/// in either case, then Z), or null for anything else: curves, arcs, subpaths.
List<(double, double)>? _polygon(String pathData) {
  final token = RegExp(r'[MmLlHhVvZz]|[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?');
  if (pathData.replaceAll(token, '').replaceAll(RegExp(r'[\s,]'), '').isNotEmpty) return null;
  final tokens = [for (final m in token.allMatches(pathData)) m.group(0)!];
  final points = <(double, double)>[];
  var (x, y) = (0.0, 0.0);
  String? command;
  var closed = false;
  for (var i = 0; i < tokens.length;) {
    if (closed) return null;
    if (RegExp('[A-Za-z]').hasMatch(tokens[i])) {
      command = tokens[i++];
      if (points.isEmpty && command != 'M' && command != 'm') return null;
      if (command == 'Z' || command == 'z') closed = true;
      if ((command == 'M' || command == 'm') && points.isNotEmpty) return null;
      continue;
    }
    /// The next number, or NaN where a command letter or the end comes first.
    double next() => i < tokens.length ? double.tryParse(tokens[i++]) ?? double.nan : double.nan;
    switch (command) {
      case 'M' || 'L':
        (x, y) = (next(), next());
      case 'm' || 'l':
        (x, y) = (x + next(), y + next());
      case 'H':
        x = next();
      case 'h':
        x += next();
      case 'V':
        y = next();
      case 'v':
        y += next();
      default:
        return null;
    }
    if (x.isNaN || y.isNaN) return null;
    points.add((x, y));
    // Further pairs after a move are lines.
    if (command == 'M') command = 'L';
    if (command == 'm') command = 'l';
  }
  return closed ? points : null;
}

/// Whether [points] trace the whole `0..size` square with straight horizontal
/// and vertical edges through all four corners.
bool _fillsSquare(List<(double, double)>? points, double size) {
  if (points == null || points.length < 4) return false;
  bool corner(double v) => v == 0 || v == size;
  if (!points.every((p) => corner(p.$1) && corner(p.$2))) return false;
  for (var i = 0; i < points.length; i++) {
    final (a, b) = (points[i], points[(i + 1) % points.length]);
    if (a.$1 != b.$1 && a.$2 != b.$2) return false;
  }
  return points.toSet().length == 4;
}

/// Decodes a PNG to straight RGBA. Must run inside `tester.runAsync`.
Future<(int, int, ByteData)> _decode(String path) async {
  final codec = await ui.instantiateImageCodec(File(path).readAsBytesSync());
  final image = (await codec.getNextFrame()).image;
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!;
  return (image.width, image.height, data);
}

int _alpha(ByteData data, int width, int x, int y) => data.getUint8((y * width + x) * 4 + 3);

/// The farthest pixel centre from the canvas centre with at least [minAlpha], in dp.
double _reachDp(int size, ByteData data, int minAlpha) {
  final c = size / 2;
  var far = 0.0;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      if (_alpha(data, size, x, y) < minAlpha) continue;
      final dx = x + .5 - c, dy = y + .5 - c;
      final d = dx * dx + dy * dy;
      if (d > far) far = d;
    }
  }
  return sqrt(far) * 108 / size;
}

/// Separate opaque shapes (4-connected), ignoring specks under 0.2% of the canvas.
int _shapes(int size, ByteData data) {
  final seen = Uint8List(size * size);
  var shapes = 0;
  for (var start = 0; start < size * size; start++) {
    if (seen[start] == 1 || _alpha(data, size, start % size, start ~/ size) < _opaque) continue;
    var area = 0;
    final stack = [start];
    seen[start] = 1;
    while (stack.isNotEmpty) {
      final p = stack.removeLast();
      area++;
      final x = p % size, y = p ~/ size;
      for (final (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]) {
        if (nx < 0 || ny < 0 || nx >= size || ny >= size) continue;
        final n = ny * size + nx;
        if (seen[n] == 1 || _alpha(data, size, nx, ny) < _opaque) continue;
        seen[n] = 1;
        stack.add(n);
      }
    }
    if (area >= size * size * .002) shapes++;
  }
  return shapes;
}

/// How the layers frame the master: the mark's enclosing circle, centred at
/// (521.6, 522.1) in the 1024 master, sits at the canvas centre, and the
/// 108 dp canvas spans 1335 master units (enclosing radius 389.4 at 31.5 dp).
const _frameCentre = (521.6, 522.1);
const _frameSide = 1335.0;

/// Points well inside each part of the mark, in master SVG coordinates.
const _coral = (778.0, 429.0); // pulled-out slice, upper right of the coin
const _rimLeft = (182.0, 530.0); // gold rim, left, between the face and the ticks
const _rimBottom = (500.0, 848.0); // gold rim, bottom
const _teal = (516.0, 717.0); // lower slice
const _indigo = (316.0, 491.0); // left slice
const _violet = (490.0, 342.0); // upper slice

/// Mean straight RGBA within 1.5 dp of a master point.
List<double> _sample(int size, ByteData data, (double, double) master) {
  final scale = size / _frameSide;
  final cx = (master.$1 - _frameCentre.$1) * scale + size / 2;
  final cy = (master.$2 - _frameCentre.$2) * scale + size / 2;
  final r = 1.5 * size / 108;
  final sum = [0.0, 0.0, 0.0, 0.0];
  var n = 0;
  for (var y = (cy - r).floor(); y <= (cy + r).ceil(); y++) {
    for (var x = (cx - r).floor(); x <= (cx + r).ceil(); x++) {
      final dx = x + .5 - cx, dy = y + .5 - cy;
      if (dx * dx + dy * dy > r * r) continue;
      for (var c = 0; c < 4; c++) {
        sum[c] += data.getUint8((y * size + x) * 4 + c);
      }
      n++;
    }
  }
  return [for (final s in sum) s / n];
}

// Colour classes, with wide margins around the values a resvg render gives at
// every density: coral (247,119,85), gold (236,188,82) and (213,149,36),
// teal (16,135,138), indigo (47,57,139), violet (165,134,245).
bool _isCoral(List<double> c) => c[0] >= 200 && c[1] >= 70 && c[1] <= 170 && c[2] <= 130 && c[0] - c[2] >= 100;
bool _isGold(List<double> c) => c[0] >= 180 && c[0] > c[1] && c[1] - c[2] >= 60 && c[2] <= 130;
bool _isTeal(List<double> c) => c[0] <= 100 && c[1] - c[0] >= 60 && c[2] - c[0] >= 60;
bool _isIndigo(List<double> c) => c[1] <= 110 && c[2] - c[0] >= 50 && c[2] - c[1] >= 50;
bool _isViolet(List<double> c) => c[0] >= 120 && c[2] >= 200 && c[2] - c[1] >= 60;

/// Opaque and not the cream face: the rim, ticks, slices and their outlines.
bool _colouredMark(ByteData data, int i) {
  final r = data.getUint8(i * 4), g = data.getUint8(i * 4 + 1), b = data.getUint8(i * 4 + 2);
  final cream = r > 230 && g > 220 && b > 190;
  return data.getUint8(i * 4 + 3) >= _opaque && !cream;
}

void main() {
  group('adaptive icon XML', () {
    test('ic_launcher in mipmap-anydpi-v26 is an adaptive icon with all three layers', () {
      final icon = _root(_adaptiveIcon);
      expect(icon.name.local, 'adaptive-icon');
      expect(_layers(icon).keys, unorderedEquals(['background', 'foreground', 'monochrome']));
    });

    test('every layer resolves to exactly the files these tests check', () {
      final layers = _layers(_root(_adaptiveIcon));
      expect(_resolve(layers['background']!).map(_inRes), ['drawable/ic_launcher_background.xml']);
      for (final name in ['foreground', 'monochrome']) {
        // A same-named file in any other folder (anydpi, night, a version or
        // density qualifier) or format (xml, webp, 9.png) could win on a device.
        expect(layers[name], '@mipmap/ic_launcher_$name', reason: name);
        expect(_resolve(layers[name]!).map(_inRes).toList()..sort(), _layerPngs('ic_launcher_$name'), reason: name);
      }
    });

    test('nothing anywhere in res shares a name with the icon or its layers', () {
      expect(_filesNamed('ic_launcher'), ['mipmap-anydpi-v26/ic_launcher.xml', ..._layerPngs('ic_launcher')]..sort());
      expect(_filesNamed('ic_launcher_background'), ['drawable/ic_launcher_background.xml']);
      for (final name in ['foreground', 'monochrome']) {
        expect(_filesNamed('ic_launcher_$name'), _layerPngs('ic_launcher_$name'), reason: name);
      }
    });

    test("the background is the master's cream gradient across the visible 72 dp", () {
      final background = _resolve(_layers(_root(_adaptiveIcon))['background']!);
      expect(background, hasLength(1));
      final vector = XmlDocument.parse(background.single.readAsStringSync()).rootElement;
      expect(vector.name.local, 'vector');
      expect(vector.getAttribute('viewportWidth', namespaceUri: _android), '108');
      expect(vector.getAttribute('viewportHeight', namespaceUri: _android), '108');
      expect(vector.getAttribute('alpha', namespaceUri: _android), isNull);

      // One path, untransformed and unclipped, painting the whole canvas.
      expect(vector.findAllElements('group'), isEmpty);
      expect(vector.findAllElements('clip-path'), isEmpty);
      final paths = vector.findAllElements('path').toList();
      expect(paths, hasLength(1));
      final path = paths.single;
      expect(_fillsSquare(_polygon(path.getAttribute('pathData', namespaceUri: _android) ?? ''), 108), isTrue,
          reason: path.getAttribute('pathData', namespaceUri: _android));
      for (final attr in ['fillAlpha', 'fillColor', 'strokeColor', 'trimPathEnd', 'trimPathStart']) {
        expect(path.getAttribute(attr, namespaceUri: _android), isNull, reason: attr);
      }

      // Its fill is the gradient, through an aapt:attr that aapt2 recognises.
      final gradients = vector.findAllElements('gradient').toList();
      expect(gradients, hasLength(1));
      final holder = gradients.single.parentElement!;
      expect((holder.name.local, holder.name.namespaceUri), ('attr', 'http://schemas.android.com/aapt'));
      expect(holder.getAttribute('name'), 'android:fillColor');
      expect(holder.parentElement, same(path));
      expect(gradients.single.childElements, isEmpty, reason: 'items would replace the start and end colours');
      String attr(String name) => gradients.single.getAttribute(name, namespaceUri: _android) ?? '';
      expect(attr('type'), 'linear');
      expect(attr('tileMode'), 'clamp');

      final master = File(_master).readAsStringSync();
      final stops = RegExp(r'<linearGradient id="bg"[^>]*>(.*?)</linearGradient>').firstMatch(master)!.group(1)!;
      final colours = [for (final m in RegExp(r'stop-color="(#[0-9A-Fa-f]{6})"').allMatches(stops)) m.group(1)!.toUpperCase()];
      expect(colours, ['#FDFBF6', '#EEE8DC']);
      expect([attr('startColor').toUpperCase(), attr('endColor').toUpperCase()], colours);
      // Top to bottom of the 72 dp the masks show, as the master runs over its tile.
      expect([attr('startX'), attr('startY'), attr('endX'), attr('endY')], ['54', '18', '54', '90']);
    });

    test('the manifest icon resolves to the adaptive icon, with no separate round icon', () {
      final manifest = _root('android/app/src/main/AndroidManifest.xml');
      final application = manifest.findElements('application').single;
      expect(application.getAttribute('icon', namespaceUri: _android), '@mipmap/ic_launcher');
      expect(application.getAttribute('roundIcon', namespaceUri: _android), isNull);
    });
  });

  group('layer art', () {
    testWidgets('foreground and monochrome are 108 dp at every density with a transparent edge', (tester) async {
      await tester.runAsync(() async {
        for (final layer in ['foreground', 'monochrome']) {
          for (final entry in _layerSizes.entries) {
            final (width, height, data) = await _decode('$_res/mipmap-${entry.key}/ic_launcher_$layer.png');
            final reason = '$layer ${entry.key}';
            expect((width, height), (entry.value, entry.value), reason: reason);
            final edge = [
              for (var i = 0; i < width; i++) ...[
                _alpha(data, width, i, 0),
                _alpha(data, width, i, height - 1),
                _alpha(data, width, 0, i),
                _alpha(data, width, width - 1, i),
              ],
            ];
            expect(edge.every((a) => a == 0), isTrue, reason: reason);
            // The coin's face; the monochrome centre is the gap where the slices meet.
            if (layer == 'foreground') expect(_alpha(data, width, width ~/ 2, height ~/ 2), 255, reason: reason);
          }
        }
      });
    });

    testWidgets('the mark fills the 66 dp safe zone without leaving it', (tester) async {
      await tester.runAsync(() async {
        for (final layer in ['foreground', 'monochrome']) {
          for (final entry in _layerSizes.entries) {
            final (size, _, data) = await _decode('$_res/mipmap-${entry.key}/ic_launcher_$layer.png');
            final reason = '$layer ${entry.key}';
            final reach = _reachDp(size, data, _opaque);
            // Rim and pulled-out slice inside the 33 dp radius, with a small margin.
            expect(reach, lessThanOrEqualTo(32.5), reason: reason);
            // Large, unlike the legacy icon on a plate.
            expect(reach, greaterThanOrEqualTo(30), reason: reason);
            // Even the faint shadow stays inside a circular mask's 36 dp radius.
            expect(_reachDp(size, data, _visible), lessThan(36), reason: reason);
          }
        }
      });
    });

    testWidgets('the monochrome layer is one colour', (tester) async {
      await tester.runAsync(() async {
        for (final density in _layerSizes.keys) {
          final (size, _, data) = await _decode('$_res/mipmap-$density/ic_launcher_monochrome.png');
          final colours = <int>{
            for (var i = 0; i < size * size; i++)
              if (data.getUint8(i * 4 + 3) > 0) data.getUint32(i * 4) | 0xFF,
          };
          expect(colours, {0xFFFFFFFF}, reason: density);
        }
      });
    });

    testWidgets('the monochrome rim, three slices and the pulled-out slice stay separate shapes', (tester) async {
      await tester.runAsync(() async {
        for (final density in _layerSizes.keys) {
          final (size, _, data) = await _decode('$_res/mipmap-$density/ic_launcher_monochrome.png');
          expect(_shapes(size, data), 5, reason: density);
        }
      });
    });

    testWidgets('the foreground shows each part of the mark in its colour and place', (tester) async {
      await tester.runAsync(() async {
        for (final density in _layerSizes.keys) {
          final (size, _, data) = await _decode('$_res/mipmap-$density/ic_launcher_foreground.png');
          final checks = {
            'coral slice upper right': (_coral, _isCoral),
            'gold rim left': (_rimLeft, _isGold),
            'gold rim bottom': (_rimBottom, _isGold),
            'teal slice below': (_teal, _isTeal),
            'indigo slice left': (_indigo, _isIndigo),
            'violet slice above': (_violet, _isViolet),
          };
          checks.forEach((part, check) {
            final (point, matches) = check;
            final colour = _sample(size, data, point);
            final reason = '$density $part: ${[for (final v in colour) v.round()]}';
            expect(colour[3], greaterThanOrEqualTo(250), reason: reason);
            expect(matches(colour), isTrue, reason: reason);
          });
        }
      });
    });

    testWidgets('the monochrome lies on the coloured parts of the foreground', (tester) async {
      await tester.runAsync(() async {
        for (final density in _layerSizes.keys) {
          final (size, _, mono) = await _decode('$_res/mipmap-$density/ic_launcher_monochrome.png');
          final (_, _, colour) = await _decode('$_res/mipmap-$density/ic_launcher_foreground.png');
          var inMono = 0, onMark = 0;
          for (var i = 0; i < size * size; i++) {
            if (mono.getUint8(i * 4 + 3) < _opaque) continue;
            inMono++;
            if (_colouredMark(colour, i)) onMark++;
          }
          // 1.000 at every density today; a turned or mirrored silhouette scores 0.83 to 0.90.
          expect(onMark / inMono, greaterThanOrEqualTo(.97), reason: density);
        }
      });
    });
  });

  group('legacy launcher icons', () {
    test('are unchanged', () {
      for (final entry in _legacySha256.entries) {
        final bytes = File('$_res/mipmap-${entry.key}/ic_launcher.png').readAsBytesSync();
        expect(sha256.convert(bytes).toString(), entry.value, reason: entry.key);
      }
    });

    test('have no round variant to keep in step', () {
      final files = [
        for (final dir in Directory(_res).listSync().whereType<Directory>())
          for (final f in dir.listSync().whereType<File>())
            if (f.uri.pathSegments.last.startsWith('ic_launcher_round')) f.path,
      ];
      expect(files, isEmpty);
    });
  });

  group('the parsers', () {
    test('a commented-out layer is not counted', () {
      final icon = XmlDocument.parse('''
<adaptive-icon xmlns:android="$_android">
  <background android:drawable="@drawable/ic_launcher_background" />
  <!-- <foreground android:drawable="@mipmap/ic_launcher_foreground" /> -->
</adaptive-icon>''').rootElement;
      expect(_layers(icon).keys, ['background']);
    });

    test('only a path through all four corners of the canvas fills it', () {
      for (final full in ['M0,0h108v108h-108z', 'M0 0 H108 V108 H0 Z', 'm0,0 l108,0 l0,108 l-108,0 z', 'M0,0L0,108L108,108L108,0Z']) {
        expect(_fillsSquare(_polygon(full), 108), isTrue, reason: full);
      }
      for (final partial in [
        'M0,0h54v54h-54z', // a quarter
        'M0,0h108v108h-108', // never closed
        'M0,0L108,108L108,0L0,108Z', // a bow tie
        'M0,0h108v108h-108zM0,0h1v1z', // a second subpath
        'M0,0h108v108c0,0 -108,0 -108,0z', // a curve
      ]) {
        expect(_fillsSquare(_polygon(partial), 108), isFalse, reason: partial);
      }
      expect(_polygon('h108v108h-108z'), isNull);
    });

    test('a reference to a missing resource resolves to nothing', () {
      expect(_resolve('@drawable/does_not_exist'), isEmpty);
      expect(_resolve('@mipmap/does_not_exist'), isEmpty);
      expect(_resolve('not a reference'), isEmpty);
    });
  });
}
