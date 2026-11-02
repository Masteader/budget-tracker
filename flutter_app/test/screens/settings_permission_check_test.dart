import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:budget_tracker/providers/locale_provider.dart';
import 'package:budget_tracker/providers/theme_provider.dart';
import 'package:budget_tracker/screens/settings/settings_screen.dart';
import '../support/localized_app.dart';

class _FakeSettingsPermissionPlatform extends PermissionHandlerPlatform {
  PermissionStatus cameraStatus = PermissionStatus.denied;
  PermissionStatus microphoneStatus = PermissionStatus.denied;
  PermissionStatus notificationStatus = PermissionStatus.denied;

  bool throwOnNotification = false;
  bool throwOnCamera = false;
  bool throwOnMicrophone = false;

  PermissionStatus? requestCameraResult;
  PermissionStatus? requestMicrophoneResult;

  @override
  Future<PermissionStatus> checkPermissionStatus(Permission permission) async {
    if (permission == Permission.camera) {
      if (throwOnCamera) throw Exception('Simulated camera check failure');
      return cameraStatus;
    }
    if (permission == Permission.microphone) {
      if (throwOnMicrophone) throw Exception('Simulated microphone check failure');
      return microphoneStatus;
    }
    if (permission == Permission.notification) {
      if (throwOnNotification) throw Exception('Simulated notification check failure');
      return notificationStatus;
    }
    return PermissionStatus.denied;
  }

  @override
  Future<Map<Permission, PermissionStatus>> requestPermissions(List<Permission> permissions) async {
    final results = <Permission, PermissionStatus>{};
    for (final p in permissions) {
      if (p == Permission.camera && requestCameraResult != null) {
        results[p] = requestCameraResult!;
      } else if (p == Permission.microphone && requestMicrophoneResult != null) {
        results[p] = requestMicrophoneResult!;
      } else {
        results[p] = await checkPermissionStatus(p);
      }
    }
    return results;
  }
}

void main() {
  late PermissionHandlerPlatform originalPlatform;
  late _FakeSettingsPermissionPlatform fakePlatform;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    originalPlatform = PermissionHandlerPlatform.instance;
    fakePlatform = _FakeSettingsPermissionPlatform();
    PermissionHandlerPlatform.instance = fakePlatform;
  });

  tearDown(() {
    PermissionHandlerPlatform.instance = originalPlatform;
  });

  Widget createSettingsScreen() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
      ],
      child: localizedApp(const SettingsScreen(), lang: 'en', scaffold: false),
    );
  }

  group('SettingsScreen Permission Check & Resilience', () {
    testWidgets(
        'isolated try-catch ensures camera and microphone update to granted even when notification check throws',
        (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      fakePlatform.cameraStatus = PermissionStatus.granted;
      fakePlatform.microphoneStatus = PermissionStatus.granted;
      fakePlatform.throwOnNotification = true;

      await tester.pumpWidget(createSettingsScreen());
      await tester.pumpAndSettle();

      // Open Hardware & App Permissions section
      final permissionsHeader = find.text('HARDWARE & APP PERMISSIONS');
      await tester.scrollUntilVisible(permissionsHeader, 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(permissionsHeader);
      await tester.pumpAndSettle();

      // Camera and Microphone should both be GRANTED despite notification check failing
      expect(find.text('Camera Access'), findsOneWidget);
      expect(find.text('Microphone Access'), findsOneWidget);

      // We expect 2 "GRANTED" badges (for camera and microphone)
      expect(find.text('GRANTED'), findsNWidgets(2));
      // And 1 "NOT GRANTED" badge for notification
      expect(find.text('NOT GRANTED'), findsOneWidget);
    });

    testWidgets(
        'status.isLimited is treated as granted in row UI and enables camera test action',
        (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      fakePlatform.cameraStatus = PermissionStatus.limited;
      fakePlatform.microphoneStatus = PermissionStatus.limited;
      fakePlatform.notificationStatus = PermissionStatus.granted;

      await tester.pumpWidget(createSettingsScreen());
      await tester.pumpAndSettle();

      final permissionsHeader = find.text('HARDWARE & APP PERMISSIONS');
      await tester.scrollUntilVisible(permissionsHeader, 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(permissionsHeader);
      await tester.pumpAndSettle();

      // All 3 permissions show as GRANTED (limited is considered granted)
      expect(find.text('GRANTED'), findsNWidgets(3));
      // "Test Camera" button is enabled
      expect(find.text('Test Camera'), findsOneWidget);
    });

    testWidgets(
        '_requestCameraPermission shows dialog with Open Settings on regular denied status',
        (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      fakePlatform.cameraStatus = PermissionStatus.denied;
      fakePlatform.microphoneStatus = PermissionStatus.granted;
      fakePlatform.notificationStatus = PermissionStatus.granted;
      // Request returns denied
      fakePlatform.requestCameraResult = PermissionStatus.denied;

      await tester.pumpWidget(createSettingsScreen());
      await tester.pumpAndSettle();

      final permissionsHeader = find.text('HARDWARE & APP PERMISSIONS');
      await tester.scrollUntilVisible(permissionsHeader, 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(permissionsHeader);
      await tester.pumpAndSettle();

      // Find "Grant Access" button for camera
      final grantButton = find.widgetWithText(ElevatedButton, 'Grant Access');
      expect(grantButton, findsOneWidget);
      await tester.tap(grantButton);
      await tester.pumpAndSettle();

      // Dialog opens guiding user to Open Settings
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Open Settings'), findsOneWidget);
    });

    testWidgets(
        '_requestMicrophonePermission shows dialog with Open Settings on regular denied status',
        (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      fakePlatform.cameraStatus = PermissionStatus.granted;
      fakePlatform.microphoneStatus = PermissionStatus.denied;
      fakePlatform.notificationStatus = PermissionStatus.granted;
      fakePlatform.requestMicrophoneResult = PermissionStatus.denied;

      await tester.pumpWidget(createSettingsScreen());
      await tester.pumpAndSettle();

      final permissionsHeader = find.text('HARDWARE & APP PERMISSIONS');
      await tester.scrollUntilVisible(permissionsHeader, 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(permissionsHeader);
      await tester.pumpAndSettle();

      final grantButton = find.widgetWithText(ElevatedButton, 'Grant Access');
      expect(grantButton, findsOneWidget);
      await tester.tap(grantButton);
      await tester.pumpAndSettle();

      // Dialog opens guiding user to Open Settings
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Open Settings'), findsOneWidget);
    });
  });
}
