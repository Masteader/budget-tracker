# Offline SQLite Queue & Sync Engine Implementation Plan

> **Goal:** Build an enterprise-grade offline-first SQLite transaction queue and background synchronization engine with SHA-256 idempotency guarantees, exponential backoff retries, and automatic replay upon connectivity restoration.

---

## Proposed Changes

### 1. `flutter_app/lib/models/offline_queue_item.dart`
- Model representing queued offline operations (`sms`, `chat`, `receipt`).
- Handles JSON serialization, status transitions (`pending`, `syncing`, `failed`), and error tracking.

### 2. `flutter_app/lib/services/offline_queue_manager.dart`
- Manages SQLite database lifecycle with schema versioning (`offline_sync_queue` table).
- Computes deterministic SHA-256 idempotency keys from operation parameters.
- Atomically enqueues items, ignoring duplicate submissions.
- Provides queries for pending items, status transitions, and retry count tracking.

### 3. `flutter_app/lib/services/sync_worker.dart`
- Monitors network connectivity using `connectivity_plus` and application lifecycle events.
- Replays pending operations sequentially through `ApiService.instance`.
- Implements exponential backoff on transient errors and marks non-recoverable items as `failed`.
- Notifies UI listeners (`pendingCountNotifier`, `onItemsFlushed`).

### 4. Integration into UI & Services
- Update `offline_sync_service.dart` facade to delegate to `OfflineQueueManager` and `SyncWorker`.
- Hook connectivity listeners into `main.dart` / `dashboard_screen.dart`.

---

## Detailed Task Breakdown

### Task 1: Create `OfflineQueueItem` Model & Tests
- File: `flutter_app/lib/models/offline_queue_item.dart`
- Test: `flutter_app/test/models/offline_queue_item_test.dart`
- TDD: Test serialization, deserialization, idempotency key generation, and copyWith.

### Task 2: Implement `OfflineQueueManager` (SQLite CRUD & Migrations)
- File: `flutter_app/lib/services/offline_queue_manager.dart`
- Test: `flutter_app/test/services/offline_queue_manager_test.dart`
- TDD: Test table creation, migration from v1 `offline_tx_queue`, duplicate prevention, and retry increment.

### Task 3: Implement `SyncWorker` with Backoff & Connectivity Listener
- File: `flutter_app/lib/services/sync_worker.dart`
- Test: `flutter_app/test/services/sync_worker_test.dart`
- TDD: Test replay execution through mock API client, error handling, and flushed notification stream.

### Task 4: Connect `OfflineSyncService` Facade & Mobile Lifecycle
- Modify: `flutter_app/lib/services/offline_sync_service.dart`
- Modify: `flutter_app/lib/main.dart`
- Verify `flutter test` across entire project.

### Task 5: Build Debug APK & Verify on Realme 8
- Build debug APK with `flutter build apk --debug`.
- Install onto Realme 8 device (`DUGIWSL74PWCJFHA`).
- Verify offline queue banner and sync triggers.
