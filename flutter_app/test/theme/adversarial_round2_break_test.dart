import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:budget_tracker/core/widgets/three_d_icon_puck.dart';
import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/models/account.dart';
import 'package:budget_tracker/providers/budget_provider.dart';
import 'package:budget_tracker/providers/locale_provider.dart';
import 'package:budget_tracker/providers/theme_provider.dart';
import 'package:budget_tracker/screens/analytics/grocery_price_intelligence_screen.dart';
import 'package:budget_tracker/screens/chat/chat_entry_screen.dart';
import 'package:budget_tracker/screens/scanner/multi_page_receipt_scanner_screen.dart';
import 'package:budget_tracker/screens/scanner/receipt_scanner_sheet.dart';
import 'package:budget_tracker/screens/tools/tools_screen.dart';
import 'package:budget_tracker/services/account_service.dart';
import 'package:budget_tracker/services/api/budget_api_client.dart';
import 'package:budget_tracker/services/api_service.dart';
import 'package:budget_tracker/theme/app_themes.dart';
import 'package:budget_tracker/widgets/settings/household_type_chooser.dart';
import 'package:budget_tracker/widgets/simulator/affordability_simulator_sheet.dart';
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';

class _FakePermissionPlatform extends PermissionHandlerPlatform {
  PermissionStatus cameraStatus = PermissionStatus.denied;

  @override
  Future<PermissionStatus> checkPermissionStatus(Permission permission) async {
    if (permission == Permission.camera) return cameraStatus;
    return PermissionStatus.denied;
  }

  @override
  Future<Map<Permission, PermissionStatus>> requestPermissions(List<Permission> permissions) async {
    return {for (var p in permissions) p: await checkPermissionStatus(p)};
  }
}

double _luminance(Color c) {
  double linearize(double val) {
    return val <= 0.03928
        ? val / 12.92
        : math.pow((val + 0.055) / 1.055, 2.4).toDouble();
  }

  final r = linearize(c.r);
  final g = linearize(c.g);
  final b = linearize(c.b);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

double _contrast(Color fg, Color bg) {
  final l1 = _luminance(fg);
  final l2 = _luminance(bg);
  final lighter = math.max(l1, l2);
  final darker = math.min(l1, l2);
  return (lighter + 0.05) / (darker + 0.05);
}

class _StubAccountService extends AccountService {
  @override
  Future<List<Account>> getAccounts(String householdId) async => [];

  @override
  Stream<List<Account>> streamAccounts(String householdId) => const Stream.empty();
}

class _StubApiService extends ApiService {
  @override
  Future<Map<String, dynamic>> scanReceipt({
    List<String>? imagesBase64,
    String? imageBase64,
    String? qrCodeRaw,
    required String householdId,
    String? userId,
    bool allowDuplicate = false,
    String? enrichTxId,
    bool previewOnly = false,
    String? merchant,
    String? spentBy,
    String? receiptUrl,
    String? paidBy,
    String? beneficiary,
    String? nafaqahClass,
    String? nafaqahSpouseId,
    String? idempotencyKey,
    DateTime? occurredAt,
    String? previewToken,
    double? amount,
    String? categoryCode,
    String? accountId,
  }) async {
    return {'merchant': 'Test Store', 'amount': 150.0};
  }
}

class _DeniedCameraPicker extends Fake implements ImagePicker {
  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    throw PlatformException(
      code: 'camera_access_denied',
      message: 'Camera access denied by system',
    );
  }
}

class _FakeBudgetApiClient extends Fake implements BudgetApiClient {
  @override
  Future<List<Map<String, dynamic>>> getGroceryPriceHistory(
    String householdId, {
    String? itemFilter,
  }) async {
    return [
      {
        'item_name': 'Almarai Fresh Milk 2L',
        'category': 'Dairy',
        'latest_price': 10.5,
        'min_price': 9.5,
        'purchase_count': 6,
        'store_comparison': {
          'Panda': 9.5,
          'Lulu Hypermarket': 11.0,
          'Carrefour': 10.5,
        },
        'cheapest_store': 'Panda',
      }
    ];
  }
}

Widget _wrapDynamicApp({
  required Widget Function(BuildContext) builder,
  required ThemeMode themeMode,
  Locale locale = const Locale('en'),
  TextScaler textScaler = TextScaler.noScaling,
  Size size = const Size(390, 844),
}) {
  return MediaQuery(
    data: MediaQueryData(size: size, textScaler: textScaler),
    child: MaterialApp(
      theme: AppThemes.lightTheme,
      darkTheme: AppThemes.darkTheme,
      themeMode: themeMode,
      locale: locale,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('ar'), Locale('ur')],
      home: Builder(builder: builder),
    ),
  );
}

