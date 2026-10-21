# Product & engineering review (Fable) — 2026-10-21

Independent, report-only review of how the product works (not a bug hunt), branch `audit/claude-comprehensive-review` @ `10a96cf`.

## ملخص لصاحب المشروع (١٠ سطور)

1. البرنامج صار آمن ومتين بعد التدقيقات، بس من ناحية "المنتج" هو حالياً أثقل وأعقد من اللي يحتاجه بيت سعودي عادي: لوحة رئيسية فيها ١٠ كروت، و٥ طرق لتسجيل مصروف، وإعدادات طويلة فيها خيارات ما لها أثر.
2. السؤال الأساسي "كم باقي لي لحد الراتب؟" الجواب موجود بس مبني على "المخصصات" اللي المستخدم لازم يعبّيها بند بند بنفسه أول ما يسجّل؛ المستخدم الجديد يشوف أصفار. لازم معالج بداية: راتبك كم → نقترح لك المظاريف → أول مصروف.
3. أهم شي ناقص: **التنبيهات**. ما في ولا تنبيه (لا يوم الراتب، لا فاتورة مستحقة، لا قسط تابي/تمارا) رغم إن المكتبة موجودة بالتطبيق. هذا أكبر سبب إن الناس ينسون التطبيق.
4. **الأقساط**: تابي وتمارا يسحبون كل أسبوعين (٤ دفعات)، والتطبيق يحسبها شهرية — لازم تتصلح لأنها أكثر حالة واقعية.
5. **التصنيفات** ناقصة أشياء سعودية أساسية: الإيجار كبند رئيسي (حالياً تحت "الخدمات")، المدارس، الخادمة/السائق، مساعدة الأهل والصدقة/الزكاة، التحويلات للخارج، تأمين وقسط السيارة، وادخار لأهداف (إيجار سنوي، عيد، حج/عمرة).
6. **الذكاء الاصطناعي**: التكلفة شبه صفر (أقل من ريال بالشهر لكل بيت)، بس كل مصروف بالشات أو الفاتورة يروح للنموذج **مرتين** (مرة للمعاينة ومرة للحفظ)، فالمستخدم ينتظر ضعف الوقت بلا فايدة. سهلة تنصلح.
7. **النفقة**: المنطق سليم شرعياً ومحمي بقاعدة البيانات، بس تجربة الزوجة الموظفة محتاجة تلطيف (لو ما عندها "مصروف" محدد يظهر لها إنها "تجاوزت"). مصروف الأطفال يُخزَّن بس ما يُتابع.
8. **التشغيل**: ما في نسخ احتياطي ولا مراقبة أعطال؛ مطلوب فوراً: خطة Supabase Pro (نسخ يومي) أو نسخة أسبوعية تلقائية، وخدمة مراقبة أخطاء بسيطة، وتوحيد الهجرات (٤٨ ملف ينسخ باليد).
9. **وقّف**: مسودة الفاتورة "بدون إنترنت" اللي تطلّع دايماً "العثيم ٨٥ ريال" (كود تجريبي)، صفحات التسويق الثلاث المكررة، الأرقام التسويقية غير الحقيقية ("دقة ٩٩.٤٪")، وكروت مقارنة الأسعار قبل ما يكون فيه بيانات.
10. الخلاصة: البرنامج جاهز تقنياً، والمرحلة الجاية لازم تكون **تبسيط + تنبيهات + تصنيفات سعودية + معالج بداية** مش مزايا جديدة.

---

# Budget Tracker — Product & Engineering Review (how the product works, not a bug hunt)

Scope: `/home/user/budget-tracker` @ `10a96cf`, branch `audit/claude-comprehensive-review`. Read: `docs/PROJECT_DETAILS.md`, `README.md`, `.agents/rules/*`, `docs/review/audit/MASTER_AUDIT_REPORT.md`, `fable_review.md`, then the code behind each feature (dashboard, chat, scanner, manual entry, budgets/cycles, Nafaqah, settlement, installments, recurring bills, settings, API, migrations, web landing). Report-only; nothing modified, no live service contacted.

Legend per recommendation: **Problem** (evidence) → **Change** → **Impact** → **Effort** S/M/L → **Risk**.

---

## 1. Core loop & value

### 1.1 Verdict on the promise ("how much is left until payday / where is it going / who owes whom")

