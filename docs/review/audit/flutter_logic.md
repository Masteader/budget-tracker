# Flutter Logic & Security Audit (mobile app)

Scope: `flutter_app/lib/services`, `lib/providers`, `lib/models`, `lib/main.dart`,
`lib/supabase_config.dart`, `flutter_app/test`, `pubspec.yaml`, Android config. I made
logic-only edits in screens and widgets where a fix needed them. Every changed screen or
widget file is listed under "Files outside the mobile-logic ownership touched" at the end.
Base commit: `f17eb2b`. File:line references point to the base commit unless noted.

## Gates: baseline vs final

| Gate | Baseline (`f17eb2b`) | Final |
|---|---|---|
| `flutter analyze` | No issues found | No issues found |
| `flutter test` | 141 passed, 0 failed | 340 passed, 0 failed |

After the follow-up fixes (MOB-19, MOB-26..28, UI-20, UI-25; commits `b73c865`..`29b83f6`), on base `820a6a3`: `flutter analyze` reports no issues and `flutter test` passes 410, fails 0.

Toolchain: Flutter 3.47.7 stable / Dart 3.13.5. There is no Android SDK in the sandbox, so
I could not build the APK or AAB. The Android manifest and Gradle changes are covered only
by tests that check the source files.

Two existing tests asserted the buggy behaviour and were rewritten:
- `offline_queue_manager_test` "Prevents duplicate enqueue with identical payload" (MOB-05).
- `sync_worker_test` expected a network error to consume a retry (MOB-09).

The other new tests use injection points added by the fixes (`api:`, `transactionInserter:`,
`blobDirectoryProvider:`, `AuthGate` builders). For those, the reproduction steps below show
how each bug was observed.

## Findings

