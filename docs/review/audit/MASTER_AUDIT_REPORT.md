# Master Audit & Engineering Report — Budget Tracker

Branch: `audit/claude-comprehensive-review` (base `main` @ `f17eb2b`) · Date: 2026-10-19
Detailed reports: [`db.md`](db.md) · [`ai_service.md`](ai_service.md) · [`flutter_logic.md`](flutter_logic.md) · [`ui_web.md`](ui_web.md) · Fix log: [`../FIX_LOG.md`](../FIX_LOG.md)

---

## ملخص تنفيذي (بالعربي)

**شو عملنا:** فحصنا المشروع كامل: قاعدة البيانات، وسيرفر الذكاء الاصطناعي، وتطبيق Flutter، وموقع الويب. لقينا حوالي **120 مشكلة**، منها **4 حرجة** وحوالي **30 عالية الخطورة**، وصلّحنا الأغلبية الكبيرة منها، وكل إصلاح معه اختبار بيثبت إنه انحلّ. كل الشغل على فرع منفصل اسمه `audit/claude-comprehensive-review`، وما انلمس `main` ولا قاعدة البيانات الحقيقية ولا السيرفر الحقيقي.

**أخطر الأشياء اللي انحلّت:**
1. **أسرار السيرفر الحقيقية كانت منشورة بالمستودع العام.** انشالت من الكود، بس **لازم تتغير** لأن تاريخ git بيحتفظ فيها.
2. **أكواد دعوات العائلات كانت مكشوفة،** وأي حدا كان بيقدر ينضم لأي عائلة أو يعدّل ميزانياتها.
3. **في أماكن بالسيرفر كانت بتسمح لمستخدم يعدّل بيانات عائلة تانية** (الأقساط، التصنيفات، المصاريف).
4. **المصاريف المسجّلة بدون إنترنت كانت تضيع،** والحفظ اليدوي كان يفشل دايماً، فمعلومة مين دفع، يعني ديون النفقة، كانت تضيع.
5. **تقسيم المصاريف بين الزوجين كان 50/50** بالسيرفر، وهاد عكس قواعد النفقة.
6. **حوالي 760 نص بالتطبيق كانوا مكتوبين مباشرة** (أغلبهم إنجليزي)، وهلق صاروا مترجمين للعربي والإنجليزي والأوردو.

**الاختبارات:** كلها ناجحة. Flutter: 367 اختبار (كانوا 141). Python: 251 (كان في 11 فاشلين). قاعدة البيانات: 17 من 17 (كانوا 2 بس ناجحين).

**المطلوب من صاحب المشروع قبل النشر** (التفاصيل بالقسم 6):
1. يغيّر `WEBHOOK_SECRET` و`APP_AUTH_TOKEN`.
2. يحط مفتاح السيرفر السري الصحيح (`sb_secret_…`)، لأن المحطوط حالياً هو المفتاح العام.
3. ينشر بالترتيب: قاعدة البيانات، بعدين السيرفر، بعدين التطبيق.
4. ياخد قرار بـ5 أسئلة تخص طريقة عمل المنتج (القسم 6.3).

---

## 1. Executive Summary & Health Scorecard

Four parallel reviews (DB, AI service, Flutter logic/security, UI/localization/web) produced ~120 findings, of which 4 were Critical and ~30 High. All Critical findings and the large majority of High findings are fixed on this branch with regression tests; the remainder need owner decisions, owner-side actions on live infrastructure, or tooling not available in the audit sandbox (Android SDK).

Scores are the auditors' qualitative assessment (0–10) of the code as found vs. as left on this branch, assuming the owner actions in §6 are completed.

| Dimension | Before | After | Main drivers |
|---|---|---|---|
| **Security** | 3 | 8 | Live secrets in a public repo; RLS disabled on invites; unauthenticated/IDOR API routes; quota failing open; anon key used as service key. |
| **Reliability / data integrity** | 4 | 8 | Offline chat expenses lost; manual saves always failing; money created by rounding; tests that could not fail; non-hermetic test suite hitting live. |
| **Architecture** | 5 | 7 | Blocking LLM calls in async server; float money; cycle logic duplicated three times with divergence; migration chain not replayable. |
| **UI / UX & i18n** | 5 | 8 | ~760 hardcoded strings; Urdu treated as Arabic/English; RTL mirroring gaps; light-mode contrast failures; web form loses signups. |

