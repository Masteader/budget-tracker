# ai_service audit (Python backend) — 2026-10-19

Scope: `ai_service/**` (FastAPI app, routes, auth, rate limiting, Supabase client, salary cycle,
ZATCA decoder, settlement engine, installments, support agent, tests, Docker), checked against
`AGENTS.md` and `.agents/rules/*`. Secret values are never reproduced here; leaked values are
referred to by name and SHA-256 prefix only.

Branch: `worktree-agent-adf77fe78f2b74766` (base `f17eb2b`).

## Test results

Command (from `ai_service/`): `/opt/venv/bin/python -m pytest -q -p no:cacheprovider`

| | Result |
|---|---|
| Baseline (`f17eb2b`) | **11 failed, 127 passed, 6 skipped**. The 11 failures were tests reaching the network (`mockproject.supabase.co` via the proxy, 502). With a developer `.env` present these tests talk to the live Supabase project instead (API-24). |
| Final (`d1b60db`) | **251 passed, 6 skipped, 0 failed** (hermetic: no `.env`, no sockets to non-loopback hosts, no LLM calls). |

New test modules: `test_api_audit.py`, `test_jwt_hardening.py`, `test_supabase_key_validation.py`,
`test_rate_limit_and_env.py`, `test_input_hardening.py`, `test_salary_cycle_riyadh.py`,
`test_zatca_tlv.py`, `test_settlement_audit.py`, `test_budget_cycle_lookup.py`, plus
`tests/fakes.py` (in-memory Supabase) and `tests/secret_scan.py` (digest-based scanner).

## Findings

| ID | Sev | Title | Status |
|---|---|---|---|
| API-01 | Critical | Live WEBHOOK_SECRET and old APP_AUTH_TOKEN committed in a public repo; secret scanner blind to them | Fixed in `fb4e647` (+ owner must rotate) |
| API-02 | High | `POST /budgets/installments/{plan_id}/pay` unauthenticated, pays any household's plan | Fixed in `eec180a` |
| API-03 | High | `GET`/`PATCH /budgets/sub-categories` unauthenticated; PATCH renames shared definitions for every household | Fixed in `eec180a` |
| API-04 | High | `enrich_tx_id` IDOR: chat/receipt overwrite items/receipt of any household's transaction | Fixed in `eec180a` |
| API-05 | High | Installment creation rewrites `original_transaction_id` amount in any household; budgets never recalculated (`cls` in staticmethod) | Fixed in `eec180a` |
| API-06 | High | Cross-tenant category tampering: `/budgets/categories` edits shared/system codes and inserts global codes; sub-category removal purges shared definitions | Fixed in `eec180a` |
| API-07 | High | Supabase key never validated; `SUPABASE_SECRET_KEY` (anon JWT in owner env) overrides the service-role key | Fixed in `dd4dd24` (+ owner env fix) |
| API-08 | High | LLM quota fails open when `consume_quota` errors; window keyed by client-supplied household | Fixed in `f32dfd3` |
| API-09 | Medium | Redis sliding window: colliding members, rejected requests consume window, reconnect storm, `redis` not in requirements | Fixed in `f32dfd3` |
| API-10 | Medium | `X-Forwarded-For` trusted from any peer (invite-inspection rate-limit bypass) | Fixed in `f32dfd3` |
| API-11 | Medium | Missing `ENV` = development → unsigned requests accepted when `WEBHOOK_SECRET` empty | Fixed in `f32dfd3` |
| API-12 | Medium | JWT: no `exp` requirement, no role check, alg check after header trust, unthrottled blocking JWKS fetch, exception text in 401 | Fixed in `87caea9` |
| API-13 | Medium | Stale `users.household_id` grants access when membership row is absent | Fixed in `87caea9` |
| API-14 | High | Salary cycle uses UTC date (00:00–03:00 Riyadh on payday → previous cycle); ignores household payday on insert; category activation uses calendar month | Fixed in `b45274b` |
| API-15 | Medium | ZATCA TLV decoder: truncation, NaN/inf totals, lenient base64, no BER lengths, invalid UTF-8 | Fixed in `3a676fa` |
| API-16 | High | Legacy `/settlement` imposes 50/50 spousal split (Nafaqah violation); unbounded `split_ratio` | Fixed in `a69cb08` |
| API-17 | Medium | Nafaqah: wife-paid expense for a dependent id not counted; no Tabarru' exclusion; admin wife treated as husband | Fixed in `a69cb08` |
| API-18 | Medium | Float money math in pairwise split/simplification/installments (lost halalas, 0.01 residual) | Fixed in `a69cb08` |
| API-19 | High | Sync `litellm.completion` inside async support handler blocks the event loop | Fixed in `aee439b` |
| API-20 | Medium | Support chat: client history can inject `system` messages; unverified `household_id` | Fixed in `aee439b` |
| API-21 | Medium | Raw DB/LLM exception text returned to clients; 422 echoes input and 500s on NaN; invite lockout surfaced as 400/500 | Fixed in `aee439b` |
| API-22 | Medium | Money fields accept NaN/Infinity/negative; unbounded strings/lists; NaN passes chat/OCR validators | Fixed in `aee439b` |
| API-23 | Medium | `receipt_url` stored unvalidated (foreign folder, traversal); no image count/type/size limits | Fixed in `aee439b` |
| API-24 | High | Test suite not hermetic: loads developer `.env`, hits live Supabase (writes rows), rewrites tracked files | Fixed in `1d11d57` |
| API-25 | Low | SMS simulators / SMS LangGraph pipeline and dev scripts in repo and Docker image; no `.dockerignore` (`.env` copied into image) | Fixed in `5a457d9` (`.dockerignore`) and `504bfa2`, `aab959d`, `79f9fc4`, `71a3a70` (deletion, no `sms` channel) |
| API-26 | Low | Reimbursement: insert failure reported as success; body/URL household mismatch ignored | Fixed in `aee439b` |
| API-27 | Medium | Savings sweep resets accumulated total when the household row is missing | Fixed in `1d11d57` |
| API-28 | Low | `python-jose>=3.3.0` (CVE-2024-33663/33664) | Fixed in `5a457d9` (PyJWT migration recommended) |
| API-29 | Low | `/docs`, `/redoc`, `/openapi.json` public in production | Fixed in `f32dfd3` |
| API-30 | High | Client contract: firewall returned 403 for expired JWT, required static token/HMAC that the new app no longer sends; no idempotent replays | Fixed in `8c7ab2b` |
| API-31 | Medium | Reallocation looks up budgets by calendar month instead of salary cycle | Fixed in `d1b60db` |
| API-32 | Medium | Non-atomic read-modify-write: cycle rollover (`ensure_household_cycle_budgets`), savings sweep, legacy `reallocate_budget` fallback | Not fixed (suspected race; needs DB RPC) |
| API-33 | Medium | Local JSON / in-memory fallbacks (settings, invites, installment plans, dependents) silently diverge from DB and per container | Not fixed (design) |
| API-34 | Low | `override_category_code` / `sub_category` from chat body not validated against the household's categories | Not fixed |
| API-35 | Low | Performance: JWT decoded twice per request; `recalculate_budgets` loads every household transaction on each insert | Not fixed |