| ID | Sev | Title | Location (base) | Status |
|---|---|---|---|---|
| MOB-01 | Critical | Offline chat replay only *previews* (never stores); the offline "preview" fallback counts as synced | `services/sync_worker.dart:115-125`, `services/api_service.dart:63` | Fixed `b875e71` + test |
| MOB-02 | High | Production URLs/keys hard-coded as defaults; the static `APP_AUTH_TOKEN` is sent from the client; no config validation | `supabase_config.dart:6-35`, `services/api/base_api_client.dart:11-14,68` | Fixed `b875e71`, `4e329a5` + tests |
| MOB-03 | High | Manual expenses: the online insert names a non-existent `paid_by` column, so every save goes offline. The replay goes through the AI chat endpoint, which drops or coerces payer, beneficiary, account and time (the wife's reimbursable debt is lost) | `widgets/transactions/manual_expense_sheet.dart:221-266`, `sync_worker.dart:115-121` | Fixed `b875e71` + tests |
| MOB-04 | High | Rows left in `syncing` after an app kill are never replayed again | `services/offline_queue_manager.dart:134-157` | Fixed `b875e71` + test |
| MOB-05 | High | Two identical offline purchases are silently merged into one (content-hash dedup) | `offline_queue_manager.dart:88-117` | Fixed `b875e71` + test |
| MOB-06 | High | Replays are not idempotent: no key is sent and `allow_duplicate=true`, so a request that timed out after the server committed gets booked twice | `sync_worker.dart:115-158` | Partly fixed `b875e71` (client) + test; backend must honour `Idempotency-Key` |
| MOB-07 | Medium | FastAPI JSON error bodies (`{"detail":..}`) come back without `status:'error'`, so callers treat 4xx responses as success | `base_api_client.dart:109-123` (and in get/put/delete) | Fixed `b875e71` + tests |
| MOB-08 | Medium | An expired JWT gets 403 from the firewall, not 401, so refresh-and-retry never fires; there is no proactive refresh | `base_api_client.dart:100-107`; `ai_service/main.py:186-192` | Fixed `b875e71` + tests |
| MOB-09 | Medium | Transient failures use up the 5-try budget, so expenses end up `failed` with no visibility or retry. No FIFO guarantee | `offline_queue_manager.dart:167-186`, `sync_worker.dart:79-92` | Fixed `b875e71` + tests |
| MOB-10 | Low | A concurrent flush returns 0 instead of awaiting the drain; only 50 items are processed per drain | `sync_worker.dart:59`, `offline_queue_manager.dart:135` | Fixed `b875e71` + tests |
| MOB-11 | High (suspected) | Base64 receipt images are stored inline in SQLite. Rows over Android's ~2 MB CursorWindow make `getPendingItems` throw, which blocks the whole queue | `offline_queue_manager.dart:135-146`; enqueuers in scanner screens | Fixed defensively `b875e71` + test (not reproduced on a device) |
| MOB-12 | Medium | Replayed expenses are stamped with the server's "now", so an expense made offline on the 26th lands in the next cycle | `ai_service/chat_parser.py:615` (`now_iso`) | Partly fixed `b875e71` (client sends `client_occurred_at`; manual expenses keep their own timestamp); backend must read it |
| MOB-13 | High | Dart cycle keys use device-local time, a hard-coded 27, and ignore the payday clamping and labelling rules, so they diverge from `get_saudi_cycle_for_timestamp` | `screens/home/dashboard_screen.dart:347-353`, `budget_management_screen.dart:166-171`, `accounts_overview_screen.dart:37-43`, `widgets/accounts/record_income_sheet.dart:109-115`, `widgets/salary/payday_income_sheet.dart:131-134`, `widgets/dashboard/budget_hero_card.dart:24-53`, `models/models.dart:365-384` | Fixed `4e329a5` + 123 parity/invariant tests |
| MOB-14 | High | Arabic-Indic and Urdu digits in amount fields parse to null, so an amount typed as "١٥٠" becomes 0 | 39 `double.tryParse(...text)` sites (screens/widgets) | Fixed `867a2e3` + tests |
| MOB-15 | Medium | `_AuthGate` re-queries the profile on every auth event (hourly token refresh), which tears down and rebuilds the Dashboard. Offline start shows the onboarding screen to existing users | `main.dart:125-170` | Fixed `4e329a5` + widget tests |
| MOB-16 | Medium | Providers keep the previous household's data (and Realtime channel) across a sign-out or household switch | `providers/transaction_provider.dart:93-98`, `budget_provider.dart:36-40` (init) | Fixed `4e329a5` + tests |
| MOB-17 | Low | `selectCycle` race: a stale breakdown response overwrites the newer cycle | `providers/budget_provider.dart:42-47,98-115` | Fixed `4e329a5` + test |
| MOB-18 | Medium | Android `allowBackup` is on by default (session tokens, offline queue and receipts end up in backups); release builds are signed with the debug key (plus a TODO) | `android/app/src/main/AndroidManifest.xml:24-27`, `android/app/build.gradle.kts:30-35` | Fixed `4e329a5` + source tests (build not verified) |
| MOB-19 | Medium | The Supabase session (refresh token) sits in plaintext SharedPreferences | `supabase_flutter` default storage | Fixed `b73c865` + tests (`flutter_secure_storage` LocalStorage with one-time migration; APK build not verified, no Android SDK) |
| MOB-20 | Low | The Dashboard `onItemsFlushed` listener is never cancelled (leak plus dead context) | `screens/home/dashboard_screen.dart:63` | Fixed `ef203c1` (no automated test: the screen needs an initialised Supabase) |
| MOB-21 | Low | Three raw `http` calls bypass BaseApiClient (no refresh, no error normalisation) | `services/api/budget_api_client.dart:363-380,435-461,465-492` | Fixed `b875e71` |
| MOB-22 | Low | Stored signed receipt URLs are returned verbatim (they break after expiry); on failure the code returns unusable URLs; the cache is unbounded and survives sign-out | `services/receipt_storage_service.dart:106-145` | Fixed `ef203c1` + tests |
| MOB-23 | Medium | `WEBHOOK_SECRET` (HMAC for chat and receipt calls) is compiled into the client and can be extracted | `supabase_config.dart:37`, `ai_service/routes/chat.py:32`, `routes/receipts.py:33` | Not fixed: the backend still requires `X-Signature` in production; needs a backend change (see below) |
| MOB-24 | Medium | Naive local ISO timestamps go to `timestamptz`, shifting Riyadh times by 3 h; batch receipt insert used non-existent `date`/`vat_amount` columns, so it always went offline | `manual_expense_sheet.dart:234`, `widgets/scanner/batch_item_review_sheet.dart:223-232`, `services/account_service.dart:74,90,139` | Fixed `b875e71` + test |
| MOB-25 (DB-17) | Low | The app read `households.invite_code` directly, which blocks the DB from restricting it to admins | `screens/settings/ingestion_settings_screen.dart:129-133`, `budget_api_client.dart:564` | Fixed `4e329a5` + source test |
| MOB-26 | Low | The statement-PDF URL is shown or opened without auth; the firewall returns 403 | `budget_api_client.dart:getStatementPdfUrl`, `screens/home/transaction_feed_screen.dart:825` | Fixed `82f4478` + tests (authenticated download, share sheet; no signed-URL endpoint exists) |
| MOB-27 | Low | Payday save reports success even if the server rejects it, so client and DB cycles can diverge | `ingestion_settings_screen.dart:216-236` | Fixed `69f622c` + tests (server-first save; income and rollover too) |
| MOB-28 | Low | `OfflineSyncService.enqueue` returns null on a SQLite failure; screens still say "Saved offline" | `offline_sync_service.dart`, callers | Fixed `28ae0cc` + tests |
| MOB-29 | Info | Money is `double` end to end. Totals are folded in double for display; settlement is server-side | models/providers | Not fixed: inputs are now rounded to halalas (MOB-14). Recommend integer halalas or `Decimal` in a future model migration |

## Details

### MOB-01: offline chat replay never commits
- **Root cause:** `SyncWorker._dispatchItem('chat')` called `ApiService.postChatTransaction`, whose `previewOnly` defaults to `true`. The server returns `pending_confirmation` and inserts nothing. When the backend was unreachable, `ChatApiClient` fell back to a local parse with `status:'preview'`, which the worker listed as a success, so it deleted the queue row.
- **Reproduction:** queue `{'message': 'Coffee 15 SAR'}`, then drain against a mock server. The request body has `preview_only: true`. With an unreachable server the row is deleted and no transaction exists.
- **Impact:** every expense captured offline through chat was lost, either silently or after 5 retries.
- **Fix:** replay with `preview_only:false`. Only `success`/`enriched` (and `simulation`, which has nothing to store) count as committed. A local `preview` is treated as transient. `pending_confirmation`, `duplicate_candidate`, `non_transactional` and a missing status are permanent failures.
- **Tests:** `test/services/offline_sync_regression_test.dart`, group MOB-01.

### MOB-02: client configuration and static secrets
- **Root cause:** `SUPABASE_URL`, the publishable key and the backend URLs had production default values, so any build without defines, including CI and tests, talked to production. `BaseApiClient` sent `X-App-Token` (APP_AUTH_TOKEN) whenever it was defined at build time. A token compiled into an APK can be extracted, and that token alone bypasses the FastAPI firewall.
- **Fix:**
  - Removed all defaults.
  - `validateClientConfig` / `ensureValidClientConfig` (called first in `main`) throw a `StateError` naming each missing flag.
  - Service-role keys (`sb_secret_…`, or a JWT with `role=service_role`) are rejected.
  - Release builds must use `https://` and must define `WEBHOOK_SECRET`.
  - `X-App-Token` is no longer sent; the per-user Supabase JWT is the only credential (the firewall already accepts a verified Bearer token).
  - README documents the flags.
- **Tests:** `test/services/client_config_test.dart`, plus updated `base_api_client_test`s.
- **Ops note:** builds that relied on the defaults must now pass `--dart-define`s.

### MOB-03: manual expense payer lost and every save diverted offline
- **Root cause:** `public.transactions` has no `paid_by` column. I checked this against all repository migrations and the migrated local audit DB, but could not check the live DB. The online insert therefore always failed (PGRST204). The `catch` queued a free-text chat message with `paid_by:'wife'`, which the worker never forwarded. The chat endpoint also accepts only `me`/`partner`.
- **Impact:** the user sees "Saved offline" while online. The replay goes through the AI parser, which loses account, payer, beneficiary and time. Islamic-compliance tracking of the wife's reimbursable spending (Nafaqah) silently disappears.
- **Fix:** `models/manual_expense_row.dart` builds a schema-valid row:
  - a client-generated `id`;
  - a UTC timestamp;
  - the payer recorded in the `raw_sms` `PaidBy:` tag, which `Transaction.fromMap` and the settlement engine already parse (wife becomes partner).

  The same row is queued as `transaction_insert` and replayed verbatim through Supabase (RLS still applies). A `23505` unique violation on replay means the earlier attempt committed. Legacy `chat` rows now forward `spent_by`/`paid_by`/`category_code`.
- **Tests:** `test/models/manual_expense_row_test.dart`; regression group MOB-03.
- **Follow-up (DB owner):** if the live DB does have `paid_by`/`beneficiary`, add them to the migrations. `TransactionProvider.updateTransaction` (unused) and `edit_transaction_sheet` (has a `raw_sms` fallback) also write those columns.

### MOB-04, MOB-05, MOB-09, MOB-10, MOB-11: queue mechanics
- **MOB-04:**
  - Root cause: `markSyncing` persists `syncing`, but `getPendingItems` reads only `pending`.
  - Repro: an app kill between those two calls leaves the row stuck forever, while it still counts in the pending badge.
  - Fix: `recoverInterruptedItems()` at the start of every drain. This is safe because drains are single-flight per process.
- **MOB-05:**
  - Root cause: the key was a SHA-256 of `(op, household, payload)`, so a second identical coffee returned the first row's id.
  - Fix: a per-enqueue nonce. Callers can still pass an explicit `idempotencyKey` for double-submit protection.
- **MOB-09:**
  - Root cause: every failure did `retry_count+1` and became `failed` at 5, so five connectivity flaps (for example, Wi-Fi without internet) parked the expense where the UI never shows it.
  - Fix: outcomes are classified.
    - Transient (no HTTP status, 401/403, 408/425/429, 502-504, Socket/Timeout/Client exceptions): keep `pending`, keep the retry budget, halt the drain to preserve FIFO.
    - Permanent: count toward `maxPermanentRetries`, then park as `failed`.
  - New `getFailedCount` / `requeueFailed` / `OfflineSyncService.retryFailed` give the UI a retry entry point.
- **MOB-10:** concurrent callers now share `_inFlightDrain`, and the drain loops over batches.
- **MOB-11:** images are written to `<databases>/offline_blobs/<id>_<n>.b64` and the row stores only relative file names (iOS container paths change between updates). Rows are loaded one by one, and an unreadable row is quarantined as `failed` instead of throwing for the batch. A test covers a 4 MB image and a corrupt row.

### MOB-06 / MOB-12: idempotency and original time (needs backend)
- **Client fix:**
  - Each replay sends `Idempotency-Key: <row key>`, stable across retries (test: timeout followed by retry reuses the key).
  - It also sends `client_occurred_at` (the enqueue time, UTC).
  - Manual expenses are fully idempotent through the client `id` and keep their own timestamp.
- **Backend still to do (ai_service owner):**
  - Persist `Idempotency-Key` for `/agent/chat-transaction` and `/agent/scan-receipt`, and return the original result on a repeat.
  - Use `client_occurred_at`, clamped to the past few days, as the transaction timestamp.
- Until then, a chat or receipt replay that times out after the server commits can still create a duplicate.

### MOB-07 / MOB-08 / MOB-21: API client
- All verbs now go through a single `_send`:
  - It refreshes before sending when `session.isExpired`.
  - On 401, or on the firewall's `403 "Untrusted endpoint access"`, it refreshes once and replays the identical request (same body and signature).
  - A real authorisation 403 is not retried.
  - Errors are normalised to `{..., status:'error', status_code, message}`.
  - A non-object JSON success body no longer throws a `TypeError`.
- `archiveBudgetCategory`, `renameSubCategory` and `removeSubCategory` now use the shared client.

### MOB-13: salary cycle parity
- `services/salary_cycle_service.dart` is a line-by-line port of the SQL:
  - Riyadh date (UTC+3, no DST) of the instant;
  - payday clamp 1..31 (null → 27), then per-month clamp;
  - payday 1 means the calendar month;
  - cycles labelled by the start month for payday ≤ 15 and by the next month for payday ≥ 16.
- `test/services/salary_cycle_service_test.dart` holds an explicit table of 109 cases. I generated their expected values by running the migrated `get_saudi_cycle_for_timestamp` on local Postgres 16, never the live project. The table covers:
  - the brief's cases (Oct 28 2026 → `2026-11`; Dec 27 → `2027-01`);
  - the 21:00Z boundary;
  - devices at +05:00 and -05:00;
  - Feb and leap years with paydays 27/29/30/31;
  - 30-day months with payday 31;
  - paydays 1/10/15/16, out-of-range values and null;
  - 60 seeded random instants.
- Invariant tests check that, for 10 paydays, every day from 2026 to 2030 falls in exactly one cycle of 28-31 days, cycles are contiguous, and keys advance one month at a time.
- The six scattered client computations now call the service. `BudgetProvider` caches the household payday (from `/households/{id}/payday`, persisted under the existing `payday_day` preference). `SalaryCycleInfo.daysTotal`/`daysElapsed` use UTC date arithmetic on the Riyadh "today".
- **Repro of the old bug:**
  - A device at UTC+5 at `2026-10-27T01:00+05:00` (Oct 26 23:00 in Riyadh) computed `2026-11`; the DB says `2026-10`.
  - With payday 25, the client kept Oct 25-26 in `2026-10`; the DB says `2026-11`.
- **Also found (backend, not mine):** `ai_service/salary_cycle.py` uses `datetime.now(timezone.utc).date()` rather than the Riyadh date, so it disagrees with the DB between 21:00 and 24:00 UTC.

### MOB-14: Arabic-Indic digits
- `models/money.dart` `parseMoneyInput` handles:
  - digits U+0660-0669 and U+06F0-06F9;
  - `٫` (decimal) and `٬`/`،`/`,` (grouping);
  - NBSP and bidi marks;
  - `SAR`/`ر.س`/`ريال`/`﷼`.
- It rounds to halalas and returns null for non-numbers, keeping the old validation semantics. It replaced all 39 money-input `double.tryParse(...text)` sites. The dependent-allowance input formatter now accepts Arabic digits.

### MOB-15 / MOB-16 / MOB-17: auth gate and providers
- **AuthGate** (`main.dart`, now public and injectable):
  - It looks up the household once per user id.
  - `HouseholdResolver` caches the household per user, so an offline start opens the dashboard. Offline with no cache shows a "try again" retry state (existing l10n key), never onboarding.
  - It initialises providers once per household and resets them on sign-out.
  - Household join and leave flows navigate back through `AuthGate`, so sign-out is always observed (before, they replaced the gate route).
- **Providers:** `TransactionProvider` and `BudgetProvider` clear their state and the Realtime channel on household change or `reset()`. In-flight responses for a superseded request are dropped using generation counters.

### MOB-18: Android
- Manifest:
  - `allowBackup="false"`, `fullBackupContent="false"`;
  - `dataExtractionRules` excludes every domain from cloud backup and device transfer;
  - explicit `usesCleartextTraffic="false"`.
- Gradle: release signing comes from the git-ignored `android/key.properties`. The debug key is used only when that file is missing, with a build warning. The TODO is gone.
- Zero SMS policy: verified that there are no SMS permissions, receivers or SMS plugins (a test enforces this).

### MOB-23: client-side HMAC secret (not fixed, needs backend)
- The HMAC secret ships in every APK, so `X-Signature` proves nothing about the caller. The chat and receipt routes already call `verify_household_access` with the user's JWT.
- **Recommendation (backend):** skip the HMAC requirement when a verified user JWT is present; keep HMAC only for true server-to-server webhooks. Then drop `WEBHOOK_SECRET` from client builds.

### MOB-19: session in secure storage (follow-up fix)
- **Fix:** `services/secure_session_storage.dart` implements supabase_flutter's `LocalStorage` on `flutter_secure_storage` 11 and is passed to `Supabase.initialize(authOptions: FlutterAuthClientOptions(localStorage: ...))` in `main.dart`. It uses the same key as the default storage (`sb-<project>-auth-token`).
- **Migration:** on start, a plaintext session in SharedPreferences is written to secure storage, read back to verify, then deleted. If the secure write fails, the plaintext copy is kept so the user stays signed in, and the move is retried on the next start. A stale plaintext copy next to a secure session is deleted. `persistSession` and `removePersistedSession` always delete the plaintext key and never write it again.
- **Android options:** `AndroidOptions()` (Keystore RSA-OAEP wrapped AES-GCM). The `encryptedSharedPreferences` flag relied on the deprecated Jetpack Security library and no longer exists in v10+; the plugin migrates data written by it (`migrateOnAlgorithmChange`). `resetOnError` drops an undecryptable value (e.g. after a restore) and the user signs in again instead of the app crashing. Plugin minSdk 24, app minSdk 26. `allowBackup` stays off (MOB-18). iOS: `first_unlock_this_device`.
- **Not covered:** the PKCE code verifier (short-lived, used only during an OAuth/magic-link exchange) still uses the default SharedPreferences store.
- **Limits:** I could not build the APK (no Android SDK). The Gradle/Kotlin compatibility of `flutter_secure_storage` 11 and `share_plus` 13 must be confirmed with a real `flutter build apk`.
- **Tests:** `test/services/secure_session_storage_test.dart` (fake stores: migration, failed secure write, stale copy, persist/remove, unreadable keystore, wiring, minSdk/backup source checks).

### MOB-26: statement PDF download (follow-up fix)
- **Backend contract:** `GET /reports/statement-pdf?household_id=&cycle_key=` returns the PDF bytes behind `verify_household_access` (JWT). There is no signed-URL endpoint, so no backend change was needed or made.
- **Fix:** `BaseApiClient.getBinary` reuses the JSON calls' auth path (refresh an expired session, one replay on 401 or the firewall's 403). It throws `ApiDownloadException` on any HTTP or network error. `BudgetApiClient.downloadStatementPdf` also rejects a 200 response without a `%PDF` header. `StatementPdfService` writes the file to `<cache>/statements/`, deleting earlier statements, and opens the system share sheet (`share_plus`) to open, save or send it. The transactions screen no longer shows or copies a URL; failures show a localized error.
- **Tests:** `test/services/statement_pdf_download_test.dart`.