- **"How much is left until payday"** — answered by `BudgetHeroCard` (`/home/user/budget-tracker/flutter_app/lib/widgets/dashboard/budget_hero_card.dart`, lines 22–57): remaining = Σ allocated − Σ spent across *budget rows*, daily allowance, days to payday. It is correct only once the household has typed allocations for every category. A fresh household sees "No allocations for {cycle}" (`dashboard_screen.dart` ~line 953) and must go to the Budgets tab and add categories one by one. The salary the user records (`income_records`, `households.monthly_income`) is **not** what drives "left until payday"; allocations are. For a Saudi family the natural model is: salary in on the 27th → fixed commitments (rent/installments/bills) → what's left for daily life. The app has every ingredient (income records, recurring reserves, installments) but does not compose them into one number.
- **"Where is it going"** — good: category cards, sub-allocations, feed with filters, ZATCA line items, PDF statement. Weak points: taxonomy (see 1.3) and the silent "flexible pool" raiding (see 2.2).
- **"Who owes whom"** — good and now sound: `FamilyReimbursementCard` / `MultiRoommateSettlementCard`, Nafaqah ledger, debt simplification. Day-to-day usability issues in §2.3/2.4.

**R1 — One "left until payday" number built from income, not allocations.**
Problem: hero = allocations math; new users see 0/0; monthly income lives in settings only (`income_settings_card.dart`, `households.monthly_income`). Change: hero shows `income this cycle (or monthly_income) − committed (recurring reserve + installments due) − spent`, with "unallocated" as its own line; allocations become optional envelopes. Impact: first-session value for every household; the daily allowance becomes meaningful. Effort: M (backend `get_salary_cycle_forecast` already has most pieces; one new field set + card). Risk: low; keep allocation view as a tab.

**R2 — Starter wizard instead of an empty Budgets tab.**
Problem: onboarding = sign up (email confirm) → `HouseholdScreen` (name + type) → dashboard with no budgets → manual category creation (`budget_management_screen.dart` add dialog). Change: after household creation ask "net salary? rent? number of people?" and seed 6–8 envelopes with suggested amounts (rent, groceries, fuel, bills, dining, kids/school, family support, savings). Impact: time-to-first-value from ~10 min to ~1 min. Effort: M. Risk: low.

### 1.2 Central vs. distraction (what the dashboard stacks today)

`_BudgetDashboard` renders, in order: offline banner, payday banner, hero, a 4-button dock (Scan, Voice, Simulator, Prices), `AccountsSummaryCard`, `SalaryCycleWidget` (a second burn-rate panel largely repeating the hero), settlement/family card, recurring bills, installments, then **Price Tracker + Affordability Simulator again as a row** (lines 871–940), then category cards. Plus a 7-item speed-dial FAB (`app_speed_dial_fab.dart`) and a 5-tab nav where tab 5 is a 1,844-line settings screen.

- **Central (keep, polish):** hero, category cards, recurring bills + installments (merge into one "Commitments" card), family/roommate card, chat & scanner entry, feed.
- **Secondary (move to a "Tools" screen):** affordability simulator, accounts summary, PDF/CSV export.
- **Distraction at this stage (park):** `GroceryPriceIntelligenceScreen` and `SmartShoppingBasketSheet` — price history is per-household (`price_tracker.py`), so it needs dozens of receipts across chains before it says anything; the dock shows it twice. Remove from the dashboard; revisit when there is cross-household (anonymised) data.
- **Redundant:** `SalaryCycleWidget` vs `BudgetHeroCard` (both show burn rate/days); "Copy previous month" dialog (`bm_option_sweep`/`bm_option_rollover`) vs the household `rollover_rule` setting vs server auto-rollover (`ensure_household_cycle_budgets`) — three ways to do one thing.

**R3 — Simplify the dashboard to 5 cards and 2 primary actions.** Effort S/M. Risk: none functional; pure removal + reordering.

### 1.3 What Saudi users will expect that is missing

Taxonomy today (`supabase/seed.sql`): `OPEX-GROCERY, DINING, FUEL, UTILITIES, SHOPPING, HEALTH, ENTERTAINMENT, GOV, MISC`. Housing rent is a *sub-category of UTILITIES* (`housing_rent`), which is the single largest line in most Saudi budgets. Missing top-level or first-class items:

