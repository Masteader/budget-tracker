# UI/UX, Localization & Web Audit

Scope: `flutter_app/lib/screens`, `lib/widgets`, `lib/theme`, `lib/l10n`, `web_app/`, `landing_page/`.
Branch: `worktree-agent-a6e22181f4544ee4c` (base `f17eb2b`). Date: 2026-10-19.

## Results: baseline vs final

| Gate | Baseline (`f17eb2b`) | Final (`3fdb8cd`) |
|---|---|---|
| `flutter analyze` | No issues found | No issues found |
| `flutter test` | 141 passed | 168 passed (27 new) |
| `web_app` `npm run build` (tsc + vite) | pass; JS 462.6 kB, CSS 37.6 kB | pass; JS 466.5 kB, CSS 39.1 kB |
| `web_app` `npm run lint` (oxlint) | 1 warning (`react(purity)` in Simulator) | 0 warnings |
| Web at 360 px (ar + en, Playwright) | not measured | no horizontal scroll; 0 unnamed controls; 0 page errors |
| Translation keys (en / ar / ur) | 508 / 504 / 504 | 1206 / 1206 / 1206 |
| Hardcoded UI string literals | ~760 replaced (scanner flagged 1,172 candidate lines, which include data and sentinel strings) | 0 in user-facing parameters, enforced by `test/ui_l10n_guard_test.dart` |
| Directional layout fixes | n/a | 32 (`EdgeInsetsDirectional`, `AlignmentDirectional`, `PositionedDirectional`, `BorderRadiusDirectional`) |
| Hardcoded `Color(0x...)` in screens/widgets | 848 | 290 (553 replaced by `AppThemes` tokens) |
| Icon-only buttons with no tooltip or label | 22 | 0 |

New tests:
- `test/ui_l10n_guard_test.dart`: key parity, placeholder parity, ar/ur values written in Arabic script, no rupees in Urdu, every `tr()` key defined, and no hardcoded literals in screens/widgets. Also covers the `format`, `sar` and `cycleMonth` helpers.
- `test/screens/ui_rtl_locale_test.dart`: login screen in ar (RTL), ur (RTL) and en (LTR); "forgot password" placed at the logical end; payday card without English ordinals; no overflow at 2x text scale on a 360 dp phone.
- `test/screens/ui_light_mode_test.dart`: forgot-password step 2 is readable in light mode; WCAG contrast check for the new text tokens.
- `test/widgets/ui_payday_checkin_banner_test.dart`: column name, payday window, shown/hidden states, lookup failure, dismiss.
- `test/widgets/ui_settlement_failure_test.dart`: a failed settlement is reported and not confirmed; Arabic RTL roommate card.

## Findings