### MOB-27: household settings saved server-first (follow-up fix)
- **Fix:** `saveHouseholdSetting()` calls the API first. SharedPreferences, `SalaryCycleService.paydayDay` and screen state are updated only when the server returned `status: success`. A `false` result throws `HouseholdSettingNotSavedException` and shows "The server did not confirm the change. Your previous setting is still in effect." `PaydaySettingsCard` reverts its selection on failure. Monthly income and the rollover rule had the same bug and use the same helper. The best-effort direct `households` update now runs only after the API confirmed.
- **Tests:** `test/services/household_setting_saver_test.dart`.

### MOB-28: offline queue write failures (follow-up fix)
- **Fix:** `OfflineQueueManager.enqueueOrThrow` and `OfflineQueueWriteException`. `OfflineSyncService.enqueue` now returns `Future<String>` and throws.
- **Callers:**
  - Chat used to enqueue fire-and-forget inside `setState`; it now awaits the write before replying.
  - Manual expense keeps the sheet open with an error.
  - Single and multi-page receipt scanners show the error and do not close.
  - The batch review sheet no longer counts an unsaved receipt as saved; it stays on that receipt for a retry or skip.
- **Tests:** `test/services/offline_queue_write_failure_test.dart` (closed SQLite DB, blob directory blocked, service contract, source checks).