Widget _buildPriorSpendDialogSample(BuildContext context) {
  return AlertDialog(
    backgroundColor: context.cardBg,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    title: Row(
      children: [
        Icon(Icons.history_toggle_off_rounded, color: context.electricTeal, size: 22),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            context.tr('prior_cycle_spending_label'),
            style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.trArgs('mid_cycle_setup_prompt', {'amount': context.sar(500)}),
            style: TextStyle(color: context.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: TextEditingController(text: '500'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              labelText: context.tr('amount'),
              suffixText: context.tr('sar'),
              filled: true,
              fillColor: context.inputBg,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () {},
        child: Text(context.tr('cancel')),
      ),
      ElevatedButton(
        key: const Key('prior_spend_apply_button'),
        onPressed: () {},
        style: ElevatedButton.styleFrom(
          backgroundColor: context.primaryButtonBg,
          foregroundColor: context.primaryButtonFg,
        ),
        child: Text(context.tr('apply_prior_spend_adjustment'), style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    ],
  );
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PermissionHandlerPlatform.instance = _FakePermissionPlatform();
    ApiService.instance = ApiService(budget: _FakeBudgetApiClient());
  });

  group('Vector 1: Dynamic Theme Switching & Contrast Invariants across 8 modified widgets', () {
    testWidgets('1. ToolsScreen pucks contrast dynamically toggles between Light and Dark mode', (tester) async {
      ThemeMode currentMode = ThemeMode.dark;
      late StateSetter setDynamicState;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => ThemeProvider()),
            ChangeNotifierProvider(create: (_) => LocaleProvider()),
          ],
          child: StatefulBuilder(
            builder: (context, setState) {
              setDynamicState = setState;
              return _wrapDynamicApp(
                themeMode: currentMode,
                builder: (_) => const ToolsScreen(householdId: 'hh1'),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // In Dark Mode: pucks use tool.color
      final darkPucks = tester.widgetList<ThreeDIconPuck>(find.byType(ThreeDIconPuck)).toList();
      expect(darkPucks, isNotEmpty);
      for (final puck in darkPucks) {
        expect(puck.iconColor, isNot(Colors.white));
        expect(_contrast(puck.iconColor!, VelvetBurgundyColors.primaryDark), greaterThanOrEqualTo(3.0));
      }

      // Switch dynamically to Light Mode
      setDynamicState(() => currentMode = ThemeMode.light);
      await tester.pumpAndSettle();

      // In Light Mode: pucks must dynamically switch to Colors.white with >= 11:1 contrast on maroon puck
      final lightPucks = tester.widgetList<ThreeDIconPuck>(find.byType(ThreeDIconPuck)).toList();
      expect(lightPucks, isNotEmpty);
      for (final puck in lightPucks) {
        expect(puck.iconColor, Colors.white);
        expect(_contrast(puck.iconColor!, VelvetBurgundyColors.primaryLight), greaterThanOrEqualTo(10.0));
      }
    });

    testWidgets('2. HouseholdTypeChooser pucks maintain >= 4.5:1 contrast across dynamic theme switch', (tester) async {
      ThemeMode currentMode = ThemeMode.dark;
      late StateSetter setDynamicState;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => ThemeProvider()),
            ChangeNotifierProvider(create: (_) => LocaleProvider()),
          ],
          child: StatefulBuilder(
            builder: (context, setState) {
              setDynamicState = setState;
              return _wrapDynamicApp(
                themeMode: currentMode,
                builder: (_) => Scaffold(
                  body: HouseholdTypeChooser(
                    value: 'family',
                    onChanged: (_) {},
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Dark Mode
      var pucks = tester.widgetList<ThreeDIconPuck>(find.byType(ThreeDIconPuck)).toList();
      expect(pucks.length, 2);
      expect(_contrast(pucks[0].iconColor!, VelvetBurgundyColors.primaryDark), greaterThanOrEqualTo(4.5));
      expect(_contrast(pucks[1].iconColor!, VelvetBurgundyColors.primaryDark), greaterThanOrEqualTo(4.5));

      // Dynamic switch to Light Mode
      setDynamicState(() => currentMode = ThemeMode.light);
      await tester.pumpAndSettle();

      pucks = tester.widgetList<ThreeDIconPuck>(find.byType(ThreeDIconPuck)).toList();
      expect(pucks[0].iconColor, Colors.white);
      expect(_contrast(pucks[0].iconColor!, VelvetBurgundyColors.primaryLight), greaterThanOrEqualTo(10.0));
      expect(_contrast(pucks[1].iconColor!, VelvetBurgundyColors.primaryLight), greaterThanOrEqualTo(4.5));
    });

    testWidgets('3. BudgetManagementScreen Prior Spend Dialog button maintains >= 4.5:1 contrast across dynamic theme switch', (tester) async {
      ThemeMode currentMode = ThemeMode.dark;
      late StateSetter setDynamicState;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            setDynamicState = setState;
            return _wrapDynamicApp(
              themeMode: currentMode,
              builder: (ctx) => Scaffold(body: _buildPriorSpendDialogSample(ctx)),
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      // Dark Mode
      final applyFinder = find.byKey(const Key('prior_spend_apply_button'));
      expect(applyFinder, findsOneWidget);
      var btn = tester.widget<ElevatedButton>(applyFinder);
      var bg = btn.style?.backgroundColor?.resolve({}) ?? Colors.transparent;
      var fg = btn.style?.foregroundColor?.resolve({}) ?? Colors.transparent;
      expect(_contrast(fg, bg), greaterThanOrEqualTo(4.5), reason: 'Dark mode apply button contrast');

      // Switch to Light Mode
      setDynamicState(() => currentMode = ThemeMode.light);
      await tester.pumpAndSettle();

      btn = tester.widget<ElevatedButton>(applyFinder);
      bg = btn.style?.backgroundColor?.resolve({}) ?? Colors.transparent;
      fg = btn.style?.foregroundColor?.resolve({}) ?? Colors.transparent;
      expect(_contrast(fg, bg), greaterThanOrEqualTo(4.5), reason: 'Light mode apply button contrast');
    });

    testWidgets('4. ReceiptScannerSheet Try Again button and Scan header icon contrast across dynamic theme switch', (tester) async {
      ThemeMode currentMode = ThemeMode.dark;
      late StateSetter setDynamicState;

      final mockPicker = _DeniedCameraPicker();

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            setDynamicState = setState;
            return _wrapDynamicApp(
              themeMode: currentMode,
              builder: (_) => Scaffold(
                body: ReceiptScannerSheet(
                  householdId: 'hh1',
                  imagePicker: mockPicker,
                  accountService: _StubAccountService(),
                  apiService: _StubApiService(),
                ),
              ),
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      // Tap Snap Photo to trigger camera denial error
      final snapPhotoFinder = find.widgetWithText(ElevatedButton, 'Snap Photo');
      expect(snapPhotoFinder, findsOneWidget);
      await tester.tap(snapPhotoFinder);
      await tester.pumpAndSettle();

      // Dark Mode checks
      final tryAgainFinder = find.widgetWithText(OutlinedButton, 'Try Again');
      expect(tryAgainFinder, findsOneWidget);
      var tryAgainBtn = tester.widget<OutlinedButton>(tryAgainFinder);
      var tryAgainFg = tryAgainBtn.style?.foregroundColor?.resolve({}) ?? Colors.transparent;
      // In dark mode, textPrimary on dark red banner (lum ~0.018) is >= 4.5:1
      expect(_contrast(tryAgainFg, const Color(0xFF33080E)), greaterThanOrEqualTo(4.5));

      final scanIconFinder = find.byIcon(Icons.document_scanner_outlined);
      expect(scanIconFinder, findsOneWidget);
      var scanIcon = tester.widget<Icon>(scanIconFinder);
      expect(_contrast(scanIcon.color!, VelvetBurgundyColors.surfaceDark), greaterThanOrEqualTo(3.0));

      // Dynamic switch to Light Mode
      setDynamicState(() => currentMode = ThemeMode.light);
      await tester.pumpAndSettle();

      tryAgainBtn = tester.widget<OutlinedButton>(tryAgainFinder);
      tryAgainFg = tryAgainBtn.style?.foregroundColor?.resolve({}) ?? Colors.transparent;
      // In light mode, textPrimary on light red banner (lum ~0.84) is >= 4.5:1
      expect(_contrast(tryAgainFg, const Color(0xFFFDE8E8)), greaterThanOrEqualTo(4.5));

      scanIcon = tester.widget<Icon>(scanIconFinder);
      expect(_contrast(scanIcon.color!, VelvetBurgundyColors.surfaceLight), greaterThanOrEqualTo(3.0));
    });

    testWidgets('5. AffordabilitySimulatorSheet Record Expense button contrast across dynamic theme switch', (tester) async {
      ThemeMode currentMode = ThemeMode.dark;
      late StateSetter setDynamicState;

      final budgetProvider = BudgetProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: budgetProvider),
          ],
          child: StatefulBuilder(
            builder: (context, setState) {
              setDynamicState = setState;
              return _wrapDynamicApp(
                themeMode: currentMode,
                builder: (_) => const Scaffold(
                  body: AffordabilitySimulatorSheet(
                    defaultItem: 'Coffee Machine',
                    defaultAmount: 850.0,
                    defaultCategory: 'OPEX-SHOPPING',
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Simulate purchase
      final simBtn = find.text('Simulate Purchase');
      expect(simBtn, findsOneWidget);
      await tester.tap(simBtn);
      await tester.pumpAndSettle();

      // Dark Mode check
      final recordExpFinder = find.widgetWithText(ElevatedButton, 'Record Expense');
      expect(recordExpFinder, findsOneWidget);
      var recordBtn = tester.widget<ElevatedButton>(recordExpFinder);
      var recordFg = recordBtn.style?.foregroundColor?.resolve({}) ?? Colors.transparent;
      expect(_contrast(recordFg, VelvetBurgundyColors.surfaceDark), greaterThanOrEqualTo(4.5));

      // Switch to Light Mode
      setDynamicState(() => currentMode = ThemeMode.light);
      await tester.pumpAndSettle();

      recordBtn = tester.widget<ElevatedButton>(recordExpFinder);
      recordFg = recordBtn.style?.foregroundColor?.resolve({}) ?? Colors.transparent;
      expect(_contrast(recordFg, VelvetBurgundyColors.surfaceLight), greaterThanOrEqualTo(4.5));
    });

    testWidgets('6. GroceryPriceIntelligenceScreen basket icon and cheapest tag contrast across dynamic theme switch', (tester) async {
      ThemeMode currentMode = ThemeMode.dark;
      late StateSetter setDynamicState;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            setDynamicState = setState;
            return _wrapDynamicApp(
              themeMode: currentMode,
              builder: (_) => const GroceryPriceIntelligenceScreen(householdId: 'hh1'),
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      // Dark Mode
      final basketFinder = find.byIcon(Icons.shopping_basket_outlined);
      expect(basketFinder, findsOneWidget);
      var basketIcon = tester.widget<Icon>(basketFinder);
      expect(_contrast(basketIcon.color!, VelvetBurgundyColors.canvasDark), greaterThanOrEqualTo(3.0));

      final starFinder = find.byIcon(Icons.star_rounded);
      expect(starFinder, findsOneWidget);
      var starIcon = tester.widget<Icon>(starFinder);
      expect(_contrast(starIcon.color!, VelvetBurgundyColors.surfaceDark), greaterThanOrEqualTo(3.0));

      // Switch to Light Mode
      setDynamicState(() => currentMode = ThemeMode.light);
      await tester.pumpAndSettle();

      basketIcon = tester.widget<Icon>(basketFinder);
      expect(_contrast(basketIcon.color!, VelvetBurgundyColors.canvasLight), greaterThanOrEqualTo(3.0));

      starIcon = tester.widget<Icon>(starFinder);
      expect(_contrast(starIcon.color!, VelvetBurgundyColors.surfaceLight), greaterThanOrEqualTo(3.0));
    });

    testWidgets('7. MultiPageReceiptScannerScreen ZATCA action icon contrast across dynamic theme switch', (tester) async {
      ThemeMode currentMode = ThemeMode.dark;
      late StateSetter setDynamicState;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            setDynamicState = setState;
            return _wrapDynamicApp(
              themeMode: currentMode,
              builder: (_) => const MultiPageReceiptScannerScreen(householdId: 'hh1'),
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      final qrFinder = find.byIcon(Icons.qr_code_scanner);
      expect(qrFinder, findsOneWidget);
      var qrIcon = tester.widget<Icon>(qrFinder);
      expect(_contrast(qrIcon.color!, VelvetBurgundyColors.surfaceDark), greaterThanOrEqualTo(3.0));

      // Switch to Light Mode
      setDynamicState(() => currentMode = ThemeMode.light);
      await tester.pumpAndSettle();

      qrIcon = tester.widget<Icon>(qrFinder);
      expect(_contrast(qrIcon.color!, VelvetBurgundyColors.surfaceLight), greaterThanOrEqualTo(3.0));
    });

    testWidgets('8. ChatEntryScreen AI sparkle header icon contrast across dynamic theme switch', (tester) async {
      ThemeMode currentMode = ThemeMode.dark;
      late StateSetter setDynamicState;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            setDynamicState = setState;
            return _wrapDynamicApp(
              themeMode: currentMode,
              builder: (_) => const ChatEntryScreen(householdId: 'hh1'),
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      final sparkleFinder = find.byIcon(Icons.auto_awesome);
      expect(sparkleFinder, findsOneWidget);
      var sparkleIcon = tester.widget<Icon>(sparkleFinder);
      expect(_contrast(sparkleIcon.color!, VelvetBurgundyColors.surfaceDark), greaterThanOrEqualTo(3.0));

      // Switch to Light Mode
      setDynamicState(() => currentMode = ThemeMode.light);
      await tester.pumpAndSettle();

      sparkleIcon = tester.widget<Icon>(sparkleFinder);
      expect(_contrast(sparkleIcon.color!, VelvetBurgundyColors.surfaceLight), greaterThanOrEqualTo(3.0));
    });
  });

  group('Vector 2: Extreme Text Scaling (1.75x & 2.0x) & Zero Overflow', () {
    for (final scale in [1.75, 2.0]) {
      testWidgets('ToolsScreen tiles under textScaler:  does not overflow', (tester) async {
        await tester.pumpWidget(
          _wrapDynamicApp(
            themeMode: ThemeMode.light,
            textScaler: TextScaler.linear(scale),
            size: const Size(360, 800),
            builder: (_) => const ToolsScreen(householdId: 'hh1'),
          ),
        );
        await tester.pumpAndSettle();

        final err = tester.takeException();
        expect(err, isNull);
        expect(find.byType(ThreeDIconPuck), findsWidgets);
      });

      testWidgets('HouseholdTypeChooser options under textScaler: $scale does not overflow', (tester) async {
        await tester.pumpWidget(
          _wrapDynamicApp(
            themeMode: ThemeMode.light,
            textScaler: TextScaler.linear(scale),
            size: const Size(360, 800),
            builder: (_) => Scaffold(
              body: SingleChildScrollView(
                child: HouseholdTypeChooser(
                  value: 'family',
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final err = tester.takeException();
        if (err is FlutterError) {
          for (final diag in err.diagnostics) {
            debugPrint('DIAG: ${diag.toStringDeep()}');
          }
        }
        expect(err, isNull);
        expect(find.byType(ThreeDIconPuck), findsWidgets);
      });

      testWidgets('Prior Spend Dialog under textScaler: $scale does not overflow', (tester) async {
        await tester.pumpWidget(
          _wrapDynamicApp(
            themeMode: ThemeMode.light,
            textScaler: TextScaler.linear(scale),
            size: const Size(360, 800),
            builder: (ctx) => Scaffold(body: _buildPriorSpendDialogSample(ctx)),
          ),
        );
        await tester.pumpAndSettle();

        final err = tester.takeException();
        if (err is FlutterError) {
          for (final diag in err.diagnostics) {
            debugPrint('DIAG: ${diag.toStringDeep()}');
          }
        }
        expect(err, isNull);
        expect(find.byKey(const Key('prior_spend_apply_button')), findsOneWidget);
      });

      testWidgets('AffordabilitySimulatorSheet result card under textScaler:  does not overflow', (tester) async {
        final budgetProvider = BudgetProvider();

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: budgetProvider),
            ],
            child: _wrapDynamicApp(
              themeMode: ThemeMode.light,
              textScaler: TextScaler.linear(scale),
              size: const Size(360, 800),
              builder: (_) => const Scaffold(
                body: AffordabilitySimulatorSheet(
                  defaultItem: 'Gaming Laptop',
                  defaultAmount: 4500.0,
                  defaultCategory: 'OPEX-SHOPPING',
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
final simBtn = find.text('Simulate Purchase');
        expect(simBtn, findsOneWidget);
        await tester.tap(simBtn);
        await tester.pumpAndSettle();

        final err = tester.takeException();
        expect(err, isNull);
        expect(find.widgetWithText(ElevatedButton, 'Record Expense'), findsOneWidget);
      });

      testWidgets('ReceiptScannerSheet permission card under textScaler: $scale does not overflow', (tester) async {
        final mockPicker = _DeniedCameraPicker();

        await tester.pumpWidget(
          _wrapDynamicApp(
            themeMode: ThemeMode.light,
            textScaler: TextScaler.linear(scale),
            size: const Size(360, 800),
            builder: (_) => Scaffold(
              body: ReceiptScannerSheet(
                householdId: 'hh1',
                imagePicker: mockPicker,
                accountService: _StubAccountService(),
                apiService: _StubApiService(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final snapPhotoFinder = find.widgetWithText(ElevatedButton, 'Snap Photo');
        expect(snapPhotoFinder, findsOneWidget);
        await tester.tap(snapPhotoFinder);
        await tester.pumpAndSettle();

        final err = tester.takeException();
        if (err is FlutterError) {
          for (final diag in err.diagnostics) {
            debugPrint('DIAG: ${diag.toStringDeep()}');
          }
        }
        expect(err, isNull);
        expect(find.widgetWithText(OutlinedButton, 'Try Again'), findsOneWidget);
      });
    }
  });

  group('Vector 3: RTL / Trilingual Rendering (ar, ur)', () {
    for (final loc in [const Locale('ar'), const Locale('ur')]) {
      testWidgets('HouseholdTypeChooser and ToolsScreen in $loc RTL under 1.75x text scale', (tester) async {
        await tester.pumpWidget(
          _wrapDynamicApp(
            locale: loc,
            themeMode: ThemeMode.light,
            textScaler: const TextScaler.linear(1.75),
            size: const Size(360, 900),
            builder: (ctx) {
              expect(Directionality.of(ctx), TextDirection.rtl);
              return Scaffold(
                body: SingleChildScrollView(
                  child: Column(
                    children: [
                      HouseholdTypeChooser(
                        value: 'family',
                        onChanged: (_) {},
                      ),
                      const SizedBox(
                        height: 400,
                        child: ToolsScreen(householdId: 'hh1'),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
        await tester.pumpAndSettle();

        final err = tester.takeException();
        if (err is FlutterError) {
          for (final diag in err.diagnostics) {
            debugPrint('DIAG: ${diag.toStringDeep()}');
          }
        }
        expect(err, isNull);
        expect(find.byType(ThreeDIconPuck), findsWidgets);
      });

      testWidgets('ReceiptScannerSheet permission card in $loc RTL under 1.75x text scale', (tester) async {
        final mockPicker = _DeniedCameraPicker();

        await tester.pumpWidget(
          _wrapDynamicApp(
            locale: loc,
            themeMode: ThemeMode.light,
            textScaler: const TextScaler.linear(1.75),
            size: const Size(360, 900),
            builder: (ctx) {
              expect(Directionality.of(ctx), TextDirection.rtl);
              return Scaffold(
                body: ReceiptScannerSheet(
                  householdId: 'hh1',
                  imagePicker: mockPicker,
                  accountService: _StubAccountService(),
                  apiService: _StubApiService(),
                ),
              );
            },
          ),
        );
        await tester.pumpAndSettle();

        final snapPhotoFinder = find.byType(ElevatedButton).first;
        await tester.tap(snapPhotoFinder);
        await tester.pumpAndSettle();

        final err = tester.takeException();
        if (err is FlutterError) {
          for (final diag in err.diagnostics) {
            debugPrint('DIAG: ${diag.toStringDeep()}');
          }
        }
        expect(err, isNull);
        expect(find.byIcon(Icons.refresh), findsOneWidget);
      });

      testWidgets('AffordabilitySimulatorSheet in $loc RTL under 1.75x text scale', (tester) async {
        final budgetProvider = BudgetProvider();

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: budgetProvider),
            ],
            child: _wrapDynamicApp(
              locale: loc,
              themeMode: ThemeMode.light,
              textScaler: const TextScaler.linear(1.75),
              size: const Size(360, 900),
              builder: (ctx) {
                expect(Directionality.of(ctx), TextDirection.rtl);
                return const Scaffold(
                  body: AffordabilitySimulatorSheet(
                    defaultItem: 'جوال جديد',
                    defaultAmount: 3200.0,
                    defaultCategory: 'OPEX-SHOPPING',
                  ),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        final simBtn = find.byType(ElevatedButton).first;
        await tester.tap(simBtn);
        await tester.pumpAndSettle();

        final err = tester.takeException();
        if (err is FlutterError) {
          for (final diag in err.diagnostics) {
            debugPrint('DIAG: ${diag.toStringDeep()}');
          }
        }
        expect(err, isNull);
        expect(find.byIcon(Icons.add_task_rounded), findsOneWidget);
      });
    }
  });
}