## Details

### API-01 — Critical — Leaked secrets in a public repo; broken scanner
- **Where:** `ai_service/tests/test_sec04_jwt_and_secrets.py:113-145` (raw values as regex literals; scanned only `flutter_app/lib` and `ai_service/routes`), `tests/test_security_posture.py:6-7`, `tests/test_secret_config.py:20`, `send_simulated_sms.py:13` and `test_chat_endpoint.py:10` (fallback default), `docs/runbooks/security-secret-rotation.md:5-6`, `docs/superpowers/plans/2026-10-02-…:241,248`, `…2026-10-05-…:89`, `…2026-10-15-security-hardening.md:64,1834-1835,1906-1907`.
- **Root cause:** the "leaked secret" test embedded the very values it looked for, and the dev scripts used the live webhook secret as a default. Digests: WEBHOOK_SECRET `f516a232df76…`, legacy 64-hex token `c3d7f5e65951…`, APP_AUTH_TOKEN `34164266f633…`.
- **Impact:** anyone can forge `X-Signature`/`X-App-Token`. After API-30 neither is an authentication factor any more, but both remain in git history.
- **Fix:** `tests/secret_scan.py` stores only SHA-256 digests; candidate tokens (64-hex, `bt_sec_*`, `sb_secret_*`, JWTs) are hashed and compared, plus structural checks (real-looking `bt_sec_`/`sb_secret_` keys, `service_role` JWTs). Scans `*.py *.dart *.ts(x) *.js *.md *.json *.yaml` across `flutter_app/lib`, `ai_service`, `web_app/src`, `docs`. Values redacted to `<redacted: rotated>`; dev-script defaults removed.
- **Tests:** `test_working_tree_secret_scanner` (failed on the two dev scripts before their fix), `test_secret_scanner_detects_leaked_digest_and_structural_patterns`.
- **Owner action:** rotate `WEBHOOK_SECRET` and `APP_AUTH_TOKEN` (git history keeps the old values); consider history rewrite.

### API-02 — High — Installment payment IDOR
- **Where:** `routes/budgets.py:201-215`, `installment_service.py:365-391`.
- **Root cause:** no auth dependency; `pay_installment(plan_id)` updated by id only with the service-role client.
- **Repro:** `POST /budgets/installments/<any plan id>/pay` with only the (public) app token.
- **Fix:** JWT required; plan's household resolved server-side; membership verified; update scoped by `household_id`.
- **Tests:** `test_pay_installment_requires_authentication`, `test_pay_installment_of_foreign_household_is_forbidden`, `test_every_non_public_route_rejects_anonymous_requests`.