| Need | Evidence of gap | Suggested change |
|---|---|---|
| Housing/Rent as a top-level category, often paid annually/semi-annually; housing allowance (بدل سكن) paid annually | `housing_rent` under UTILITIES; `income_records.source_type` has no `housing_allowance`; no sinking fund | New `OPEX-HOUSING`; income type `housing_allowance`; "sinking fund" goals (R5) |
| School fees (tuition, buses, uniforms) | only `tuition_fees` as a recurring default day in `recurring_detector.py` | `OPEX-EDUCATION` with per-dependent attribution (dependents already exist) |
| Domestic worker / driver salary + Iqama/visa fees for them | none (only `iqama_visas` sub-code) | `OPEX-DOMESTIC_HELP` |
| Family support to parents (بر الوالدين), Sadaqah, Zakat | chat classifier marks gifts/relatives "undetermined" (`chat_parser.py` `_EXTERNAL_BENEFICIARY_CUES`) and there is no category for it | `OPEX-FAMILY_SUPPORT`, `OPEX-CHARITY`; simple Zakat helper (2.5% of liquid accounts above nisab) later |
| Car installment, insurance, Tamm/traffic fines | none | `OPEX-TRANSPORT` (fuel becomes sub), `OPEX-INSURANCE` |
| Remittances abroad (critical for Urdu-speaking expats) | none | `OPEX-REMITTANCE` |
| Ramadan/Eid seasonal budgets, Hajj/Umrah savings | no goals, no per-cycle override; `accumulated_savings` is one untyped number | Named savings goals + "seasonal cycle override" |
| Fast capture without SMS | Chat/receipt/manual only. Bank apps, STC Pay, Urpay, Apple/Google Pay push **notifications and screenshots** are the realistic replacement | Android share-sheet target: share a screenshot into the app → reuse the existing receipt OCR pipeline (`/agent/scan-receipt` already accepts any image). S/M. Also optional Android `NotificationListenerService` for bank-app pushes (not SMS; iOS impossible) — later, with explicit opt-in |
| Open Banking (SAMA) readiness | roadmap v1.1 | Premature at 4 households; needs a licensed TPP (Lean/Tarabut) and an AIS agreement. Keep the data model ready: `accounts` already has `bank` type; add `external_ref`, `imported_at` columns when the time comes. Later. |

**R4 — Taxonomy refresh** (seed migration + l10n keys + chat prompt list). Effort S. Risk: low (categories are data; archiving is supported by the hybrid lifecycle).
**R5 — Savings goals / sinking funds** (annual rent, school, Eid, Hajj) fed by the rollover sweep instead of a single `accumulated_savings`. Effort M. Risk: low.

---

## 2. Workflows

### 2.1 Data entry speed and failure modes

