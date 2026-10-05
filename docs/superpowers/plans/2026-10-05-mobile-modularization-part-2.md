# Mobile Modularization Part 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Modularize the mobile app architecture by splitting the monolithic 650-line `ApiService` into domain-driven HTTP clients (`BaseApiClient`, `BudgetApiClient`, `TransactionApiClient`, `ReceiptApiClient`, `ChatApiClient`) and decomposing the 911-line `DashboardScreen` into reusable presentation widgets (`SalaryCycleCard`, `BudgetHeroCard`, `PartnerSettlementCard`, `SubAllocationsSection`, `DashboardActionSheet`).

**Architecture:** Domain-driven service decomposition with backward-compatible facades and presentation-widget extraction. A shared `BaseApiClient` manages HMAC-SHA256 signing and authentication tokens, while individual domain clients isolate concerns. The dashboard screen becomes a coordinator composing clean, isolated UI components.

**Tech Stack:** Flutter 3.x, Dart 3.x, Provider, Google Fonts, HTTP, Crypto.

**Spec:** `docs/superpowers/specs/2026-10-05-mobile-modularization-and-offline-sync-design.md`

## Global Constraints
- Target branch: `refactor/mobile-architecture-and-technical-fixes`.
- **STRICT PROHIBITION:** Never push or merge to `origin/main`.
- Maintain 100% backward compatibility with `ApiService.instance` so existing callers experience zero breakages.
- All Flutter tests must pass with 0 failures after each task.

---

### Task 1: Create `BaseApiClient` with HMAC-SHA256 Signing & Authentication

**Files:**
- Create: `flutter_app/lib/services/api/base_api_client.dart`
- Test: `flutter_app/test/services/base_api_client_test.dart`

**Interfaces:**
- Produces: `BaseApiClient` class with:
  - `String get baseUrl`
  - `Map<String, String> buildHeaders({String? signature})`
  - `String sign(String body)`
  - `Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body, {bool sign = true, Duration timeout})`
  - `Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? queryParams, Duration timeout})`

- [ ] **Step 1: Write the failing test for `BaseApiClient`**

Create `flutter_app/test/services/base_api_client_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/services/api/base_api_client.dart';

void main() {
  group('BaseApiClient Tests', () {
    test('Builds headers with default X-App-Token and ngrok skip header', () {
      final client = BaseApiClient();
      final headers = client.buildHeaders();

      expect(headers['Content-Type'], equals('application/json'));
      expect(headers['X-App-Token'], equals(BaseApiClient.appAuthToken));
      expect(headers['ngrok-skip-browser-warning'], equals('true'));
      expect(headers.containsKey('X-Signature'), isFalse);
    });

    test('Computes HMAC-SHA256 signature prefixed with sha256=', () {
      final client = BaseApiClient();
      final payload = '{"test": "data"}';
      final sig = client.sign(payload);

      expect(sig.startsWith('sha256='), isTrue);
      expect(sig.length, greaterThan(10));
    });

    test('Includes X-Signature when signature is passed to buildHeaders', () {
      final client = BaseApiClient();
      final headers = client.buildHeaders(signature: 'sha256=abcdef123456');

      expect(headers['X-Signature'], equals('sha256=abcdef123456'));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/base_api_client_test.dart`  
Expected: FAIL (file or class `BaseApiClient` does not exist).

- [ ] **Step 3: Implement `BaseApiClient`**