### API-03 — High — Shared sub-category rename without auth
- **Where:** `routes/budgets.py:317-348`, `salary_cycle.py:814-839`.
- **Root cause:** `cost_control_sub_categories` has no `household_id`; rename/list routes had no auth.
- **Fix:** JWT required; rename only under a parent category owned by a household and only by an admin of it; shared/system definitions are read-only (403). Proper per-household overrides need a schema change (owner/supabase).
- **Tests:** `test_sub_category_routes_require_authentication`, `test_rename_of_shared_system_sub_category_is_forbidden`, `test_rename_of_own_custom_sub_category_by_admin_succeeds`.

### API-04 — High — Enrichment IDOR
- **Where:** `chat_parser.py:507`, `receipt_scanner.py` (enrich branch), `dedup_engine.py:119-156`.
- **Root cause:** `update(...).eq("id", enrich_tx_id)` without household filter; service role bypasses RLS; result reported "enriched" regardless.
- **Fix:** `enrich_transaction_items(..., household_id=)` scopes the update and returns False when nothing matched → `status: error`.
- **Tests:** `test_chat_enrichment_cannot_touch_foreign_transaction`, `test_receipt_enrichment_cannot_touch_foreign_transaction`.

### API-05 — High — Installment creation rewrites a foreign transaction
- **Where:** `installment_service.py:120-201`, `routes/budgets.py:182-198`.
- **Root cause:** `original_transaction_id` not checked against `household_id`; `_adjust_original_transaction` was a `@staticmethod` calling `cls.recalculate_budgets` (NameError swallowed).
- **Fix:** ownership check before creating the plan (404), scoped update, classmethod with recalculation; route requires `household_id` and JWT.
- **Tests:** `test_installment_creation_cannot_adjust_foreign_transaction`, `test_installment_creation_requires_household_and_auth`, `test_installment_adjusts_own_transaction_and_recalculates`.

### API-06 — High — Cross-tenant category tampering
- **Where:** `salary_cycle.py:632-652` (`add_category_and_budget`), `salary_cycle.py:842-901` (`remove_sub_category_for_household`).
- **Fix:** only the household's own custom code is edited; new codes inserted with `household_id`; shared definitions never purged.
- **Tests:** `test_add_category_does_not_modify_shared_system_category`, `test_add_new_category_is_scoped_to_household`, `test_remove_sub_category_never_purges_shared_definition`.

### API-07 — High — Supabase key role never validated
- **Where:** `supabase_client.py:24-38`, `is_supabase_configured`.
- **Root cause:** `SUPABASE_SECRET_KEY or SUPABASE_SERVICE_ROLE_KEY` — first non-empty wins. The owner env sets `SUPABASE_SECRET_KEY` to a JWT with role `anon`; docker-compose passes the real key as `SUPABASE_SERVICE_ROLE_KEY`, which was ignored.
- **Impact (pre-fix):** all queries ran as `anon`: membership lookups empty → every household route 403; `consume_quota` (service_role-only) failed → quota silently skipped (API-08); writes failed into container-local JSON fallbacks.
- **Fix:** keys classified without logging (`sb_secret_`/`service_role` accepted; `anon`, `authenticated`, `sb_publishable_`, unknown rejected); first privileged key wins; `get_client()` fails closed; CRITICAL startup log (`main._log_security_configuration`).
- **Tests:** `test_supabase_key_validation.py` (4 tests).
- **Owner action:** set `SUPABASE_SECRET_KEY` to an `sb_secret_…` key (or remove it so the service-role key is used). With the current env, DB-backed routes now fail closed with 500 instead of answering 403.
- **SUPABASE_JWT_SECRET empty:** HS256 user tokens are rejected (fail closed, covered by `test_empty_secret_fails_closed_for_hs256`); only ES256 tokens verifiable via the project JWKS pass. If the project still signs with the legacy HS256 secret, every user request will 401 — either migrate to asymmetric JWT signing keys or set the secret.

### API-08 — High — Quota fail-open / mis-keyed window
- **Where:** `rate_limiter.py:126-171`.
- **Fix:** inconclusive DB quota → 503 in production; window keyed by verified user.
- **Tests:** `test_quota_fails_closed_in_production_when_rpc_errors`, `test_quota_denied_by_db_returns_429`, `test_sliding_window_is_per_user_not_per_client_supplied_household`.

### API-09 — Medium — Redis limiter correctness
- **Where:** `rate_limiter.py:28-87`.
- **Root cause:** member `str(now)` collides; rejected entries stay in the ZSET; `_get_redis` retried a 2 s connect each request while Redis was down; `redis` missing from requirements (ImportError → silent per-process memory limiter).
- **Fix:** unique members, `ZREM` on rejection, 30 s back-off, `redis>=5.0.0`.
- **Tests:** `test_redis_counts_concurrent_requests_with_identical_timestamps`, `test_redis_rejected_requests_do_not_consume_window`, `test_redis_outage_backs_off_instead_of_reconnecting_every_request`.

