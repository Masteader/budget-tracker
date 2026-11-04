// The brand surfaces: logo on login and the dashboard header, titles fitting a
// narrow screen in every language and direction, native names, web brand
// strings, and bidi behaviour of the Latin name inside Urdu sentences.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/models/account.dart';
import 'package:budget_tracker/models/operating_cash.dart';
import 'package:budget_tracker/providers/account_provider.dart';
import 'package:budget_tracker/providers/budget_provider.dart';
import 'package:budget_tracker/providers/installment_provider.dart';
import 'package:budget_tracker/providers/recurring_bills_provider.dart';
import 'package:budget_tracker/providers/transaction_provider.dart';
import 'package:budget_tracker/screens/auth/login_screen.dart';
import 'package:budget_tracker/screens/home/dashboard_screen.dart';
import 'package:budget_tracker/services/account_service.dart';
import 'package:budget_tracker/services/commitments_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/localized_app.dart';

const _logoAsset = 'assets/images/brand_logo.png';
const _languages = ['en', 'ar', 'ur'];
const _directions = [TextDirection.rtl, TextDirection.ltr];
const _rlm = '‏';
const _latinName = 'Wafeer';
const _arabicName = 'وفيير';

ImageProvider _unwrap(ImageProvider provider) =>
    provider is ResizeImage ? _unwrap(provider.imageProvider) : provider;

final _logo = find.byWidgetPredicate((w) {
  if (w is! Image) return false;
  final provider = _unwrap(w.image);
  return provider is AssetImage && provider.assetName == _logoAsset;
});

String _value(String lang, String key) => AppLocalizations(Locale(lang)).get(key);

class _EmptyAccountService extends AccountService {
  @override
  Future<List<Account>> getAccounts(String householdId) async => [];

  @override
  Future<List<IncomeRecord>> getCycleIncome(String householdId, String cycleKey) async => [];

  @override
  Future<double> getHouseholdConfiguredIncome(String householdId) async => 0.0;

  @override
  Stream<List<Account>> streamAccounts(String householdId) => const Stream.empty();
}

class _EmptyCommitmentsService extends CommitmentsService {
  @override
  Future<List<PendingCommitment>> getPendingCommitments({
    required String householdId,
    required int paydayDay,
    required String cycleKey,
    DateTime? today,
  }) async => [];
}

Widget _directed(Widget child, TextDirection? direction) =>
    direction == null ? child : Directionality(textDirection: direction, child: child);

Widget _login(String lang, {TextDirection? direction}) =>
    localizedApp(_directed(const LoginScreen(), direction), lang: lang, scaffold: false);

Widget _dashboard(String lang, {TextDirection? direction}) {
  final service = _EmptyAccountService();
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AccountProvider>(
        create: (_) => AccountProvider(
          accounts: service,
          commitments: _EmptyCommitmentsService(),
          income: AccountServiceIncomeSource(service),
        ),
      ),
      ChangeNotifierProvider<TransactionProvider>(create: (_) => TransactionProvider()),
      ChangeNotifierProvider<RecurringBillsProvider>(create: (_) => RecurringBillsProvider()),
      ChangeNotifierProvider<BudgetProvider>(create: (_) => BudgetProvider()),
      ChangeNotifierProvider<InstallmentProvider>(create: (_) => InstallmentProvider()),
    ],
    child: localizedApp(
      _directed(
        BudgetDashboard(
          householdId: 'test-hid',
          fetchHouseholdIdOverride: () async => 'test-hid',
          budgetStreamOverride: (_) => Stream.value(const []),
        ),
        direction,
      ),
      lang: lang,
      scaffold: false,
    ),
  );
}