**Test gates on the final merged branch (verified after merge):**

| Gate | Baseline (`f17eb2b`) | Final |
|---|---|---|
| `flutter analyze` | 0 issues | 0 issues |
| `flutter test` | 141 passed | **367 passed**, 0 failed |
| `pytest` (ai_service) | 127 passed, **11 failed**, 6 skipped (and non-hermetic: talks to live Supabase when a dev `.env` exists) | **251 passed**, 0 failed, 6 skipped; no network, no `.env`, no LLM |
| DB SQL suites (local Postgres 16, rebuilt from scratch) | 2 passed / 5 failed | **17 / 17 passed** |
| `web_app` build + lint | pass, 1 lint warning | pass, 0 warnings |

---

## 2. Critical & High Severity Findings

Full root cause, reproduction and test names are in the per-area reports; this is the consolidated view.

### Critical

| ID | Finding | Impact | Fix / Status |
|---|---|---|---|
| API-01 | Live `WEBHOOK_SECRET` and an earlier `APP_AUTH_TOKEN` were committed to the **public** repo (tests, dev scripts, runbook, plan docs). The repo's own secret-scanner test only globbed `*.dart` and so never inspected those files. | Anyone can forge server-to-server webhook calls. | Values purged from the tree; scanner now stores SHA-256 digests only and scans py/dart/ts/js/md/json/yaml. **Owner must rotate** (history retains values). |
| DB-01 | `household_invites` never had RLS enabled; its policies were inert. | Anon key could list every invite code; any user could mint an invite for any household and join it → full household takeover. | Fixed + test 08. |
| DB-03 | `reallocate_budget` was `SECURITY DEFINER`, executable by PUBLIC, with no auth/household checks. | Any caller could rewrite any household's budgets. | Fixed + test 10. |
| MOB-01 | Offline chat replay requested only a preview and treated the local fallback as "synced". | Expenses entered offline via chat were silently never stored. | Fixed: replay commits, idempotent. |

### High

| ID | Finding | Status |
|---|---|---|
| DB-02 | Self-referencing membership policy → infinite recursion; receipt upload/view and membership reads broken. | Fixed |
| DB-04 | Anyone could add/move categories in any household. | Fixed |
| DB-05 | Targeted invites always failed (non-existent column); target member not checked to be in same household. | Fixed |
| API-02…06 | Unauthenticated installment "pay"; unauthenticated sub-category list/rename (renaming shared definitions for all households); chat/receipt enrich and installment creation could overwrite other households' transactions; members editing system categories. | Fixed |
| API-07 | Service picked `SUPABASE_SECRET_KEY` without role validation; the configured value is an **anon** JWT, so every DB-backed route ran as anon (403s) and quota checks were silently skipped. | Fixed (startup role validation); **owner must set a real secret key** |
| API-08 | LLM quota failed open; window keyed by client-supplied household id. | Fixed (fail closed, per-user) |
| API-14 / MOB-13 | Cycle computed from UTC date (API) and device time + hard-coded 27th (app) → wrong cycle 00:00–03:00 Riyadh on payday and for non-27 paydays. | Fixed; Dart port verified against 109 vectors generated from the DB function |
| API-16 | `/settlement` split spouses 50/50, contradicting the Nafaqah invariant. | Fixed (Nafaqah applied in family mode; response gains `mode`) |
| API-19 | Support-chat LLM call blocked the event loop (whole server stalls). | Fixed |
| API-24 | Test suite non-hermetic: loaded dev `.env` and wrote to live Supabase. | Fixed |
| API-30 | Backend contract for new client (JWT-only auth, 401 on expiry, idempotency, `client_occurred_at`). | Implemented, backward compatible with old app builds |
| MOB-02 | Production URLs/keys compiled in as defaults; static `X-App-Token` sent from APK. | Fixed: `--dart-define` required, service-role keys rejected, https enforced in release, JWT only |
| MOB-03/24 | Manual-expense and batch-receipt inserts used non-existent columns → every online save failed; replay dropped payer → wife-paid Nafaqah debt lost; local-time timestamps shifted by 3h. | Fixed (see §6.2 — verify live columns) |
| MOB-08 | Expired session received 403 so the app never refreshed. | Fixed (both sides) |
| MOB-18 | Android backups included tokens/queue/receipts; release signed with debug key. | Fixed (config verified by tests; APK not built — no Android SDK in sandbox) |
| UI (several) | Payday banner never shown (wrong column `income_type` vs `source_type`, error swallowed); settlement sheets confirmed success on failure; Arabic/Urdu category names collided on code `OPEX-`; Urdu amounts labelled in rupees. | Fixed |
| WEB-09 | Web waitlist shows success + confetti but sends the email nowhere. | Fixed: VIP and support requests are emailed to the developer via `/public/inquiries` and `/support/inquiries` (needs the email env vars on the deployment) |