### API-10 — Medium — XFF spoofing
- **Where:** `routes/households.py:216-225`. **Fix:** `utils.get_client_ip` honours XFF only from `TRUSTED_PROXY_IPS` (default loopback). **Test:** `test_xff_ignored_from_untrusted_peer`. **Owner action:** set `TRUSTED_PROXY_IPS` to the reverse proxy address.

### API-11 / API-29 — Medium/Low — Fail-open default environment; public API docs
- **Where:** `utils.py:47`, `main.py:46-52,129`.
- **Fix:** `utils.is_production()` is True unless `ENV` is explicitly development/dev/local/test; docs/schema hidden in production.
- **Tests:** `test_missing_env_is_treated_as_production`, `test_api_docs_hidden_in_production`.
- **Owner note:** local development must now set `ENV=development` explicitly.

### API-12 — Medium — JWT verification gaps
- **Where:** `auth.py:43-125`.
- **Findings:** `exp` not required (a token without `exp` never expires), no `role == authenticated` check, `alg` defaulted to HS256 when missing, each unknown `kid` triggered a blocking 5 s JWKS fetch on the event loop, 401 detail echoed exception text. Algorithm confusion/`none` were already rejected (verified by test).
- **Fix:** explicit allow-list (ES256 via JWKS EC P-256 keys / HS256 via secret), required `exp/iat/sub`, pinned issuer/audience/role, 30 s leeway, JWKS refresh at most once per 60 s, token length cap, generic 401.
- **Tests:** `test_jwt_hardening.py` (12 tests incl. ES256 via JWKS).

### API-13 — Medium — Stale membership fallback
- **Where:** `auth.py:146-180`. **Fix:** `users.household_id` consulted only when the memberships query errors. **Test:** `test_stale_users_household_id_does_not_grant_access`.

### API-14 — High — UTC vs Asia/Riyadh cycle parity
- **Where:** `salary_cycle.py:43,96,148,…`, `supabase_client.py:244-251` (insert), `salary_cycle.py:1065` (toggle).
- **Repro:** at 2026-10-26T22:30Z (01:30 Riyadh on the 27th) `get_cycle_for_date()` returned `2026-10`; DB trigger files the same transaction under `2026-11`.
- **Fix:** `utils.riyadh_today()` / `riyadh_date_for_timestamp()` (fixed UTC+3) everywhere; insert uses the household payday; activation uses the salary cycle.
- **Tests:** `test_salary_cycle_riyadh.py` (Oct 28 → 2026-11, Dec 27 → 2027-01, payday 30/31 in Feb incl. 2028 leap year, midnight boundary, insert and activation).

### API-15 — Medium — ZATCA decoder
- **Where:** `receipt_scanner.py:35-75`.
- **Repro:** total tag `NaN` decoded to `float('nan')` and flowed into the amount; truncated buffers produced short values; `0x81`-prefixed long names were misparsed.
- **Fix:** strict base64 (std/url-safe, optional padding), exact TLV parsing, BER lengths, strict UTF-8, decimal amounts via regex + `Decimal`.
- **Tests:** `test_zatca_tlv.py` (15 cases).

