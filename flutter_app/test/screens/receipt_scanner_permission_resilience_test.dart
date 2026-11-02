import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';
import 'package:budget_tracker/screens/scanner/batch_receipt_scanner_screen.dart';
import 'package:budget_tracker/screens/scanner/receipt_scanner_sheet.dart';
import 'package:budget_tracker/services/account_service.dart';
import 'package:budget_tracker/services/api_service.dart';
import 'package:budget_tracker/models/account.dart';
import '../support/localized_app.dart';

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
    return {'merchant': 'Test Merchant', 'amount': 100.0};
  }
}

class _MockImagePicker extends Fake implements ImagePicker {
  final Future<XFile?> Function(ImageSource source)? onPickImage;
  int pickCallCount = 0;

  _MockImagePicker({this.onPickImage});

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    pickCallCount++;
    if (onPickImage != null) {
      return onPickImage!(source);
    }
    return null;
  }
}

void main() {
  late PermissionHandlerPlatform originalPlatform;
  late _FakePermissionPlatform fakePlatform;

  setUp(() {
    originalPlatform = PermissionHandlerPlatform.instance;
    fakePlatform = _FakePermissionPlatform();
    PermissionHandlerPlatform.instance = fakePlatform;
  });

  tearDown(() {
    PermissionHandlerPlatform.instance = originalPlatform;
  });

  group('ReceiptScannerSheet Permission Resilience', () {
    testWidgets(
        'proceeds to native camera capture even when permission_handler status reports denied',
        (tester) async {
      fakePlatform.cameraStatus = PermissionStatus.denied;

      final mockPicker = _MockImagePicker(
        onPickImage: (source) async => XFile('test_photo.jpg'),
      );

      await tester.pumpWidget(
        localizedApp(
          ReceiptScannerSheet(
            householdId: 'hh-100',
            imagePicker: mockPicker,
            accountService: _StubAccountService(),
            apiService: _StubApiService(),
          ),
          lang: 'en',
        ),
      );
      await tester.pumpAndSettle();

      // Find the camera button and tap it
      final cameraBtn = find.widgetWithText(ElevatedButton, 'Snap Photo');
      expect(cameraBtn, findsOneWidget);
      await tester.tap(cameraBtn);
      await tester.pumpAndSettle();

      // Native ImagePicker must have been invoked despite permission_handler reporting denied
      expect(mockPicker.pickCallCount, 1);
      // No error message displayed because native capture succeeded
      expect(find.text('Camera permission is needed to take receipt photos.'), findsNothing);
      expect(find.text('Camera access was denied by the system. Please grant Camera permission in Settings.'), findsNothing);
    });

    testWidgets(
        'shows system denial message and settings button when native picker throws camera_access_denied',
        (tester) async {
      fakePlatform.cameraStatus = PermissionStatus.denied;

      final mockPicker = _MockImagePicker(
        onPickImage: (source) async {
          throw PlatformException(
            code: 'camera_access_denied',
            message: 'Camera access denied by system',
          );
        },
      );

      await tester.pumpWidget(
        localizedApp(
          ReceiptScannerSheet(
            householdId: 'hh-100',
            imagePicker: mockPicker,
            accountService: _StubAccountService(),
            apiService: _StubApiService(),
          ),
          lang: 'en',
        ),
      );
      await tester.pumpAndSettle();

      final cameraBtn = find.widgetWithText(ElevatedButton, 'Snap Photo');
      await tester.tap(cameraBtn);
      await tester.pumpAndSettle();

      expect(mockPicker.pickCallCount, 1);
      // Expected system denied banner
      expect(
        find.text('Camera access was denied by the system. Please grant Camera permission in Settings.'),
        findsOneWidget,
      );
      expect(find.text('Open Settings'), findsOneWidget);
      expect(find.text('Try Again'), findsOneWidget);
    });
  });

  group('BatchReceiptScannerScreen Permission Resilience', () {
    testWidgets(
        'proceeds to native camera capture even when permission_handler status reports denied',
        (tester) async {
      fakePlatform.cameraStatus = PermissionStatus.denied;

      final mockPicker = _MockImagePicker(
        onPickImage: (source) async => XFile('test_photo_batch.jpg'),
      );

      await tester.pumpWidget(
        localizedApp(
          BatchReceiptScannerScreen(
            householdId: 'hh-100',
            imagePicker: mockPicker,
          ),
          lang: 'en',
          scaffold: false,
        ),
      );
      await tester.pumpAndSettle();

      // Shutter button
      final shutterBtn = find.byKey(const Key('batch_shutter_button'));
      expect(shutterBtn, findsOneWidget);
      await tester.tap(shutterBtn);
      await tester.pumpAndSettle();

      expect(mockPicker.pickCallCount, 1);
      // Photo successfully enqueued
      expect(find.byKey(const Key('queue_item_thumbnail_0')), findsOneWidget);
      expect(find.text('Camera access was denied by the system. Please grant Camera permission in Settings.'), findsNothing);
    });

    testWidgets(
        'shows error HUD with Open Settings button when native picker throws camera_access_denied',
        (tester) async {
      fakePlatform.cameraStatus = PermissionStatus.denied;

      final mockPicker = _MockImagePicker(
        onPickImage: (source) async {
          throw PlatformException(
            code: 'camera_access_denied',
            message: 'Camera access denied by system',
          );
        },
      );

      await tester.pumpWidget(
        localizedApp(
          BatchReceiptScannerScreen(
            householdId: 'hh-100',
            imagePicker: mockPicker,
          ),
          lang: 'en',
          scaffold: false,
        ),
      );
      await tester.pumpAndSettle();

      final shutterBtn = find.byKey(const Key('batch_shutter_button'));
      await tester.tap(shutterBtn);
      await tester.pumpAndSettle();

      expect(mockPicker.pickCallCount, 1);
      expect(
        find.text('Camera access was denied by the system. Please grant Camera permission in Settings.'),
        findsOneWidget,
      );
      expect(find.text('Open Settings'), findsOneWidget);
    });
  });
}