---

## 3. Medium & Low Findings (summary)

- **Data integrity:** transfer rounding minted money (1.005 → −1.00/+1.01) and negative income parts (DB-06); clients could write income records directly (DB-07) and relabel `cycle_key` to hide spending (DB-08); float money math in Python (API-18) and Dart (MOB-29, inputs now rounded to halalas; full integer model pending); NaN/Infinity accepted (API-22); ZATCA TLV decoder lenient on truncation/BER lengths (API-15, fixed); Arabic-Indic digits parsed as 0 (MOB-14, fixed in 39 fields).
- **Zero-SMS policy:** SMS simulators, the legacy SMS LangGraph pipeline, root dev scripts and the `sms` transaction channel (DB default/CHECK, API, app) removed; historical rows kept and relabelled (API-25, fixed).
- **Offline sync:** stuck rows after app kill, merged identical purchases, retry budget burned by network errors, re-entrant drains, receipt blobs in SQLite (MOB-04/05/09/10/11, fixed).
- **Security hardening:** Redis limiter correctness and `X-Forwarded-For` spoofing (API-09/10); missing `ENV` treated as dev, API docs public in prod (API-11/29); JWT `exp` not required / no role check / unthrottled JWKS (API-12); stale membership honoured (API-13); receipt path traversal and MIME checks (API-23); receipts bucket without size/type limits (DB-11); search_path not pinned (DB-09); vulnerable `python-jose` (API-28).
- **Account lifecycle:** sole admin could not delete their account (DB-12).
- **Islamic family finance (UI-24, resolved by owner decision; extends API-16/17):** family mode never splits between the spouses. Wife-paid shared expenses are a debt the husband owes her (`nafaqah_class = wife_reimbursable`, append-only `spouse_reimbursements`, partial/full repayment, overpayment rejected); her personal purchases are charged to a per-cycle allowance (`member_allowances`, overspend shown negative); husband-paid shared expenses stay plain expenses. Migration `20261020300000_nafaqah_wife_allowance_and_reimbursements.sql` + DB test 18; API `/households/{id}/nafaqah*` (`ai_service/tests/test_nafaqah.py`); app family card, allowance card and Nafaqah selector (no "Shared 50/50" in family mode). Roommate mode unchanged.
- **Tests that could not fail:** DB suites 03/06/07 (DB-14) — note FIX_LOG SEC-06/SEC-08 "verified" entries relied on them.
- **UI/UX:** 32 RTL mirroring fixes; 22 icon buttons labelled; ~15 white-on-white spots in light mode; brand teal/green text failing contrast replaced by AA tokens; ~25 `mounted`/context-after-await fixes; leaked subscriptions/controllers.
- **Web:** hardcoded Arabic in English mode, a11y (labels, skip link, focus, reduced motion), multi-MB icon font trimmed, meta/SEO.
- **Performance:** per-row RLS helper evaluation and 7 missing indexes (DB-13: 50k-row query 55 ms → 11 ms).

**Open (not fixed), with reason:**