### API-16 / API-17 — High/Medium — Nafaqah rules
- **Where:** `routes/households.py:376-396`, `settlement_engine.py:16-188` (legacy), `227-257` (Nafaqah), `436-443` (v2 roles).
- **Fix:** family households (a member with `financial_role = spouse`) never split 50/50 — the husband carries shared expenses; wife-paid household/husband/children/dependent expenses are owed back in full unless flagged Tabarru' (`is_tabarru`/`is_gift`; the schema has no such column yet — owner/supabase); role detection uses `financial_role`, not admin rights; `split_ratio` limited to [0,1] and only for roommate/partner households; response gains `mode`.
- **Tests:** `test_settlement_audit.py` (family/no-50-50, wife-paid owed in full, dependent-by-id, Tabarru', admin wife, ratio bounds).
- **Follow-up (UI-24 owner decision):** the wife's debt and allowance are now persisted and explicit. `nafaqah_service.py` classifies expenses (`wife_reimbursable` / `wife_personal`, only when the wife paid), keeps the ledger in halalas and writes through the DB RPCs with the verified caller as `p_actor_user_id`. New routes in `routes/nafaqah.py`: `GET /households/{id}/nafaqah`, `GET|POST /households/{id}/nafaqah/reimbursements`, `GET|PUT /households/{id}/nafaqah/allowance` (403 not allowed, 409 overpayment / not a family, 422 bad input or a wife from another household). `POST /households/{id}/reimbursements` records into the Nafaqah ledger in family households and refuses any other direction. The chat parser suggests the class («اشتريت لنفسي…» → personal; «دفعت فاتورة البيت / أغراض البيت / للعيال» → reimbursable) and accepts the user's confirmed `nafaqah_class` (`wife_reimbursable` / `wife_personal` / `none`; any split value → 422). Both settlement engines honour `nafaqah_class`. Tests: `tests/test_nafaqah.py` (69 cases).

### API-18 — Medium — Money arithmetic
- **Fix:** integer halalas with deterministic remainder distribution; net positions preserved exactly; largest-first greedy (≤ n−1 transfers; absolute minimum is NP-hard); installment remaining computed in `Decimal`.
- **Tests:** `test_three_way_split_conserves_every_halala`, `test_simplification_*`, `test_completed_installment_plan_has_no_residual_halala`.

### API-19 / API-20 — Support chat
- **Fix:** LLM call via `asyncio.to_thread`; history roles restricted to user/assistant, sizes bounded; supplied `household_id` must be the caller's.
- **Tests:** `test_support_llm_call_does_not_block_event_loop`, `test_support_history_roles_are_restricted`, `test_support_rejects_household_caller_is_not_member`, `test_support_rejects_oversized_message`.
- Prompt-injection impact on the chat parser is limited to the caller's own household (no tools; amounts validated); see API-34 for remaining override validation.

### API-21 — Error sanitisation (+ DB invite lockout)
- **Fix:** invite claim returns a generic error; DB message "Too many failed join attempts…" → **429** with `Retry-After: 900`; receipt LLM failures generic; custom 422 handler without `input`.
- **Tests:** `test_claim_invite_db_error_is_not_echoed`, `test_claim_invite_lockout_maps_to_429`, `test_receipt_llm_failure_message_is_generic`, NaN 422 tests.

### API-22 / API-23 / API-26 — Input validation, receipt paths, reimbursements
- **Fix:** `Money` type (finite, 0..10M SAR) across request models; bounded strings/lists; receipt path must match `{household_id}/<name>.(jpg|jpeg|png|webp|heic)` after percent-decoding (legacy URLs normalised); ≤ 8 photos, strict base64, JPEG/PNG/WebP magic, 40 MP cap before stitching; reimbursement household match and real insert errors.
- **Tests:** `test_input_hardening.py`.

### API-24 / API-27 — Hermetic tests; savings reset
- **Where:** `tests/conftest.py:8-22`, `supabase_client.py:653-698`.
- **Fix:** forced test env, neutralised `load_dotenv`, socket guard, LLM guard, `FakeSupabaseClient`, tmp fallback files; savings sweep only trusts the DB when the row exists.
- **Test:** `test_savings_surplus_accumulates_on_existing_household_row` (and the previously network-dependent tests).

### API-25 — Low — SMS/dev artefacts
- **Was:** `send_simulated_sms.py`, `batch_simulate.py` (posted to the removed `/webhook/sms`) and `graph.py` (SMS LangGraph pipeline) contradicted the zero-SMS policy; root `test_*.py` scripts called live services; `transactions.source` defaulted to and allowed `'sms'`.
- **Fix:** `5a457d9` added `.dockerignore` and `testpaths = tests`. Then, on owner request ("zero SMS"):
  - `504bfa2` deleted the simulators, `graph.py`, the `langgraph` dependency, the SMS webhook models, `is_duplicate_sms` and the skipped SMS-parser tests; `insert_transaction` defaults to `manual` and rejects any source outside `chat`/`receipt_scan`/`manual`.
  - `aab959d` migration `20261020200000_remove_sms_artifacts.sql`: `source` DEFAULT `'manual'`, CHECK without `'sms'`; historical `'sms'` rows are relabelled with the mapping the app already used to display them (no row deleted, no money column touched); `raw_sms` is kept as the audit-note column (installed builds write it). No SMS-only table, function or trigger ever existed, so nothing is dropped.
  - `79f9fc4` removed the `sms` channel from the Flutter client.
  - `71a3a70` deleted `test_chat_endpoint.py`, `test_chat.py`, `test_zatca.py`.
- **Tests:** `tests/test_sms_removal.py` (no SMS route, module, simulator, pipeline identifier, dependency, root dev script or `sms` source), `supabase/tests/18_remove_sms_artifacts.sql`, Flutter `client_config_test.dart` (no SMS permission/receiver/plugin, no SMS code in `lib/`) and `transaction_source_test.dart`.

### API-30 — High — Client contract (Flutter)
- **Fix (`8c7ab2b`):** verified JWT alone passes the firewall (old `X-App-Token` still accepted there for old builds); firewall answers 401 + `WWW-Authenticate: Bearer` for missing/invalid/expired credentials; chat/receipt endpoints authenticate by JWT and no longer require `X-Signature` (so `WEBHOOK_SECRET` can be rotated without breaking installed builds; `utils.verify_signature` kept for server-to-server webhooks); `Idempotency-Key` dedupes commits per (user, endpoint, key) and replays the stored result (`Idempotent-Replayed: true`, 409 while in flight); `client_occurred_at` validated (≤ 5 min future, ≤ 90 days old) and used as the transaction time.
- **Tests:** `test_verified_jwt_alone_passes_firewall_without_app_token`, `test_firewall_answers_401_for_missing_or_expired_jwt`, `test_chat_commit_needs_jwt_not_webhook_signature`, `test_idempotency_key_dedupes_replayed_commit`, `test_client_occurred_at_becomes_transaction_timestamp`, `test_idempotency_store_is_shared_across_instances_via_redis`.
- **Limitation:** without `REDIS_URL` the idempotency store is per process; durable dedupe across instances needs Redis or an `idempotency_keys` table (owner/supabase).

### API-31 — Medium — Budget lookup by calendar month
- **Fix:** `fetch_budget`/`fetch_flexible_budgets` use the household `cycle_key`, month only for legacy rows. **Tests:** `test_budget_cycle_lookup.py`.

### Not fixed
- **API-32 (suspected):** concurrent first requests of a new cycle can both insert rollover rows and both sweep savings; `add_household_savings_surplus` and the `reallocate_budget` fallback are read-modify-write. Needs a SECURITY DEFINER RPC with row locks / unique `(household_id, cycle_key, category_code)` (supabase owner).
- **API-33:** JSON-file and in-memory fallbacks (`data/*.json`, `_memory_dependents`) return success without persisting to the DB and differ per container. Recommend removing the fallbacks once migrations are confirmed applied.
- **API-34:** chat `category_code`/`sub_category`/`beneficiary` overrides are free text; validate against the household's active categories and dependents.
- **API-35:** JWT verified in middleware and again in the route; `recalculate_budgets` scans all household transactions after every insert.

## External review (Gemini) — platform items

Second-opinion review of this branch (2026-10-20). Each claim was checked against the code at
`682fdd3`, the installed libraries in `/opt/venv` (supabase-py 2.33.0, postgrest 2.33.0,
Starlette 1.9.0) and published wheels of older supabase-py releases, inspected offline and probed
with `python -I` against mocked HTTP (`respx`), never against a live service.

| Item | Verdict | Fix |
|---|---|---|
| BLOCKER 1 — supabase-py too old for `sb_secret_` keys; key selection | **Confirmed** (lower bound) + **partly confirmed** (selection) | `3627484` |
| BLOCKER 2 — `WEBHOOK_SECRET` / `APP_AUTH_TOKEN` contradiction | **Confirmed** (docs/app/backend disagreed); firewall logic **not** a bug | `03ce01e` |
| BLOCKER 3 — quota RPC shape → 503 | **Partly confirmed**: no 503 with the current client and SQL, but any wrapped shape would 503 | `6be0159` |
| HIGH 3 — JWKS lock-out and blocking fetch | **Confirmed** (both) | `4df94fb` |
| HIGH 5 — hard-coded payday 27 | **Confirmed** (and two more call sites) | `d857855` |
| MEDIUM 6 — `raw_sms` reads/writes | **Not a bug**: the column exists by design | docs only |

### BLOCKER 1 — supabase-py and `sb_secret_` keys
- **Library evidence.** `supabase/_sync/client.py` in every release up to **2.15.3** rejects any key
  that does not match `^[A-Za-z0-9-_=]+\.[A-Za-z0-9-_=]+\.?[A-Za-z0-9-_.+/=]*$` with
  `SupabaseException("Invalid API key")` (2.5.0 line 60–63, 2.15.3 line 61–64). An `sb_secret_…`
  key has no dot, so `create_client` raised; reproduced with 2.15.3 in a scratch venv. **2.16.0** is
  the first release without the check (verified for 2.16.0, 2.17.0, 2.18.x, 2.22.x, 2.23.0, 2.33.0).
- **Headers.** 2.16.0 and 2.33.0 both send `apikey: <key>` and `Authorization: Bearer <key>` (the
  identical value) to PostgREST and Storage, which is exactly what supabase-js 2.x sends without a
  session (`SupabaseClient._getAccessToken` falls back to the key; `fetchWithAuth`), and supabase-js
  is the client Supabase documents for the new keys. Supabase's "send on `apikey`, not `Authorization`"
  warning is about Edge Functions' `verify_jwt` and `pg_net`; `ai_service` uses neither (only
  PostgREST, RPCs and Storage). So the "wrong header" part is **not confirmed** for this service.
