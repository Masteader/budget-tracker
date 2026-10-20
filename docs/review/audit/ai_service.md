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
| API-25 | Low | SMS simulators / SMS LangGraph pipeline and dev scripts in repo and Docker image; no `.dockerignore` (`.env` copied into image) | Partially fixed in `5a457d9` (deletion blocked) |
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
- `send_simulated_sms.py`, `batch_simulate.py` (post to the removed `/webhook/sms`) and `graph.py` (SMS LangGraph pipeline) contradict the zero-SMS policy; root `test_*.py` scripts call live services. **Deletion was denied by the session's permission policy**; mitigated by `.dockerignore`, `testpaths = tests`, and removing the embedded secret. **Owner action:** delete these files.

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

## Owner actions
1. Rotate `WEBHOOK_SECRET` and `APP_AUTH_TOKEN` (old values remain in git history). With `8c7ab2b` the app no longer needs either for authentication.
2. Replace the anon JWT in `SUPABASE_SECRET_KEY` with an `sb_secret_…` key (or remove it so `SUPABASE_SERVICE_ROLE_KEY` is used).
3. Confirm the project's JWT signing: with `SUPABASE_JWT_SECRET` empty only ES256 (JWKS) user tokens are accepted.
4. Set `ENV=production` explicitly in deployment and `ENV=development` locally; set `TRUSTED_PROXY_IPS`; provision `REDIS_URL` (shared rate limits + idempotency).
5. Delete `ai_service/send_simulated_sms.py`, `batch_simulate.py`, `graph.py`, `test_chat_endpoint.py`, `test_chat.py`, `test_zatca.py`.