| ID | Sev | Item | Why open |
|---|---|---|---|
| DB-15 | Medium | Migration chain not replayable by Supabase CLI (order, duplicate versions); live has drifted. | Needs fresh baseline from live (owner). Local replay fixed. |
| DB-16 | Medium (suspected) | Any member can move the whole shared pool to their own account. | Product decision |
| DB-18 | Low (suspected) | Transaction owner not bound to creator; members can edit each other's. | Product decision |
| DB-17 | Low | Non-admins can read join code via direct table read. | App now uses RPC (MOB-25); tighten policy after new app is adopted |
| API-32 | Medium (suspected) | Cycle rollover vs savings sweep can double-apply. | Needs DB locking function |
| API-33 | Medium | Local JSON / in-memory fallbacks diverge across containers. | Design change (require Redis/DB) |
| API-34/35 | Low | Chat category overrides not validated; JWT decoded twice; full scan after insert. | Low priority |
| MOB-06/12 | Medium | Idempotency/`client_occurred_at`: app + backend done; keys are per-process unless `REDIS_URL` is set. | Set `REDIS_URL` in prod |
| MOB-19 | Medium | Tokens in plain SharedPreferences. | Needs `flutter_secure_storage` native build |
| MOB-23 | Medium | `WEBHOOK_SECRET` still compiled into app for old backend compatibility. | Remove after backend from this branch is live |
| MOB-26/27/28 | Low | Statement PDF opens unauthenticated; payday save / "saved offline" report success on failure. | UI changes |
| UI-25 | Medium | Undo-after-delete recreates the transaction without payer/beneficiary/account. | Data-layer change |
| UI misc | Low | 17 undisposed dialog controllers; Arabic font not Cairo/Tajawal; 290 remaining hardcoded colors; dead footer links; no Urdu on web; Tailwind via CDN on landing pages. | Low priority |

---

## 4. Architectural Recommendations & Modernization Blueprint

1. **One source of truth for authorization.** Most High findings are one class of bug: the backend uses a privileged Supabase client and re-implements household checks by hand. Prefer forwarding the user's JWT to PostgREST so RLS enforces access, and reserve the secret key for narrow `SECURITY DEFINER` RPCs that check `auth.uid()` membership themselves. This removes the IDOR class instead of patching instances.
2. **Money as integers end to end.** Store and compute halalas as `bigint` (or keep `numeric(14,2)` with `CHECK` constraints in DB), `Decimal` in Python (done), and a `Money` value type over `int` in Dart (MOB-29). Ban `double` for currency via an analyzer lint.
3. **Single cycle specification.** `get_saudi_cycle_for_timestamp` is canonical. Keep the 109 vectors as a shared JSON fixture consumed by the SQL, pytest and Flutter suites so the three implementations cannot drift again.
4. **Replayable migrations + CI.** Re-baseline from live (`supabase db pull`), renumber duplicates, and add a GitHub Actions workflow that: rebuilds Postgres from `00_local_supabase_stubs.sql` + migrations and runs `supabase/tests/run_tests.py --psql --rebuild`; runs `pytest`; runs `flutter analyze` + `flutter test`; builds `web_app`; runs a secret scanner (e.g. gitleaks) on every PR.
5. **No shared secrets in clients.** Finish the move to JWT-only: after the new backend is live and old builds age out, stop accepting `X-App-Token` and drop `WEBHOOK_SECRET` from app builds (MOB-23).
6. **Durable idempotency and quotas.** Make Redis mandatory in production (or add an `idempotency_keys` table) so dedup and rate limits hold across instances (API-33, MOB-06/12).
7. **Domain decisions encoded in schema.** Add `is_tabarru` and household-scoped sub-categories; decide DB-16/DB-18 and enforce them in RLS rather than in UI (UI-24 is decided and enforced in schema: `transactions.nafaqah_class`, `member_allowances`, `spouse_reimbursements`).
8. **Mobile hardening.** `flutter_secure_storage` for tokens; certificate/https enforcement already added; build a release APK in CI to validate the Android changes made here.
9. **Repository hygiene.** SMS/dev simulation scripts, the legacy SMS pipeline and the `sms` transaction channel are deleted (API-25, guarded by tests); keep secrets only in environment/secret managers; keep `.env` out of Docker build context (`.dockerignore` added).

---