- **Decision:** `supabase>=2.16.0` in `ai_service/requirements.txt` (was `>=2.5.0`). `/opt/venv` has
  2.33.0. The full pytest suite was also run in a scratch venv with exactly `supabase==2.16.0`
  (gotrue 2.12.4, postgrest 1.1.1, storage3 0.12.2): all green.
- **Key selection (`supabase_client.describe_supabase_key`).** Before: the loop returned on the
  first privileged key in `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_SECRET_KEY` order, so an anon value
  in the other variable was silently skipped and a legacy JWT beat an `sb_secret_` key. Now both
  variables are always inspected: an `sb_secret_` key wins over a legacy `service_role` JWT
  (`SUPABASE_SECRET_KEY` first on a tie), anon/publishable/authenticated/unknown values are never
  used, an ignored value or a second different privileged key produces a warning (startup log in
  `main._log_security_configuration` and at client creation), and with no privileged key the
  startup log is CRITICAL and `get_client()` fails closed. A bare `sb_secret_` prefix is not a key.
- **Tests:** `tests/test_supabase_key_validation.py` (33 cases: each variable alone with
  sb_secret / service_role JWT / anon / authenticated / publishable / bare prefix / garbage /
  other-role JWT; every mixed pair; both privileged; identical and different sb_secret keys;
  startup log levels without echoing values; requirements lower bound; the installed client
  accepts the key offline and sends it as `apikey`).