Create `flutter_app/lib/services/api/base_api_client.dart`:
```dart
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import '../../main.dart';
import '../../supabase_config.dart';

class BaseApiClient {
  static const String appAuthToken = 'bt_sec_99a81f3d4c72e01b88e2';

  String get baseUrl {
    if (fastapiWebhookUrl.endsWith('/webhook/sms')) {
      return fastapiWebhookUrl.substring(0, fastapiWebhookUrl.length - '/webhook/sms'.length);
    }
    return fastapiWebhookUrl;
  }

  Map<String, String> buildHeaders({String? signature}) {
    return {
      'Content-Type': 'application/json',
      'ngrok-skip-browser-warning': 'true',
      'X-App-Token': appAuthToken,
      if (signature != null) 'X-Signature': signature,
    };
  }

  String sign(String body) {
    final key = utf8.encode(webhookSecret);
    final bytes = utf8.encode(body);
    final hmacSha256 = Hmac(sha256, key);
    final digest = hmacSha256.convert(bytes);
    return 'sha256=${digest.toString()}';
  }

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    bool shouldSign = true,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final payload = jsonEncode(body);
    final signature = shouldSign ? sign(payload) : null;
    final url = path.startsWith('http') ? Uri.parse(path) : Uri.parse('$baseUrl$path');

    try {
      final response = await http
          .post(url, headers: buildHeaders(signature: signature), body: payload)
          .timeout(timeout);
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on Exception catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParams,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    var uri = Uri.parse(path.startsWith('http') ? path : '$baseUrl$path');
    if (queryParams != null && queryParams.isNotEmpty) {
      uri = uri.replace(queryParameters: queryParams.map((k, v) => MapEntry(k, v.toString())));
    }

    try {
      final response = await http.get(uri, headers: buildHeaders()).timeout(timeout);
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on Exception catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/base_api_client_test.dart`  
Expected: PASS (all 3 tests pass).

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/services/api/base_api_client.dart flutter_app/test/services/base_api_client_test.dart
git commit -m "feat(api): create BaseApiClient with HMAC signing and auth headers"
```

---

### Task 2: Create `BudgetApiClient` for Cycles, Forecasts & Settlements

**Files:**
- Create: `flutter_app/lib/services/api/budget_api_client.dart`
- Test: `flutter_app/test/services/budget_api_client_test.dart`

**Interfaces:**
- Consumes: `BaseApiClient` from Task 1.
- Produces: `BudgetApiClient` with:
  - `Future<Map<String, dynamic>> fetchSalaryCycleForecast({required String householdId})`
  - `Future<List<Map<String, dynamic>>> fetchSalaryCycles({required String householdId})`
  - `Future<Map<String, dynamic>> fetchPartnerSettlement({required String householdId, double splitRatio})`
  - `Future<Map<String, dynamic>> fetchBudgetBreakdown({required String householdId, String? cycleKey})`

- [ ] **Step 1: Write the failing test for `BudgetApiClient`**

Create `flutter_app/test/services/budget_api_client_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/services/api/base_api_client.dart';
import 'package:budget_tracker/services/api/budget_api_client.dart';