## 5. Summary of Verified Code Changes & Tests

All work is on `audit/claude-comprehensive-review` as four merged streams (conventional commits; per-commit detail in each report and FIX_LOG):

| Stream | Scope | Key artifacts |
|---|---|---|
| Database | 10 new migrations `supabase/migrations/20261020010000_*` … `20261020100000_*` (no shipped migration edited); `supabase/tests/00_local_supabase_stubs.sql`; tests `08_*`–`17_*`; `run_tests.py --psql --rebuild --db` | [`db.md`](db.md) |
| AI service | Security fixes across routes/auth/quota/storage; Riyadh-time cycles; strict ZATCA decoder; Nafaqah + Decimal settlements; client contract (JWT-only, 401, idempotency, `client_occurred_at`); hermetic test suite; `.dockerignore`; dependency bumps | [`ai_service.md`](ai_service.md) |
| Flutter logic | Offline sync rewrite (commit-on-replay, idempotent, ordered, crash-safe); config via `--dart-define` only; `SalaryCycleService` parity; Arabic/Urdu digit parsing; auth gate; signed URLs; Android backup/cleartext/signing | [`flutter_logic.md`](flutter_logic.md) |
| Nafaqah (UI-24) | Migration `20261020300000_nafaqah_wife_allowance_and_reimbursements.sql` + test 18; `nafaqah_service.py`, `routes/nafaqah.py`, chat classification; Flutter family card, wife allowance card, Nafaqah selector | [`ui_web.md`](ui_web.md#ui-24-resolved-owner-decision), rule 02 |
| UI / i18n / web | ~760 strings localized (1206 keys × en/ar/ur, guard test); 32 RTL fixes; a11y labels; light-mode contrast tokens; lifecycle fixes; web a11y/perf/meta | [`ui_web.md`](ui_web.md) |

Commands to reproduce the gates:

```bash
# Flutter
cd flutter_app && flutter analyze && flutter test
# Python (no .env needed)
cd ai_service && python -m pytest -q
# Database (plain Postgres 16; Docker mode remains the default)
PGHOST=localhost PGPORT=54329 PGUSER=postgres python3 supabase/tests/run_tests.py --psql --rebuild --db bt_audit_tests
# Web
cd web_app && npm ci && npm run build && npm run lint
```

---

## 6. Owner Actions & Release Plan

### 6.1 Before anything else
1. **Rotate** `WEBHOOK_SECRET` and `APP_AUTH_TOKEN` (values exist in public git history and in shared chat messages).
2. **Replace** the value in `SUPABASE_SECRET_KEY` (`ai_service/.env`) — it is an anon-role JWT — with a real `sb_secret_…` key. The service now refuses non-privileged keys and fails closed.
3. **Check** `SUPABASE_JWT_SECRET`: it is empty, so only ES256 tokens verified against the project JWKS are accepted. If the project still signs user tokens with the legacy HS256 secret, set it or every request returns 401.
4. **Set** `ENV=production`, `TRUSTED_PROXY_IPS`, and `REDIS_URL` on the production service.

### 6.2 Deployment order
1. **Database:** run the catalog checks in [`db.md`](db.md) against live (it has drifted from the repo), confirm whether live `transactions` has `paid_by` / `beneficiary` columns (affects MOB-03), then apply the 10 new migrations in order, followed by `20261020300000_nafaqah_wife_allowance_and_reimbursements.sql` (Nafaqah ledger and wife allowance; deploy before the backend that calls its RPCs). Re-baseline the migration chain for the Supabase CLI (DB-15).
2. **Backend:** deploy `ai_service` from this branch. It accepts both old app builds (`X-App-Token`) and the new JWT-only client.
3. **Mobile:** release a new build with all `--dart-define` values (documented in the root `README.md`, "Flutter App (`--dart-define` flags)") and a release keystore (`key.properties`).
4. **Later:** once old builds are gone, remove `X-App-Token` acceptance and `WEBHOOK_SECRET` from the app, and tighten the join-code policy (DB-17).

### 6.3 Product decisions needed
- DB-16: may any member move the entire shared pool into their own account?
- DB-18: may members edit each other's transactions?