### BLOCKER 2 — `WEBHOOK_SECRET` / `APP_AUTH_TOKEN`
- **Contradiction confirmed.** README (`README.md:217`) and the app
  (`flutter_app/lib/supabase_config.dart:74`, StateError in release builds) said the backend requires
  the signature; `routes/chat.py` and `routes/receipts.py` no longer verified it; `main.py:27`
  imported `verify_signature` without using it; rule 04 §5 still mandated signature verification.
- **Firewall (`main.py:224` `token_valid or bearer_valid`) is not a bug.** It is a coarse pass for
  proxied requests; every non-public route verifies the JWT itself. New tests prove it:
  `test_app_token_alone_never_grants_access_to_user_routes` (every API route via the proxy with only
  `X-App-Token` → 401/403/422) and `test_app_token_with_invalid_or_expired_bearer_cannot_reach_user_data`
  (expired, forged and malformed Bearer next to a valid `X-App-Token` → 401). They passed before the
  change, confirming the behaviour.
- **Design now implemented everywhere:** user routes are authenticated by the Supabase JWT.
  `auth.verify_signature_if_present` is a dependency of every router (`main.py`): a present
  `X-Signature` must be a valid HMAC of the exact body, otherwise 401 (also 401 in production when
  `WEBHOOK_SECRET` is unset); an absent header is fine. There is currently no server-to-server
  route without a JWT (`test_every_non_public_route_rejects_anonymous_requests` guards that); such a
  route must call `utils.verify_signature`, which rejects a missing signature. `X-App-Token` stays a
  legacy firewall pass only. Flutter: `WEBHOOK_SECRET` is optional (no StateError), and
  `BaseApiClient` signs only when a secret is supplied (`signingSecret`, injectable for tests).
- **Deployment consequence:** an installed build that signs with the pre-rotation `WEBHOOK_SECRET`
  now gets 401 on its signed POSTs once the rotated secret is live (before this change the signature
  was ignored). The old value is public, so it cannot be accepted; release the new build with the
  backend (no define, or the new value).
- **Tests:** `tests/test_api_audit.py` (invalid signature on every API route with a valid JWT → 401,
  malformed/empty header → 401, valid signature → 200, signed request in production without a
  secret → 401, valid signature without JWT never reaches data), Flutter
  `test/services/client_config_test.dart`, `test/services/api/base_api_client_test.dart`.
- Docs aligned: `README.md`, `.agents/rules/04-security-and-privacy.md` §2/§5, `ai_service/.env.example`,
  `docs/runbooks/security-secret-rotation.md`, MOB-23 in `flutter_logic.md`, master report §3/§4/§6.

### BLOCKER 3 — `consume_quota` result shapes
- **SQL matches the call.** `supabase/migrations/20261019070000_sec07_api_quota_and_rate_limits.sql:30`
  `consume_quota(p_user_id UUID, p_bucket TEXT, p_limit INT, p_window_seconds INT) RETURNS BOOLEAN`;
  the only later change (`20261019100000_sec08_round6_hardening.sql:549-550`) restricts EXECUTE to
  `service_role`. `rate_limiter._consume_db_quota` sends exactly those named parameters.
- **Shape:** probing supabase-py 2.16.0 and 2.33.0 against a mocked PostgREST, a `true` body gives
  `res.data is True`, so the current deployment does not 503. But `[true]`, `{"consume_quota": true}`
  and `[{"consume_quota": true}]` (proxies, a SETOF/TABLE variant, other client versions) reached
  `allowed is not True` (`rate_limiter.py:206` at `682fdd3`) and would have been 503 in production.
- **Fix:** `_normalize_quota_result` maps unambiguous allowed shapes (incl. `"true"`/`"t"`) to True and
  denied shapes to False (→ 429); empty, multi-valued, foreign-keyed, numeric or null values are
  unknown (→ 503 in production, logged; pass in development).
- **Tests:** `tests/test_rate_limit_and_env.py` (8 allowed, 7 denied, 10 unknown shapes, each at
  unit level and through `check_api_quota` in production; SQL signature parsed from the migrations
  and compared with the RPC parameters).

