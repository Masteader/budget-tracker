# Social Engine Design

**Date:** 2026-11-03, owner decisions applied 2026-11-04
**Status:** Owner-reviewed design. The ten open decisions were accepted on 2026-11-04 and are now in the decision log (Section 2). The implementation plan is `docs/PLAN.md`. **Brand name chosen (Qawam Money / قوام المال) but not shown as vetted, and no logo yet: nothing public can happen until the launch gate in Section 13 is met.**
**Author:** Claude Code (Opus 5.5), from the recovered Antigravity brainstorm plus corrections verified on 2026-11-03.
**Location:** Everything for this project lives in `marketing/social_engine/`. Heavy media and runtime data live outside OneDrive (Section 4).

**Sensitive:** yes, because the engine handles API tokens and secrets (`.env*`) and performs outward-facing publishing.

Round 3 review (Fable, effort high) applies when this is implemented, on top of Rounds 1 and 2, per `.agents/rules/06-pr-and-audit-pipeline.md` and `docs/sensitive.md`.

**How to read the tags.** External facts were checked on 2026-11-03 unless a date is given. `[verify]` means it could not be confirmed, or rests on a vendor or secondary source, and must be checked before relying on it. Effort and usage figures marked "estimate" are planning guesses, not measurements.

---

## 1. Goal and non-goals

### Goal

On each scheduled day (3 reels a week at first, then daily once stable, D24) the engine researches a money topic, writes a short script with Claude, generates a voiceover, renders a modern 9:16 reel from real app clips and motion graphics, and sends it to the owner on Telegram. Nothing goes out without the owner tapping approve on that exact reel. The reels should stop the scroll in the first 3 seconds and look premium.

Language: Saudi/GCC Arabic voiceover with English on-screen text and subtitles. 1 reel in 5 has English audio (D28).
Market: Saudi Arabia is where we launch, not the only audience. Content mix is 50% global, 30% regional Arab, 20% Saudi launch.

### Success looks like

- A reel reaches the owner's Telegram with no manual work after the clips are recorded.
- Every product statement in it is true and traceable to the app (Section 6.5).
- One reel can never be posted twice, even after a crash or restart (Section 3.5).
- No real financial data ever appears in a reel (Section 5.2).
- No reel carries an unapproved brand (Section 13).

### Non-goals

- Changing any app code or app identifiers (`com.budgettracker` and the like stay). Renaming the app's display names in the Flutter app, `web_app` and `ai_service` belongs to the app rename, owned by session `budget-tracker-02` on `feat/qawam-money-branding` and `feat/qawam-money-backend`. It is referenced here and not specified.
- Reading from or writing to any Supabase project, or calling `ai_service`.
- Automatic posting without a per-post approval tap, at any phase.
- Urdu reels. Rule 03's trilingual requirement covers the app and web. The reel languages are the owner's decision.
- Static image posts, comment replies, DMs, paid ads and influencer management.
- Running in the cloud. The engine runs on the owner's Windows laptop.
- Fully scraping platform "algorithms". We start from hypotheses and revise them from our own results.

---

## 2. Decision log

| # | Decision | By | Source | Status |
|---|---|---|---|---|
| D1 | **Brand name is `Qawam Money` / `قوام المال`.** Meaning: قوام is moderate spending, between waste and stinginess. Tagline: لا إسراف ولا تقتير / Spend in balance. There is no Urdu-script form; Urdu uses the English letters. Always use the full name (G18). History: the earlier name `Wafeer وفيير` and its V4 logo (`flutter_app/assets/images/wafeer_logo.png`) were withdrawn on 2026-11-03, because a licensed Saudi personal finance app already uses that name. Neither that logo nor the withdrawn launcher icons may be used as assets, even in tests. The new logo is not ready. Display names change while identifiers such as `com.budgettracker` stay. | Owner, relayed from session `budget-tracker-02` | Replaces the transcript's name | Name chosen. Vetting not shown as done and logo pending, so the launch gate stays closed |
| D2 | Hybrid architecture: Python automates and orchestrates; Remotion (React) renders. Chosen for modern, eye-catching visuals and a strong hook. | Owner | Transcript | Final |
| D3 | Approval over Telegram bot. Nothing publishes without an explicit per-post tap. | Owner | Transcript | Final |
| D4 | Saudi/GCC Arabic voiceover, English on-screen text and subtitles, sometimes English audio. | Owner | Transcript | Final |
| D5 | Mix is 50% global, 30% regional Arab, 20% Saudi launch. `saudi_finance_topics.json` becomes `finance_topics_repository.json`. | Owner | Transcript | Final |
| D6 | Three templates: Feature in Action, Daily Money Hack, Stop Doing This. Four-zone canvas. Kinetic word captions and audio ducking. | Owner | Transcript Section 3 | Final, with colour and frame corrections in Section 8 |
| D7 | ChatTTS rejected because it has no Arabic. | Owner | Transcript | Final |
| D8 | **Azure Speech is the only voice tool: one tool, not two.** Edge-TTS is rejected because it is an unofficial module over Microsoft Edge's read-aloud service, with a [commercial-terms risk](https://learn.microsoft.com/en-us/answers/questions/2088770/are-opensource-edge-tts-free-for-commercial-use) for advertising. The owner creates the Azure account personally. | Owner | Owner decision 2026-11-03, overriding the transcript's Edge-TTS choice | Final |
| D9 | Claude only, never Gemini, anywhere in this pipeline. The transcript's Gemini and LiteLLM mentions are overruled. | Owner | Transcript chunk 1 and 2 | Final |
| D10 | Default LLM route is headless Claude Code (`claude -p`) on the Max plan, run on the laptop. Anthropic API key stays a config alternative, model configurable. | Owner | Brief | Final for Phase 0, with the limit stated in Section 6.3. Unattended runs move to an API key (D20) |
| D11 | Ayrshare at $29/mo as the Phase 2 publisher. | Transcript agent | Transcript | Overruled: Ayrshare Premium is $149/mo. Publisher is provider-agnostic (Section 10) |
| D12 | `publishing_mode: telegram_only` is the Phase 1 default. | Brief | Corrected | Final for Phase 1. The Phase 2 route is D21 |
| D13 | Posting windows and doubled payday-week frequency. | Transcript agent | Transcript | Downgraded to untested hypotheses in config |
| D14 | "Pixel-perfect 60 FPS". | Transcript agent | Transcript | Downgraded: 30 FPS default, 60 optional (Section 8.6) |
| D15 | Gold highlight `#C9933B`. | Transcript agent | Transcript | Overruled: not a brand colour. Zero matches in the repository. Use Rose Gold `#E598B0` (Section 8.5) |
| D16 | iPhone/Android bezel in the device mockup. | Transcript agent | Transcript | Changed to a generic device frame until a real iOS build exists, then an iPhone frame is allowed (D31). `flutter_app/ios/` does not exist in the repository today and the app is in early access |
| D17 | Raw media under `assets/` inside the repo. | Transcript agent | Transcript Section 1 | Corrected: heavy media moves outside OneDrive (Section 4) |
| D18 | ElevenLabs is only a possible later paid upgrade behind the provider interface. Not a Phase 1 option. | Owner | Owner decision 2026-11-03 | Final |
| D19 | **Azure tier.** Paid S0 for audio in public reels. Free F0 for tests and the bake-off (Section 7.3). | Owner | Owner decision 2026-11-04, former open decision 1 | Final |
| D20 | **Claude auth.** Max login for Phase 0. Once the job runs unattended, an API key from a Console organization linked to Max, using the $100 monthly credits (Section 6.3). | Owner | Owner decision 2026-11-04, former open decision 2 | Final |
| D21 | **Publisher.** `telegram_only` first, then real test posts on Zernio and Upload-Post. The choice is made on those results (Section 10). | Owner | Owner decision 2026-11-04, former open decision 3 | Final |
| D22 | **Demo data.** A separate demo login with fake data, created by hand by the owner through the app (Section 5.2). | Owner | Owner decision 2026-11-04, former open decision 4 | Final |
| D23 | **Final clips** are recorded after the rename ships in the app. The launch gate still applies to them. Clips before that are test clips. | Owner | Owner decision 2026-11-04, former open decision 5 | Final |
| D24 | **Cadence.** 3 reels a week, then daily once stable. The owner makes that change in config (Section 10.5). | Owner | Owner decision 2026-11-04, former open decision 6 | Final |
| D25 | **Music.** None first, then a licensed library, after reading its licence. | Owner | Owner decision 2026-11-04, former open decision 7 | Final |
| D26 | **CTA is "coming soon".** All social profiles and reels are prepared for early access. `cta.mode: coming_soon` is the default, with the wording in Section 6.7. No links, store badges, or download or "link in bio" wording while `cta.landing_url` is empty. The mode moves to `early_access` when a landing URL exists. This replaces the earlier brand-tag-only recommendation. Preparing a profile means its wording is ready: registering handles still waits for the launch gate. | Owner | Owner decision 2026-11-04, changed from the spec's recommendation, former open decision 8 | Final. The wording in Section 6.7 was drafted to carry out this decision, for the owner to read on review |
| D27 | **Operator.** The owner, personally, as an individual. Remotion's free tier should apply (Section 8.1). L3 is updated for this, with no legal conclusion drawn. | Owner | Owner decision 2026-11-04, former open decision 9 | Final |
| D28 | **English audio.** 1 reel in 5 (`content.english_audio_share: 0.2`). | Owner | Owner decision 2026-11-04, former open decision 10 | Final |
| D29 | **No banks.** There is no bank feature or comparison. No bank names, bank comparison or bank SMS contrast anywhere in scripts, seed topics, templates or asset lists (G20). | Owner | Owner decision 2026-11-04 | Final |
| D30 | **Smart Basket may be filmed.** The owner keeps the hard-coded prices for now and films clips with them, to be fixed later. A separate task adds the code marker in `ai_service/price_tracker.py`; this engine does not edit that file. Safeguards on any public clip: real store names and logos are masked or not legible, an `illustrative prices / أسعار توضيحية` label is on screen, and no script or caption claims real savings or that a named store is cheaper (G19). | Owner for filming. Safeguards from the orchestrator | Owner decision 2026-11-04 | Filming: final. Safeguards: flagged to the owner, who may overrule them |
| D31 | **iOS.** The owner wants the project made ready for iOS, in a separate task. The generic device frame in D16 stays until a real iOS build exists, then an iPhone frame is allowed. | Owner | Owner decision 2026-11-04 | Final |
| D32 | **Dropped claims.** The 30% figures, "3 clicks", a fixed 27th and "link in bio" are out of all examples and seeds. Price tracking may only be described as using line items from your own receipts, not the ZATCA QR. All are enforced through the rejected claims in Section 6.5. | Owner | Owner decision 2026-11-04 | Final |
| D33 | **Two transitive parsers in the Remotion lockfile.** `@remotion/openai-whisper` and `@remotion/elevenlabs` 4.0.540 may appear in `remotion_studio/package-lock.json` and nowhere else, because `@remotion/studio` depends on them. Each only parses a transcript it is handed: no network call, no API key, no install script. Neither is in the studio's `package.json` or `src/`. This changes nothing in D8 or D18: Azure stays the only voice provider. Enforced by `tests/test_boundaries.py`. | Orchestrator | Package source read 2026-11-04 | Applied. Owner to confirm, because the boundary test names any widening as an owner decision |
| D34 | **Research uses `--output-format stream-json --verbose`.** This departs from the command shape in Section 6.3, which gives `json`. The `json` format carries no tool log, and Section 6.4 needs one to prove a URL was fetched. Writing and review have no tools, so they stay on `json`. The stream's `system/init` event also shows which tools and MCP servers the run was given, and the run fails closed on anything it cannot read: a tool or server outside the list, a missing list, or an unknown content block. | Implementer | Review finding, 2026-11-04 | Applied. Flags and event shapes stay subject to LIVE-2 |
| D35 | **Figures and product statements are checked by what they must match.** Word lists cannot catch everything, especially in dialect, so G2 and G1 are allowlists first and lists second (Section 6.5). The engine alone adds the closing line, disclaimer and disclosure, so a general tip with no claim ids passes G1, and a script says each line once. Seeds g021 and g022 no longer name 50/30/20, because that rule cannot be explained without the 30% that R01 refuses. | Orchestrator | Review findings, 2026-11-04 | Applied. Owner reviews the seeds at LIVE-6 |

---

## 3. Architecture and end-to-end flow

### 3.1 The pieces

| Part | Language | Job |
|---|---|---|
| `core/` | Python | Config, paths, state store, locking, logging, the `tick` loop |
| `phone_capture/` | Python | Android demo mode, screen recording over `adb`, ingesting manual clips |
| `content_engine/` | Python | Topic choice, research and scripting through Claude, guardrails, voice providers, word timing |
| `remotion_studio/` | TypeScript/React | Templates and rendering, called by Python |
| `approval/` | Python | Telegram bot, the only way a reel gets approved |
| `publisher/` | Python | Scheduling and the provider-agnostic publisher interface |

Python calls Remotion as a subprocess with a validated JSON props file. There is no server, no web UI and no shared database with the app.

### 3.2 Daily flow

```
Task Scheduler ── every 30 min ──► engine tick (single instance, safe to re-run)
                                       │
 1 Choose topic   finance_topics_repository.json + rolling 50/30/20 mix
 2 Research       claude -p with web tools only → cited facts as JSON
 3 Write script   claude -p → hook, body, CTA, captions, claim IDs
 4 Guardrails     deterministic checks, then a separate Claude review
                  fail → blocked_guardrails → one notice, nothing sent as a reel
 5 Voice          provider from config → audio + word timings
 6 Render         Remotion with allow-listed clips → MP4 → conform → size check
 7 Telegram       video, captions, sources, guardrail report, buttons
                                       │
                               owner taps a button
          ┌─────────────┬──────────────┼────────────────┐
       Reject      Regenerate       Approve        (no tap)
                  new revision    scheduled       expired after 72 h
                  back to step 3      │
 8 Publish at window. Phase 1: bot sends the ready-to-post package and the owner
   uploads by hand, then taps Posted per platform. Phase 2: publisher adapter.
```

### 3.3 Reel state machine

A reel has one reel-level state. Each target platform also has its own row (Section 3.4).

```
 draft ──► blocked_guardrails ──(regenerate within limit)──► draft
   │
   ▼
 voiced ──► rendered ──► awaiting_approval ──► rejected   (terminal)
                               │  │  │
                               │  │  └──► expired         (terminal, can be revived by /requeue)
                               │  └─────► regenerating ──► draft (revision + 1)
                               ▼
                           approved ──► scheduled ──► publishing ──► posted (terminal)
                                                          │
                                                          └──► needs_attention

 Any step before approval on repeated error ──► failed (retry budget used up)
```

| From | To | Trigger | Actor |
|---|---|---|---|
| (none) | `draft` | `tick` picks a topic and writes research and script | Engine |
| `draft` | `blocked_guardrails` | Any hard guardrail fails | Engine |
| `draft` | `voiced` | Guardrails pass and audio plus timings are stored | Engine |
| `voiced` | `rendered` | MP4 passes conform and size checks | Engine |
| `rendered` | `awaiting_approval` | Live reel only, launch gate met, and Telegram confirms the message was sent | Engine |
| `rendered` | `test_delivered` | Test reel, sent to Telegram with no Approve button. Terminal | Engine |
| `awaiting_approval` | `approved` | Approve tap from owner, reel revision and file hash match | Owner only |
| `awaiting_approval` | `regenerating` | Regenerate tap, within regeneration limit | Owner only |
| `awaiting_approval` | `rejected` | Reject tap | Owner only |
| `awaiting_approval` | `expired` | No tap in `approval.expire_after_hours` (default 72) | Engine |
| `approved` | `scheduled` | Next posting window assigned | Engine |
| `scheduled` | `publishing` | Window arrives | Engine |
| `publishing` | `posted` | All target platforms are `posted` or `skipped` | Engine or owner |
| `publishing` | `needs_attention` | Any platform is `failed` or `unknown_outcome` | Engine |
| `needs_attention` | `publishing` | Owner taps Retry on a platform that is `failed` | Owner only |
| `needs_attention` | `posted` | Owner confirms outcome for every platform | Owner only |

