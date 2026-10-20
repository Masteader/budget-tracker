# Final Fresh-Eyes Review: Flutter App and Web

Branch `audit/claude-comprehensive-review`, reviewed from `952098d` (base `4ab1534`). Date: 2026-10-20.
Scope: `git diff 4ab1534...HEAD -- flutter_app/lib web_app/src landing_page`, the API clients in
`flutter_app/lib/services` checked against `ai_service/routes` + `models.py`, and every Supabase table/RPC call
checked against `supabase/migrations`. Backend and SQL were read only; nothing was changed there.

## Summary

The merged parallel work is mostly coherent: the API clients match the FastAPI routes and Pydantic models
(Nafaqah, household roles, support/VIP inquiries, chat/receipt Nafaqah and idempotency fields), the RPC
parameters match the SQL signatures (`transfer_between_accounts`, `record_income`, `reconcile_account_balance`,
`get_user_households`, `switch_active_household`), and the l10n guard keeps en/ar/ur in sync.

The real defects sat where streams met: the Nafaqah class was read from recorder-relative fields in the edit
sheet, the offline queue had three different ways to block itself forever, the manual sheet still offered the
roommate split between spouses and used a different family source than the other flows, and several paths still
reported success (BNPL plan, installment payment, invite code, "saved offline") for things the server refused.

| Severity | Found | Fixed | Open |
|---|---|---|---|
| High | 4 | 4 | 0 |
| Medium | 7 | 7 | 0 |
| Low | 14 | 3 | 11 |

Gates after the last commit: `flutter analyze` 0 issues; `flutter test` **531 passed** (511 at the start, +20 new);
`web_app`: `npm ci && npm run build && npm run lint` pass with 0 warnings.

## Findings