### HIGH 3 — JWKS fetch
- **Confirmed:** `auth._get_jwk_for_kid` stamped `last_fetch` before downloading (`auth.py:78` at
  `682fdd3`), so one transient error rejected every ES256 token for 60 s, and the `urllib` download
  (`auth.py:60`) ran synchronously on the event loop (via the firewall and `get_current_user_id`
  inside async routes).
- **Fix:** the 60 s throttle starts only after a successful download; a failure starts a 2 s back-off
  (`_JWKS_FAILURE_BACKOFF_SECONDS`), with or without cached keys; known keys survive a failed
  refresh; a successful refresh replaces the key set (revoked keys stop verifying). The download runs
  in a worker thread (`asyncio.to_thread`) behind a lock (one fetch per burst) through the new async
  `auth.decode_token` / `ensure_jwks_for_token`, which the firewall middleware awaits for every
  protected request. The synchronous `_decode_token` used by `get_current_user_id` only reads the
  cache, so no route signature changed.
- **Tests:** `tests/test_jwt_hardening.py` (sync path never fetches; fetch runs off the loop;
  failure → retry after 2 s, not 60 s; unknown kids throttled 60 s after success; failed refresh with
  cached keys keeps them and backs off; 5 concurrent requests → 1 fetch; ES256 request through the
  firewall to a real route → 200).

### HIGH 5 — hard-coded payday 27
- **Confirmed** in `salary_cycle.py` (`get_cycle_breakdown` 464-466 — which also rolled budgets over
  with the household payday and so mismatched its own key —, `add_category_and_budget` 691,
  `archive_category_for_household` 753, `add_sub_category_for_household` 828,
  `remove_sub_category_for_household` 893, `save_sub_allocations` 960,
  `create_household_custom_category` 1167, and the affordability advice text "27th"), in
  `recurring_detector.py` (`detect_recurring_bills` 128 plus the `>= 27` due-date heuristic at 307 and
  383, `toggle_household_recurring_bill` 509, `get_recurring_bill_candidates` 564), and in
  `pdf_statement_generator.py:41` (which also used the current cycle's dates for any requested key).
- **Fix:** `salary_cycle.current_household_cycle(household_id)` / `get_household_payday` at every
  household-scoped call; `detect_recurring_bills(..., payday_day=)` with due dates placed relative to
  the cycle start day and clamped to the month length; PDF statements use the household payday and
  the requested cycle's own dates; creating a custom category with an amount updates the row that
  activation created instead of inserting a duplicate.
- **Tests:** `tests/test_household_payday.py` (household paid on the 10th on 2026-10-28 Riyadh:
  cycle `2026-10`, not `2026-11`, for every function above; due-date cases; payday 1 / February clamp).
- **Not changed (other stream's files):** `settlement_engine.py:68` and `:456` still call
  `get_salary_cycle_dates()` without the household payday; `support_agent.py` help texts describe the
  27th as the usual Saudi payday (informational, not a computation).

### MEDIUM 6 — `raw_sms`
- **Not a bug.** `transactions.raw_sms` is defined in `supabase/schema.sql:101`, never dropped or
  renamed by any migration, and `20261020200000_remove_sms_artifacts.sql:28-32` deliberately keeps it
  as the free-text audit note (installed app builds write it through PostgREST; renaming it would
  break them and lose notes) and re-documents it (`COMMENT ON COLUMN`, line 77). After rebuilding the
  local database from all migrations (`run_tests.py --psql --rebuild --db bt_review_b`, 20/20 passed)
  the column exists as `text` with the audit-note comment, and DB test 18 asserts that. The reads and
  writes in `dedup_engine.py:177-184` and `installment_service.py:238-248` use it as that note. No
  code change; the column is not renamed.

### Test results (after `d857855`)
- `ai_service`: 530 passed (`/opt/venv`, supabase-py 2.33.0) and 530 passed in a scratch venv with
  supabase-py 2.16.0.
- `flutter analyze`: no issues; `flutter test`: 497 passed.
- DB suite (local Postgres 16, rebuilt): 20/20 passed (no SQL changed).

## Owner actions
1. Rotate `WEBHOOK_SECRET` and `APP_AUTH_TOKEN` (old values remain in git history). With `8c7ab2b` the app no longer needs either for authentication.
2. Put an `sb_secret_…` key in `SUPABASE_SECRET_KEY` or `SUPABASE_SERVICE_ROLE_KEY` (either works; an anon value next to it is ignored with a warning). Deploy with `supabase>=2.16.0`.
3. Confirm the project's JWT signing: with `SUPABASE_JWT_SECRET` empty only ES256 (JWKS) user tokens are accepted.
4. Set `ENV=production` explicitly in deployment and `ENV=development` locally; set `TRUSTED_PROXY_IPS`; provision `REDIS_URL` (shared rate limits + idempotency).
