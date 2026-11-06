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
        for (final ext in ['png', 'xml', 'webp'])
          if (File('${dir.path}/$name.$ext').existsSync()) File('${dir.path}/$name.$ext'),
  ];
}

/// The PNG of a mipmap layer at one density.
String _layerPng(String reference, String density) => '$_res/mipmap-$density/${reference.split('/').last}.png';

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

void main() {
  group('adaptive icon XML', () {
    test('ic_launcher in mipmap-anydpi-v26 is an adaptive icon with all three layers', () {
      final icon = _root(_adaptiveIcon);
      expect(icon.name.local, 'adaptive-icon');
      expect(_layers(icon).keys, unorderedEquals(['background', 'foreground', 'monochrome']));
    });

    test('every layer references a resource that exists', () {
      final layers = _layers(_root(_adaptiveIcon));
      expect(_resolve(layers['background']!), isNotEmpty, reason: layers['background']);
      for (final name in ['foreground', 'monochrome']) {
        final reference = layers[name]!;
        expect(reference, startsWith('@mipmap/'), reason: name);
        for (final density in _layerSizes.keys) {
          expect(File(_layerPng(reference, density)).existsSync(), isTrue, reason: '$name $density');
        }
      }
    });

    test("the background is the master's cream gradient across the visible 72 dp", () {
      final background = _resolve(_layers(_root(_adaptiveIcon))['background']!);
      expect(background, hasLength(1));
      final vector = XmlDocument.parse(background.single.readAsStringSync()).rootElement;
      expect(vector.name.local, 'vector');
      expect(vector.getAttribute('viewportWidth', namespaceUri: _android), '108');
      expect(vector.getAttribute('viewportHeight', namespaceUri: _android), '108');

      final gradients = vector.findAllElements('gradient').toList();
      expect(gradients, hasLength(1));
      String attr(String name) => gradients.single.getAttribute(name, namespaceUri: _android) ?? '';

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

    test('a reference to a missing resource resolves to nothing', () {
      expect(_resolve('@drawable/does_not_exist'), isEmpty);
      expect(_resolve('@mipmap/does_not_exist'), isEmpty);
      expect(_resolve('not a reference'), isEmpty);
    });
  });
}