| ID | Sev | File:line | What / why | Verified how | Status |
|---|---|---|---|---|---|
| FR-A-01 | High | `flutter_app/lib/screens/home/edit_transaction_sheet.dart:183` | The Nafaqah class was derived from `paid_by`/`beneficiary`, which are relative to whoever recorded the row ('me' = recorder). A stored NULL class was not applied, so the wife opening the husband's ordinary expense saw "the husband owes the wife SAR X", and any save (e.g. fixing the amount) wrote `nafaqah_class = wife_reimbursable`: a false debt. Same in reverse for a wife-recorded "husband paid" row on the husband's phone. | 2 widget tests (failed before the fix) in `test/widgets/edit_transaction_sheet_test.dart`. | Fixed `f7f024b`: the stored class is authoritative (NULL = husband paid); class columns are not written until it is loaded. |
| FR-A-02 | High | `flutter_app/lib/services/api/budget_api_client.dart:498`, `edit_transaction_sheet.dart:~700` | `createInstallmentPlan` parsed the normalised error map into an empty plan instead of failing. A refused BNPL conversion (403 for another member's transaction, 400, 5xx, offline) still rewrote the transaction to the monthly amount and showed "plan active": the budget dropped to 1/N with no plan behind it. | Unit tests in `test/services/budget_api_client_test.dart` (403 must throw). | Fixed `075333a` (`ApiRequestException`). |
| FR-A-03 | Medium | `budget_api_client.dart:503`, `providers/installment_provider.dart:120`, `widgets/dashboard/installment_plans_card.dart:~630` | `payInstallment` returned a bogus plan for an error answer and `recordPayment` always returned true; the card refreshed silently (and called `setState` after an await without a mounted check). | Unit test (error answer → null). | Fixed `075333a`: null on error, card shows `rb_payment_failed`, mounted guard. |
| FR-A-04 | Medium | `flutter_app/lib/screens/scanner/multi_page_receipt_scanner_screen.dart:~150` | The multi-page scanner committed without an `Idempotency-Key`, then queued the shots under a fresh key with `allow_duplicate=true`; a request that timed out after the server stored it was booked twice on replay. Every non-422 error (403, 409, 400) was also parked as "queued offline". | Code trace + `SyncWorker.shouldQueueAfterOnlineFailure` unit test + replay-key test in `test/services/sync_worker_test.dart`. | Fixed `f319930`: one key for the online attempt and the queue item; refusals are shown. |
| FR-A-05 | Medium | `flutter_app/lib/widgets/transactions/manual_expense_sheet.dart:~540` | In a family household the manual sheet still offered the Family/Roommates toggle; choosing Roommates stored an equal `all_peers` split between the spouses (rule 02: never a split in family mode). | Widget test `family household: Nafaqah choice only, no roommate split toggle`. | Fixed `f43c19b`: toggle hidden when the household has a wife. |
| FR-A-06 | Low | same file | The Nafaqah selector was shown in households without a wife; a chosen class was silently dropped (no spouse id). | Widget test (roommate household has no selector). | Fixed `f43c19b`. |
| FR-A-07 | Medium | same file, `_loadHouseholdMembers` | Family detection used `users.household_id` (each member's *active* household) while the DB trigger, chat, receipt, edit and multi-page flows use household memberships. A wife active in another household was invisible to the husband's manual sheet, and a non-spouse family member could record a class the other flows never offer. | Widget tests `the wife is found even when her active household is another one` and `another family member ... without a Nafaqah class`. | Fixed `762d747`: context from `GET /households/{id}/nafaqah`, member list as offline fallback. |
| FR-A-08 | Medium | same file, `_saveExpense` | Any insert error (including permanent DB rejections: 42501, the Nafaqah trigger 23503/23514, PGRST204) was queued and reported "saved offline"; the row then failed on every replay. A provider-refresh exception after a successful insert also queued the row a second time. | Widget tests (rejection is shown and not queued; network failure queues the same row id); `isPermanentInsertError` unit test. | Fixed `f43c19b`. |
| FR-A-09 | High | `flutter_app/lib/services/sync_worker.dart:~290` | The queue drains FIFO and halts at the first transient failure. Every 403 was transient, but the current backend answers 401 for expired credentials and 403 only for "not a member / not allowed". One refused item (a household the user left; another account's queued entry after an account switch on the same device) sat at the head forever and nothing queued after it ever synced. Items of a previous account were also replayed with the current user's JWT. | Tests `a 403 refusal does not block later items`, `another account's queued items wait for that account`, legacy-firewall 403 stays transient. | Fixed `59b8e6b`: 403 = rejection with retry budget (except the legacy `Untrusted endpoint access` 403); items whose `user_id` is another account wait; multi-page and batch drafts now record `user_id`. |
| FR-A-10 | Medium | `flutter_app/lib/screens/scanner/receipt_scanner_sheet.dart:~500` | When `/agent/scan-receipt` refused the commit (403 enriching another member's transaction, 409 Nafaqah state, 400) the sheet inserted the receipt directly into `transactions`, bypassing the server check; for a refused enrichment this created a second transaction. | Code trace; decision function unit-tested. | Fixed `f453087` (refined in `833526d`). |
| FR-A-11 | Medium | `budget_api_client.dart:createRoleInvite`, `widgets/settings/role_invite_dialog.dart:76` | Both the client and the dialog fabricated a local `INVxxxxx` code when invite creation failed (403 for non-admins, offline) and presented it as generated; nobody can join with it. The existing widget test depended on the fake code. | Client test (403 throws) and widget test (no code, error, retry possible). | Fixed `95ba2e5` (+ `rid_generate_failed` / `rid_admin_only` in en/ar/ur). |
| FR-A-12 | High | `flutter_app/lib/services/api/base_api_client.dart:_send`, `sync_worker.dart:classifyResponse` | `/agent/scan-receipt` answers HTTP 200 `{"status":"error"}` when it cannot read the images or the total is 0. The client map had no status code, identical to a lost connection, so the worker classified it transient: an unreadable queued receipt stalled the whole queue forever. | Regression test `a 200 {"status": "error"} answer is a rejection` in `test/services/offline_sync_regression_test.dart` (failed before). | Fixed `833526d`: transport failures carry `network_error`; other code-less error answers are rejections. Backend follow-up below. |
| FR-A-13 | Low | `web_app/src/components/Simulator.tsx:58`, `App.tsx:46` | The AI demo sentence was captured once from the initial language and stayed Arabic after switching to English. | `npm run build` + reasoning (no web test runner in the repo). | Fixed `1988ed1` (`key={lang}`). |
| FR-A-14 | Low | `web_app/src/components/Simulator.tsx:16-36` | Payday demo started on the 28th although it highlights the 27th standard; a payday after the end of a short month gave a wrong countdown. | Build + reasoning. | Fixed `1988ed1`. |
| FR-A-15 | Low | `edit_transaction_sheet.dart:212` | Husband with several wives: switching an unclassified expense to a wife class silently uses the first wife (no chooser, unlike chat/receipt/manual). | Code trace. | Open: needs a wife chooser in the edit sheet; rare (multiple wives and a retroactive class). |
| FR-A-16 | Low | `edit_transaction_sheet.dart:293`, `providers/transaction_provider.dart:352` | Every edit first sends `paid_by`/`beneficiary`, columns `transactions` does not have (confirmed in `live_db_preflight.md`), and only then the `raw_sms` fallback: two requests per save. `TransactionProvider.updateTransaction` (unused) writes the same columns and would always fail. | Code + migrations grep. | Open: harmless; remove the first attempt and the dead method in a cleanup. |
| FR-A-17 | Low | `screens/home/dashboard_screen.dart:596`, `ingestion_settings_screen.dart:1047` | `FutureBuilder(future: getSettlementV2(hid))` is created in `build`, so each rebuild re-requests settlement v2. Pre-existing. | Code trace. | Open: cache the future in state. |
| FR-A-18 | Low | `widgets/settings/household_switch_sheet.dart:88` | A failed switch (`switchActiveHousehold` → false) shows nothing; the offline household cache (`HouseholdResolver`) is not updated after a switch. | Code trace. | Open. |
| FR-A-19 | Low | `screens/chat/chat_entry_screen.dart:_confirmPendingExpense` | Confirming a chat expense while offline shows an error and keeps nothing (the Nafaqah choice must be re-entered); an offline-queued chat *message* replays as a commit without confirmation and gets the server's default class. | Code trace. | Open: product decision (queue the confirmed payload). |
| FR-A-20 | Low | `widgets/scanner/batch_item_review_sheet.dart:253,293` | Batch offline drafts store `image_local_path`, which replay ignores; the receipt image is never uploaded and a draft with amount 0 can only fail. Pre-existing. | Code trace (`OfflineQueueManager.loadImages`). | Open. |
| FR-A-21 | Low | many (e.g. `wife_allowance_card.dart:265`, `{'error': e}` in ~48 snackbars) | Raw exception text (`NafaqahApiException(network, 500): ...`, `PostgrestException(...)`) shown to users instead of a localized message. | grep. | Open: low-risk polish. |
| FR-A-22 | Low | `web_app/src/i18n/translations.ts:369,711` | Family demo row shows the wife paying the groceries as "Budget 100% reconciled"; under rule 02 that is a debt the husband owes her. | Read. | Open: marketing copy, owner wording. |
| FR-A-23 | Low | `screens/settings/ingestion_settings_screen.dart:986` | `setState` after `await Permission.notification.request()` without a mounted check. | Mounted-gap scan. | Open: trivial. |
| FR-A-24 | Low | `flutter_app/lib/main.dart:181` | Sign-out resets transaction, budget and role providers but not `RecurringBillsProvider` / `InstallmentProvider`; a second account briefly sees the previous account's bills/plans until they refetch. | Code trace. | Open. |
| FR-A-25 | Low | `flutter_app/lib/services/household_permissions.dart:27` | The app treats `account_type = shared_pool` as a pool even when `is_shared_pool` is false; the DB checks only the flag, so such an owner is hidden an allowed transfer. | Code vs `transfer_between_accounts` SQL. | Open: align once the data model guarantees both are set together. |

## Contract checks that passed

- Nafaqah: `GET/POST /households/{id}/nafaqah[/reimbursements|/allowance]` paths, methods, bodies
  (`amount`, `payment_method` enum, `wife_user_id`, `cycle_key` pattern) and response fields match
  `routes/nafaqah.py` and `nafaqah_service.py`; 409 `detail.code` (`overpayment`, `not_family`) is read from the
  spread error map.
- Roles: `/households/{id}/members`, `/members/{uid}/admin` (POST/DELETE), `/primary-admin` and `HouseholdRoster`
  fields match `household_permissions.list_members`; 403/404/409 mapping matches `_permission_http_error`.
- Chat/receipt: `paid_by`, `beneficiary`, `nafaqah_class` (`wife_reimbursable|wife_personal|none`),
  `nafaqah_spouse_id`, `client_occurred_at`, `Idempotency-Key` are all read by `routes/chat.py` / `routes/receipts.py`.
- Support/VIP: `POST /support/inquiries` and `/public/inquiries` bodies satisfy `extra="forbid"`, the locale regex
  (`ar|en|ur`) and the honeypot; web/landing show success only on 2xx.
- Direct inserts use only existing columns and allowed `source` values (`chat|receipt_scan|manual`); the
  manual/batch/receipt rows set `nafaqah_class` and `nafaqah_spouse_id` together, as the trigger requires.

## Backend issues to hand off (not changed here)

1. **`/agent/scan-receipt` and `/agent/chat-transaction` answer HTTP 200 with `{"status": "error"}`**: the
   receipt route for invalid images, unreadable receipts, total <= 0 and failed enrichment
   (`receipt_scanner.py` ~L475-615), the chat route for failed enrichment (`chat_parser.py` ~L540). They should be 4xx
   (422) so every client can tell a refusal from success by status code. FR-A-12 works around it on the client.
2. **Idempotency is per process** without `REDIS_URL` (known MOB-06/12): FR-A-04's shared key only prevents the
   duplicate when the replay reaches the same instance, or Redis is configured.
3. Optional: `transfer_between_accounts` decides "pool" by `is_shared_pool` only (see FR-A-25); consider a CHECK
   that `account_type = 'shared_pool'` implies `is_shared_pool`.