| Path | Steps today | Round trips | Failure modes |
|---|---|---|---|
| **Chat** (`chat_entry_screen.dart`, `routes/chat.py`, `chat_parser.py`) | type/speak → wait (LLM #1 + ~8 DB calls) → confirmation card (merchant, category, sub-category, who paid, for whom, Nafaqah class) → confirm → wait (**LLM #2**: `process_chat_transaction` always re-runs `parse_chat_expense(message)` even on commit, line 588) → done | 2 LLM + ~20 PostgREST calls | duplicate prompt, inactive-category dialog, 409 no-provider, offline → queued |
| **Receipt** (`receipt_scanner_sheet.dart`, `receipt_scanner.py`) | photo(s) → preview (vision LLM #1) → review → save (stitch + upload to Storage **before** vision LLM #2, then insert) | 2 vision calls + upload | 10–20 s end-to-end; `temperature=1.0` on OCR (line 453) adds variance between the preview and the commit parse — the saved items can differ from what the user approved |
| **Manual** (`manual_expense_sheet.dart`) | merchant, amount, category, account, paid-by, family/roommate chips, split | 1 insert | fastest path, but hidden behind the FAB's 7th item |
| **Offline receipt draft** | uses `LocalOcrService` whose default recognizer is `MockOcrTextRecognizer` returning `'Al Othaim Supermarket Total: 85.00 SAR …'` (`/home/user/budget-tracker/flutter_app/lib/services/ocr/local_ocr_service.dart` lines 11–18; no ML Kit in `pubspec.yaml`); `receipt_scanner_sheet.dart` lines 414–431 show that draft as merchant/amount | — | **every offline photo becomes "Al Othaim, 85 SAR"** — a fabricated draft |

**R6 — Commit should not re-run the LLM.** Change: the confirmation card already holds the structured result; send it back (`parsed_payload`) and let the server validate + insert, or cache the preview under the idempotency store (`idempotency.py`) for 10 min. Impact: halves LLM latency and calls; removes preview/commit drift (especially for receipts at temperature 1.0 → set 0.1–0.2). Effort S/M. Risk: low (validation already exists in `ParsedChatExpense` / `validate_ocr_receipt_payload`).
**R7 — Make quick manual entry the primary action** (amount → category chips → who paid; 3 taps), chat second, scanner third; run the heuristic parser on-device/first and only call the LLM when it is low-confidence. Effort M. Risk: low.
**R8 — Remove the mock offline OCR draft** (or wire real on-device ML Kit). Effort S. Risk: none; it violates rule 05 (no placeholders) today.
**R9 — Receipt save path:** parse first, upload after insert (or in background); shrink the photo to 1024 px for OCR (already 1280/1600). Effort S.

### 2.2 Budgeting model: is it understandable?

Model: per-category `budgets` rows keyed by **both** `month` (1st of month) and `cycle_key` (`YYYY-MM` naming the month the cycle *ends* in for payday > 15), `sub_allocations` JSONB, `previous_cycle_delta`, `is_active`, `account_id`; `is_flexible` categories get raided automatically when another category overspends (`reallocate_budget` called from `chat_parser.py` lines 801–808 and `receipt_scanner.py`); rollover rule per household; capacity margin per account.

Where users will get confused:
1. **Cycle naming**: a cycle running 27 Oct → 26 Nov is called "2026-11" and `budgets.month` is `2026-10-01` or `2026-11-01` depending on which code path created the row (fallback-by-month everywhere: `ensure_household_cycle_budgets` lines 668–676, `get_salary_cycle_forecast` lines 163–171). The app also matches budgets by `month` prefix (`_matchesSelectedCycle` in `dashboard_screen.dart`). Users see "November budget" while still in October. Change: label cycles by dates ("27 Oct – 26 Nov"), never by month name, and stop writing `month` once `cycle_key` is universal. Effort S (labels) / M (drop `month` dependency). Risk: low/medium.
2. **Silent reallocation**: an 80 SAR dinner over budget quietly moves 80 SAR out of "Shopping" and marks the transaction `is_reallocated`. Nobody asked. Change: make it a prompt in the confirmation card ("Dining is 80 over; cover from Shopping? / leave over budget"). Effort S. Risk: low.
3. **Three rollover controls** (settings rule, "copy previous" dialog with sweep/rollover choice, server auto-rollover on first read). Keep the settings rule; auto-rollover creates rows; delete the dialog. Effort S.
4. **Zero-based capacity + account linking** is a power feature; keep but off the default path (show only when ≥2 accounts exist).
5. **Sub-allocations** are flexible but the `_recurring_config` metadata inside the same JSONB (`recurring_detector.py` line ~556) couples bills to budgets in a way that is hard to explain; fine to keep, but hide from users.

### 2.3 Nafaqah model (family mode) day to day

What works: rules 1–4 enforced in DB; wife-paid shared → reimbursable; wife personal → allowance; husband paid → plain; multiple wives; explicit provider; repayment ledger with history; chat suggests the class with a confirmation step; roles per household.

Edge cases a real family hits:
- **Working wife without an allowance**: `WifeAllowanceCard` shows "not set" and `allowance_overspent` once she logs anything personal (`wife_allowance_card.dart` lines 142–151). A wife who earns her own salary should not be told she "overspent" an allowance nobody set. Change: allowance optional; when unset show "her personal spending this cycle" neutrally. S.
- **Her own salary**: works (personal account, income record), but her personal spending is excluded from category budgets by design (owner decision) — fine, but then the hero "remaining" ignores it; label it.
- **Gifts to relatives / her mother**: classifier → `attribution_needs_confirmation` and the card offers only Husband paid / Shared / Personal. Add "Her own money, not family" (= `wife_personal` without allowance semantics) wording. S.
- **Children's allowances**: `household_dependents.monthly_allowance` is stored and editable (`add_household_member_sheet.dart`) and expenses can be attributed to a dependent, but there is no card tracking allowance vs spent per child. M.
- **Cash مصروف handed over monthly**: representable as allowance; a "transfer to wife" from the husband's account is not modeled as such (becomes an expense or a transfer). Add a `allowance_transfer` income/transfer type. S.
- **Reimbursement in practice**: "copy STC Pay note" only; fine for now. A WhatsApp deep link (`wa.me`) is roadmap and trivial once `url_launcher` is added.

### 2.4 Roommates model

Works: equal split, personal vs shared, pairwise + simplified debts, settle via recorded payment (STC Pay/bank/cash), WhatsApp text copy.
Gaps: (a) **unequal shares** (master room pays more; a couple occupying one room) — very common; add per-member weight for shared expenses. M. (b) **Member leaving mid-cycle**: `calculate_settlement_v2` resolves payers against current `household_memberships`; transactions whose payer is no longer a member are skipped (`settlement_engine.py` lines ~810–813: "payer unknown; not attributed"), so outstanding debts to/from a leaver disappear from the card. Freeze a "final statement" when a member leaves (D3 did this for the wife only). M. (c) **Joining mid-cycle** inherits the whole cycle's shared costs equally — add a join date cutoff. S.

### 2.5 Installments / BNPL realities

`installment_service.py`: `day_of_month`, monthly `calculate_installment_terms`, default 4 "months". **Tabby and Tamara "Pay in 4" charge every 2 weeks**, first payment at purchase; Tamara also has 3 monthly; bank installments are monthly. The model mis-schedules the most common plan type and the dashboard says "/month" (`installment_plans_card.dart` line 572). Also `list_plans` re-derives plans by regex over every transaction's `raw_sms` note each time the card loads (lines 374–416) — legacy and O(n). **R10:** add `frequency` (`biweekly|monthly`) + `next_due_at`, default biweekly for Tabby/Tamara; stop regex reconstruction after a one-time backfill. Effort S/M. Risk: low.

### 2.6 Recurring bills

Detection = keyword/merchant patterns + sub-allocations marked recurring + clustering; "1-tap pay" writes a transaction. Reasonable. Missing: due reminders (no notifications), variable-amount bills (SEC) shown as "average" without a "bill arrived, amount X" entry; Sadad reference number is irrelevant since there is no bank link. Keep; add reminders (R11) and an "enter actual amount" step on pay.

### 2.7 Notifications / alerts — the biggest retention gap

`flutter_local_notifications` is a dependency (`pubspec.yaml`) and the settings screen has a "Notifications" permission row, but **no code schedules or shows a notification** (grep over `flutter_app/lib` finds no plugin usage). There is no payday reminder, no bill-due reminder, no installment reminder, no "burning fast" alert, no weekly digest. FCM is roadmap v1.3, but **local scheduled notifications need no server**: payday check-in on `payday_day` morning, each recurring bill's `expected_day`, installment due dates, and a "cycle ends in 3 days" nudge can all be scheduled on-device from data the app already has.
**R11 — Local notifications now, FCM later.** Effort M. Risk: low; Android 13+ permission flow already handled in settings.

---

## 3. AI usage

### 3.1 Where the LLM adds value vs. deterministic rules
- **Receipt OCR (vision)**: genuine value; hard to replace. Keep. Lower temperature to ~0.2, send one call per receipt (R6), keep ZATCA TLV as the source of truth for merchant/total/VAT (already done; good).
- **Chat parsing**: medium value. The heuristic fallback (`_fallback_heuristic_parse`, ~300 lines: merchant map, amount regex, category keywords, attribution cues) already handles the common Saudi phrasings (15/15 reviewer phrases after FABLE-LOGIC-07). Proposal: run the heuristic first; call the LLM only when amount is missing, merchant unknown, or more than one item; show the heuristic result instantly. Saves ~1–3 s and one call on most entries.
- **Affordability simulation**: deterministic already (`simulate_affordability`); the LLM only detects intent — a few keywords do that.
- **Support chat** (`support_agent.py`): low value at 4 households and the prompt hard-codes "27th payday" and "Iqama fees (400 SAR)" (stale/incorrect for non-27 households). Keep the FAQ + email; downgrade the chat to optional. S.
- **Price intelligence / basket optimizer**: deterministic; data-starved (see 1.2).

### 3.2 Cost per active household (order-of-magnitude, flash-lite-class pricing ≈ $0.10/M input, $0.40/M output)
- Chat expense: ~1.2k-token system prompt + message, ~150 output tokens, **×2 calls** ≈ 2.6k in / 300 out ≈ $0.0004.
- Receipt: 1280-px JPEG ≈ 1–1.5k image tokens + 600 prompt, 300–1,500 output for 20–60 items, **×2 calls** ≈ $0.001–0.002.
- A household logging 40 chat + 20 receipts a month ≈ **$0.05/month**; 1,000 households ≈ $50/month. LLM spend is not the constraint; Railway (~$5–20) and Supabase ($0/$25) dominate. The real costs of the double call are latency and preview/commit drift, not dollars. Quotas (`check_api_quota`: 30 chats/10 min, 10 receipts/10 min, DB-backed `api_quota`) are sensible protection against abuse.

### 3.3 Latency
Chat preview = 1 LLM call (1–3 s) + category/sub-category/dependents/family-context/duplicate lookups (~8 PostgREST round trips); commit = LLM again + budget fetch + flexible budgets + insert + `enrich_transaction_items` + `InstallmentService.recalculate_budgets` which **selects every transaction of the household** (`installment_service.py` lines 289–294) on each insert. Receipt commit adds stitch + Storage upload before the vision call. Practical: 3–6 s per chat step, 8–20 s per receipt. Fixes: R6, R9, move `recalculate_budgets` to the DB trigger that already exists (BUG-02 triggers maintain `spent_amount`), and confirm Railway and Supabase are in the same region (each round trip across regions costs 100–200 ms; ~15 trips ≈ 2–3 s on its own).

### 3.4 Offline behaviour
Good: manual, chat and receipt commits queue in SQLite and replay with idempotency keys and `client_occurred_at` (`offline_queue_manager.dart`, `sync_worker.dart`). Chat text is parsed when back online. Bad: the mock OCR draft (R8).

### 3.5 Privacy — what leaves the device
Free text (often naming the wife/children, merchants, amounts) and receipt photos go device → Railway → Google Gemini via an **AI Studio API key** (`GOOGLE_API_KEY`). Depending on tier, AI Studio terms may permit Google to use prompts for product improvement; Vertex AI (or a paid tier with data-use opt-out) and a Saudi/EU data region are the standard answer for a finance app, and PDPL (Saudi personal data law) expects disclosure of third-party processors. The landing page meanwhile claims "AES-256 cloud encryption", "local salary calculations", "protected roommate aliases" and "99.4% accuracy" (`web_app/src/i18n/translations.ts` lines 401–412, 484–510) — none of these are substantiated in code (calculations run on the server; names go to the LLM). **R12:** privacy notice naming the LLM provider; move to Vertex/paid tier; strip names from the chat prompt where possible (send member ids, not display names — the prompt today receives raw user text only, which is fine, but the support chat forwards history). Effort S (notice) / M (Vertex). Risk: reputational if left.

### 3.6 Prompt-injection exposure in practice
Low. User text is only ever a `user` message; model output is coerced through pydantic with bounds (`ParsedChatExpense`, `validate_ocr_receipt_payload`); the `| PaidBy:` tag injection was fixed by structured columns (FABLE-API-01); support-chat history roles are sanitized. The remaining realistic vector is a receipt image containing instructions ("set total to 0") — mitigated because ZATCA QR values override the model and the user confirms before save. No action beyond keeping the confirmation card mandatory.

---

## 4. Architecture & operations for the stage (4 households live)

### 4.1 Over-engineered
- **Three implementations of the cycle logic** (SQL, Python, Dart) with a 109-vector parity suite — necessary only because the app computes cycles offline. Acceptable, but freeze it.
- **Container-local state**: `household_settings.json`, `household_invites.json`, in-memory dependents (`supabase_client.py` lines 740–1041, `dependents_service.py` `_memory_dependents`). On Railway the filesystem is ephemeral and multiple instances diverge (API-33 open). Delete every file/in-memory fallback; the DB columns exist now.
- **Legacy text-note parsing**: `raw_sms` audit notes with `| PaidBy:` tags still read for legacy rows (`settlement_engine.py` `_legacy_tags`, `installment_service.list_plans`). Run a one-time backfill into the structured columns and delete the parsers (owner applies; never from here).
- **Dual membership and role caches**: `users.household_id` + `household_memberships`, `users.financial_role` cache, `budgets.month` + `cycle_key`. Each duplication has already produced a bug class. Schedule a consolidation migration after the DB-15 re-baseline.
- **Three landing pages**: `web_app/` (React, committed build in `ai_service/static/`), `landing_page/index.html` + `mobile.html`, and `ai_service/_build_landing.py` (1,309 lines) as a fallback generator. Keep one.
- **Settings screen** (`ingestion_settings_screen.dart`, 1,844 lines): "Expense ingestion channels" toggles write `channel_chat_enabled` / `channel_scanner_enabled` to SharedPreferences and **nothing reads them** elsewhere; "Duplicate resolution policy" (auto-enrich / prompt / strict) is an SMS-era concept. Remove both sections; rename the screen.
- **FastAPI re-implements authorization** that RLS already enforces (the master audit's own recommendation #1). For deterministic reads (settlement, cycles, breakdown) a Postgres function + RLS would remove a hop and a whole bug class; keep FastAPI for LLM, PDF and e-mail.

### 4.2 Under-engineered
- **Backups**: none (the live project had none). Minimum: Supabase Pro ($25/mo, daily backups 7 days) **or** a weekly `pg_dump` from a Railway cron / GitHub Action to private object storage, tested restore once. Effort S (owner). Risk of not doing it: total data loss.
- **Observability**: `logging.basicConfig` only; `safe_error_response` emits a reference id but nothing collects it. Add Sentry (FastAPI + Flutter SDKs, free tier), an uptime ping on `/health`, and a daily "LLM calls / failures / p95" log line. Effort S.
- **CI**: no `.github/workflows` (owner declined). Even without Actions, a pre-push hook running `flutter analyze`, `flutter test`, `pytest -q` is cheap. The rule-06 bundle assumes Windows PowerShell + clipboard.
- **Migrations**: 48 files applied by copy-paste into the SQL editor, with one documented order exception and DB-15 (not replayable by CLI) still open. **R13:** re-baseline from live (`supabase db pull` into one baseline), keep new migrations CLI-applied against a free **staging** project first, then live. Effort M. Risk: medium (do once, carefully, with the existing preflight scripts).
- **Scaling cliffs (later, not now)**: the app downloads the entire transaction history per load (`transaction_provider.dart` line 177, no range); `recalculate_budgets` and `list_plans` scan all transactions; `getSettlementV2` is re-fetched on every dashboard rebuild (`dashboard_screen.dart` line 853, `FutureBuilder` with the future created in `build`). Fine at 4 households; paginate and cache before ~50.

### 4.3 Release process (rule 06 Argon loop)
Two-stage external audit per PR with a full unified diff in a Markdown bundle is appropriate for schema/money/permission changes and heavy for copy, UI and docs changes. Suggest: tiered gate — "money/schema/auth" → full audit; everything else → analyzer + tests + self-review. Effort S (rule text). Risk: none.

### 4.4 Test strategy cost — keep vs. slim
Counts: pytest 611 tests (~11.9k lines), Flutter 505 (~11.6k lines), e2e 67 (~2.9k lines + PostgREST download), SQL 26 files (~6.5k lines), migrations ~9.9k lines.
- **Keep**: SQL proof tests (money invariants, RLS, roles) — they are the product's safety net; hermetic pytest for parsers, cycles, settlement, Nafaqah; the l10n guard test; the 109-vector cycle parity fixture.
- **Slim**: e2e suite → run only before a release (it duplicates many pytest assertions); Flutter widget tests that assert copy strings (brittle); pytest files that re-test the same regression from three angles (`test_fable_*`, `test_fable_r2_*`, e2e `test_08/09`) — consolidate per feature.
- **Add**: one golden-path UI test (sign up → household → first expense → hero shows a number) — the thing the current suites do not cover.

---

## 5. Growth & retention

- **Onboarding friction**: email + password + confirmation mail (`login_screen.dart`); no Google/Apple sign-in, no phone OTP (Saudi users expect Nafath-style or OTP flows; Apple sign-in is mandatory on iOS if any third-party login is added). Add Google + Apple via Supabase Auth. Effort S/M.
- **Invitations**: 8–16-char code typed by hand (`household_screen.dart`); `share_plus` exists but is only used for the PDF. Add "Share invite" (WhatsApp text with a `https://budget.fmsco.com.sa/join/<code>` link + QR in the household card) and handle the link on open. Effort S/M. Impact: the household's second member is the whole value proposition in family/roommate mode.
- **Retention hooks**: none today (no notifications, no weekly summary, no streaks). R11 covers the basics; add a Friday weekly summary notification and a payday "cycle closed: you saved X" moment that feeds a savings goal (R5).
- **Monetization fit**: the "VIP early access" form (`/public/inquiries`) is a waitlist, not a plan. Right for the stage. Natural paid tiers later: receipts beyond N/month, multi-household, exports, shared-roommate groups above 3. Do not gate anything before notifications and onboarding are fixed.
- **Localization reach / Urdu users**: in Saudi, Urdu speakers are mostly Pakistani expatriates — a large share are drivers, domestic workers, construction and shop staff, plus a professional class (doctors, engineers, accountants) and families. Their realities: cash salary, bachelor shared housing (roommate mode fits well), monthly **remittances** home (no category), Iqama/visa fees (exists), WhatsApp as the only channel. The UI is translated (1,206 keys × 3), speech locale `ur_PK` is wired, but the chat system prompt has **no Urdu examples** and the heuristic parser has **no Urdu cues**, so Urdu input quality is untested; the Urdu support prompt is machine-flavoured. Recommendation: add 5–6 Urdu examples to `SYSTEM_PROMPT`, Urdu amount words/cues to the heuristic, a remittance category, and a WhatsApp-first invite — but do not invest further in Urdu until a real cohort exists.
- **Landing page**: jargon-heavy ("12 Pillars of Financial Governance", "Telemetry HUD", "Sovereign Access Seat") with invented metrics. Replace with three plain benefits in Arabic, real screenshots, and the Nafaqah story, which is the genuinely differentiated feature.

---

## Prioritised roadmap

**Next 2 weeks (small, high leverage)**
1. Backups + Sentry + uptime ping (R-ops; owner action). S.
2. Local notifications: payday check-in, bill due, installment due, cycle-ends-in-3-days (R11). M.
3. Fix BNPL schedule (bi-weekly Tabby/Tamara, `frequency` + `next_due_at`) (R10). S/M.
4. Single LLM call per expense; OCR temperature 0.2; parse before upload (R6, R9). S/M.
5. Remove: mock offline OCR draft, dead "ingestion channels" and "duplicate policy" settings, duplicated dashboard shortcuts, `SalaryCycleWidget` (R3, R8). S.
6. Taxonomy refresh (housing, education, domestic help, family support/charity, transport, insurance, remittance) (R4). S.
7. Share invite via share sheet + join link (R-growth). S/M.

**Next 2 months**
8. Starter wizard + income-based "left until payday" hero (R1, R2). M.
9. Dashboard to 5 cards; Tools screen for simulator/accounts/exports; park price intelligence (R3). M.
10. Savings goals / sinking funds fed by the rollover sweep; Ramadan/Eid seasonal override (R5). M.
11. Screenshot import via Android share intent reusing `/agent/scan-receipt` (fast capture without SMS). M.
12. Nafaqah polish: optional allowance wording for working wives, "her own money" option, child allowance tracking card, allowance-transfer type (2.3). M.
13. Roommates: weighted shares, join/leave cutoffs with a frozen final statement (2.4). M.
14. Reallocation becomes a prompt, not automatic; cycles labelled by dates; delete the "copy previous" dialog (2.2). S/M.
15. Migrations re-baseline + staging project + CLI apply; pre-push gate; tiered audit rule (R13, 4.3). M.
16. Google/Apple sign-in. S/M.
17. Privacy notice naming the LLM processor; move to Vertex/paid tier (R12). S/M.

**Later (when > ~100 households or a partner appears)**
18. Open Banking read-only via a licensed TPP (Lean/Tarabut); FCM push; WhatsApp deep links; Zakat helper on account balances.
19. Consolidate schema (drop `budgets.month`, `users.household_id`/`financial_role` caches, legacy note parsing after backfill); move deterministic reads into Postgres functions behind RLS; integer money end to end.
20. Pagination and caching (feed, settlement, installments).
21. Drop the wearable roadmap item.

## Stop doing / remove
- The offline receipt "draft" that always produces "Al Othaim, 85 SAR" (`flutter_app/lib/services/ocr/local_ocr_service.dart`).
- Calling the LLM twice per expense/receipt (`chat_parser.py` line 588; `receipt_scanner.py` lines 605–615).
- Three landing-page implementations (`web_app/`, `landing_page/`, `ai_service/_build_landing.py`); the "12 pillars / 99.4% / AES-256 / Sovereign" copy.
- JSON-file and in-memory fallbacks in the API container (`supabase_client.py` `HOUSEHOLD_SETTINGS_FILE`, `HOUSEHOLD_INVITES_FILE`; `dependents_service._memory_dependents`).
- Regex reconstruction of installment plans and attribution from `raw_sms` notes (one-time backfill, then delete).
- Silent flexible-budget raiding on insert.
- "Expense ingestion channels" and "Duplicate resolution policy" sections in settings; the 7-item speed dial (keep 3).
- Price Tracker / Smart Basket on the dashboard until there is data.
- Full-diff external audit for non-money, non-schema changes.
- The support chatbot's hard-coded "27th payday / Iqama 400 SAR" facts (make it read household settings or drop the bot).
- Adding roadmap features (wearables, FX feeds) before notifications, onboarding and backups exist.