**Invariants, enforced in code and covered by tests:**

1. The only code path to `approved` is the Telegram callback handler, after the owner check. No CLI flag, config value or test hook skips it.
2. An approval is bound to `reel_id`, `revision` and the SHA-256 of the MP4. The publisher re-hashes the file before every send. A mismatch sends the reel back to `awaiting_approval`.
3. A stale button (old revision) does nothing except show "this version is out of date".
4. Regenerating creates a new revision and invalidates all older approvals.
5. `posted`, `rejected` are terminal. Nothing leaves them.
6. A reel voiced on Azure F0 cannot move to `approved` while `voice.allow_public_on_f0` is false (Section 7.3).
7. A test reel can never become `approved`. In `live` mode, a reel cannot be rendered, offered for approval or published while the brand gate fails. The callback handler and the publisher both re-check this (Section 13).

### 3.4 State store

SQLite at `%LOCALAPPDATA%\SocialEngine\state\engine.db`, WAL mode, outside OneDrive. OneDrive syncing a live database risks corruption and lock errors.

- `reels`: `reel_id`, `state`, `revision`, `tier`, `template`, `topic_id`, `target_duration`, `created_at`, `content_hash`, `mp4_path`, `mp4_sha256`.
- `approvals`: `reel_id`, `revision`, `mp4_sha256`, `telegram_user_id`, `action`, `callback_query_id` (unique), `at`.
- `platform_posts`: `reel_id`, `platform`, `status` (`pending`, `in_flight`, `posted`, `failed`, `unknown_outcome`, `skipped`), `idempotency_key`, `remote_id`, `attempts`, `posted_at`. **Unique on (`reel_id`, `platform`).**
- `runs`: one row per scheduled day and step, with a unique key, so a re-run finds work already done.
- `events`: append-only audit log of every transition.

Every transition is a compare-and-swap inside a transaction: `UPDATE reels SET state = :new WHERE reel_id = :id AND state = :old`. Zero rows changed means someone else got there first, and the handler stops.

### 3.5 Windows reliability

**Scheduling.** The laptop is the server. If it is off or asleep, nothing runs.

| Task Scheduler task | Trigger | Settings |
|---|---|---|
| `SocialEngine-Tick` | At logon, then repeat every 30 min | `MultipleInstances` = ignore new; `StartWhenAvailable` on; stop after 2 h; run only when the user is logged on, so it can reach `%USERPROFILE%\.claude` and stores no Windows password |
| `SocialEngine-Bot` | At logon | Long-running poller; `RestartCount` and `RestartInterval` set for automatic restart; no time limit |

Setting names are from Microsoft's [TaskSettings reference](https://learn.microsoft.com/en-us/windows/win32/taskschd/tasksettings). By default a task is stopped after 72 hours, so the bot's limit has to be turned off explicitly. Use absolute paths for `python`, `claude` and `node` because Task Scheduler does not load a user shell. Laptop power settings must be checked: sleep on lid close stops everything (see Section 15).

**Why a repeating `tick` rather than a once-a-day job.** Each tick asks the state store "what is due now?" and does the next step. Missing a scheduled time then needs no special handling.

**Missed-run behaviour.**