| ID | Sev | Title | Location | Status |
|---|---|---|---|---|
| UI-01 | High | Urdu currency shown as rupees ("روپے") | `lib/l10n/app_localizations.dart` (ur `sar`, `amount_sar`, `high_to_low`, `low_to_high`) | Fixed in 4c39b67 |
| UI-02 | High | About 760 hardcoded user-facing strings in 60+ screens/widgets; Arabic (primary) and Urdu users saw English | all of `lib/screens`, `lib/widgets` | Fixed in 4c39b67, 00565fd, 9c67fef, 886913f, 2d0e26e, 85c90c3, c1665dd |
| UI-03 | Medium | 4 keys used but never defined, so the raw key text was shown (`who_paid`, `for_whom_title`, `paid_for_whom_title`, `no_children_hint`) | `screens/home/edit_transaction_sheet.dart:871,909,959,1006` | Fixed in 00565fd |
| UI-04 | Low | 4 keys existed only in English (`copy_code`, `join_with_code`, `new_household`, `save_income`) | `app_localizations.dart:283-286` | Fixed in 00565fd |
| UI-05 | Medium | Inline locale ternaries that ignored Urdu or the app locale | `category_budget_card.dart:131-139`, `installment_plans_card.dart:591-595`, `sub_budget_breakdown_sheet.dart:289,305`, `voice_listening_banner.dart:45`, `help_support_screen.dart:34-58` | Fixed in 4c39b67, 00565fd, 2d0e26e, c1665dd |
| UI-06 | Medium | Amounts always rendered as "SAR x" (unit on the wrong side in RTL, no thousands separators in places) | many widgets | Fixed: `context.sar()` in 4c39b67 and later commits |
| UI-07 | Medium | Month and day names always English (`DateFormat` without a locale; server `month_name` is English-only) | `budget_management_screen.dart`, `salary_cycle_selector_bar.dart`, `transaction_feed_screen.dart` | Fixed in 9c67fef, c1665dd |
| UI-08 | Low | English ordinals ("27th") in Arabic/Urdu | `widgets/settings/payday_settings_card.dart` | Fixed in 85c90c3 |
| UI-09 | High | Payday check-in banner queried a column that does not exist (`income_type`) and swallowed the error, so it never showed | `widgets/dashboard/payday_checkin_banner.dart:42-46` | Fixed in 5503698 |
| UI-10 | High | Settlement sheets showed "Settlement Recorded" and confirmed even when the API call failed | `family_reimbursement_card.dart` and `multi_roommate_settlement_card.dart`, `_submitSettlement` | Fixed in 886913f |
| UI-11 | High | Custom categories named in Arabic/Urdu all got the code `OPEX-` (ASCII-only slug), so they collided | `screens/home/budget_management_screen.dart` (add category) | Fixed in 9c67fef |
| UI-12 | Medium | Text hardcoded white was invisible on light surfaces in light mode | settings tiles, delete dialog title, sub-budget total, smart basket, chat input, voice banner, pending-sync banner, forgot-password step 2, filter sheet, walkthrough, grocery cards | Fixed in 4c39b67, 00565fd, 9c67fef, 2d0e26e, c1665dd, a349f81 |
| UI-13 | Medium | Brand teal/emerald used as text color on light backgrounds (1.6:1 and 2.3:1 contrast) | login links and about 50 text styles | Fixed in 4c39b67, 8be0ab0 (direct `color:` uses). Ternary uses not converted |
| UI-14 | Low | Brand colors hardcoded as hex literals instead of theme tokens | 848 `Color(0x..)` | Partly fixed in 8be0ab0 (553 replaced; 290 one-off palette colors remain) |
| UI-15 | Medium | Layout not mirrored in RTL | chat bubbles, Dismissible background, forgot link, badges and overlays, header paddings | Fixed in 4c39b67, 2b4acb8 |
| UI-16 | Medium | Accessibility: icon-only buttons without tooltip or label; tap targets under 48 dp | 22 IconButtons, remove-photo icons, forgot-password link, payday banner close | Fixed in 4c39b67, 5503698, 2b4acb8 |
| UI-17 | Medium | Dashboard stream subscription never cancelled | `screens/home/dashboard_screen.dart:63` | Fixed in 4c39b67 |
| UI-18 | Medium | `setState` after `await` without a `mounted` check, and context used across async gaps | scanner sheets, chat, edit sheet, sub-budget dialog, budget mgmt, installments, household screen | Fixed in 00565fd, 9c67fef, 886913f, 2d0e26e, c1665dd |
| UI-19 | Low | Walkthrough `PageController` never disposed | `widgets/onboarding/user_guide_walkthrough_dialog.dart` | Fixed in 2d0e26e |
| UI-20 | Low | `TextEditingController`s created inside dialog builders are never disposed (17 sites in 7 files) | e.g. `budget_management_screen.dart:289-295`, `sub_budget_allocation_dialog.dart:254-394` | Fixed in 29b83f6 (`DisposeOnUnmount`, see below) |
| UI-21 | Low | Overflow with large text or narrow screens | hero amount, accounts summary, recurring-bill totals, unspent dialog | Fixed in 4c39b67, 886913f, 9c67fef. Remaining screens suspected, not audited exhaustively |
| UI-22 | Low | Outfit font has no Arabic glyphs; the rules ask for Cairo/Tajawal | `theme/app_themes.dart` textTheme | Not fixed (reason below) |
| UI-23 | Low | Date fallback used the uninitialized `'en'` locale and would throw | `AppLocalizations.date` | Fixed in c1665dd (found while testing) |
| UI-24 | Suspected / compliance | "Shared 50/50" partner split is offered in the edit sheet and partner card, while rule 02 prohibits 50/50 spousal splits | `edit_transaction_sheet.dart` settlement banner, `partner_settlement_card.dart` | Not fixed (domain decision) |
| UI-25 | Suspected | Undo after deleting a transaction re-inserts only some columns (drops paid_by, beneficiary, account_id, sub_category) | `screens/home/transaction_feed_screen.dart` `_deleteTransaction` onUndo | Fixed in ad26480 (full row restored with the same id, see below) |
| WEB-01 | High | English mode showed hardcoded Arabic (hero settled state, simulator amounts, ZATCA label, family/roommate ledgers); Arabic mode showed English AI categories | `web_app/src/components/Hero.tsx:153-164`, `Simulator.tsx:50,299-822` | Fixed in b627c01 |
| WEB-02 | Medium | Screen readers: icon ligatures read aloud, unlabeled controls, no ARIA state | Header, Faq, EarlyAccess, Simulator, all icons | Fixed in b627c01 |
| WEB-03 | Medium | No `prefers-reduced-motion` support for the canvas, SVG river, CSS loops, framer-motion or confetti | `GlacialParticlesCanvas.tsx`, `AliveGlacialRiver.tsx`, `index.css` | Fixed in b627c01 |
| WEB-04 | Low | Canvas: NaN particles (division by zero), no DPR scaling, kept animating off-screen | `GlacialParticlesCanvas.tsx:103-107` | Fixed in b627c01 |
| WEB-05 | Medium | Loaded the full Material Symbols variable font (several MB) to show about 43 icons | `web_app/index.html` | Fixed in b627c01 (subset via `icon_names`) |
| WEB-06 | Low | No favicon link, Open Graph or theme-color meta; title not localized | `web_app/index.html`, `App.tsx` | Fixed in b627c01 |
| WEB-07 | Low | No skip link and no visible focus style | `App.tsx`, `index.css` | Fixed in b627c01 |
| WEB-08 | Low | Decorative hero image had an English alt text | `Hero.tsx:36` | Fixed in b627c01 |
| WEB-09 | High | Early-access form shows success and confetti but sends the email nowhere | `web_app/src/components/EarlyAccess.tsx:14-25` | Not fixed (needs backend) |
| WEB-10 | Low | Footer legal links (privacy, terms, security charter) are `href="#"` | `Footer.tsx:31` | Not fixed (pages don't exist) |
| WEB-11 | Low | Web offers ar/en only; the app supports Urdu | `web_app/src/i18n/translations.ts:1` | Not fixed (product scope) |
| WEB-12 | Low | Unused or duplicate assets (`hero.png`, `react.svg`, `vite.svg`, `hero_glacier.jpg`, and a JPEG saved as `.png`) | `web_app/src/assets`, `web_app/public` | Not fixed (not bundled, no runtime cost) |
| WEB-13 | Medium | Landing prototypes: Tailwind Play CDN at runtime, full icon font, hidden scrollbars, 4 dead links in `mobile.html`, remote avatar | `landing_page/*.html` | Partly fixed in 3fdb8cd (reduced motion, focus, meta, consistent digits) |
| WEB-14 | Low | oxlint purity warning (`new Date()` during render) | `Simulator.tsx:20` | Fixed in b627c01 |

## Details

### UI-01: Urdu currency was rupees
- **Root cause:** the Urdu map translated `sar` as "روپے" (Pakistani rupees), and three labels reused it.
- **Impact:** every amount and sort label in Urdu named the wrong currency. Urdu speakers are a large share of the expat audience.
- **Fix:** changed to "ریال". A regression guard test fails on "روپے/روپیہ" in any Urdu value.

### UI-02: hardcoded strings
- **Root cause:** most widgets added after the first localization pass used English literals in `Text`, snackbars, dialogs, hints and tooltips. A few used Arabic-only literals instead.
- **Impact:** the Arabic-first app was mostly English after login (auth, onboarding, settings, scanners, chat, budgets, settlements, accounts). Urdu fell back to English.
- **Fix:**
  - Extracted about 760 literals into 698 new keys, with Saudi-dialect Arabic and Urdu translations. English values stay byte-identical, so existing English tests still pass.
  - Added `context.trArgs`/`AppLocalizations.format` for `{placeholder}` substitution, and `context.sar`, `context.fmtDate` and `context.cycleMonth` helpers.
  - FAQ, walkthrough steps and role cards are now stored as translation keys.
- **Kept as data on purpose:** strings persisted to the database or parsed by the server stay English. These are `raw_sms` audit tags, BNPL notes and the offline chat payloads.
- **Kept as data on purpose:** chat quick-chip example inputs, grocery search terms, brand names (Tamara, Tabby, STC Pay) and endonyms (العربية / English / اردو) are not translated.

### UI-09: payday banner never showed (reported by the DB agent)
- **Root cause:** the banner filtered `.eq('income_type', 'salary')`, but the column is `income_records.source_type` (migration `20261018_multi_source_income_and_accounts.sql:58`; `IncomeRecord.toMap`). PostgREST rejected the query, and `catch (_)` hid the error.
- **Fix:**
  - Filter on `source_type` using `IncomeSourceType.salary.value`.
  - Log failures with `debugPrint` and a stack trace instead of swallowing them.
  - Make the lookup and clock injectable, and add 7 tests.

### UI-10: false "Settlement Recorded"
- **Root cause:** `catch (_) {}` around `recordReimbursementPayment`, followed by unconditional success UI. The family card comment said "In tests or offline mode, continue gracefully".
- **Impact:** a failed request (offline, 4xx/5xx) closed the sheet, showed success and refreshed. The user believed the debt was settled when nothing was recorded.
- **Fix:** errors now show an error snackbar and the sheet stays open. The recorder is injectable; existing tests use a fake recorder, and new tests cover the failure path.

### UI-11: Arabic category names
- **Root cause:** `name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')` returns an empty string for Arabic and Urdu names, which produced the code `OPEX-`.
- **Fix:** if the name has no ASCII letters, use a generated `OPEX-CUSTOM<base36 timestamp>` code instead. The server should still reject an empty slug (handed off to the services/DB owner).

### UI-12 / UI-13: light-mode legibility and contrast
- **Root cause:** many widgets were written for dark mode with `Colors.white` text, and the brand teal (#00E5BF) and emerald (#00C896) were used for text on white.
- **Fix:**
  - The invisible texts now use `textPrimary`.
  - New tokens `context.accentText` (#00796B, 5.1:1) and `context.successText` (#047857), plus `AppThemes.success` / `accentTextLight` / `successTextLight`. These keep the bright brand colors in dark mode.
  - Text on surfaces that are always dark (snackbar, modal barrier, camera overlay) keeps the bright color.

### UI-15: RTL
- **Fix:**
  - Chat bubbles now sit at the logical start/end, with a mirrored tail corner.
  - The Dismissible delete background and "forgot password" link use directional alignment.
  - Badges, overlay positions (photo strip, multi-page and batch scanners, filter badge), the speed-dial anchor, the deficit pill and header paddings are directional.
- **Verified, no change needed:** the directional Material icons used (`chevron_*`, `arrow_back*`, `arrow_forward*`, `send`, `trending_*`) have `matchTextDirection: true`, so they already mirror.
- **Kept on purpose:** decorative gradients (`Alignment.topLeft` → `bottomRight`) and the price-chart padding stay LTR.

### UI-18: async lifecycle
- **Fix:** a `_safeSetState` helper (setState only while mounted) in the three scanner screens; `if (!mounted) return` guards before post-await `setState`, snackbars and navigation; `ctx.mounted` checks before `setDialogState`; and no parent `context` across async gaps in bottom sheets.

### UI-20: fixed (follow-up, 29b83f6)
- **Constraint:** disposing a controller right after `await showDialog` can throw "used after disposed", because the exit animation still rebuilds the `TextField`.
- **Fix:** a small `StatefulWidget`, `widgets/dispose_on_unmount.dart`, wraps each dialog's content and disposes the controllers in `State.dispose`. That runs after the route is removed and after its `TextField`s have detached. Values read synchronously after the `await` still work.
- **Sites (14):** ingestion settings ×2, edit sheet ×1, budget management ×4, receipt scanner ×1, ZATCA scanner ×1, installment plans ×2, sub-budget add/rename ×3.
- **Sub-budget list controllers (the other 3 of the 17):** these were already disposed in `State.dispose`. Controllers replaced by a reload, or created after the dialog closed, are now disposed too. The clipboard paste checks `ctx.mounted` before writing.
- **Tests:** `test/widgets/dispose_on_unmount_test.dart` checks that the controller stays alive through the exit animation and is disposed afterwards. It also scans `lib/` so that every local dialog controller is passed to `disposables:`.

### UI-22: not fixed
- Using Cairo/Tajawal for Arabic needs a font decision: either a `GoogleFonts` fallback, which is fetched at runtime and also affects tests, or bundled assets. It also needs a change to `main.dart`, which is outside this agent's ownership.
- Today Arabic glyphs fall back to the platform font (Noto Naskh Arabic on Android), which is legible.

### UI-24 / UI-25: handed off
- **UI-24:** the partner settlement UI still offers "Shared 50/50". Whether this applies to spouses (prohibited by rule 02) or only to peer partners is a product/compliance decision. The text was translated but its meaning was not changed.
- **UI-25:** the undo re-insert in `transaction_feed_screen.dart` copies only a subset of transaction columns, so undo drops the payer/beneficiary/account attribution. This belongs with the data-layer owner.
  - **Fixed later in ad26480:** `TransactionProvider.deleteTransaction` deletes with `delete().select()` and keeps the returned row. If no row comes back, it falls back to the full `Transaction.toMap()`. `restoreDeletedTransaction` re-inserts that row unchanged: same id and every column, including `paid_by`, `beneficiary*`, `account_id`, `sub_category`, `user_id`, `qr_code_raw` and `receipt_url`. DB triggers recompute `cycle_key`, budget spend and account balance.
  - **Receipt image:** it used to be deleted from storage before the DB delete, even when that delete failed. It is now deleted only after a 10 s undo window with no undo.
  - **Other changes:** undo snapshots are dropped on sign-out or household switch. A failed undo shows a localized error.
  - **Limit:** foreign-key side effects of the delete are not reversed. The only reference is `installment_plans.original_transaction_id` (`ON DELETE SET NULL`), which stays null after an undo. Line items live in the row's own `items`/`line_items` columns and are restored.
  - **Tests:** `test/providers/transaction_undo_restore_test.dart`.

### WEB-01: language leaks on the web
- **Fix:**
  - Added `hero.settled*`, simulator unit/label keys and the AI category keys.
  - Added `familyRows`/`roommateRows` arrays (an English ledger now exists).
  - Added `a11y.*` and `pageTitle` keys.
  - The simulator renders the ledgers from the dictionary and formats every amount through one locale-aware formatter.

### WEB-03 / WEB-04: motion and canvas
- **Fix:**
  - A global reduced-motion CSS block, `<MotionConfig reducedMotion="user">`, and `confetti({ disableForReducedMotion: true })`.
  - The SVG river calls `pauseAnimations()` when reduced motion is on.
  - The canvas draws one static frame under reduced motion and pauses when off-screen (IntersectionObserver) or when the tab is hidden.
  - The canvas renders at DPR (capped at 2x), uses 32 particles under 640 px, and guards the `dist === 0` NaN.

### WEB-09: not fixed (High)
- The early-access form calls `preventDefault`, sets `submitted=true` and fires confetti. There is no network request and no storage, so every waitlist signup is lost while the user sees a success message.
- Fixing it needs a backend endpoint (for example a Supabase table with RLS for anonymous inserts plus rate limiting) or a decision to replace the form with a `mailto:` call to action. Both are owner decisions.

### WEB-13: landing_page
- These look like design prototypes (Stitch exports) that the Vite app has superseded.
- Tailwind Play CDN compiles CSS at runtime in the browser and is documented as not for production use. If these pages are deployed, move them into the Vite build or pre-compile the CSS.

## Screenshots
- `docs/review/audit/screens/web_phone_ar_360.jpg` and `web_phone_en_360.jpg`: the web app at 360 px after the fixes, Arabic RTL and English LTR.