Future<void> _settleDashboard(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void _setView(WidgetTester tester, Size size, {double dpr = 1.0, double textScale = 1.0}) {
  tester.view.physicalSize = size * dpr;
  tester.view.devicePixelRatio = dpr;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

/// Words whose on-screen order differs from the logical order in an RTL
/// paragraph. The two-word Latin name is one unit: it reads left to right.
List<String> _misorderedWords(String line) {
  final painter = TextPainter(
    text: TextSpan(text: line, style: const TextStyle(fontSize: 14)),
    textDirection: TextDirection.rtl,
  )..layout(maxWidth: 100000);
  final words = RegExp('$_rlm?$_latinName|\\S+').allMatches(line).toList();
  final spans = [
    for (final m in words)
      () {
        final boxes = painter.getBoxesForSelection(TextSelection(baseOffset: m.start, extentOffset: m.end));
        final left = boxes.map((b) => b.left).reduce((a, b) => a < b ? a : b);
        final right = boxes.map((b) => b.right).reduce((a, b) => a > b ? a : b);
        return (left, right);
      }(),
  ];
  painter.dispose();
  final problems = <String>[];
  for (var i = 1; i < words.length; i++) {
    final (prevLeft, _) = spans[i - 1];
    final (_, right) = spans[i];
    if (right > prevLeft + 0.01) problems.add('${words[i - 1].group(0)} -> ${words[i].group(0)}');
  }
  return problems;
}

/// Decodes a PNG to straight RGBA. Must run inside `tester.runAsync`.
Future<(int, int, ByteData)> _decode(String path) async {
  final codec = await ui.instantiateImageCodec(File(path).readAsBytesSync());
  final image = (await codec.getNextFrame()).image;
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!;
  return (image.width, image.height, data);
}

/// Whether the first strong character decides an RTL paragraph, which is how
/// apps that receive shared text pick a direction.
bool _firstStrongIsRtl(String line) {
  final match = RegExp('[A-Za-z$_rlm؀-ۿ]').firstMatch(line);
  return match != null && !RegExp('[A-Za-z]').hasMatch(match.group(0)!);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('login brand mark', () {
    for (final lang in _languages) {
      testWidgets('shows the logo and app_title, not the wallet icon, in $lang', (tester) async {
        await tester.pumpWidget(_login(lang));
        await tester.pumpAndSettle();

        expect(_logo, findsOneWidget);
        expect(find.byIcon(Icons.account_balance_wallet_rounded), findsNothing);
        expect(tester.getSize(_logo), const Size(88, 88));
        expect(tester.widget<Image>(_logo).excludeFromSemantics, isTrue);
        expect(find.text(_value(lang, 'app_title')), findsOneWidget);
        // A boxed glow would show as a rectangle behind the transparent round mark.
        final boxedShadow = find.ancestor(
          of: _logo,
          matching: find.byWidgetPredicate((w) {
            if (w is! DecoratedBox) return false;
            final decoration = w.decoration;
            return decoration is BoxDecoration && (decoration.boxShadow?.isNotEmpty ?? false);
          }),
        );
        expect(boxedShadow, findsNothing);
      });

      for (final direction in _directions) {
        for (final scale in [1.0, 2.0, 3.0]) {
          testWidgets('title fits 320px, $lang, ${direction.name}, text scale $scale', (tester) async {
            _setView(tester, const Size(320, 640), textScale: scale);
            await tester.pumpWidget(_login(lang, direction: direction));
            await tester.pumpAndSettle();

            expect(tester.takeException(), isNull);
            final rect = tester.getRect(find.text(_value(lang, 'app_title')));
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(320));
          });
        }
      }
    }
  });

  group('dashboard brand mark', () {
    for (final lang in _languages) {
      testWidgets('shows the logo and app_title_short, not the shield, in $lang', (tester) async {
        _setView(tester, const Size(1080, 2400));
        await tester.pumpWidget(_dashboard(lang));
        await _settleDashboard(tester);

        expect(_logo, findsOneWidget);
        expect(find.byIcon(Icons.shield_rounded), findsNothing);
        expect(tester.getSize(_logo), const Size(26, 26));
        expect(find.text(_value(lang, 'app_title_short')), findsOneWidget);
        if (lang != 'ur') {
          // In Urdu both keys are the same Latin name.
          expect(find.text(_value(lang, 'app_title')), findsNothing);
        }
      });

      for (final direction in _directions) {
        for (final scale in [1.0, 1.5, 2.0, 3.0]) {
          testWidgets('header fits 320px, $lang, ${direction.name}, text scale $scale', (tester) async {
            _setView(tester, const Size(320, 700), textScale: scale);
            final errors = <String>[];
            final previous = FlutterError.onError;
            FlutterError.onError = (details) {
              final text = details.toString();
              // Only the brand row: other dashboard cards have their own suites.
              if (text.contains('overflowed') && text.contains('dashboard_screen.dart:')) errors.add(text);
            };
            addTearDown(() => FlutterError.onError = previous);

            await tester.pumpWidget(_dashboard(lang, direction: direction));
            await _settleDashboard(tester);
            FlutterError.onError = previous;

            expect(errors, isEmpty, reason: errors.join('\n'));
            final rect = tester.getRect(find.text(_value(lang, 'app_title_short')));
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(320));
          });
        }
      }
    }

    testWidgets('decodes the logo at display size for the device pixel ratio', (tester) async {
      _setView(tester, const Size(400, 800), dpr: 3.0);
      await tester.pumpWidget(_dashboard('ar'));
      await _settleDashboard(tester);

      final image = tester.widget<Image>(_logo);
      expect(image.excludeFromSemantics, isTrue);
      expect(image.image, isA<ResizeImage>());
      expect((image.image as ResizeImage).width, 78);
    });
  });

  group('brand art', () {
    const res = 'android/app/src/main/res';
    const densities = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192};

    int alpha(ByteData data, int width, int x, int y) => data.getUint8((y * width + x) * 4 + 3);

    testWidgets('launcher icons are the right size with rounded transparent corners', (tester) async {
      await tester.runAsync(() async {
        for (final entry in densities.entries) {
          final (width, height, data) = await _decode('$res/mipmap-${entry.key}/ic_launcher.png');
          expect((width, height), (entry.value, entry.value), reason: entry.key);
          expect(alpha(data, width, 0, 0), 0, reason: entry.key);
          expect(alpha(data, width, width ~/ 2, height ~/ 2), 255, reason: entry.key);
        }
      });
    });

    testWidgets('launcher icons have valid dimensions and opaque center', (tester) async {
      await tester.runAsync(() async {
        final (size, _, data) = await _decode('$res/mipmap-xxxhdpi/ic_launcher.png');
        expect(size, 192);
        expect(alpha(data, size, size ~/ 2, size ~/ 2), 255);
      });
    });

    testWidgets('in-app logo is the mark on a transparent background', (tester) async {
      await tester.runAsync(() async {
        final (width, height, data) = await _decode(_logoAsset);
        expect((width, height), (512, 512));
        for (final (x, y) in [(0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1)]) {
          expect(alpha(data, width, x, y), 0, reason: '$x,$y');
        }
        expect(alpha(data, width, width ~/ 2, height ~/ 2), 255);
      });
    });

    test('the master artwork is committed', () {
      // master artwork check
      final master = File('assets/images/wafeer_logo.png').existsSync();
      expect(master, isTrue);
      // verified master logo exists
    });

    test('the web favicon and logo are the mark, not the old teal calendar', () {
      for (final path in ['../web_app/public/favicon.svg', '../web_app/src/components/Header.tsx']) {
        final source = File(path).readAsStringSync();
        expect(source, contains('#F0553F'), reason: path);
        expect(source, isNot(contains('#006575')), reason: path);
      }
    });
  });

  group('native and shell names', () {
    const res = 'android/app/src/main/res';

    test('manifest references the string resource and identifiers are unchanged', () {
      final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(manifest, contains('android:label="@string/app_name"'));
      expect(File('android/app/build.gradle.kts').readAsStringSync(), contains('com.budgettracker'));
    });

    test('launcher name is English by default and Arabic on Arabic devices', () {
      expect(
        File('$res/values/strings.xml').readAsStringSync(),
        contains('<string name="app_name">Wafeer وفيير</string>'),
      );
      expect(
        File('$res/values-ar/strings.xml').readAsStringSync(),
        contains('<string name="app_name">وفيير Wafeer</string>'),
      );
      expect(
        File('$res/values-ur/strings.xml').readAsStringSync(),
        contains('<string name="app_name">وفيير Wafeer</string>'),
      );
    });

    test('MaterialApp title is generated from app_title_short', () {
      final mainSource = File('lib/main.dart').readAsStringSync();
      expect(mainSource, contains("onGenerateTitle: (context) => context.tr('app_title_short'),"));
      expect(mainSource, isNot(contains('Budget Tracker')));
    });

    test('logo asset is committed at the path the app loads', () {
      expect(File(_logoAsset).existsSync(), isTrue);
    });
  });

  group('web brand strings', () {
    final webFiles = [
      File('../web_app/index.html'),
      ...Directory('../web_app/src')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.ts') || f.path.endsWith('.tsx')),
    ];

    test('name and page titles are the approved values', () {
      final translations = File('../web_app/src/i18n/translations.ts').readAsStringSync();
      expect(translations, contains("name: 'وفيير Wafeer',"));
      expect(translations, contains("name: 'Wafeer وفيير',"));
      expect(translations, contains("pageTitle: 'وفيير Wafeer | "));
      expect(translations, contains("pageTitle: 'Wafeer وفيير | "));
      expect(translations, contains("shortName: 'وفيير',"));
      expect(translations, contains("shortName: 'Wafeer',"));
      final index = File('../web_app/index.html').readAsStringSync();
      expect(index, contains('<title>وفيير Wafeer | '));
      expect(index, contains('<meta property="og:site_name" content="وفيير Wafeer" />'));
      expect(index, contains('<meta property="og:title" content="وفيير Wafeer | '));
      expect(index, contains('<h1>وفيير Wafeer</h1>'));
    });

    test('no source file contains an old or withdrawn app name', () {
      final oldNames = RegExp('budget tracker|qawam money|(?<![؀-ۿ])قوام(?![؀-ۿ])', caseSensitive: false);
      expect(oldNames.hasMatch('qawam money'), isTrue);
      expect(oldNames.hasMatch('توفير'), isFalse);
      final offenders = [
        for (final f in webFiles)
          if (oldNames.hasMatch(f.readAsStringSync())) f.path,
      ];
      expect(offenders, isEmpty);
    });

    test('the Arabic old name survives only where it means "household budget"', () {
      final uses = [
        for (final f in webFiles)
          if (f.readAsStringSync().contains('ميزانية الأسرة')) f.path.replaceAll(r'\', '/').split('/').last,
      ];
      expect(uses, ['BudgetsView.tsx']);
    });
  });

  group('Latin name inside Urdu sentences', () {
    final ur = AppLocalizations(const Locale('ur'));
    const samples = {'household': 'Noor', 'code': 'ABCD1234', 'role': 'زوجہ'};
    const sharedKeys = {'invite_share_text': 2, 'invite_share_subject': 1, 'role_invite_share_text': 2};
    const inAppKeys = ['camera_permission_msg', 'support_chat_hint'];

    for (final key in [...sharedKeys.keys, ...inAppKeys]) {
      test('$key keeps logical word order in an RTL paragraph', () {
        final text = ur.format(key, samples);
        expect(text, contains(_arabicName));
        for (final line in text.split('\n')) {
          if (line.trim().isEmpty) continue;
          expect(_misorderedWords(line), isEmpty, reason: line);
        }
      });
    }

    sharedKeys.forEach((key, marks) {
      test('$key is formatted naturally in RTL', () {
        final text = ur.format(key, samples);
        for (final line in text.split('\n')) {
          expect(_firstStrongIsRtl(line), isTrue, reason: line);
        }
      });
    });

    test('the mark never touches the invite code or the household name', () {
      for (final key in sharedKeys.keys) {
        final raw = ur.get(key);
        for (final placeholder in ['{code}', '{household}']) {
          expect(raw, isNot(contains('$_rlm$placeholder')), reason: key);
          expect(raw, isNot(contains('$placeholder$_rlm')), reason: key);
        }
      }
      for (final key in ['invite_share_text', 'role_invite_share_text']) {
        final text = ur.format(key, samples);
        final at = text.indexOf('ABCD1234');
        expect(text[at - 1], ' ', reason: key);
        expect(text.substring(at), 'ABCD1234', reason: key);
      }
    });

    test('strings shown only inside the app carry no mark', () {
      for (final key in inAppKeys) {
        expect(ur.get(key), isNot(contains(_rlm)), reason: key);
      }
    });

    test('other languages carry no mark', () {
      for (final lang in ['en', 'ar']) {
        for (final key in sharedKeys.keys) {
          expect(_value(lang, key), isNot(contains(_rlm)), reason: '$lang:$key');
        }
      }
    });
  });
}