| Situation | Behaviour |
|---|---|
| Laptop off during the generation time | Next tick generates the reel for the latest due slot in the cadence (D24). Missed earlier slots are not backfilled: at most one new reel per slot and never more than `reels_per_week` in a week, so no pile of stale reels arrives |
| Laptop off when a posting window passes | The reel is never posted late on its own. It moves to the next window and the bot says so |
| Owner taps while the laptop is off | Telegram holds updates, but [not for longer than 24 hours](https://core.telegram.org/bots/api). On startup the bot processes pending taps normally. A tap older than that is lost, and the reel stays in `awaiting_approval`, so the buttons still work once the bot is back |
| No tap for 72 hours | `expired`. Stops the queue from clogging. `/requeue <id>` revives it |
| Several reels waiting | Generation pauses while `approval.max_waiting` (default 3) reels are unanswered, to save Claude usage |

**Retries and idempotency.**

| Step | Retry | Why re-running is safe |
|---|---|---|
| Research and script | 3 tries with growing delay, then `failed` and one Telegram notice | Output stored only when schema-valid. A usage-limit error is not counted as a failure; it waits for a later tick |
| Voice | 3 tries with growing delay on 429 and server errors, as [Microsoft advises](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/speech-services-quotas-and-limits), then `failed` and one notice. No other provider is tried | Files keyed by a hash of script text, voice, region and tier |
| Render | 2 tries | `content_hash` covers props, clip hashes, template version and audio. Same hash reuses the file. Render goes to a temp name and is renamed only after checks pass |
| Telegram send | 5 tries with growing delay | The state moves only after Telegram confirms |
| Publish | **Never automatic after a request may have reached the provider** | See below |

**Double-post protection.**

1. Before calling a provider, set the platform row to `in_flight` and commit.
2. Call the provider with `idempotency_key = sha256(reel_id + platform)` if it supports one.
3. On success, store `remote_id` and set `posted`.
4. On a definite rejection, set `failed`.
5. On a crash, timeout or unclear answer, set `unknown_outcome`.

At startup, any row still `in_flight` becomes `unknown_outcome`. The bot asks the owner to check that platform and tap Posted or Retry. **The engine never retries an unknown outcome by itself.** A rare duplicate is worse than a rare manual check.

A lock file plus `MultipleInstances` stops overlapping ticks. Telegram itself returns a conflict if two pollers run, which the bot treats as fatal and reports in the log.

**Timezone.** All schedule logic uses `Asia/Riyadh` with Python `zoneinfo`. Windows has no system timezone database, so the `tzdata` package is a required dependency.

---

## 4. Folder structure

Code, config and docs are in the repo. Heavy and private data are not.

```
marketing/social_engine/                     # in git, in OneDrive
├── README.md                                # setup guide, written in the later plan
├── docs/SPEC.md                             # this file
├── docs/PLAN.md                             # implementation plan
├── config.yaml                              # no secrets
├── .env.example                             # placeholders only
├── .gitignore
├── pyproject.toml
├── core/                                    # config, paths, state, locks, tick
├── phone_capture/
│   └── capture_cli.py
├── content_engine/
│   ├── finance_topics_repository.json       # renamed from saudi_finance_topics.json
│   ├── approved_claims.json                 # product claims and their evidence
│   ├── researcher.py                        # Claude research and scripting
│   ├── llm_backends.py                      # claude_cli and anthropic_api
│   ├── guardrails.py
│   ├── voiceover_engine.py                  # provider interface
│   └── voice_providers/azure_speech.py      # the only provider in Phase 1
├── remotion_studio/
│   ├── package.json
│   ├── package-lock.json
│   └── src/
│       ├── compositions/                    # FeatureDemo, DailyTip, MythVsFact
│       ├── components/                      # device frame, kinetic captions, HUD
│       └── Root.tsx
├── approval/
│   └── telegram_bot.py
├── publisher/
│   ├── scheduler.py                         # windows, from config
│   ├── base.py                              # publisher interface
│   └── telegram_only.py
├── assets/
│   └── branding/
│       ├── brand_tokens.json                # colours, from velvet_burgundy_theme.dart
│       ├── test_logo.svg                    # plain "TEST" mark, for test reels only
│       └── fonts/                           # Cairo, Outfit, each with its OFL.txt
├── scheduling/                              # Task Scheduler XML definitions
└── tests/

%LOCALAPPDATA%\SocialEngine\           # data_root; NOT in OneDrive, NOT in git
├── .env                                     # real secrets, entered by the owner
├── venv\                                    # Python environment
├── remotion_work\                           # build copy of remotion_studio + node_modules
├── assets\
│   ├── raw_recordings\                      # the folder the owner drops clips into
│   │   ├── payday_cycle\
│   │   ├── zatca_receipt_scan\
│   │   ├── receipt_photo_scan\
│   │   ├── chat_and_voice_entry\
│   │   ├── multi_account_ledger\
│   │   ├── budget_capacity\
│   │   ├── nafaqah_wife_expenses\
│   │   ├── roommate_debt_split\
│   │   ├── recurring_and_installments\
│   │   ├── price_tracker\
│   │   ├── smart_basket\
│   │   └── app_experience\
│   ├── screenshots\
│   ├── manifest.json                        # per-file hash and privacy sign-off
│   └── audio\
│       ├── bg_music\                        # licensed tracks only
│       └── voiceovers\                      # audio + timing JSON
├── renders\
├── state\engine.db
├── claude_cwd\                              # empty working folder for claude -p
└── logs\
```

`data_root` is configurable in case the C: drive is short of space.

**Node modules and OneDrive.** Thousands of small files under `node_modules` would sync constantly. The rule: `npm` only ever runs in `remotion_work\`. Before a render, the engine copies `src/`, `package.json`, `package-lock.json` and config from the repo into `remotion_work\`, runs `npm ci` only if the lockfile changed, and renders from there. Pre-flight fails with a clear message if `marketing/social_engine/remotion_studio/node_modules` exists. A junction is a possible alternative, but how OneDrive treats junctions needs checking `[verify]`, so the copy is the default.

**`marketing/social_engine/.gitignore`** (needed because the root file has no `node_modules/` or `.venv/`, and covers `.env` but not `.env.*`):

```gitignore
.env
.env.*
!.env.example
.venv/
__pycache__/
node_modules/
out/
output/
assets/raw_recordings/
assets/screenshots/
assets/audio/
*.mp4
*.mov
*.m4a
*.mp3
*.wav
*.db
*.db-wal
*.db-shm
logs/
```

A test asserts these patterns with `git check-ignore` on sample paths.

**Logo.** `brand.logo_path` is empty by default. Test reels use `assets/branding/test_logo.svg`, a plain "TEST" mark with no real name. Once a logo is approved, the owner sets the path and the render step copies the file into `remotion_work\public\` at build time. Config validation rejects the withdrawn logo and launcher icons (D1).

**Retention.** Automatic deletion is off by default because rule 06 requires asking before deleting data. The bot reports disk use weekly, and the owner decides.

---

## 5. Phone capture pipeline and asset shot list

### 5.1 How capture works

The owner connects an Android phone with USB debugging on, then runs:

```
python capture_cli.py --feature zatca_receipt_scan
```

1. **Find adb.** `adb` is not on PATH on this laptop. It exists at `%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe`, which becomes the default `capture.adb_path`.
2. **Check the phone.** Exactly one device, authorised. Print the pre-capture checklist (5.3) and wait for the owner to confirm.
3. **Turn on demo mode**, using [Android's documented commands](https://android.googlesource.com/platform/frameworks/base/+/master/packages/SystemUI/docs/demo_mode.md):
   ```
   adb shell settings put global sysui_demo_allowed 1
   adb shell am broadcast -a com.android.systemui.demo -e command enter
   adb shell am broadcast -a com.android.systemui.demo -e command clock -e hhmm 0941
   adb shell am broadcast -a com.android.systemui.demo -e command battery -e level 100
   adb shell am broadcast -a com.android.systemui.demo -e command network -e wifi show -e level 4
   adb shell am broadcast -a com.android.systemui.demo -e command notifications -e visible false
   ```
   Demo mode always exits in a `finally` block, with `-e command exit`. Some phone makers may ignore parts of it, so this is tested on the owner's actual phone in Phase 0 `[verify]`.
4. **Record** after a 3-2-1 countdown: `adb shell screenrecord /sdcard/social_engine_tmp.mp4`.
5. **Stop** on Enter, then pull the file, delete it from the phone, and save it as `raw_recordings/<feature>/clip_NN.mp4`.
6. **Sign off.** The owner watches the clip and confirms it is privacy-clean. Only then is it added to `manifest.json` as `privacy_checked: true`.

**Limits from the [adb docs](https://developer.android.com/tools/adb):** recording stops at 3 minutes at most, audio is not recorded, default bit rate is 20 Mbps, some phones cannot record at native resolution, and rotating the screen during recording cuts off part of the picture. Keep each clip under 60 seconds and portrait.

**Stopping a recording on Windows.** Ctrl+C on `adb shell` from Windows may leave an unfinished file `[verify]`. The default is a second adb call that sends an interrupt to `screenrecord` on the phone, followed by a short wait. This is a Phase 0 test.

**Trimming and FFmpeg.** `ffmpeg` is not installed and does not need to be. Remotion [ships FFmpeg](https://www.remotion.dev/docs/cli/ffmpeg) through `npx remotion ffmpeg`, built for its supported codecs (H.264, H.265, VP8, VP9, ProRes). Trimming, conforming and metadata stripping use that binary from `remotion_work\`.

**Manual fallback.** If capture does not work on the phone, the owner records with the phone's own screen recorder and drops files into the feature folder under `raw_recordings\`. Then `python capture_cli.py --ingest` hashes each file, strips metadata by re-encoding, shows the checklist and asks for sign-off. Files without sign-off cannot be rendered. iPhone recordings are not relevant until a real iOS build exists (D31): `flutter_app/ios/` does not exist today.

### 5.2 Privacy rules

- Recordings use a **dedicated demo household with fake data**, never the owner's real finances.
- Use a **separate login**, not a second household on the real account. The app's household switcher could otherwise show or expose the real household mid-clip.
- The owner creates and fills the demo household by hand in the app. **The engine never touches Supabase**, including to seed demo data.
- Demo names, amounts, merchants, phone numbers and emails are invented. Amounts must follow the app's real ledger rules, so the status badges shown are ones the app really produced.
- Receipts on camera are sample receipts made for the demo, not real ones. A real receipt carries a real merchant, a real VAT number and real purchases. Any sample QR must use an obviously fake seller name.
- Render inputs are allow-listed: only files in `manifest.json` with `privacy_checked: true` and a matching hash. Render props have a strict schema with no free-form fields for account data. The renderer has no network access to app data.

The owner chose this route (D22). The cost is some fake rows in the live database, created only through the app, by the owner.

### 5.3 Pre-capture checklist

Shown in the terminal before every capture session. The owner has to confirm each line.

- [ ] Logged in to the demo account only, not the real account.
- [ ] Household switcher shows only the demo household.
- [ ] Do Not Disturb is on; no messages or calls can pop up.
- [ ] Demo-mode status bar is showing (or the bar will be cropped out).
- [ ] App language and theme match what this shot needs.
- [ ] No real name, photo, email, phone number or IBAN is visible anywhere, including settings and the profile screen.
- [ ] No bank name or logo in the frame, ever (D29).
- [ ] No real merchant or store name or logo in the frame unless legal check L4 is cleared. The one exception is a `smart_basket` clip, where the names on screen are masked at render (D30).
- [ ] Debug banners and test toasts are off.
- [ ] For a final clip: the launch gate is met and the build on screen says Qawam Money / قوام المال. On the base of this branch, the Android label and app title still say "Budget Tracker" and the Arabic title says "ميزانية الأسرة". Until then, clips are test clips only (D23).

### 5.4 Shot list by feature

Claim IDs refer to Section 6.5. Durations are estimates. Record each in Arabic first; record English again only where marked.

| Folder | Clips to record | Demo data needed | Claims | Length |
|---|---|---|---|---|
| `payday_cycle` | Dashboard payday hero and days left. Change payday in settings from 27 to another day, to show it is per household. Payday check-in sheet. Salary distribution proposal | Admin login, salary, 2 to 3 accounts | C01, C02, C03 | 4 clips, 10-20 s each |
| `payday_cycle` | Rollover rule settings with all three options | As above | C04 | 10 s |
| `zatca_receipt_scan` | Point scanner at sample QR, show seller, VAT number, time, total and VAT filled in | Sample QR with fake seller | C05 | 15 s |
| `receipt_photo_scan` | Photograph a sample receipt, review extracted line items, save | Sample receipt | C06 | 20 s |
| `chat_and_voice_entry` | Type a dialect phrase and confirm the expense card. Same by voice | Fake phrase and fake merchant | C07, C08 | 2 clips, 15 s each (English too) |
| `multi_account_ledger` | Accounts list with a main account, wallet and cash, named generically. Privacy eye toggle. A transfer. Reconciliation | Accounts named "Main Account", "Wallet", "Cash" | C09 | 4 clips, 10 s each |
| `budget_capacity` | Budget linked to an account, status badge changes between Zero-Based, Surplus and Deficit, Quick Transfer | Amounts set to produce each status | C10 | 3 clips, 10-15 s each |
| `nafaqah_wife_expenses` | Family mode expense entry with three choices, wife reimbursement balance and a repayment, wife allowance with allocated, spent, remaining | Family demo household with spouse role and a named Nafaqah provider | C11 | 3 clips, 15 s each |
| `roommate_debt_split` | Roommate household, equal split, simplified debts, copy settle message | Roommate demo household, 3 or more members | C12 | 3 clips, 15 s each |
| `recurring_and_installments` | Recurring bill candidates. Installment plan with remaining count and next due date | Several monthly bills. Generic plan name | C13, C14 | 2 clips, 15 s each |
| `price_tracker` | Item price history across several own receipts, with the price-change label | Many saved demo receipts with line items | C15 | 15 s |
| `smart_basket` | Smart Basket sheet: add a demo shopping list and show the comparison. Hard-coded prices stay as they are (D30) | Demo list. Mask regions covering every store name, logo and "cheapest store" line, recorded in `manifest.json` | C21 | 15 s |
| `app_experience` | Language switch to show RTL. Light and dark mode. Offline entry then sync. Can-I-afford-it card | Same demo account | C16, C17, C19 | 4 clips, 10 s each |

**The Smart Basket store comparison may be filmed, under the owner's decision (D30).** The prices in it are hard-coded for now. On any public clip the store names and logos are masked or not legible and the illustrative prices label is on screen (G19). The app's own screen shows a cheapest store and a saving, so the mask has to cover the store name on those lines as well. See the Smart Basket row in Section 6.6.

Screenshots: one clean PNG of each main screen in light and dark, saved to `screenshots\`, using `adb exec-out screencap -p` under the same checklist.

---

## 6. Content strategy, research, scripts and guardrails

### 6.1 Topic mix

`finance_topics_repository.json` holds topics tagged by tier, region, season, template fit and the app feature they lead to (if any). Target: about 100 seed topics, reviewed by the owner. The scheduler keeps a rolling 30-reel mix within a few points of 50/30/20.

| Tier | Share | Topics |
|---|---|---|
| Tier 1 Global | 50% | Stopping paycheck-to-paycheck, supermarket traps and grocery budgeting, three-part splits versus zero-based, recurring subscriptions, emergency and sinking funds, fair rent and utility splits between roommates |
| Tier 2 Regional Arab | 30% | Ramadan and Eid surges, social pressure spending on gifts and weddings, expat remittances and transfer fees, household maintenance and Nafaqah handled per Section 6.5 |
| Tier 3 Saudi launch | 20% | Getting through the salary cycle, using VAT QR receipts, tracking several accounts and wallets by hand |

Topics are education first. Mentioning the app is allowed only through an approved claim. Topics may teach an idea the app does not implement, such as a three-part salary split, as long as the script does not imply that the app does it. A topic with no claim ids is a general tip, and its script says nothing about the app. The engine still adds the closing line.

Seed topics carry no bank names or bank comparisons (D29), so a transfer-fee topic stays general, with no named bank, exchange house or wallet. No seed uses a 30% figure, a click count, a fixed 27th or "link in bio" (D32).

### 6.2 Script shape

Claude returns JSON matching a schema. Target structure, from the approved brainstorm:

| Part | Time | Purpose |
|---|---|---|
| Hook | 0-3 s | Relatable pain, e.g. "راتبك وين يروح كل شهر؟" |
| Problem | 3-15 s | The trap, in plain language |
| `{brand}` | 15-30 s | One feature that helps, from `approved_claims.json` |
| CTA | 30-35 s | From config, `coming_soon` by default (Section 6.7), gated on the URL by G11. The engine adds it after the script's text, so the writer never writes it |

Scripts never contain a brand name. Claude writes the tokens `{brand_ar}`, `{brand_en}` and `{brand_hashtag}`, and the engine fills them from config at voice and render time. Schema fields: `topic_id`, `tier`, `template`, `language`, `hook_ar`, `voice_script`, `on_screen_en[]`, `subtitles_en`, `feature_clip_folder`, `claim_ids[]`, `numbers[]` (each number with a source URL), `sources[]`, `caption_ar`, `caption_en`, `hashtags[]`, `speech_seconds_estimate`.

**Length check.** An informal single-sentence test made before the Azure decision ran about 57 characters in about 6.5 seconds, or roughly 9 characters per second. That suggests 270 to 400 characters for a 30-45 s reel. It is one sample on a different service, so re-measure on Azure in S2, then enforce before voice generation and again against real audio length.

### 6.3 Claude: what it can do on the Max plan, and the limit

**Rule.** Claude only. No Gemini, no LiteLLM, no other provider, in code, config or dependencies. A test fails the build if such names appear in `marketing/social_engine/` outside this document. Note that the *app's own* AI service uses Gemini by default ([rule 01](../../../.agents/rules/01-architecture-and-tech-stack.md)). This pipeline neither calls it nor describes it.

**What the docs say:**

- `claude -p` is the documented [non-interactive mode](https://code.claude.com/docs/en/headless), with JSON output and a `--json-schema` option that returns validated `structured_output`. It exits non-zero on failure, and failures inside a run appear in the result on stdout, so the engine must check for `structured_output` and not rely on exit code alone.
- Signed in with Max, [`claude -p` draws from the plan's usage limits](https://support.claude.com/en/articles/15036540-use-the-claude-agent-sdk-with-your-claude-plan) (support article, updated 2026-10-07). The separate Agent SDK credit announced earlier is paused.
- So the daily job **shares one allowance with the owner's own Claude Code work**. Heavy days could block the job, and the job takes a little from those days.
- Anthropic's [legal page](https://code.claude.com/docs/en/legal-and-compliance) says advertised limits "assume ordinary, individual usage", that subscription login is "designed to support ordinary use of Claude Code", and that developers building products should use API keys.
- The [Consumer Terms](https://www.anthropic.com/legal/consumer-terms) (effective 2025-10-08) prohibit automated or non-human access such as through a script, "except when you are accessing our Services via an Anthropic API Key or where we otherwise explicitly permit it".
- Anthropic documents `claude -p` and a one-year `claude setup-token` [for "CI pipelines, scripts"](https://code.claude.com/docs/en/authentication), which reads as permission for scripting. But I found no page that says a scheduled, unattended marketing job on a Max login is fine.

**The limit, plainly.** It works today and it is low volume, one person on their own laptop. It is not explicitly blessed for scheduled unattended use, it competes with interactive work, and login can expire with nobody watching. This is not a legal conclusion. If it matters, ask Anthropic.

**The cleaner route with no new cost.** [Max includes $100 per month of API credits](https://support.claude.com/en/articles/17154008-monthly-api-credits-for-max-ultra-and-team-plans) when linked to a Console organization, which also cover `claude -p` when run with an API key. API-key access is the Terms' stated exception. Credits do not roll over, requests stop when they run out unless credits were bought, usage is never charged to the plan, the plan must be active for 7 days first, and only one organization can be linked. The owner chose this route for when the job runs unattended (D20).

**One more reason to plan for an API key.** The docs say [`--bare` "will become the default for `-p` in a future release"](https://code.claude.com/docs/en/headless), and bare mode reads neither subscription login nor `CLAUDE_CODE_OAUTH_TOKEN`. A future update could stop a subscription-based job working. So the engine pins the Claude Code version, runs a pre-flight check before each scheduled day, and reports a clear error.

**Config:**

```yaml
llm:
  backend: claude_cli       # claude_cli | anthropic_api
  auth: subscription        # claude_cli only: subscription | api_key. Phase 0 only; a scheduled run refuses subscription (D20)
  model: opus               # alias or full model name, owner can change
  claude_path: ""           # absolute path, required under Task Scheduler
  max_turns: 12
  max_budget_usd: 2.00      # enforced for api_key use
```

**Default command shape** (exact flags confirmed against the [CLI reference](https://code.claude.com/docs/en/cli-reference); empty `--setting-sources` value checked in Phase 0 `[verify]`):

```
claude -p <prompt> --model <model> --output-format json --json-schema <schema>
       --tools "WebSearch,WebFetch" --allowedTools "WebSearch,WebFetch"
       --permission-prompts none --strict-mcp-config --setting-sources ""
       --no-session-persistence --max-turns <n>
```

Research uses `--output-format stream-json --verbose` in place of `json`, for its tool log (D34).

**Isolation requirements, each with a test:**

1. Run with the working directory set to the empty `claude_cwd\`, never the repo. A non-bare `-p` run [loads hooks, `.mcp.json` servers and CLAUDE.md without any trust prompt](https://code.claude.com/docs/en/headless). Running inside the repo would pull in the project's agents rules and any configured MCP server.
2. `--strict-mcp-config` with no servers, so no user-level MCP server (including any Supabase MCP) connects. This enforces "the engine never reaches Supabase".
3. Tools limited to web search and fetch for research, and to none for script writing and guardrail review. No Bash, no file access.
4. Start the subprocess with a **scrubbed environment**. Remove `TELEGRAM_BOT_TOKEN`, `AZURE_SPEECH_KEY`, `AZURE_SPEECH_REGION`, every `SUPABASE_*`. Remove `ANTHROPIC_API_KEY` unless `auth: api_key`, because [`-p` always uses that key when it is present](https://code.claude.com/docs/en/authentication), which would silently bill the API instead of the plan.
5. Web pages are untrusted input. They can contain instructions aimed at the model. Tool limits, schema validation and guardrails contain this, and research output is treated as data.

**Failure handling.** Usage limit reached: wait for a later tick, send one Telegram notice. Login expired: send one notice telling the owner to run `/login`. Credentials on Windows are at `%USERPROFILE%\.claude\.credentials.json`, which is why the task runs as the logged-in user.

**`anthropic_api` backend.** Uses the official `anthropic` Python SDK directly with the server-side `web_search_20260209` tool, structured outputs and `ANTHROPIC_API_KEY`. Same prompts, same schemas. No model outside Claude is accepted by config validation.

### 6.4 Research output

Research returns structured facts, not prose:

```json
{"facts":[{"claim":"...","source_url":"https://...","publisher":"...",
           "accessed":"2026-11-03","paraphrase_ar":"...","paraphrase_en":"..."}]}
```

- Every fact has a real URL that was actually fetched in that run. A URL not seen in the run's tool log fails the check.
- Scripts paraphrase. A copy check compares script text with fetched excerpts and fails on a long overlap (`guardrails.max_copied_words`, default 12 consecutive words).
- Every figure in a fact must also be in the text returned for the URL that fact cites. At most 8 facts and 10,000 characters of research go on, because both later steps carry them on one Windows command line.
- Sources appear in the Telegram message so the owner can check them.

**What the copy check can and cannot prove.** Under `claude_cli`, WebFetch does not return the page. A small model reads the page and returns its answer to the prompt the research session gave it, so an excerpt is a summary written by a model. So the checks prove less than they appear to:

| Check | What a pass proves | What it cannot prove |
|---|---|---|
| URL in the tool log | The run fetched that URL, and the fetch returned success | That the page says what the fact says |
| No long overlap with an excerpt (G3) | The script and the facts copy no long run from what WebFetch returned | That they copy nothing from the page. A passage the summary reworded is invisible here |
| Figure in the excerpt | The summary holds the same number | That the page does, because a model may have misread it or a page may have instructed it |

The `anthropic_api` route gets the fetched text itself, so its copy check does compare with the page, although a page can still be wrong. On either route the facts are model output, and web pages can carry instructions. The separate review and the owner reading the sources on Telegram cover what these checks cannot.

### 6.5 Guardrails

Run **before anything reaches Telegram**. Three layers:

1. **Deterministic checks** in `guardrails.py`, on Arabic and English text. Hard fails block the reel.
2. **Separate Claude review.** A new session with no memory of the writing step checks the script against this section and the research facts, and returns pass or fail with reasons. Catches meaning the word lists miss, especially in dialect, and figures or facts the script bends. A verdict that passes but lists a problem counts as a fail.
3. **The owner**, on Telegram. The message shows claims used, numbers with sources and any soft flags.

| ID | Rule | Check | Level |
|---|---|---|---|
| G1 | Product statements must match what the app does | Each product statement maps to an approved claim ID. A sentence that names the app, or opens on a verb with the app as its unspoken subject, needs a claim id, and at least half of what it says must come from the wording of the claims the script names. The closing line is not a product statement. Wording stays within the claim's allowed meaning, which the Claude review checks | Hard |
| G2 | No unverifiable numbers | Any percentage, money amount, multiplier, or bare number of 100 or more must match, in value and unit, a fact from the URL it cites in `numbers[]`, or an approved claim the script uses, or carry a visible "example" label in its own sentence. Anything else is refused. An entry in `numbers[]` that no fact from its URL states also fails. "Save 30%" fails | Hard |
| G3 | Research is cited, not copied | Section 6.4 | Hard |
| G4 | No SMS-reading implication (Zero SMS) | Lexicon: SMS, رسائل البنك, رسالة البنك, "reads your messages", "auto-imports from your bank". The only allowed mention is the approved claim that the app does not read SMS | Hard |
| G5 | Payday is per household | Never "the 27th" as a fixed fact about the app. Allowed: "your household's payday", or "the default is the 27th, and you can change it". `#راتب_27`, "Payday 27th HUD" and "27th-to-27th" fail | Hard |
| G6 | No spousal percentage split | Lexicon near husband or wife terms: 50/50, نص بنص, مناصفة, percentages, "split with your wife/husband". Split language is roommate-only | Hard |
| G7 | Family messaging follows rules 1 to 4 | Nafaqah is the husband's responsibility. Wife paying for something shared is a debt he owes her. Her personal spending comes from her allowance, set by the husband or an admin, never by her. A wife's contribution is voluntary and never assumed. Never imply she should pay | Hard, plus Claude review |
| G8 | No promotion of interest-based products | Lexicon: loans, credit offers, APR, قرض, فوائد, بطاقة ائتمان, savings "interest". Neutral warnings get a soft flag for the owner. Tracking a BNPL plan is not recommending BNPL | Hard if promotional |
| G9 | No personalised financial advice | No "you should invest in X" or "buy this". Tips are general. A short disclaimer is in `config.yaml` for captions | Hard |
| G10 | No certification or endorsement claims | No "Sharia-certified", "halal-approved", "ZATCA-approved" or "SAMA-licensed". Nothing in the repo supports these | Hard |
| G11 | Availability and CTA | `cta.mode` defaults to `coming_soon` (D26). While `cta.landing_url` is empty: no URL, no link wording, no store badge or app store name, and no "download", "install", "available now" or "link in bio" in any language, in scripts, captions, on-screen text, hashtags or bios. Bios and CTA lines use only the approved wording in Section 6.7. Config refuses `early_access` or `store` with an empty URL, and refuses `coming_soon` once a URL is set, so the move is an explicit owner edit. The landing page's own FAQ says the mobile app is in early access | Hard |
| G12 | Brand comes from config only | Scripts use `{brand_*}` tokens. Arabic text shows `{brand_ar} {brand_en}`, English text shows `{brand_en} {brand_ar}`. A hard-coded name, the withdrawn name (D1), `BudgetTracker` and `#BudgetTracker` all fail | Hard |
| G13 | No competitor or store comparisons | No named bank, chain or app shown as better or cheaper. Smart Basket clips follow G19 | Hard |
| G14 | No privacy overclaim | Receipt photos go to an AI service on the server. The landing page names Google Gemini as the processor. "Never leaves your phone" and "no AI sees your receipts" fail. QR decoding on the device may be stated as such | Hard |
| G15 | Clips | `privacy_checked: true` and the hash matches | Hard |
| G18 | Always the full name, clearly about money | Because قوام alone can also mean body shape: `قوام` (with or without an attached prefix such as بـ or لـ) must be followed by `المال`, and `Qawam` by `Money`, in captions, hashtags, handles, on-screen text and voiceover. `#قوام`, `@qawam` and "Qawam" alone fail. Copy must be clearly about money: body-shape words near the name (رشاقة, الجسم, وزن, fitness, slim) fail, and the Claude review checks the meaning. `قوامة`, a different word, gets a soft flag in family scripts | Hard |
| G16 | Reel uses only allowed brand colours and fonts | Token check at render, `#C9933B` is banned | Hard |
| G17 | The synthetic voice is disclosed | Caption contains the configured disclosure line, and the posting package lists each platform's AI-label step. [Microsoft's Code of Conduct requires disclosure](https://learn.microsoft.com/en-us/legal/ai-code-of-conduct) | Hard |
| G19 | Smart Basket safeguards (D30) | On any public clip: real store names and logos are masked or not legible, and `illustrative prices / أسعار توضيحية` stays on screen while the clip shows. No script or caption claims real savings or that a named store is cheaper. Checks: render refuses a `smart_basket` clip without mask regions and the owner's mask sign-off in `manifest.json`; the composition always draws the label for that folder; a lexicon fails the store names and any saving or cheaper claim tied to the basket. Whether a mask is really unreadable is the owner's check, at sign-off and at the approval tap | Hard. The owner may overrule the safeguards, which then needs a spec and test change |
| G20 | No banks (D29) | No bank or wallet names, no comparison with banks, and no contrast with bank SMS, in scripts, seeds, templates or asset lists. The plain word "bank" or "بنك" gets a soft flag for the owner | Hard |
| G21 | Price tracking source (D32) | Price tracking is described only as using line items from your own receipts. QR or ZATCA terms tied to price, inflation or tracking fail, and so does "market prices" | Hard |
| G22 | No click counts (D32) | "3 clicks", "3 نقرات" or any other click or tap count fails, since none has been measured | Hard |

**Approved claims register.** `approved_claims.json` is the only source of product statements. Each entry has allowed wording in Arabic and English, evidence paths, and a date last checked against code. The plan must re-verify every row against code, because `docs/PROJECT_DETAILS.md` was last verified on 2026-10-20.

| ID | Allowed meaning | Evidence |
|---|---|---|
| C01 | Budgets follow your household's payday, not the calendar month. Default is the 27th, an admin can change it | PROJECT_DETAILS 3.2, rule 02 §1 |
| C02 | On payday the app prompts you to record salary, overtime and bonuses | 3.2 |
| C03 | The app can propose transfers from the salary account to under-funded accounts. It proposes; it does not move money on its own | 3.2 |
| C04 | The household chooses what happens to leftovers: savings (default), roll into categories, or fresh start | 3.2 |
| C05 | The app decodes the QR on Saudi e-invoices on the device: seller, VAT number, time, total and VAT amount. The QR has no line items | 3.4, rule 02 §2 |
| C06 | Photograph a receipt and AI reads merchant, date, payment method and line items. You review before saving | 3.4 |
| C07 | Type an expense in everyday Arabic, English or Urdu and confirm it | 3.5 |
| C08 | Speak an expense; speech-to-text runs on the device | 3.5 |
| C09 | Add accounts, wallets, cash and crypto **by hand**, with balances you can reconcile, and hide balances with a privacy eye. Never implies any bank feature or bank link (D29) | 3.1 |
| C10 | Link a budget to the account that funds it and see Zero-Based, Surplus or Deficit status, with a quick transfer suggestion | 3.3, rule 02 §4 |
| C11 | Family mode: shared expenses are the husband's; what the wife pays for shared needs is tracked as a debt he owes her; her personal spending comes from her allowance | 3.6, rule 02 §3 |
| C12 | Roommates: equal splits, simplified debts, shared pools, a settle message you can copy | 3.6 |
| C13 | Finds monthly recurring payments in your history and reserves them against the next payday | 3.7 |
| C14 | Tracks installment plans: remaining count, amount and next due date. Tracking only | 3.7 |
| C15 | Shows how the price of an item you bought changed, using the line items from **your own** saved receipts, not the ZATCA QR. More useful after many scans | `ai_service/price_tracker.py`, `tool_price_tracker_desc` |
| C16 | Keep logging offline; entries sync when you reconnect | 3.10 |
| C17 | Arabic first with right-to-left layout, plus English and Urdu | 3.13 |
| C18 | The app does not read your SMS | 3.14, rule 04 §1 |
| C19 | Check whether a purchase fits your budget before you buy | 3.5 |
| C20 | Export a PDF statement | §5 of PROJECT_DETAILS |
| C21 | Smart Basket compares a shopping list across stores inside the app. In a reel it is shown as a feature, with its prices called illustrative. Never a real saving, never a cheaper store, never live or market prices (D30, G19) | `ai_service/price_tracker.py` `optimize_shopping_basket`, `smart_shopping_basket_sheet.dart`, `tool_smart_basket_desc` |

**Rejected claims register.** `approved_claims.json` also holds a `rejected_claims` list, so a dropped claim stays enforced rather than just absent (D32). Each entry has its failing samples in Arabic and English and the guardrail that catches it. A test fails if a rejected claim has no failing sample, or if any sample passes.

| ID | Rejected claim | Caught by |
|---|---|---|
| R01 | Any 30% figure, such as "save 30%" or "costs you 30% more" | G2 |
| R02 | "3 clicks" or any other click or tap count | G22 |
| R03 | A fixed 27th: "the 27th" as a fact about the app, "27th-to-27th", `#راتب_27` | G5 |
| R04 | "Link in bio", or download wording, while `cta.landing_url` is empty | G11 |
| R05 | Price tracking through the ZATCA QR, or against market prices | G21 |
| R06 | Bank names, bank comparison, or contrast with bank SMS | G4, G20 |
| R07 | A real saving from Smart Basket, or a named store being cheaper | G13, G19 |

### 6.6 Transcript claims checked

| Transcript text | Finding | What to do |
|---|---|---|
| "Scanning digital ZATCA tax receipts to spot price inflation" | **Half true, wrong mechanism.** The app has a price tracker with an "inflation" percentage (`price_tracker.py`, `grocery_price_intelligence_screen.dart`), but it compares your own saved line items, first price against latest. Line items come from receipt OCR or chat. The ZATCA QR holds only seller, VAT number, time, total and VAT. No market data. Alerts are only planned (v1.2) | Use C15. Never link QR scanning to inflation, never say "market prices". G21, R05 |
| "Tracking multiple bank/e-wallet accounts", with four named banks and wallets | **Dropped.** Accounts are hand-entered with a free-text name, and any bank name is only a hint in a text field. There is no bank feature (D29). Roadmap items are not claims. Also a trademark issue | Use C09 and generic names. G20 |
| "Why grocery shopping without an envelope budget costs you 30% more" and "كيف توفر 30% من مقاضي البيت؟" | **Invented number.** No source | G2. Rewritten in Section 9 |
| "Demonstrates the app feature solving it in 3 clicks" | **Dropped.** Not measured for any feature | Do not state click counts. G22, R02 |
| "Payday cycle 27", "Payday 27th HUD", "27th-to-27th", `#راتب_27` | **Wrong.** Payday is per household, default 27th | G5. Folder renamed `payday_cycle` |
| "Messy notes and unorganized bank SMS" versus the app, in Template C | **Risky.** Suggests the app handles bank SMS | G4. Use "messy notes and memory" |
| "Link in bio", "high app downloads" | **Not yet true.** The landing page says early access. No store listing is referenced in the repo. The site does not carry an approved brand name | Dropped. G11, R04, D26. Bios and captions use the coming-soon wording in Section 6.7 |
| "Zero-based liquidity ledger" | Supported, but it is jargon | Plain wording under C10 |
| "Smart envelope budgeting in `{brand}`" | Supported in substance. English strings use "envelopes" | Fine, under C10 |
| "Transparent family maintenance (Nafaqah / household allowance)" | Supported only in the exact sense of C11 | G6, G7 |
| "Sleek iPhone/Android bezel", "or an iPhone" | **Unsupported.** No `flutter_app/ios/` in the repo | Generic device frame until a real iOS build exists (D31) |
| "Saudi voices sound human", "indistinguishable from a real creator" | **Unproven** | Voice bake-off, Section 7.5 |
| Smart Basket (not claimed in the transcript, but the obvious next idea) | **Trap, accepted for now by the owner.** `optimize_shopping_basket` falls back to hard-coded `BENCHMARK_STORE_PRICES` for Panda, Danube, Tamimi, Othaim and Lulu, then to a made-up default of 20 SAR. These are not live prices. Showing "store X is cheaper" would be a false comparison with real brands | Filming is allowed under the owner's decision (D30), to be fixed later. Use C21 only. G19 applies: names and logos masked or not legible, the illustrative prices label on screen, no real savings or cheaper-store claim. L9 |

### 6.7 Caption and disclaimer defaults

`config.yaml` holds the tagline (لا إسراف ولا تقتير / Spend in balance), the disclaimer line, the synthetic-voice disclosure line (G17, for example "صوت مولّد بالذكاء الاصطناعي · AI-generated voice"), the CTA text and hashtag rules. Hashtags must be relevant, and we do not borrow trending tags that have nothing to do with the reel. Hashtag counts per platform are a hypothesis to test.

**CTA and bio wording (D26, G11).** While `cta.mode` is `coming_soon`, these are the only CTA and bio strings allowed. The engine fills the tokens from config and adds nothing to them. Bios are written so the profiles are ready, and registering handles still waits for the launch gate (Section 13).

```yaml
cta:
  mode: coming_soon        # coming_soon | early_access | store
  landing_url: null        # empty means no link of any kind
  coming_soon:
    bio_ar: "{brand_ar} {brand_en} · لا إسراف ولا تقتير · قريبًا: الوصول المبكر"
    bio_en: "{brand_en} {brand_ar} · Spend in balance · Early access coming soon"
    caption_ar: "{brand_ar} {brand_en} قريبًا. نجهّز الوصول المبكر."
    caption_en: "{brand_en} {brand_ar} is coming soon. Early access is on the way."
    voice_ar: "{brand_ar}، قريبًا."
    voice_en: "{brand_en}, coming soon."
  early_access: null       # owner adds wording with the URL; config refuses the mode without both
```

| Mode | Needs | Allows |
|---|---|---|
| `coming_soon` (default) | `landing_url` empty | The strings above. No links, store badges, or download or "link in bio" wording |
| `early_access` | A public landing URL under the new name, plus owner-approved wording | Early-access wording and the link |
| `store` | A real store listing and URL | Store wording and badges |

---

## 7. Voice engine

**One tool: Azure Speech.** The owner chose this and rejected Edge-TTS (decision D8). The owner creates the Azure account personally and enters the key and region. Agents never create the account or handle the key.

### 7.1 Provider interface

The engine talks to voices through one small interface, so any later change stays in one file. Phase 1 ships exactly one implementation.

```python
class VoiceProvider(Protocol):
    name: str
    def synthesize(self, text: str, voice: str, language: str) -> VoiceResult: ...

@dataclass
class VoiceResult:
    audio_path: Path               # 48 kHz, normalised before use
    words: list[TimedWord]         # text, start_ms, end_ms, aligned to the script
    provider: str
    voice: str
    azure_tier: str                # F0 or S0, recorded with the reel
    billable_characters: int
```

```yaml
voice:
  provider: azure_speech          # only value accepted in Phase 1
  azure_tier: F0                  # F0 | S0, must match the resource you created
  arabic_voice: ar-SA-HamedNeural # set by the bake-off
  english_voice: ""               # set by the bake-off
  rate: "0%"
  pitch: "0%"
  output_format: riff-48khz-16bit-mono-pcm
  monthly_char_cap: 400000        # engine stops itself below the free 500,000
  allow_public_on_f0: false       # see 7.3
```

Config validation rejects any other provider. There is no fallback provider: if Azure is down, the voice step waits and the bot says so.

**ElevenLabs** stays only as a possible later paid upgrade behind this interface. It is not a Phase 1 option, no adapter is built, and no key is requested. If it is ever added: the Starter plan is [$6/mo with a commercial licence listed](https://elevenlabs.io/pricing), the free tier lists none, Arabic is listed as ["Arabic (Saudi Arabia, UAE)"](https://elevenlabs.io/docs/overview/capabilities/text-to-speech), dialect quality is unconfirmed, and timing is [character-level](https://elevenlabs.io/docs/api-reference/text-to-speech/convert-with-timestamps), so an adapter must group characters into words.

### 7.2 What Microsoft's docs confirm

| Question | Answer | Source |
|---|---|---|
| Do the Saudi voices exist in Azure Speech? | **Yes.** `ar-SA-HamedNeural` (male) and `ar-SA-ZariyahNeural` (female) | [Language support](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/language-support?tabs=tts) |
| Do they have styles or roles? | **No.** Both are "Standard" type with the Style/Roles column empty. No ar-SA HD voice is listed either | Same page |
| Which regions offer them? | **The docs do not list regions per voice.** They tick "Neural text to speech" for all 33 listed regions and say nothing that excludes these two voices. No Saudi region is listed. **Use `uaenorth`,** the listed Middle East region, and confirm in Phase 0 by calling [`voices/list`](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/rest-text-to-speech) on your own resource | [Regions](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/regions) |
| Why does the region matter? | Keys only work in their own region. Microsoft says most 429 errors on standard voices come from capacity for that voice in that region, and suggests a voice's native region. Scripts are stored and processed in the region of the resource | [Quotas](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/speech-services-quotas-and-limits), Regions |
| Other Gulf voices? | ar-AE, ar-KW, ar-QA, ar-BH and ar-OM each list one female and one male standard voice | Language support |
| Pronunciation control? | Full SSML, including `<sub>`. ar-SA carries no "phonemes not supported" footnote, so phonemes and a custom lexicon appear to be available `[verify]` | [Pronunciation](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/speech-synthesis-markup-pronunciation) |
| Audio quality? | 48 kHz output is available, for example `riff-48khz-16bit-mono-pcm` | [REST reference](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/rest-text-to-speech) |
| Python SDK? | `azure-cognitiveservices-speech` 1.53.0 has a `py3-none-win_amd64` wheel. It installed on Python 3.14 here, but import failed from a very long test folder path with "filename too long" (WinError 206), so a short `data_root` path matters. Retest in S7 `[verify]`. May need the Visual C++ Redistributable | [Quickstart](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/get-started-text-to-speech), [PyPI](https://pypi.org/project/azure-cognitiveservices-speech/) |

### 7.3 Azure facts for the owner

| Question | Plain answer | Confidence |
|---|---|---|
| **Does signup need a card?** | **Yes.** ["All you need is a phone number, a credit card or a debit card (non-prepaid), and a Microsoft account or a GitHub account."](https://azure.microsoft.com/en-us/pricing/purchase-options/azure-account) Nothing is charged at signup. A temporary one-dollar verification hold may appear and is removed | Microsoft page |
| **What about after 30 days?** | The free account's $200 credit lasts 30 days. Then Microsoft asks you to move to pay-as-you-go. ["If you don't, your account and services will be disabled."](https://azure.microsoft.com/en-us/pricing/purchase-options/azure-account) If you do, you keep the free services. So plan for this step around day 30. Speech is listed under "Always" free services at 0.5M neural characters a month | Microsoft page |
| **F0 character limit** | [0.5 million neural characters per month](https://azure.microsoft.com/en-us/pricing/details/speech/). HD voices are not listed in the free tier. At about 400 characters a take, that is about 1,250 takes | Microsoft page |
| **F0 speed limit** | [20 transactions per 60 seconds, not adjustable](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/speech-services-quotas-and-limits). 10 minutes of audio per request. Batch synthesis is not available on F0. The docs state this as a rate. They list a concurrency limit of 1 only for speech-to-text, not text-to-speech. Our engine sends one request at a time, so this does not matter | Microsoft docs |
| **What happens when the free allowance runs out?** | **Probably stops, but this is not officially confirmed.** A [Microsoft-staff moderator](https://learn.microsoft.com/en-us/answers/questions/5566384/azure-ai-speech-what-happens-after-free-tier-t0-ex) says Azure "will not automatically start charging you" and requests are rejected until the next month. Another [Microsoft employee's answer](https://learn.microsoft.com/en-us/answers/questions/2149864/why-am-i-not-able-to-use-the-free-quota-of-0-5-mil) says "you may be charged for additional usage". The free account page says exceeding free amounts is billed at pay-as-you-go rates, though that is about the account rather than an F0 resource. `[verify]` with Azure support. Our protection does not depend on the answer: the engine stops at `monthly_char_cap` (400,000), well below the limit | Conflicting, forum answers |
| **Do F0 terms allow commercial use such as marketing videos?** | **Not expressly. Treat as no.** The [Microsoft Product Terms](https://www.microsoft.com/licensing/terms/en-US/productoffering/MicrosoftAzure/OL) say: "For Customers of the paid tier TTS Service only, Customer may use the audio output of prebuilt neural voices generated using the TTS Service, including for commercial purposes." I read this on the terms page on 2026-11-03. Every forum answer I opened reads it the same way, including a [Microsoft employee](https://learn.microsoft.com/en-us/answers/questions/2124037/can-i-use-azure-text-to-speech-to-generate-mp3-for), [Microsoft external staff](https://learn.microsoft.com/en-ca/answers/questions/6045956/can-i-use-azure-tts-prebuilt-neural-voices-free-f0) and [moderators](https://learn.microsoft.com/en-ca/answers/questions/5805156/please-clarify-the-conflicting-information-regardi). Not legal advice | Terms read directly |
| **Paid price if needed** | **[$15 per million neural characters](https://prices.azure.com/api/retail/prices?$filter=contains(productName,'Speech')%20and%20armRegionName%20eq%20'uaenorth')** in `uaenorth` and `eastus`, per Azure's retail price list. The pricing page shows blanks when fetched, and the [quotas page](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/speech-services-quotas-and-limits) also uses $15. That is $0.006 per 400-character take, or about **$0.36 for 60 takes a month** | Microsoft price list |
| **Must we disclose the voice is AI?** | **Yes.** Microsoft's [Code of Conduct](https://learn.microsoft.com/en-us/legal/ai-code-of-conduct) requires customers to disclose "the synthetic nature of generated voices", and bans false advertising. Guardrail G17 and the caption default cover this. The owner's review before posting also fits its review requirement for AI-generated video | Microsoft page |

**What this means.** The free tier is fine for prototypes, tests and the bake-off. **Audio for public reels should come from a paid (S0) resource,** which costs cents a month at this volume. The owner chose this (D19).

Because `allow_public_on_f0: false`, a reel voiced on F0 is labelled "TEST AUDIO, not for posting" in Telegram, and its Approve button is replaced by "Re-voice on paid tier". Moving from F0 to S0 may [take several hours to update quotas](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/speech-services-quotas-and-limits). A paid resource has no monthly cap from Microsoft that I could confirm, so `monthly_char_cap` stays on, and the owner sets a cost alert in the Azure portal `[verify]`.

**Resource type.** The Speech quickstart talks about creating an AI Services or Foundry resource, while a [forum answer](https://learn.microsoft.com/en-us/answers/questions/5644473/how-to-use-free-tier-requests-with-microsoft-found) says Foundry resources do not offer F0. In the portal, create a standalone **Speech** resource and check that the pricing tier shows **Free F0** before finishing `[verify]`.

### 7.4 Word timing (Phase 0 spike)

The Speech SDK raises a [`WordBoundary` event](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/how-to-speech-synthesis) "at the beginning of each new spoken word, punctuation, and sentence". It reports the offset in ticks (10,000 ticks = 1 ms) and a boundary type. The docs list no Arabic caveat, but also make no Arabic promise, so this needs testing.

**Spike S2, run on real Arabic scripts:**

1. Synthesize 3 full scripts with Hamed and Zariyah through the SDK, including slang, mixed English, and spoken numbers.
2. Record every event. Keep only `Word` boundaries. Drop `Punctuation` and `Sentence`.
3. Check that every script word gets exactly one event, in order, with text offsets that map back to the script.
4. Render captions over the audio and judge sync by eye and ear. **Pass:** no visible caption lag across a 40-second script.

**Aligner.** Whatever the spike shows, timed tokens are mapped back onto script tokens, so punctuation stays attached to its word in captions.

**Fallback, only if S2 fails:** forced alignment of the audio against the known script, or local Whisper, both `[verify]` for Saudi Arabic and for Python 3.14. The output format stays the same, so the render step does not change. Not built unless S2 fails.

### 7.5 Voice bake-off (Phase 0, before the voice is locked)

The claim that Saudi voices "sound human" is unproven, and written Saudi slang read by these voices may come out sounding formal. The bake-off compares **Azure voices only**, on real scripts.

- **Scripts:** 5 real ones from the engine: a slang-heavy hook, one per tier, one with English words mixed in.
- **Voices:** Hamed and Zariyah first. Then the Gulf voices in 7.2, and any multilingual voice whose `SecondaryLocaleList` in `voices/list` includes ar-SA `[verify]`. Standard voices are the priority, since HD is not in the free tier and costs more ([$22 per million in `eastus`](https://prices.azure.com/api/retail/prices?$filter=contains(productName,'Speech')%20and%20armRegionName%20eq%20'eastus')).
- **Styles:** Hamed and Zariyah have no styles, so the comparison there is prosody rather than style: speaking rate, pitch and pauses through SSML. For any candidate that does list styles, try them too.
- **Script wording:** heavy slang against lighter "white dialect". This may be the cheapest quality gain.
- **Test words:** راتب, فاتورة, مقاضي, حسبتك, "ZATCA" and spoken numbers, plus **قوام المال** and "Qawam Money". Fix errors with `<sub>` or a phoneme, and record what works in `config.yaml`.
- **Listeners:** the owner plus 2 or 3 Saudi listeners, labels hidden.
- **Score 1 to 5:** sounds Saudi, sounds human, slang natural, would you keep watching.
- **Brand check:** Azure must say قوام المال correctly, as the money word, in the chosen voice. Saudi listeners score it, and it must clear a 4. If it does not, apply a `<sub>` or phoneme fix and retest, then try another voice.
- **Decide:** the voice with the best score that passes the brand check. This audio stays private; test reels keep the test brand.

**If no Azure voice is good enough,** the bake-off reports that plainly to the owner. Changing tool would be a new owner decision, and the engine does not switch by itself.

The bake-off uses the free tier and stays private. Five scripts at about 400 characters across about 10 voice and prosody settings is about 20,000 characters (estimate), or 4% of the monthly free allowance.

---

## 8. Remotion templates, reel anatomy and Arabic rendering

### 8.1 Licence

[Remotion's licence](https://github.com/remotion-dev/remotion/blob/main/LICENSE.md), re-read on 2026-11-04, makes eligible for free use "an individual", "a for-profit organization with up to 3 employees", non-profits and anyone evaluating it, and says "Individuals and small companies are allowed to use Remotion to create videos for free (even commercial)". The owner operates this personally, as an individual (D27), so the free tier should apply. Others need a [Company License](https://www.remotion.pro/license) (price not confirmed `[verify]`). The licence notes that it will "slightly change" in Remotion 5.0, so it is re-read before any move to 5.0. The repo's default API host (`budget.fmsco.com.sa`) and default mail sender use a domain that looks like a company's. This row rests on the owner's statement and is not a legal conclusion: if a company turns out to operate the app or the channels, this licence and L3 are re-checked.

### 8.2 Canvas (approved)

1080×1920. Four zones:

```
┌──────────────────────────────────────────┐
│ [ذكاء مالي]  {brand_hashtag}             │  TOP: hook and badge (spring entry)
│  "راتبك يطير قبل يوم 15؟"                 │
├──────────────────────────────────────────┤
│        ┌────────────────────┐            │
│        │   generic device   │            │  CENTRE: device frame with app clip,
│        │   frame, app clip  │            │  tilts and zooms into the feature
│        └────────────────────┘            │
├──────────────────────────────────────────┤
│     [خطط] [ميزانيتك] [مع] [قوام المال]    │  SUBTITLES: Arabic word highlight
│    "Plan your budget with Qawam Money"   │  plus English line
├──────────────────────────────────────────┤
│ ━━━━━━━━━━━ [قوام المال Qawam Money]     │  BOTTOM HUD: progress and brand tag
└──────────────────────────────────────────┘
```

**Safe zones.** Platform buttons and captions cover parts of the screen, especially bottom and right. Exact margins need checking per platform `[verify]`. They live in `config.yaml`, and Phase 0 overlays each platform's real interface on a test frame. The bottom HUD may need to move up.

### 8.3 Templates (approved)

| Template | Length | Content | Goal |
|---|---|---|---|
| A: Feature in Action | 25-35 s | Real clip, device tilts and zooms into the feature | Teach a feature |
| B: Daily Money Hack | 30-45 s | Punchy mistake or sourced stat, 3 fast animated cards, ends with how `{brand}` helps | Saves and shares |
| C: Stop Doing This vs. The Smart Way | 15-25 s | Fast comparison: messy notes and memory versus a clear budget in `{brand}` | Retention |

**Test reels** carry a burned-in "TEST, not for posting" watermark on every frame and use the test brand from Section 11.3. B and C can run with no app clip, so a topic with no recorded feature still produces a reel.

**Smart Basket clips (D30, G19).** Any clip from the `smart_basket` folder is drawn with its mask regions blurred over the clip and the `illustrative prices / أسعار توضيحية` label on screen for as long as the clip shows. The composition does this from the clip's folder, and the props have no switch to turn it off.

**Device frame (D31).** Generic only. The props accept `generic` and nothing else until a real iOS build exists, when an iPhone frame can be added, subject to L4.

### 8.4 Arabic and RTL rendering

The main visual risk. Arabic letters change shape depending on neighbouring letters, so splitting text in the wrong place visibly breaks words.

**Rules:**

1. **Animate whole words only.** One word is one inline-block element. Never split a word into letters, and never colour part of a word.
2. **No `letter-spacing` on Arabic.** It breaks letter joins.
3. **Use the browser's text direction.** The caption container has `dir="rtl"`. Do not reverse arrays by hand. Word wrap comes from a flex container with wrap, under RTL.
4. **Mixed text uses `<bdi>`.** Latin words and numbers inside Arabic lines stay isolated, so punctuation does not jump to the wrong side.
5. **Word timing keys off script tokens** (Section 7.4), so punctuation stays attached to its word.
6. **Animate with `transform` and opacity.** Scale and glow do not re-shape text. Keep the same font and weight during the animation.
7. **Whole-word highlight.** The active word gets Rose Gold and a soft glow. Inactive words stay near-white.
8. **Load fonts before rendering any frame.** Use Remotion's font-loading wait, and fail the render if the Arabic font did not load, rather than showing a fallback font. Check the exact API at plan time `[verify]`.
9. **Captions helper.** [`createTikTokStyleCaptions`](https://www.remotion.dev/docs/captions/create-tiktok-style-captions) groups tokens into pages. Its docs say text is whitespace-sensitive, and do not mention RTL, so treat it as a Phase 0 test. Its `white-space: pre` advice may conflict with inline-block words. If it does not work with Arabic, write a small grouping function.
10. **Digits.** `captions.digits` in config, default Western digits, for clarity alongside English.
11. **Mirroring.** In Arabic reels the progress bar fills right to left, and the device tilt mirrors as well. English reels flip them.
12. **The brand is one caption token.** `قوام المال` and `Qawam Money` highlight together, stay on one caption page and never wrap across lines, so قوام is never on screen alone (G18). Timed words for the name merge into one token.
13. **Golden frames.** A small set of still frames with known hard Arabic words is rendered and compared with approved reference images. These are checked by eye once, and any later change flags a review.

**Fonts.** Use fonts the app itself uses, all under the SIL Open Font License, checked in Google Fonts' repository: [Cairo](https://github.com/google/fonts/tree/main/ofl/cairo) for Arabic (already in `flutter_app/assets/fonts/cairo/` with `OFL.txt`, weights 400, 600, 700), [Outfit](https://github.com/google/fonts/tree/main/ofl/outfit) for Latin, [Tajawal](https://github.com/google/fonts/tree/main/ofl/tajawal) as Arabic alternate. Store the files with their licence text in `assets/branding/fonts/`. The transcript's Plus Jakarta Sans is dropped because the app does not use it.

### 8.5 Brand tokens

Source of truth is `flutter_app/lib/core/theme/velvet_burgundy_theme.dart`, matching rule 03. `brand_tokens.json` copies these values, and a test compares them against the Dart file. Reels use the Velvet Burgundy mobile palette, not the Daylight Coastal web theme.

**`#C9933B` is not a brand colour.** It has zero matches anywhere in the repo. The token actually named `champagneGold` in the code is `#E598B0`. The spec replaces gold with Rose Gold.

| Token | Hex | Use in reels |
|---|---|---|
| `canvasDark` | `#110509` | Main background |
| `canvasDarkBg` | `#0A0205` | Outer edge, vignette |
| `surfaceDark` | `#1E0B12` | Cards |
| `surfaceDarkGradient` | `#240E17` to `#17080E` | Card gradient |
| `primaryLight` | `#4A0E1E` | Velvet Burgundy, badges and panels |
| `primaryDarkMaroon` | `#2A050E` | Burgundy gradient end |
| `primaryLightGradient` | `#6C162F` | Burgundy gradient top |
| `roseGold` | `#E598B0` | **Active caption word**, accents |
| `roseGoldGlow` | `#F0A3BC` | Glow |
| `accentRose` | `#B83253` | Secondary accent |
| `emeraldSafe` | `#10B981` | "The smart way", surplus |
| `coralDanger` | `#F43F5E` | "Stop doing this", deficit |
| `amberCaution` | `#F59E0B` | Caution |
| `textPrimaryDark` | `#FDF8FA` | Main text |
| `textSecondaryDark` | `#C7AEB6` | Subtitles |

Computed contrast: `#E598B0` on `#110509` is 9.0:1, `#FDF8FA` on `#110509` is 19.0:1, `#E598B0` on `#4A0E1E` is 6.9:1, and `#C7AEB6` on `#110509` is 9.7:1. All are well above the usual 4.5:1 reading target.

Style, from rule 03: 16 to 24 px rounded corners, thin borders at low opacity, soft atmospheric glows rather than heavy flat shadows. The device frame's 3D look uses CSS 3D transforms.

### 8.6 Frame rate and output

**Default 30 FPS, 60 optional per template.** Reason: all four platforms accept it, screen recordings have little to gain from 60, 30 renders much faster on a laptop, and it leaves more bits per frame under Telegram's 50 MB cap. If the Phase 0 reel looks noticeably stiff on hook animations, try 60 for Template C only.

Render target: MP4, H.264, 1080×1920, 30 FPS, AAC-LC 48 kHz stereo at 192 kbps.

**The 50 MB limit is verified.** The [Bot API](https://core.telegram.org/bots/api) says bots can send videos and documents "of up to 50 MB". The local Bot API server raises that to 2000 MB, but needs extra setup and is not worth it.

**Bitrate is calculated per reel:**

```
video_kbps = min(8000, floor(47 MB × 8000 / duration_s) − 192)
```

| Duration | Budget result | Approx. file size |
|---|---|---|
| 15 s | 8000 kbps (cap) | 15 MB |
| 35 s | 8000 kbps (cap) | 36 MB |
| 45 s | 8000 kbps (cap) | 46 MB |
| 60 s | 6074 kbps | 47 MB |

The 8000 kbps cap is a starting point, reviewed in Phase 0 on fast-moving frames. After rendering, the engine measures the real file. Over 48 MB, it re-encodes at 15% lower bitrate, up to twice, then fails rather than send something it cannot deliver.

**Conform step,** via Remotion's bundled FFmpeg: move the `moov` atom to the front and avoid edit lists, per [Instagram's spec](https://developers.facebook.com/docs/instagram-platform/instagram-graph-api/reference/ig-user/media), then check with a probe. Exact Remotion flags are confirmed at plan time `[verify]`.

**Audio polish (approved).** Background music at 12% under the voice, 25% in pauses. Values live in config. There is no music at first, and then a licensed library, after reading its licence (D25). Until then `audio.music_enabled` stays false.

---

## 9. Telegram approval bot

### 9.1 How it runs

Long polling via `python-telegram-bot` (22.8 lists Python 3.14 support [on PyPI](https://pypi.org/project/python-telegram-bot/)). No public URL or webhook needed, which suits a laptop.

### 9.2 Message

**Message 1,** video with a short caption and buttons. `sendVideo` captions are [limited to 1024 characters](https://core.telegram.org/bots/api), so the long text goes in message 2.

```
[VIDEO 1080x1920]

Reel R-2026-11-03-01 · revision 1 · Template B · Tier 1 Global
العنوان: مقاضي البيت تاكل ميزانيتك؟
Suggested window: today 20:45 Riyadh (hypothesis)
Voice: ar-SA-HamedNeural, Azure S0
Guardrails: passed · Soft flags: none

[ Approve & Schedule ]        [ Regenerate Script ]
[ Send HD File ]              [ Reject ]
```

**Message 2,** full text for checking and copying (up to [4096 characters](https://core.telegram.org/bots/api)):

```
Caption (Arabic)
مقاضي البيت تاكل ميزانيتك بدون ما تحس؟
3 خطوات بسيطة قبل لا تطلع من البيت:
1. لا تروح وأنت جيعان
2. حدد ميزانية لكل قسم في قوام المال Qawam Money
3. صور الفاتورة عشان تعرف وين راحت فلوسك
قوام المال Qawam Money قريبًا. نجهّز الوصول المبكر.

Caption (English)
Stop grocery traps. Plan by category before you shop with Qawam Money قوام المال.
Qawam Money قوام المال is coming soon. Early access is on the way.

صوت مولّد بالذكاء الاصطناعي · AI-generated voice

Hashtags: {brand_hashtag} #توفير_المال #المقاضي #SmartBudgeting
Claims used: C10, C06
Numbers: none
Sources: 1) <publisher, URL>  2) <publisher, URL>
Platform steps: AI voice label on (see L1), audio confirmation (see L2)
```

The mockup shows a live reel after the gate, with names filled from config. `{brand_hashtag}` stays a placeholder because hashtags are unset until vetting. Changes from the transcript mockup: the 30% figure, `#راتب_27`, `#BudgetTracker` and "link in bio" are gone, and the caption carries the coming-soon line from Section 6.7. "HD file" is the same MP4 sent as a document, so it saves without chat preview handling. It is not "uncompressed", and still has to fit in 50 MB.

### 9.3 Buttons

| Button | Mode | Action |
|---|---|---|
| Approve & Schedule | Live reels only, when the launch gate is met. **Never offered while the brand is unset or on a test reel** | `approved`, then next window |
| Regenerate Script | Live reels only | New revision, within `approval.max_regenerations` (default 3), to protect Claude usage |
| Reject | Live reels only | `rejected`. Optional typed reason feeds into the topic list |
| Send HD File | All | `sendDocument` |
| Re-voice on paid tier | Replaces Approve on F0 audio while `allow_public_on_f0` is false | New revision with S0 audio. Reel text is unchanged |
| Posted: Instagram, Facebook, TikTok, YouTube | `telegram_only` | Marks that platform `posted` |
| Post Now | API mode only | Asks a confirmation tap, then posts. Not shown in Phase 1, because in `telegram_only` it would do nothing |
| Retry / Already posted | When `failed` or `unknown_outcome` | Owner resolves the outcome |

A test reel has only Send HD File. `test_delivered` is terminal (Section 3.3), so to change a test reel, create a new one.

**Commands:** `/status`, `/queue`, `/pause`, `/resume`, `/requeue <id>`, `/metric <id> <platform> <views> <saves> <shares>`. `/pause` stops generation and publishing at the next tick.

### 9.4 Owner-only access

- Token lives only in `.env`. `TELEGRAM_OWNER_USER_ID` is a required number; the bot refuses to start without it.
- Every update goes through one check before any handler. For a callback query: `callback_query.from.id == owner` **and** the message's chat is a private chat with the owner. For a message: `from.id == owner` and private chat. This catches a forwarded message, or a bot added to a group.
- Anyone else gets no information: an empty `answerCallbackQuery` (required so [the client's spinner stops](https://core.telegram.org/bots/api)), no state change, no reply. The attempt is logged with a hashed user ID.
- The bot leaves any group it gets added to.
- `callback_data` format is `v1:<reel_id>:<revision>:<action>`, within the [1-64 byte limit](https://core.telegram.org/bots/api). It is never trusted alone: the handler re-reads state, re-checks the revision and does a compare-and-swap. `callback_query_id` is unique, so a double tap applies once.
- The bot token must not reach logs. `python-telegram-bot` uses `httpx`, whose info-level logs include request URLs that contain the token, so that logger is set to warning, and a log filter redacts anything shaped like a token. A test asserts this.

The owner has to send `/start` to the bot once, since bots cannot start a chat.

---

## 10. Publishing, formats and scheduling

**The route is decided (D21):** `telegram_only` first, then real test posts on Zernio and Upload-Post, with the choice made on those results. Telegram **cannot** post to other platforms: it is the approval and delivery channel only.

### 10.1 Publisher interface

```python
class Publisher(Protocol):
    name: str
    def capabilities(self) -> PublisherCapabilities: ...   # platforms, idempotency, scheduling
    def publish(self, job: PublishJob) -> PublishResult: ... # posted, failed or unknown
    def fetch_status(self, remote_id: str) -> PublishResult: ...

@dataclass
class PublishJob:
    reel_id: str
    platform: str
    video_path: Path
    video_sha256: str        # re-checked against the approval
    caption: str
    idempotency_key: str
```

`publisher/base.py` wraps every adapter with the same pre-check: a matching approval row, matching hash, not paused, platform row `pending`. An adapter cannot be called without it.

```yaml
publishing_mode: telegram_only   # telegram_only | <adapter name>
```

**Phase 1 `telegram_only`.** When the window arrives, the bot sends the MP4, copy-ready caption per platform, and the platform steps. The owner uploads by hand from the phone and taps Posted per platform. Zero social API keys. Also teaches what works before automating.

### 10.2 Phase 2 candidates

None is hard-coded, and none is chosen without a **real test post**: one private or test video to each platform, then check format, Arabic caption, AI-label options and the deletion path. Vendor figures below come from the vendors' own pages and are unverified claims. The owner named Zernio and Upload-Post for the test posts (D21). The other rows are kept for reference and need a new owner decision.

| Candidate | Price seen | Video and platforms | Status |
|---|---|---|---|
| [Upload-Post](https://www.upload-post.com/pricing/) | Basic $24/mo ($16/mo yearly): 5 profiles, unlimited uploads, TikTok included. Free: 10 uploads/mo, no TikTok | Instagram, YouTube, Facebook; TikTok on paid | Vendor claim, unverified |
| [Zernio](https://zernio.com/pricing) (formerly Late, per [a directory](https://www.everydev.ai/tools/zernio), not stated on its pricing page) | No plans. Per account: accounts 1-2 free, 3-10 at $6/mo each. Four accounts works out to $12/mo. Page says "nothing is gated behind a plan" | Page says videos on YouTube, TikTok, Reels, Facebook. One low-rated [review](https://www.capterra.ca/software/1085150/Late) mentions video errors | Vendor claim, unverified |
| Buffer API | Unconfirmed | New GraphQL API is in public beta [per one comparison](https://zernio.com/blog/buffer-api), by a competitor. Competitors say no video upload via API. Buffer's own API docs were not found | Unconfirmed |
| [Ayrshare](https://www.ayrshare.com/pricing/) | Premium **$149/mo**, Launch $299, Business $599. [Videos need a paid plan](https://www.ayrshare.com/docs/apis/post/post). [Its comparison page](https://www.ayrshare.com/compare/) says it has no free plan. Launch trial is 28 days on the pricing page, 14 in a [January 2026 update](https://www.ayrshare.com/docs/whatsnew/latest) | Broad | Price confirmed on vendor site. **Not $29** as the transcript said |
| Direct APIs | Free to call. Heavy setup per platform | See 10.3 | Possible long-term route |

### 10.3 Direct API realities

**TikTok.** Per [TikTok's content sharing guidelines](https://developers.tiktok.com/doc/content-sharing-guidelines): "Unaudited API Clients can only post contents in `SELF_ONLY` viewership" and "can allow up to 5 users to post in a 24 hour window". An audit lifts it. The guidelines also require showing the latest creator info, explicit consent before upload, and a music usage confirmation line. That has to be designed into the approve step if direct TikTok is ever used.

**Instagram.** Per [Meta's publishing guide](https://developers.facebook.com/docs/instagram-platform/content-publishing):

- Needs a professional (Business or Creator) account.
- **The Facebook Page question depends on login path.** Other sources conflict, and this seems to be why: Facebook Login for Business uses a Page access token, so a Page is needed. Instagram Login uses an Instagram token, and the guide lists no Page requirement.
- URL-based publishing needs the media "on a publicly accessible server". **A laptop has no public URL.** Local-file upload through the resumable route is "only for apps that have implemented Facebook Login for Business".
- App Review: this guide does not mention it. Meta's [permissions page](https://developers.facebook.com/docs/permissions) says App Review applies to "data that you do not own or manage", and that Business Verification is required for Advanced Access. So whether posting to one's *own* account needs review is unclear `[verify]`.
- The page gives two limits: 100 API posts per 24 hours, and 50 in its carousel section `[verify]`.

**Facebook.** [Reels publishing](https://developers.facebook.com/docs/video-api/guides/reels-publishing) works on Pages only, needs a Page token and the listed permissions, with a limit of 30 API posts per 24 hours.

**YouTube.** The [`videos.insert` page](https://developers.google.com/youtube/v3/docs/videos/insert) lists 100 calls per day and a cost of 1 unit in the Video Uploads bucket, says videos from unverified API projects "are not restricted to private viewing mode", and has a `status.containsSyntheticMedia` field. This differs from what is widely remembered, so re-read the page before building.

Whether a gateway really avoids these reviews on our behalf, as the transcript claimed, is unverified.

### 10.4 Per-platform format table

The render target in Section 8.6 fits all four. Keep reels 15-45 s.

| Platform | Container and codec | FPS | Size and ratio | Duration | File limit | Other | Source |
|---|---|---|---|---|---|---|---|
| Instagram Reels (API) | MOV or MP4, H.264 or HEVC, closed GOP, 4:2:0; AAC up to 48 kHz | 23-60 | Max width 1920; 9:16 recommended | 3 s to 15 min | 300 MB | `moov` at front, no edit lists | [Meta](https://developers.facebook.com/docs/instagram-platform/instagram-graph-api/reference/ig-user/media) |
| Facebook Reels (API) | MP4 recommended; H.264, H.265, VP9, AV1; AAC-LC 48 kHz stereo, 128 kbps or more | 24-60 | 9:16; 1080×1920 recommended, 540×960 minimum | 3 to 90 s | `[verify]` | Pages only | [Meta](https://developers.facebook.com/docs/video-api/guides/reels-publishing) |
| TikTok (API) | MP4 recommended, WebM, MOV; H.264 recommended | 23-60 | 360 to 4096 px per side | Commonly up to 3 min; up to 10 min via the upload endpoint | 4 GB | Unaudited limits above | [TikTok](https://developers.tiktok.com/doc/content-posting-api-media-transfer-guide) |
| YouTube Shorts | Any supported upload `[verify]` | `[verify]` | Square or vertical | Up to 3 min | 256 GB (API) | A Short over 1 min with an active copyright claim is blocked globally | [YouTube](https://support.google.com/youtube/answer/15424877) |

Caption length limits, hashtag behaviour and safe-zone margins: all `[verify]` in Phase 0, then stored in config.

### 10.5 Posting schedule: starting hypotheses

These come from the transcript and are **untested**. They live in config and are revised from real results.

```yaml
schedule:
  timezone: Asia/Riyadh
  generate_after: "09:00"
  cadence:                      # D24: owner raises reels_per_week to 7 once stable
    reels_per_week: 3
    generation_days: [sun, tue, thu]   # hypothesis
  windows:                      # hypothesis, no evidence yet
    - {name: midday,  start: "13:00", end: "14:00"}
    - {name: evening, start: "20:30", end: "22:30"}
  payday_boost:                 # hypothesis
    enabled: false              # switch on as an A/B test in Phase 3
    days_of_month: [24, 25, 26, 27, 28, 29]
    reels_per_day: 2
  ramadan_windows: null         # to be set before Ramadan; likely different
```

The payday boost targets when many Saudis get paid. It is a marketing timing idea, and scripts must still follow G5. The transcript's "corresponds to 5:30-7:30 PM in UK/Europe" is a simple time conversion, not evidence of reach.

**How they get revised.** Record results per reel: by `/metric` in Phase 1, by adapter where possible in Phase 2. After 30 posted reels, compare windows, hook types, templates, tiers and length by 3-second retention, watch time, saves and shares. Change one thing at a time. Any new value goes in config with a note on what evidence supported it.

---

## 11. Config, secrets and security

### 11.1 Secrets

Only in `.env`, never in code, config or logs. The real file is `%LOCALAPPDATA%\SocialEngine\.env`, outside OneDrive, so cloud sync does not copy it. `marketing/social_engine/.env.example` has placeholders and is committed. The repo's `.gitignore` still ignores `.env*` as a second safety.

```
TELEGRAM_BOT_TOKEN=
TELEGRAM_OWNER_USER_ID=
AZURE_SPEECH_KEY=          # pasted in by the owner
AZURE_SPEECH_REGION=       # for example uaenorth; must match the resource
ANTHROPIC_API_KEY=         # only when llm.backend=anthropic_api or llm.auth=api_key
PUBLISHER_API_KEY=         # Phase 2 only
```

`.env*` is a sensitive path under `docs/sensitive.md`. The owner enters the real values. Agents and tests never read them.

### 11.2 Hard boundaries

| Rule | Enforcement |
|---|---|
| Never access production Supabase or the service-role key | No Supabase dependency. Engine refuses to start if any `SUPABASE_*` variable is in its environment. Subprocesses are scrubbed. Test scans source for `supabase` imports. `--strict-mcp-config` on Claude runs |
| Never call or import `ai_service` | No imports across folders. Test |
| Never read real user data | Allow-listed clips and strict props schema |
| Nothing published without approval | Section 3.3 invariants |
| Bot is owner-only | Section 9.4 |
| Tests never call live services | Section 12 |
| No Gemini | Dependency and source test |
| Secrets never in logs, Telegram messages or prompts | Log filter, env scrub, test |

Rule 06 section 7 applies to agents implementing this: stop and ask the owner before creating accounts, using real keys, spending money, or making the first real post.

### 11.3 Example `config.yaml` outline

```yaml
engine: {mode: test}   # test | live; live requires the launch gate in Section 13
brand:
  name_en: "Qawam Money"
  name_ar: "قوام المال"
  tagline_en: "Spend in balance"
  tagline_ar: "لا إسراف ولا تقتير"
  handles: {instagram: "", facebook: "", tiktok: "", youtube: ""}   # unset until vetted
  hashtags: []         # unset until vetted
  logo_path: ""        # unset: old logo withdrawn, new one not ready
  tokens: "assets/branding/brand_tokens.json"
  clearance:           # empty: no evidence of vetting yet; the owner records it
    google_play_checked_on: null
    app_store_checked_on: null
    saip_checked_on: null
    approved_by_owner_on: null
test_brand:            # used only when engine.mode is test
  name_en: "TEST BRAND"
  name_ar: "علامة تجريبية"
  hashtag: "#test"
  logo_path: "assets/branding/test_logo.svg"
paths: {data_root: "%LOCALAPPDATA%/SocialEngine"}
capture: {adb_path: "%LOCALAPPDATA%/Android/Sdk/platform-tools/adb.exe"}
llm: {...}            # Section 6.3
voice: {...}          # Section 7.1
render: {fps: 30, video_kbps_cap: 8000, audio_kbps: 192, max_mb: 48}
captions: {digits: western}
audio: {music_enabled: false, music_library: null, duck_under_voice: 0.12, duck_in_pauses: 0.25}   # D25; enabling music needs a licensed library named
content: {mix: {global: 50, regional: 30, saudi: 20}, english_audio_share: 0.2}   # D28: 1 reel in 5
cta: {...}            # Section 6.7; mode coming_soon, landing_url null
approval: {expire_after_hours: 72, max_regenerations: 3, max_waiting: 3}
guardrails: {max_copied_words: 12}
publishing_mode: telegram_only
schedule: {...}       # Section 10.5
retention: {auto_delete: false}
```

Config is validated on load. Unknown keys and invalid values stop the engine with a clear message.

### 11.4 Environment

Windows 11, Python 3.14.7, Node 24.22.1, npm 11.19.1. Use a dedicated venv, separate from `ai_service`, which rule 01 lists on Python 3.11. Node 24 with Remotion, and Python 3.14 with the Azure Speech SDK, are Phase 0 checks `[verify]`. If one fails, pin an older runtime for that part only.

---

## 12. Testing strategy

Per rule 05: tests first, confirm they fail for the right reason, minimal code, then all relevant suites pass. Every test here is **hermetic**: mocks only. Tests never call Telegram, Claude, Azure, any platform or Supabase, and never post.

**Network ban.** A pytest fixture disables sockets for the entire suite, so any accidental live call fails. Claude is faked by a stub executable returning canned JSON. `adb` and Remotion are faked at the subprocess boundary, except in the explicit local render tests. Time is injected.

**Python suite** (`marketing/social_engine/tests/`):

| Area | Must prove |
|---|---|
| State machine | Every allowed transition works, every other is refused. `posted` and `rejected` are terminal |
| Approval gate | Publisher refuses without approval, with old revision, with changed file hash, when paused |
| Bot security | Callback from another user changes nothing and reveals nothing. Same for a group chat. Non-owner messages are ignored. Missing owner ID stops startup |
| Double tap | Two identical callbacks apply once |
| Restart | Kill at each step, restart, and confirm no duplicate reel, no re-approval and no re-post. `in_flight` becomes `unknown_outcome` |
| Unknown outcome | Never auto-retried |
| Unique post | Second post of same reel and platform is refused at the database level |
| Missed runs | Laptop off for 3 days produces one reel, not four. Passed window goes to the next |
| Guardrails | Each G rule has passing and failing samples in Arabic and English, including every transcript line in Section 6.6 |
| Mix | 50/30/20 holds over a rolling window |
| Research | Rejects URLs not in tool log, missing citations, copied passages, invalid JSON, a missing `structured_output` |
| Claude runner | Correct flags, working folder is `claude_cwd`, environment scrubbed, `ANTHROPIC_API_KEY` removed in subscription mode. Usage-limit and login-expired paths |
| Voice | Azure adapter parses canned SDK events and keeps only `Word` boundaries. Punctuation realigns. A script with missing word events fails. `monthly_char_cap` stops synthesis before the call. An F0 reel cannot be approved while `allow_public_on_f0` is false. Config rejects any provider other than `azure_speech` |
| Size and bitrate | Formula values, re-encode on oversize, failure after 2 tries |
| Secrets | `.env` ignored, `.env.example` has no values, token never in logs |
| Boundaries | No `supabase`, `gemini`, `litellm`, `edge_tts` in source or dependencies. Refuses to start with `SUPABASE_*` in the environment |
| Privacy | Render refused for an unsigned or changed clip. Props schema rejects unknown fields |
| Brand colours | `brand_tokens.json` matches the Dart theme. `#C9933B` absent |
| **Full brand name** | G18 samples in Arabic and English, across captions, hashtags, handles, on-screen text and voiceover. `قوام`, `بقوام`, `Qawam`, `#قوام`, `@qawam` and body-shape copy fail. `قوام المال`, `Qawam Money`, `#قوام_المال` and `#QawamMoney` pass. The caption grouper never splits the name across a page or line |
| **Brand gate** | With any of name, logo, handles, hashtags or a clearance field empty in `live` mode, which includes the config as shipped: a non-test render is refused, the bot sends no Approve button, the callback handler refuses a forged approve, and the publisher refuses. A test reel gets the watermark and can never be approved, even with a complete brand. Config as shipped has the name set but clearance, logo, handles and hashtags empty, and `engine.mode: test`. Config rejects the withdrawn name and logo. No test fixture or asset uses them. Brand order per language |
| **CTA** | In `coming_soon` with an empty URL, every link, store badge, download or "link in bio" sample fails in Arabic and English, across scripts, captions, on-screen text, hashtags and bios. The approved strings pass G11, G12 and G18. `early_access` or `store` with an empty URL, and `coming_soon` with a URL, stop on load |
| **Smart Basket** | Render is refused for a `smart_basket` clip with no mask regions or no mask sign-off. The label and mask are present whenever the clip shows, in both languages, and props cannot turn them off. Store names, and saving or cheaper claims tied to the basket, fail G19 |
| **Rejected claims** | Every R row has failing samples in Arabic and English, and all of them fail. Seed topics, templates, config and asset lists contain no sample and no bank name (G20) |
| Cadence and language | 3 reels a week at most by default, 7 once raised, no backfill. English audio lands on 1 reel in 5 over a rolling window |
| Claude route | A scheduled run refuses `auth: subscription` (D20). A manual run may use it |
| Device frame | Props accept `generic` only (D31) |
| Config | Invalid values refuse to start. `claude_cli` and `anthropic_api` both validate |

**TypeScript suite** (`remotion_studio/`): `npm run lint`, type check, unit tests for caption grouping and direction, plus local-only render checks with sample data:

- Golden frames for hard Arabic words (Section 8.4).
- A test that no caption component splits a word below token level.
- A short end-to-end render that produces a valid 1080×1920 MP4.
- A `smart_basket` sample render showing the label and mask on every frame of the clip.

**Manual Phase 0 checks** are real-service spikes, run by the owner or with the owner's approval, never in the test suite.

Before review, each batch runs the suites above. Rule 06 section 6 applies as written, including its Flutter and `ai_service` gates, unless the owner waives it. Batches do not change `flutter_app/` or `ai_service/`.

---

## 13. Rollout phases

`docs/PLAN.md` implements these. Code that needs no live service is built and tested first, ahead of the Phase 0 spikes that need the owner's credentials. The live running of a phase does not start until the previous phase has met its exit criterion.

### Launch gate (hard)

Qawam Money / قوام المال is chosen. **No evidence yet shows it has been vetted, and the logo is not ready.**

**Name clearance status, 2026-11-03.** Reported by the rename session and not re-checked for this spec. **The name is not cleared. Only the owner can clear it, and every `brand.clearance.*` field stays empty until then.**

| Check | Status | What is still open |
|---|---|---|
| App stores, Saudi storefronts | No exact title match for `Qawam Money` or `قوام المال` | The Google Play check matched exact spellings only, so variants could be missed |
| Bare name `قوام` / Qawam | **In use.** App Store: `Qawam Diet \| قوام دايت`, `Qawam: Eat, Train, Recover`. Google Play: `Qawam`, `Qawam Diet \| قوام دايت`, `QAWAMFIT`, `قوام`. Those that could be categorised are diet or fitness | The Play listings titled just `Qawam` and `قوام` were not categorised, so a finance use is not ruled out. This is why G18 matters |
| SAIP trademarks | No agent searched it. The owner reports no trademark for Qawam Money | Unconfirmed whether `قوام المال` or `قوام` alone were searched, including in the finance category |
| Lawyer review | None known | Open |
| Domains | `qawam.money` and `qawammoney.com` returned no registry record, which suggests they are free but is not registrar-confirmed. Neither is registered. `qawam.com` and `qawam.app` are taken | Registering a domain is the owner's decision |
| Social handles | Not checked | Availability check only. Registration still waits for the gate |

**No public reel, no final branded recording and no social handle registration until items 1 and 2 are done:**

1. Qawam Money / قوام المال has been vetted against the app stores, **Google Play first** because the app is Android, then the Apple App Store, and against the Saudi trademark database of the Saudi Authority for Intellectual Property (SAIP). Results and dates are saved, and the owner records them in `brand.clearance.*`. An adviser's opinion is recommended, since a store search is not legal clearance.
2. The owner has approved the new logo and set `brand.logo_path`.

**Then, before the first public reel:**

3. Handles and hashtags are registered in the full name (G18) and set in `brand.handles` and `brand.hashtags`.
4. Final clips show the new name, which depends on the app rename, owned by session `budget-tracker-02` on `feat/qawam-money-branding` and `feat/qawam-money-backend`.
5. The owner sets `engine.mode` to `live`.

The engine enforces this from config: `live` mode refuses to render, offer approval or publish while the name, logo, handles, hashtags or any clearance field is empty. The quality of the vetting and item 4 are owner checks. Until then, the engine runs in `test` mode, every reel is marked as test and uses the test brand.

### Phase 0: Spikes

Small throwaway experiments, local only, nothing posted. **These do not need the launch gate:** they use the test brand, and all reels are marked as test.

| Spike | Question | Done when |
|---|---|---|
| S1 Azure voice bake-off | Which Azure voice and settings sound right, and does it say قوام المال correctly? | Section 7.5 scored, brand check passed, owner picks, and `voices/list` confirms the voice on the owner's resource and region |
| S2 Azure word timing | Does the Speech SDK `WordBoundary` event work on real ar-SA scripts? | Section 7.4 passes on 3 scripts. The forced-alignment fallback is built only if this fails |
| S3 One Arabic reel | Can Remotion render shaped Arabic with kinetic captions on this laptop? | One real Arabic reel at 1080×1920, words unbroken, under 48 MB, render time measured and acceptable. Clip can be a placeholder |
| S4 Claude headless | Do the flags and isolation work, on subscription and API key? | Valid JSON from an empty folder with no MCP, `--setting-sources` confirmed, cost per run measured with `total_cost_usd`. The Phase 0 route in D20 works |
| S5 Phone capture | Does demo mode and stopping recording work on the owner's phone? | Clean clip pulled from the phone, or fallback chosen |
| S6 Telegram | Does a 47 MB reel send, and do buttons reach the owner only? | Sent and tapped from the owner's phone, and a second account's tap rejected |
| S7 Runtime and tools | Node 24 with Remotion, Python 3.14 with the Azure Speech SDK from `data_root` | Each works, or a pinned version chosen |

**Exit:** the owner has watched one rendered Arabic reel and says it looks good enough to continue, and the Azure voice is chosen.

### Phase 1: Telegram-only pipeline

Full code with tests. `publishing_mode: telegram_only`. Task Scheduler set up, with the API key route for unattended runs (D20). Claims register reviewed. The pipeline can be built and run in `test` mode before the gate. Recording the final shot list, registering handles and posting all wait for it.

**Exit, build stage (test mode):** two weeks of scheduled running with 0 duplicate deliveries and 0 guardrail escapes (no reel reached Telegram with a banned claim).

**Exit, public stage:** the **launch gate is met**, the shot list is recorded on the correctly named build, at least 10 reels are approved and posted by hand, all L1 to L6 and L9 legal checks in Section 17 are answered, and the owner's average approval time feels sustainable.

### Phase 2: Publisher pilot

Only if the owner wants it, and only after the launch gate. Choose per D21, with real test posts on Zernio and Upload-Post, one per platform. Start with one platform through one adapter, then add others one by one. Per-post approval stays.

**Exit:** 10 consecutive reels published through the adapter with no duplicate, no wrong caption and correct AI labels. Failure and `unknown_outcome` paths exercised against the provider's sandbox or a private post.

### Phase 3: Tune from data

Compare schedule, hooks, templates, voice and payday boost from results. Consider `Post Now`, higher frequency and more Gulf voices.

**Exit:** a dated config change backed by results from at least 30 posted reels, with a documented comparison.

---

## 14. Costs

Prices checked 2026-11-03, from each vendor's page. Vendor prices can change.

| Item | Free | Paid | Source |
|---|---|---|---|
| Telegram bot | Free | n/a | Telegram Bot API |
| Remotion | Free for individuals and for-profit organizations up to 3 employees | Company License above that, price `[verify]` | [Licence](https://github.com/remotion-dev/remotion/blob/main/LICENSE.md) |
| Python, Node, FFmpeg via Remotion | Free | n/a | |
| Claude, subscription login | Included in the existing Max plan, uses its limits | n/a | [Support](https://support.claude.com/en/articles/15036540-use-the-claude-agent-sdk-with-your-claude-plan) |
| Claude, API key | $100/mo of credits included with Max when an organization is linked | API rates after credits, only if credits are purchased: Opus 5.5 $4 in / $20 out, Sonnet 5.5 $2 / $10 per million tokens; web search $10 per 1,000 searches | [Credits](https://support.claude.com/en/articles/17154008-monthly-api-credits-for-max-ultra-and-team-plans), [pricing](https://platform.claude.com/docs/en/about-claude/pricing) |
| Azure Speech | F0: 0.5M neural characters per month, about 1,250 takes. Prototypes and bake-off only, because the commercial grant is for the paid tier (Section 7.3) | $15 per 1M neural characters. About $0.006 a take, or $0.36 for 60 takes a month. At the 400,000 `monthly_char_cap` the most it can cost is about $6 a month | [Pricing](https://azure.microsoft.com/en-us/pricing/details/speech/), [price list](https://prices.azure.com/api/retail/prices?$filter=contains(productName,'Speech')%20and%20armRegionName%20eq%20'uaenorth') |
| ElevenLabs (possible later upgrade, not Phase 1) | Free tier lists no commercial licence | Starter $6/mo, Creator $22/mo | [Pricing](https://elevenlabs.io/pricing) |
| Manual posting (Phase 1) | Free | Owner's time | |
| Name vetting and trademark | Store searches are free | SAIP search or filing fees and any adviser `[verify]` | SAIP |
| Publisher, Phase 2 | Direct APIs have no fee; heavy setup | Zernio about $12/mo for 4 accounts, Upload-Post $24/mo, Ayrshare $149/mo. All vendor claims | Section 10.2 |
| Music | YouTube Audio Library is free, but its use on other platforms needs checking `[verify]` | Licensed library, price `[verify]` | L2 |
| App store accounts | n/a | Developer account fees, separate from this project `[verify]` | |

**Illustrative Claude cost on an API key** (an assumption, to be replaced by measurement in S4): 30,000 input tokens, 3,000 output tokens and 10 searches per run on Opus 5.5 = $0.12 + $0.06 + $0.10 = about $0.28 a run, or about $8 a month at one run a day. That would sit well within the $100 monthly credit, even with regenerations. Sonnet would cost less, and that choice is the owner's.

**Cheapest viable path:**

1. Phase 0: `telegram_only`, Claude on Max, Remotion free licence (D27), Azure F0 for tests and the bake-off. **$0 on top of the Max plan**, though Azure signup needs a card.
2. Phase 1: Claude moves to the API key on the linked Console organization once the job is unattended, covered by the $100 monthly credits at this volume (D20). Azure S0 for public audio (D19), voice with no music (D25), posted by hand (D21). **Under $1 a month on top of the Max plan** at the expected volume.
3. Only if manual posting becomes the bottleneck: the cheapest publisher that passes a real test post.

The F0 free route is cheaper by those few cents, but the Product Terms' commercial grant names the paid tier only, so it is not used for public reels (D19).

---

## 15. What we need from the user

Effort figures are estimates.

**First dependency**

- [ ] **Vet Qawam Money and approve the logo.** Check `Qawam Money` and `قوام المال` against Google Play, the Apple App Store and the SAIP trademark database, record dates in `brand.clearance.*`, and approve the new logo when it is ready, per the launch gate in Section 13. Nothing public can happen without this, though Phase 0 can start with a test brand. **Depends on the owner; allow time for an adviser**
  1. Search SAIP for `قوام المال` and `قوام` alone, in the finance category. The status in Section 13 does not confirm these were searched.
  2. Check that the handles are available on Instagram, Facebook, TikTok and YouTube, but do not register them yet.
  3. Consider an adviser, because the bare name is already used by diet and fitness apps and no lawyer has reviewed it.

**Before Phase 0**

- [ ] Read the CTA wording in Section 6.7 and the Smart Basket safeguards in D30, and say if you want either changed. **5 min**
- [ ] Android phone with USB debugging on and connected. Developer Options, then USB debugging, then allow this laptop. **10 min**
- [ ] Telegram bot from [@BotFather](https://t.me/BotFather): create it, paste the token into `.env`, and send `/start` to it once. **5 min**
- [ ] Your numeric Telegram user ID, from a user-ID bot, into `.env`. **2 min**
- [ ] **Azure account and free F0 Speech resource, created by you.** **30 min**
  1. Sign up at [Azure](https://azure.microsoft.com/en-us/pricing/purchase-options/azure-account). You need a phone number, a non-prepaid credit or debit card, and a Microsoft or GitHub account. Nothing is charged at signup, though a temporary one-dollar hold may appear.
  2. In the portal, create a **Speech** resource in region **`uaenorth`** with pricing tier **Free F0**. Check the tier before you finish (Section 7.3).
  3. Open **Keys and Endpoint**. Paste one key into `AZURE_SPEECH_KEY` and the region into `AZURE_SPEECH_REGION` in `.env`, yourself. Do not send the key to anyone, including in chat with an agent.
  4. Note the date. **Around day 30, Microsoft will ask you to move to pay-as-you-go. If you don't, your account and services are disabled.**
- [ ] A second Telegram account to test that others are rejected, even a family member's for one tap. **5 min**
- [ ] Laptop power settings: stays awake when plugged in, decide lid behaviour, leave it on during generation. **5 min**
- [ ] Listen to the voice bake-off and get 2 or 3 Saudi friends to score it. **30 min for you, 10 min each**

**Before the build stage of Phase 1**

- [ ] Demo account and demo households (family and roommate) with fake data, created by hand. **1 to 2 hours**
- [ ] Sample receipts and sample QR. An agent can prepare the images; you scan them. **30 min**
- [ ] Review the seed topics and claims register. **45 min**
- [ ] Console organization linked to Max for API credits, before the job runs unattended (D20). **10 min**, needs 7 days on the plan.

**After the launch gate, before anything public**

- [ ] Switch the Speech resource to paid S0, allow a few hours for quotas to update, set `voice.azure_tier: S0`, and add a cost alert (D19). **15 min**
- [ ] When you want music: a licensed library, with its licence read (D25). **30 min**
- [ ] App build showing Qawam Money / قوام المال, from the app rename, owned by session `budget-tracker-02` on `feat/qawam-money-branding` and `feat/qawam-money-backend`. **Depends on that work**
- [ ] Record the final shot list in Section 5.4 and sign off each clip. **2 to 3 hours in total, can be split**
- [ ] Social accounts in the full name: Instagram professional, Facebook Page, TikTok, YouTube channel, plus a consistent handle, added to `brand.handles`. **1 to 2 hours, plus any platform verification waits**
- [ ] A place for viewers to go: a landing or early-access URL under the new name, or a store listing. Without it, reels and profiles stay on the `coming_soon` wording with no link (D26). **Depends on the rename and deploy**
- [ ] Legal and platform checks L1 to L6 and L9 in Section 17. **Varies; may need an adviser**

**Ongoing, public stage of Phase 1**

- [ ] Approve or reject each reel in Telegram. **2 to 5 min per reel**
- [ ] Upload by hand to up to 4 platforms and tap Posted. **10 to 15 min per reel**
- [ ] Log results with `/metric`. **5 min per week**
- [ ] Re-run `/login` if the bot says Claude's login expired.

---

## 16. Open decisions

None of the original ten remain. The owner accepted them on 2026-11-04, and they are final in the decision log.

| Former question | Now |
|---|---|
| 1. Azure tier for public audio | D19 |
| 2. Claude auth for the scheduled job | D20 |
| 3. Publishing route | D21 |
| 4. Where the demo household lives | D22 |
| 5. When to record final clips | D23 |
| 6. Cadence | D24 |
| 7. Background music | D25 |
| 8. Call to action | D26, changed from the earlier recommendation |
| 9. Who operates the app | D27 |
| 10. English audio share | D28 |

**Still with the owner, neither blocking the build:**

- The Smart Basket safeguards (D30) were added by the orchestrator and are flagged to the owner, who may overrule them.
- The CTA and bio wording (Section 6.7) was drafted to carry out D26, and the owner has not yet read the exact text.

---

## 17. Risks

### Platform and legal: confirm before launch

These are flagged, not resolved. Nothing here is legal advice.

| ID | Check | What we found | Status |
|---|---|---|---|
| L0 | Name clash and trademark | The previous name was withdrawn because a licensed Saudi personal finance app already uses it (D1). **Clearance of Qawam Money is not done.** As reported on 2026-11-03: no exact app store title match, but the Google Play check covered exact spellings only. The bare name is in use by diet and fitness apps, plus two uncategorised Play listings. No agent searched SAIP, and whether `قوام المال` or `قوام` alone were searched in the finance category is unconfirmed. No lawyer review is known, and social handles are unchecked. Full table in Section 13. Whether a name is clear is a legal judgement | **Hard launch gate, Section 13. Clearance fields stay empty until the owner clears the name** |
| L1 | AI voice disclosure per platform | [Microsoft's Code of Conduct](https://learn.microsoft.com/en-us/legal/ai-code-of-conduct) already requires disclosing synthetic voices, so a caption line is on by default (G17). Secondary sources say YouTube, TikTok and Meta have their own labelling rules. YouTube's API has `status.containsSyntheticMedia`. Official platform pages were not read | **Confirm platform rules before launch.** Assume we label |
| L2 | Licensed music | Music vendors say business accounts are limited to commercial libraries, and that trending audio generally cannot be used for marketing. Those are vendors with a stake. TikTok's direct-post rules include a Music Usage Confirmation. YouTube [blocks Shorts over 1 minute with an active copyright claim](https://support.google.com/youtube/answer/15424877) | **Confirm before launch** |
| L3 | Saudi advertising licensing | Mawthooq licence from the General Authority of Media Regulation. [Saudipedia](https://saudipedia.com/en/what-is-the-mawthooq-license) says an individual advertising their own product on a personal account is exempt. The owner operates this personally, as an individual (D27). The reels would run from brand accounts in the app's name rather than a personal account, and that source does not say how this is treated. Sources date from 2022 to 2024 and disagree on some details. No conclusion is drawn here | **Confirm before launch with the authority or an adviser, stating that the operator is an individual using brand accounts** |
| L4 | Bank and third-party trademarks | Bank, wallet, store and BNPL names and logos are in the app's hints and on real receipts. ZATCA's name and any official mark also raise endorsement concerns. Device frames should not resemble a specific brand. The iPhone frame allowed after a real iOS build (D31) is one, so Apple's rules on showing its devices need reading first `[verify]`. Bank names are out altogether (D29), and store names on Smart Basket clips are masked (D30) | **Confirm before launch.** Default: generic names, no logos |
| L5 | Financial content rules | Whether general money tips in a budgeting app's marketing raise any SAMA, CMA or similar concerns is unchecked | **Confirm before launch** |
| L6 | Availability and CTA | Reels and profiles say "coming soon" (D26, G11), with no links, store badges, or download or "link in bio" wording while `cta.landing_url` is empty. The repo's landing page says early access is open, under the old name, and reels do not link to it. `early_access` needs a public URL under the new name, and `store` needs a real listing | **Safe by default. A mode change needs its URL first** |
| L7 | Azure F0 audio in marketing | The Product Terms' commercial grant names the paid tier only. Default blocks F0 audio from public posting | Settled by D19: public reels use paid S0 |
| L8 | Claude automated use on a subscription | Section 6.3 | Settled by D20: Max login in Phase 0 only, API key once unattended |
| L9 | Illustrative prices in Smart Basket clips | The clip shows the app's hard-coded prices, and the app's own screen shows a cheapest store and a saving. Masking and the label (G19) reduce the risk of naming a brand or implying a real price. Whether showing such a screen in advertising raises any concern is unchecked | **Confirm before launch.** Safeguards flagged to the owner (D30) |

### Delivery and quality

| Risk | Effect | Mitigation |
|---|---|---|
| Public use of Qawam Money before vetting, or handles registered too early | Legal exposure, rework, lost handles | Hard launch gate. `live` mode refuses to run while clearance, logo, handles or hashtags are empty. Test reels are watermarked and cannot be approved |
| قوام read as body shape | Confusing or off-brand reel | G18, one-token captions, full name everywhere, a pronunciation check |
| A full-name handle is unavailable | Pressure to shorten, which the copy rule forbids | Check availability during vetting, and bring any variation back to the owner |
| Test reel escapes and gets posted by hand | Wrong brand in public | Burned-in watermark, no Approve button, no posting package |
| False or inflated product claim gets through | Trust and compliance damage | Claims register, three guardrail layers, the owner's tap |
| Real data in a clip | Privacy breach | Separate demo login, checklist, per-clip sign-off, render allow-list |
| Hard-coded Smart Basket prices read as real, or a mask leaves a store name legible | False comparison with real brands | G19 mask and label, C21 wording, the owner's sign-off and approval tap, L9. The code fix is a later, separate task (D30) |
| Duplicate post | Looks careless | Unique database row per platform, `unknown_outcome` never auto-retries |
| Laptop off or asleep | Missed days | Tick catch-up, no backfill, posting never late without asking. Accepted limit of a laptop |
| Claude limits or expired login | Day missed | One notice, wait, later tick. API key route once unattended (D20) |
| Future `--bare` default breaks subscription use | Job stops | Pinned version, pre-flight check, API key alternative |
| Azure 429s or an outage | Voice step stalls | Retries with delay, later tick, one notice. Change region if it persists, since Microsoft says most 429s are regional voice capacity |
| Azure account disabled around day 30 | Voice stops | Checklist reminder, pre-flight check of the key, clear bot message |
| F0 limit behaviour is unclear, or paid use surprises the owner | Unexpected bill or stoppage | `monthly_char_cap` stops the engine at 400,000 characters on either tier, about $6 a month at most, plus an Azure cost alert |
| F0 audio is posted by mistake | Terms problem | `allow_public_on_f0: false` blocks approval, and the tier is recorded with each reel |
| No Azure voice sounds right for Saudi slang | Reels sound flat | Bake-off first, then script rewrites and prosody. Any change of tool is a new owner decision |
| Slang sounds formal or brand name is mispronounced | Reel sounds fake, scrolls past | Bake-off, script rewrites, Azure SSML |
| Arabic shaping breaks during animation | Looks broken, loses trust | Word-level rules, golden frames, Phase 0 reel |
| Render too slow or heavy on the laptop | Machine busy while the owner works | Measured in S3. Render on a tick at chosen hours |
| OneDrive sync conflicts | Corrupt state or locked files | Runtime data and `node_modules` outside OneDrive |
| App UI changes make clips stale | Reel shows old screens | Clips tagged with app version. Re-record list when the app changes |
| App says "Budget Tracker" while reels show the new name | Confusing | Final clips wait for the rename to reach a build, per the launch gate |
| Prompt injection from a researched page | Bad content or attempted actions | No shell or file tools, no secrets in the environment, schema, guardrails, the owner's tap |
| Manual posting fatigue | The channel goes quiet | Start at three a week, add a publisher in Phase 2 |
| Research repeats itself or gets generic | Low retention | Topic list with cooldowns, hook variety, analytics review |
| Vendor changes prices or terms | Budget surprise | Provider-agnostic interface, no lock-in, re-check prices before paying |
| Secret leak | Bot or account takeover | `.env` outside git and OneDrive by default, log redaction, rotate on suspicion |
| Reviewer treats a marketing folder as low risk | Security gaps | Declared sensitive, Round 3 required, never lowered |
