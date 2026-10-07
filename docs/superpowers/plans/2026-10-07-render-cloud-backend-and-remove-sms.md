# Switch to Render Cloud Backend and Remove SMS Interception Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Point Flutter mobile application to the live Render cloud backend (`https://budget-tracker-ai-vwup.onrender.com`), and completely remove native and Dart Bank SMS interception features while preserving all other expense channels (AI chat, camera receipt scanning, ZATCA QR scanning, installments, sub-budgets, and offline sync) and historical transaction display.

**Architecture:** 
1. Update `supabase_config.dart` and `base_api_client.dart` with the live Render backend URL (`https://budget-tracker-ai-vwup.onrender.com`).
2. Purge SMS permissions, background services, and receivers from `AndroidManifest.xml` and delete native Kotlin SMS classes (`BootReceiver.kt`, `SmsBroadcastReceiver.kt`, `SmsListenerService.kt`, `SmsQueue.kt`) while simplifying `MainActivity.kt`.
3. Purge `SmsService` from Flutter lifecycle (`main.dart`, `dashboard_screen.dart`, `ingestion_settings_screen.dart`, `pubspec.yaml`), delete `sms_service.dart` and `sms_filter_test.dart`, and adapt offline queue tests.
4. Verify with Flutter test suite (all unit/widget tests passing) and Python pytest suite.
5. Build and install APK on Realme 8 physical device (`DUGIWSL74PWCJFHA`) and visually verify via screenshots.

**Tech Stack:** Flutter / Dart, Kotlin / Android SDK, FastAPI (Render Cloud), Supabase.

---

### Task 1: Update API Base URL Configuration

**Files:**
- Modify: `flutter_app/lib/supabase_config.dart`
- Modify: `flutter_app/lib/services/api/base_api_client.dart`
- Test: `flutter_app/test/services/base_api_client_test.dart`

- [ ] **Step 1: Update `supabase_config.dart` default URL to Render**
Update default values for `fastapiWebhookUrl` and add `fastapiBaseUrl` pointing to `https://budget-tracker-ai-vwup.onrender.com`.

- [ ] **Step 2: Update `base_api_client.dart` to use clean base URL logic**
Ensure `baseUrl` handles direct base URLs and paths ending in `/webhook/sms`.

- [ ] **Step 3: Run BaseApiClient unit tests**
Run: `flutter test test/services/base_api_client_test.dart`
Expected: PASS.

---

### Task 2: Remove SMS from Android Native Layer

**Files:**
- Modify: `flutter_app/android/app/src/main/AndroidManifest.xml`
- Modify: `flutter_app/android/app/src/main/kotlin/com/budgettracker/MainActivity.kt`
- Delete: `flutter_app/android/app/src/main/kotlin/com/budgettracker/SmsListenerService.kt`
- Delete: `flutter_app/android/app/src/main/kotlin/com/budgettracker/SmsBroadcastReceiver.kt`
- Delete: `flutter_app/android/app/src/main/kotlin/com/budgettracker/BootReceiver.kt`
- Delete: `flutter_app/android/app/src/main/kotlin/com/budgettracker/SmsQueue.kt`

- [ ] **Step 1: Clean `AndroidManifest.xml`**
Remove `RECEIVE_SMS`, `READ_SMS`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_DATA_SYNC`, `WAKE_LOCK`, `RECEIVE_BOOT_COMPLETED`.
Remove service `SmsListenerService`, receivers `SmsBroadcastReceiver` and `BootReceiver`.

- [ ] **Step 2: Clean `MainActivity.kt`**
Remove service intent calls, engine caching, and `SmsQueue` methods. Revert `MainActivity` to a clean `FlutterActivity`.

- [ ] **Step 3: Delete Kotlin SMS classes**
Remove the 4 obsolete Kotlin files.

---

### Task 3: Remove SMS from Flutter App Layer and UI

**Files:**
- Modify: `flutter_app/lib/main.dart`
- Modify: `flutter_app/lib/screens/home/dashboard_screen.dart`
- Modify: `flutter_app/lib/screens/settings/ingestion_settings_screen.dart`
- Modify: `flutter_app/pubspec.yaml`
- Delete: `flutter_app/lib/services/sms_service.dart`

- [ ] **Step 1: Remove `SmsService` from `main.dart`**
Remove import and `SmsService.instance.init()`.

- [ ] **Step 2: Remove `SmsService.instance.drainOfflineQueue()` from `dashboard_screen.dart`**
Ensure only `OfflineSyncService.instance.flushQueue()` is called.

- [ ] **Step 3: Clean `ingestion_settings_screen.dart`**
Remove `_smsEnabled`, `_smsStatus`, `_toggleSms`, `_requestSmsPermission`, `_onSmsListeningChanged`, SMS permission card, and SMS channel tile. Update descriptions.

- [ ] **Step 4: Delete `sms_service.dart` and update `pubspec.yaml` description**

---

### Task 4: Clean and Update Test Suite

**Files:**
- Delete: `flutter_app/test/sms_filter_test.dart`
- Modify: `flutter_app/test/services/sync_worker_test.dart`
- Modify: `flutter_app/test/services/offline_queue_manager_test.dart`

- [ ] **Step 1: Delete `sms_filter_test.dart`**
- [ ] **Step 2: Update queue and sync worker tests to use `'receipt'` instead of `'sms'`**
- [ ] **Step 3: Run full flutter test suite**
Run: `flutter test`
Expected: ALL test suites pass (32/32 suites).

---

### Task 5: Build, Deploy to Realme 8, and Live Device Verification

**Files:**
- Deploy to: `DUGIWSL74PWCJFHA` (Realme 8 / Android 13)

- [ ] **Step 1: Build debug APK**
Run: `flutter build apk --debug`
- [ ] **Step 2: Install APK via ADB**
Run: `& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" install -r build/app/outputs/flutter-apk/app-debug.apk`
- [ ] **Step 3: Launch app and capture screenshots on device**
Verify Settings screen shows camera and mic permissions only (no SMS permission card, no bank SMS channel).
Verify app is connected and live.

---

### Task 6: Git Commit & Push

- [ ] **Step 1: Git status and stage changes**
- [ ] **Step 2: Commit with conventional commit message**
- [ ] **Step 3: Push to GitHub origin main**