## For other owners
- **Backend:** MOB-06/12 (Idempotency-Key, `client_occurred_at`), MOB-23 (HMAC with JWT), and `salary_cycle.py` using the UTC date.
- **Secrets hygiene (ai_service, not mobile):** `ai_service/test_chat_endpoint.py` had a hard-coded fallback value for `WEBHOOK_SECRET` (default removed, file deleted in `71a3a70`, API-25). `ai_service/tests/test_sec04_jwt_and_secrets.py` lists previously leaked secret literals as scan patterns. Treat those values as compromised and rotate them if they were ever used in production.
- **DB:** confirm whether the live `transactions` table has `paid_by`/`beneficiary` (MOB-03). After MOB-25 the households policy can hide `invite_code` from non-admins (DB-17).

## Files outside the mobile-logic ownership touched (minimal logic edits)
- `screens/home/dashboard_screen.dart`, `budget_management_screen.dart`, `screens/accounts/accounts_overview_screen.dart`: cycle-key helper (MOB-13); flush-listener cancel (MOB-20).
- `screens/onboarding/household_screen.dart`, `screens/settings/ingestion_settings_screen.dart`: route through `AuthGate` (MOB-15), payday cache (MOB-13), membership RPC (MOB-25).
- `widgets/transactions/manual_expense_sheet.dart`, `widgets/scanner/batch_item_review_sheet.dart`: schema-valid rows (MOB-03/24).
- `widgets/accounts/record_income_sheet.dart`, `widgets/salary/payday_income_sheet.dart`, `widgets/dashboard/budget_hero_card.dart`: cycle service (MOB-13).
- 17 screen and widget files: `double.tryParse` replaced by `parseMoneyInput` (MOB-14).