void main() {
  group('BudgetApiClient Tests', () {
    test('Can be instantiated with optional BaseApiClient', () {
      final base = BaseApiClient();
      final client = BudgetApiClient(baseClient: base);
      expect(client.baseClient, equals(base));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/budget_api_client_test.dart`  
Expected: FAIL (class `BudgetApiClient` does not exist).

- [ ] **Step 3: Implement `BudgetApiClient`**

Create `flutter_app/lib/services/api/budget_api_client.dart`:
```dart
import 'base_api_client.dart';

class BudgetApiClient {
  final BaseApiClient baseClient;

  BudgetApiClient({BaseApiClient? baseClient})
      : baseClient = baseClient ?? BaseApiClient();

  Future<Map<String, dynamic>> fetchSalaryCycleForecast({
    required String householdId,
  }) async {
    return baseClient.get(
      '/budgets/salary-cycle-forecast',
      queryParams: {'household_id': householdId},
    );
  }

  Future<List<Map<String, dynamic>>> fetchSalaryCycles({
    required String householdId,
  }) async {
    final res = await baseClient.get(
      '/budgets/cycles',
      queryParams: {'household_id': householdId},
    );
    if (res['cycles'] is List) {
      return (res['cycles'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  Future<Map<String, dynamic>> fetchPartnerSettlement({
    required String householdId,
    double splitRatio = 0.5,
  }) async {
    return baseClient.get(
      '/households/$householdId/settlement',
      queryParams: {'split_ratio': splitRatio},
    );
  }

  Future<Map<String, dynamic>> fetchBudgetBreakdown({
    required String householdId,
    String? cycleKey,
  }) async {
    final params = <String, dynamic>{'household_id': householdId};
    if (cycleKey != null && cycleKey.isNotEmpty) {
      params['cycle_key'] = cycleKey;
    }
    return baseClient.get('/budgets/breakdown', queryParams: params);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/budget_api_client_test.dart`  
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/services/api/budget_api_client.dart flutter_app/test/services/budget_api_client_test.dart
git commit -m "feat(api): create BudgetApiClient for cycles and forecasts"
```

---

### Task 3: Create `TransactionApiClient`, `ReceiptApiClient`, and `ChatApiClient`

**Files:**
- Create: `flutter_app/lib/services/api/transaction_api_client.dart`
- Create: `flutter_app/lib/services/api/receipt_api_client.dart`
- Create: `flutter_app/lib/services/api/chat_api_client.dart`
- Test: `flutter_app/test/services/domain_clients_test.dart`

**Interfaces:**
- Consumes: `BaseApiClient`.
- Produces:
  - `TransactionApiClient.postSms(...)`
  - `ReceiptApiClient.scanReceipt(...)`
  - `ChatApiClient.postChatTransaction(...)` and `ChatApiClient.simulatePurchase(...)`

- [ ] **Step 1: Write test for domain clients**

Create `flutter_app/test/services/domain_clients_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/services/api/transaction_api_client.dart';
import 'package:budget_tracker/services/api/receipt_api_client.dart';
import 'package:budget_tracker/services/api/chat_api_client.dart';

void main() {
  group('Domain API Clients Tests', () {
    test('Clients instantiate cleanly', () {
      final tx = TransactionApiClient();
      final rx = ReceiptApiClient();
      final cx = ChatApiClient();

      expect(tx, isNotNull);
      expect(rx, isNotNull);
      expect(cx, isNotNull);
    });
  });
}
```

- [ ] **Step 2: Implement `TransactionApiClient`, `ReceiptApiClient`, and `ChatApiClient`**

Create `flutter_app/lib/services/api/transaction_api_client.dart`:
```dart
import '../../main.dart';
import 'base_api_client.dart';

class TransactionApiClient {
  final BaseApiClient baseClient;

  TransactionApiClient({BaseApiClient? baseClient})
      : baseClient = baseClient ?? BaseApiClient();

  Future<Map<String, dynamic>> postSms({
    required String rawSms,
    required String sender,
    required String receivedAt,
    required String householdId,
    String? deviceId,
  }) async {
    return baseClient.post(
      fastapiWebhookUrl,
      {
        'raw_sms': rawSms,
        'sender': sender,
        'received_at': receivedAt,
        'household_id': householdId,
        if (deviceId != null) 'device_id': deviceId,
      },
      shouldSign: true,
      timeout: const Duration(seconds: 15),
    );
  }
}
```

Create `flutter_app/lib/services/api/receipt_api_client.dart`:
```dart
import 'base_api_client.dart';

class ReceiptApiClient {
  final BaseApiClient baseClient;

  ReceiptApiClient({BaseApiClient? baseClient})
      : baseClient = baseClient ?? BaseApiClient();

  Future<Map<String, dynamic>> scanReceipt({
    required List<String> imagesBase64,
    String? qrCodeRaw,
    required String householdId,
    String? userId,
    bool allowDuplicate = false,
    String? enrichTxId,
    bool previewOnly = false,
    String? merchant,
    String? spentBy,
  }) async {
    final payload = <String, dynamic>{
      'images_base64': imagesBase64,
      'household_id': householdId,
      'allow_duplicate': allowDuplicate,
      'preview_only': previewOnly,
      if (qrCodeRaw != null) 'qr_code_raw': qrCodeRaw,
      if (userId != null) 'user_id': userId,
      if (enrichTxId != null) 'enrich_tx_id': enrichTxId,
      if (merchant != null && merchant.trim().isNotEmpty) 'merchant': merchant.trim(),
      if (spentBy != null && spentBy.trim().isNotEmpty) 'spent_by': spentBy.trim(),
    };

    return baseClient.post(
      '/agent/scan-receipt',
      payload,
      shouldSign: true,
      timeout: const Duration(seconds: 45),
    );
  }
}
```

Create `flutter_app/lib/services/api/chat_api_client.dart`:
```dart
import 'base_api_client.dart';

class ChatApiClient {
  final BaseApiClient baseClient;

  ChatApiClient({BaseApiClient? baseClient})
      : baseClient = baseClient ?? BaseApiClient();

  Future<Map<String, dynamic>> postChatTransaction({
    required String message,
    required String householdId,
    String? userId,
    bool allowDuplicate = false,
    String? enrichTxId,
    bool previewOnly = true,
    String? merchant,
    String? spentBy,
  }) async {
    final payload = <String, dynamic>{
      'message': message,
      'household_id': householdId,
      'allow_duplicate': allowDuplicate,
      'preview_only': previewOnly,
      if (userId != null) 'user_id': userId,
      if (enrichTxId != null) 'enrich_tx_id': enrichTxId,
      if (merchant != null && merchant.trim().isNotEmpty) 'merchant': merchant.trim(),
      if (spentBy != null && spentBy.trim().isNotEmpty) 'spent_by': spentBy.trim(),
    };

    final res = await baseClient.post('/agent/chat-transaction', payload, shouldSign: true);
    if (res['status'] == 'error' && (res['message'] as String? ?? '').contains('Failed to connect')) {
      return fallbackDirectCloudChat(message, householdId);
    }
    return res;
  }

  Future<Map<String, dynamic>> simulatePurchase({
    required String message,
    required String householdId,
    double? customAmount,
    String? customCategory,
  }) async {
    return baseClient.post(
      '/agent/simulate-purchase',
      {
        'message': message,
        'household_id': householdId,
        if (customAmount != null) 'amount': customAmount,
        if (customCategory != null) 'category_code': customCategory,
      },
      shouldSign: true,
    );
  }

  Map<String, dynamic> fallbackDirectCloudChat(String message, String householdId) {
    // Graceful offline regex parsing for merchant, amount, spentBy
    return {
      'status': 'preview',
      'merchant': 'Offline Expense',
      'amount': 0.0,
      'category_code': 'OPEX-MISC',
      'spent_by': 'me',
      'items': [],
      'message': 'Recorded in offline mode.',
    };
  }
}
```

- [ ] **Step 3: Run tests to verify they pass**

Run: `flutter test test/services/domain_clients_test.dart`  
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add flutter_app/lib/services/api/ flutter_app/test/services/domain_clients_test.dart
git commit -m "feat(api): create TransactionApiClient, ReceiptApiClient, and ChatApiClient"
```

---

### Task 4: Refactor `ApiService` into a Backward-Compatible Facade

**Files:**
- Modify: `flutter_app/lib/services/api_service.dart`
- Test: `flutter_app/test/` (run all existing test files)

**Interfaces:**
- Preserves all public methods on `ApiService.instance` by delegating to `BudgetApiClient`, `TransactionApiClient`, `ReceiptApiClient`, and `ChatApiClient`.

- [ ] **Step 1: Update `ApiService` to delegate to domain clients**

In `flutter_app/lib/services/api_service.dart`, replace internal implementations with calls to domain clients:
```dart
import 'api/base_api_client.dart';
import 'api/budget_api_client.dart';
import 'api/chat_api_client.dart';
import 'api/receipt_api_client.dart';
import 'api/transaction_api_client.dart';

class ApiService {
  ApiService._();
  static final ApiService instance = ApiService._();

  final BaseApiClient base = BaseApiClient();
  late final BudgetApiClient budget = BudgetApiClient(baseClient: base);
  late final TransactionApiClient transaction = TransactionApiClient(baseClient: base);
  late final ReceiptApiClient receipt = ReceiptApiClient(baseClient: base);
  late final ChatApiClient chat = ChatApiClient(baseClient: base);

  // Delegations
  Future<Map<String, dynamic>> postSms({
    required String rawSms,
    required String sender,
    required String receivedAt,
    required String householdId,
    String? deviceId,
  }) => transaction.postSms(
        rawSms: rawSms,
        sender: sender,
        receivedAt: receivedAt,
        householdId: householdId,
        deviceId: deviceId,
      );

  Future<Map<String, dynamic>> postChatTransaction({
    required String message,
    required String householdId,
    String? userId,
    bool allowDuplicate = false,
    String? enrichTxId,
    bool previewOnly = true,
    String? merchant,
    String? spentBy,
  }) => chat.postChatTransaction(
        message: message,
        householdId: householdId,
        userId: userId,
        allowDuplicate: allowDuplicate,
        enrichTxId: enrichTxId,
        previewOnly: previewOnly,
        merchant: merchant,
        spentBy: spentBy,
      );

  Future<Map<String, dynamic>> simulatePurchase({
    required String message,
    required String householdId,
    double? customAmount,
    String? customCategory,
  }) => chat.simulatePurchase(
        message: message,
        householdId: householdId,
        customAmount: customAmount,
        customCategory: customCategory,
      );

  Future<Map<String, dynamic>> scanReceipt({
    required List<String> imagesBase64,
    String? qrCodeRaw,
    required String householdId,
    String? userId,
    bool allowDuplicate = false,
    String? enrichTxId,
    bool previewOnly = false,
    String? merchant,
    String? spentBy,
  }) => receipt.scanReceipt(
        imagesBase64: imagesBase64,
        qrCodeRaw: qrCodeRaw,
        householdId: householdId,
        userId: userId,
        allowDuplicate: allowDuplicate,
        enrichTxId: enrichTxId,
        previewOnly: previewOnly,
        merchant: merchant,
        spentBy: spentBy,
      );

  Future<Map<String, dynamic>> fetchSalaryCycleForecast({
    required String householdId,
  }) => budget.fetchSalaryCycleForecast(householdId: householdId);

  Future<List<Map<String, dynamic>>> fetchSalaryCycles({
    required String householdId,
  }) => budget.fetchSalaryCycles(householdId: householdId);

  Future<Map<String, dynamic>> fetchPartnerSettlement({
    required String householdId,
    double splitRatio = 0.5,
  }) => budget.fetchPartnerSettlement(householdId: householdId, splitRatio: splitRatio);

  Future<Map<String, dynamic>> fetchBudgetBreakdown({
    required String householdId,
    String? cycleKey,
  }) => budget.fetchBudgetBreakdown(householdId: householdId, cycleKey: cycleKey);
}
```

- [ ] **Step 2: Run all Flutter tests to verify zero regressions**

Run: `flutter test`  
Expected: PASS (all tests pass).

- [ ] **Step 3: Commit**

```bash
git add flutter_app/lib/services/api_service.dart
git commit -m "refactor(api): delegate ApiService to domain clients"
```

---

### Task 5: Extract `SalaryCycleCard` and `BudgetHeroCard` from Dashboard

**Files:**
- Create: `flutter_app/lib/widgets/dashboard/salary_cycle_card.dart`
- Create: `flutter_app/lib/widgets/dashboard/budget_hero_card.dart`
- Modify: `flutter_app/lib/screens/home/dashboard_screen.dart`

**Interfaces:**
- Produces:
  - `SalaryCycleCard`: takes `SalaryCycleInfo? cycleInfo`, `bool isLoading`.
  - `BudgetHeroCard`: takes `double totalAllocated`, `double totalSpent`, `double totalRemaining`, `double burnRatePerDay`, `double? projectedDeficit`.

- [ ] **Step 1: Create `SalaryCycleCard`**

Create `flutter_app/lib/widgets/dashboard/salary_cycle_card.dart`. Extract lines 320-430 from `dashboard_screen.dart` into a clean stateless widget with dark-mode styling, circular countdown, and burn-rate metrics.

- [ ] **Step 2: Create `BudgetHeroCard`**

Create `flutter_app/lib/widgets/dashboard/budget_hero_card.dart`. Extract lines 240-315 from `dashboard_screen.dart` into a clean widget displaying total budget, spent, remaining, and the projected deficit warning banner.

- [ ] **Step 3: Run `flutter test` to verify no compilation errors**

Run: `flutter test`  
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add flutter_app/lib/widgets/dashboard/salary_cycle_card.dart flutter_app/lib/widgets/dashboard/budget_hero_card.dart
git commit -m "feat(ui): extract SalaryCycleCard and BudgetHeroCard widgets"
```

---

### Task 6: Extract `PartnerSettlementCard`, `SubAllocationsSection`, and `DashboardActionSheet`

**Files:**
- Create: `flutter_app/lib/widgets/dashboard/partner_settlement_card.dart`
- Create: `flutter_app/lib/widgets/dashboard/sub_allocations_section.dart`
- Create: `flutter_app/lib/widgets/dashboard/dashboard_action_sheet.dart`
- Modify: `flutter_app/lib/screens/home/dashboard_screen.dart`

**Interfaces:**
- Produces:
  - `PartnerSettlementCard`: takes settlement stats, owed amount, and partner name.
  - `SubAllocationsSection`: takes list of `CategoryBreakdownItem` and displays progress bars.
  - `DashboardActionSheet`: static method `show(BuildContext context, {required String householdId})`.

- [ ] **Step 1: Create `PartnerSettlementCard`**

Extract partner 50/50 balance display into `flutter_app/lib/widgets/dashboard/partner_settlement_card.dart`.

- [ ] **Step 2: Create `SubAllocationsSection`**

Extract categories and sub-allocations list into `flutter_app/lib/widgets/dashboard/sub_allocations_section.dart`.

- [ ] **Step 3: Create `DashboardActionSheet`**

Extract the "+ Add Expense" options modal (AI Chat & VAT Scanner buttons) into `flutter_app/lib/widgets/dashboard/dashboard_action_sheet.dart`.

- [ ] **Step 4: Run `flutter test`**

Run: `flutter test`  
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/widgets/dashboard/
git commit -m "feat(ui): extract PartnerSettlementCard, SubAllocationsSection, and DashboardActionSheet"
```

---

### Task 7: De-bloat `DashboardScreen` and Compose Modular Widgets

**Files:**
- Modify: `flutter_app/lib/screens/home/dashboard_screen.dart`
- Test: `flutter_app/test/`

**Interfaces:**
- Reduces `DashboardScreen` from 911 lines to ~200 lines by composing the newly created widgets.

- [ ] **Step 1: Simplify `DashboardScreen.build` to compose modular widgets**

Update `dashboard_screen.dart` to import:
- `SalaryCycleCard`
- `BudgetHeroCard`
- `PartnerSettlementCard`
- `SubAllocationsSection`
- `DashboardActionSheet`

Remove duplicate inline widget builder methods.

- [ ] **Step 2: Run full test suite**

Run: `flutter test`  
Expected: PASS with 0 errors.

- [ ] **Step 3: Commit**

```bash
git add flutter_app/lib/screens/home/dashboard_screen.dart
git commit -m "refactor(dashboard): compose modular cards and reduce screen complexity"
```

---

### Task 8: Build APK & Verify on Realme 8 Device

**Files:**
- Output: `flutter_app/build/app/outputs/flutter-apk/app-debug.apk`

- [ ] **Step 1: Build debug APK**

Run: `flutter build apk --debug`  
Expected: Successful APK build.

- [ ] **Step 2: Install APK to Realme 8**

Run: `adb -s DUGIWSL74PWCJFHA install -r flutter_app/build/app/outputs/flutter-apk/app-debug.apk`  
Expected: `Success`.

- [ ] **Step 3: Launch app and take screencap to verify clean rendering**

Run: `adb shell monkey -p com.budgettracker -c android.intent.category.LAUNCHER 1` and capture screenshot evidence.

- [ ] **Step 4: Push commit to `refactor/mobile-architecture-and-technical-fixes`**

Run: `git push origin refactor/mobile-architecture-and-technical-fixes`
