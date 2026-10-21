# UI/UX review: mobile app and web landing (with screenshots)

Branch `audit/claude-comprehensive-review`, base commit `10a96cf`. Date: 2026-10-21. This is a report only; no app code was changed.

## ملخص لصاحب المشروع

**الخلاصة:** التطبيق غني بالمزايا، وفكرته مناسبة جداً للأسر السعودية. شرح النفقة عند إنشاء المنزل واضح، ومراجعة المصروف قبل حفظه فكرة ممتازة. لكن الاستخدام اليومي فيه أربع مشاكل رئيسية:

1. **الشاشة الرئيسية طويلة ومتناقضة.** طولها نحو أربع شاشات. فيها رقمان مختلفان للصرف اليومي (208 و202.4). في نفس اللحظة تقول بطاقة إن الصرف "مرتفع وتجاوز للميزانية"، وتقول بطاقة أخرى "ضمن الميزانية". ما تحتاجه الأسرة أولاً هو: كم بقي حتى الراتب، وكم على الزوج لزوجته، وأي بند تجاوز. هذا موزّع في أماكن متفرقة.
2. **الأخطاء تظهر كأنها أخبار جيدة.** إذا تعذّر الاتصال بالخادم تختفي بطاقة "المستحق للزوجة" بلا تنبيه. وتظهر رسالة "تم سداد كافة الأقساط"، ويظهر قسم الفواتير فارغاً. قد يظن المستخدم أن لا شيء عليه، والحقيقة أن البيانات لم تُحمَّل.
3. **لغة النفقة تُربك في أهم لحظة، أي عند تسجيل المصروف.** يسأل التطبيق ثلاثة أسئلة متداخلة: "مين دفع؟ أنا / الشريك"، و"لمين؟"، و"من دفع ولأي غرض؟". ويسمّي الزوجة "الشريك" مع أيقونة قلب. وفي قائمة المعاملات يظهر كل مصروف بكلمة "مشترك"، حتى ما دفعته الزوجة من مالها، فلا ترى الأسرة من يستحق ماذا. ولا يوجد في مركز المساعدة أي سؤال عن النفقة. بل يشرح السؤال الموجود "تسوية صافية بيني وبين الشريك"، وهذا يخالف قاعدة الأسرة.
4. **الوضوح البصري في الوضع الفاتح.** مبلغ المستحق للزوجة بالذهبي على أبيض، وأزرار بيضاء النص على أخضر فاتح، وروابط سماوية. كلها تقريباً بنصف التباين المطلوب، فيصعب قراءتها في الشمس. الوضع الداكن ممتاز.

**الموقع الإلكتروني:** شكله جميل، لكن الحروف العربية في بطاقات أعلى الصفحة **مقطّعة**: "الـيـومـي"، "دا ئن". سبب ذلك تباعد الأحرف في التصميم. وفيه أرقام لا يمكن إثباتها، مثل "دقة 99.4%" و"أكثر من 1,500 أسرة" و"معالجة محلية". هذا يضر بالثقة في منتج مالي. والزر الرئيسي يفتح المحاكي بدل الدعوة للتسجيل.

**أهم ما أنصح به بالترتيب:**
1. بطاقة رئيسية واحدة: "المتبقي حتى الراتب" مع حكم واحد، وسطر "المستحق لسارة" للأسر.
2. رسائل خطأ صادقة لكل بطاقة: "تعذّر التحميل — إعادة المحاولة".
3. سؤال واحد للنفقة بأسماء حقيقية بدل "الشريك".
4. شارة النفقة في قائمة المعاملات.
5. خطوات إعداد للمنزل الجديد.
6. إصلاح ألوان الوضع الفاتح.
7. تمكين تعديل المبلغ والتاريخ قبل الحفظ.
8. إبراز البنود المتجاوزة بمقدار التجاوز.
9. توحيد شكل المبالغ والتواريخ بالعربي.
10. إصلاح الحروف المقطّعة والادعاءات في الموقع.

أغلبها تعديلات صغيرة إلى متوسطة.

**العدد:** 36 ملاحظة. منها 9 عالية الأهمية و15 متوسطة و12 تحسينات شكلية.

---

## How the screenshots were produced

**Mobile.** I made a scratch copy of `flutter_app` and wrote a throwaway widget-test harness (`test/ux/` in the copy, not committed). The harness pumps the **real screens** (`DashboardScreen`, `HouseholdScreen`, `LoginScreen`, sheets and tabs) at 390×844 logical, DPR 2. It writes PNGs with `RepaintBoundary.toImage`. Two runs are not covered here: the web build in Playwright was run separately, and the accessibility sweep is described in the Accessibility section.

**Fakes, no network.** Supabase was initialised against an in-memory fake through an `http` `MockClient`, with a silent realtime transport and a fake session. The FastAPI client ran inside `http.runWithClient` with the same fake. Platform channels were mocked, and sqflite used FFI.

**Fixture data:**
- *Family household:* husband Ahmed (admin and Nafaqah provider) and wife Sara, plus two child dependents.
  - Six budgets in the October cycle; Shopping is at 131% and Dining at 115%.
  - Ten transactions, including one wife advance and one wife-personal purchase.
  - Three accounts.
  - Nafaqah ledger: owed 386.40, advanced 686.40, repaid 300.
  - Wife's allowance: 1,000 allocated, 645 spent.
- *Roommates household:* three peers, with simplified debts.
- *Empty household.*
- *"API down" variant:* Supabase answers but FastAPI is unreachable, and three items sit in the offline queue.
- **The clock was real:** 2026-10-21, payday 27, so 6 days to payday.

**Fonts and rendering limits:**
- The app's `google_fonts` families (Outfit, Inter, JetBrains Mono) were bundled as local static instances taken from the OFL sources in google/fonts. Runtime fetching was off.
- Outfit has no Arabic glyphs. To match an Android phone, Arabic-script text falls back to **Noto Naskh Arabic** (the Android system Arabic font).
- **Urdu is therefore shown in Naskh, not Nastaliq.**
- **Emoji are not rendered.** Category emoji and language flags show as boxes; on a phone they render normally.
- The test engine draws text that has no font family with a box font. A scratch-only patch therefore added `fontFamily: 'Roboto'` to 32 family-less `TextStyle(color: …)` dropdown styles. That family is registered as Roboto + Naskh, as on Android.
- Layout overflows were measured only after this patch, so the overflows listed below are real, not test-font artefacts.
- Material shadows were turned on.
- Artefact: the language selector in Settings shows "English" as selected because the harness sets the locale directly. Ignore it.

**Web.** I made a scratch copy of `web_app` and ran `npm ci`, then `VITE_API_BASE_URL= npm run build`, then `vite preview`. Playwright Chromium (preinstalled) captured 390 px and 1280 px, Arabic and English. Reduced motion was on, and the page was scrolled through so that scroll-reveal sections render. Google Fonts loaded.

**Output.** 49 mobile PNGs and 8 web PNGs were produced in the scratchpad. 21 of them are curated and downscaled to 1× in [`ux_screens/`](ux_screens/), all under 160 KB.

| # | File | What it shows |
|---|---|---|
| 1 | [01_onboarding_type_ar.png](ux_screens/01_onboarding_type_ar.png) | Create household: family vs roommates |
| 2 | [02_dashboard_top_ar.png](ux_screens/02_dashboard_top_ar.png) | Dashboard, first viewport (family) |
| 3 | [03_dashboard_cycle_nafaqah_ar.png](ux_screens/03_dashboard_cycle_nafaqah_ar.png) | Salary-cycle card, Nafaqah card, wife allowance card |
| 4 | [04_dashboard_categories_ar.png](ux_screens/04_dashboard_categories_ar.png) | Category budgets (131% shown as 100%) |
| 5 | [05_dashboard_new_household_ar.png](ux_screens/05_dashboard_new_household_ar.png) | Brand-new household |
| 6 | [06_dashboard_api_down_ar.png](ux_screens/06_dashboard_api_down_ar.png) | API unreachable plus 3 queued items |
| 7 | [07_dashboard_textscale160_ar.png](ux_screens/07_dashboard_textscale160_ar.png) | System text size 160% |
| 8 | [08_speed_dial_ar.png](ux_screens/08_speed_dial_ar.png) | "Add expense" speed dial |
| 9 | [09_transaction_feed_ar.png](ux_screens/09_transaction_feed_ar.png) | Transaction feed |
| 10 | [10_chat_confirmation_ar.png](ux_screens/10_chat_confirmation_ar.png) | Chat entry plus confirmation card (family) |
| 11 | [11_chat_confirmation_ur.png](ux_screens/11_chat_confirmation_ur.png) | Same card in Urdu |
| 12 | [12_edit_sheet_nafaqah_ar.png](ux_screens/12_edit_sheet_nafaqah_ar.png) | Edit sheet of a wife advance |
| 13 | [13_manual_expense_ar.png](ux_screens/13_manual_expense_ar.png) | Manual expense sheet |
| 14 | [14_receipt_review_ar.png](ux_screens/14_receipt_review_ar.png) | Receipt scanner review |
| 15 | [15_accounts_ar.png](ux_screens/15_accounts_ar.png) | Accounts overview |
| 16 | [16_settings_members_ar.png](ux_screens/16_settings_members_ar.png) | Settings: household card, Members & Admins, payday |
| 17 | [17_roommates_settlement_ar.png](ux_screens/17_roommates_settlement_ar.png) | Roommates settlement card |
| 18 | [18_nafaqah_card_en.png](ux_screens/18_nafaqah_card_en.png) | Nafaqah card in English |
| 19 | [19_dashboard_top_ar_dark.png](ux_screens/19_dashboard_top_ar_dark.png) | Dashboard, dark mode |
| 20 | [20_web_mobile_ar.png](ux_screens/20_web_mobile_ar.png) | Web landing at 390 px, Arabic |
| 21 | [21_web_desktop_ar.png](ux_screens/21_web_desktop_ar.png) | Web landing at 1280 px, Arabic |

## Totals

| Severity | Mobile | Web | Total |
|---|---|---|---|
| High: blocks or confuses core use | 7 | 2 | **9** |
| Medium: noticeable friction | 13 | 2 | **15** |
| Low: polish | 9 | 3 | **12** |
| **Total** | 29 | 7 | **36** |

## The 10 highest-leverage improvements (priority order)

Effort: S is up to about 1 day, M is 2–4 days, L is a week or more.

| # | Improvement | Fixes | Effort |
|---|---|---|---|
| 1 | **One "until payday" hero** (described below the table). | UX-07, UX-09 | M |
| 2 | **Honest per-card error and stale states** (described below the table). | UX-01 | S–M |
| 3 | **One Nafaqah question in family mode** (described below the table). | UX-03, UX-05 | M |
| 4 | **Nafaqah and date context in the feed** (described below the table). | UX-04, UX-11 | S |
| 5 | **Guided first-run setup** (described below the table). | UX-02, UX-17 | M |
| 6 | **Light-mode contrast token pass** (described below the table). | UX-06, UX-27 | S |
| 7 | **Correctable, faster entry** (described below the table). | UX-12, UX-13 | M |
| 8 | **Over-budget made visible** (described below the table). | UX-08 | S |
| 9 | **Money, date and font localisation sweep** (described below the table). | UX-10, UX-20, UX-21 | S–M |
| 10 | **Web landing: legibility and trust** (described below the table). | WEB-UX-01–04 | S–M |

1. **One "until payday" hero.**
   - Show one number, "المتبقي حتى الراتب", with the days left.
   - Give one verdict, computed once (server forecast or client, not both).
   - In family mode add one line, "مستحق لسارة: 386.40 ر.س ←", that links to the ledger.
   - Drop the separate salary-cycle card, or merge its ring into the hero.
2. **Honest per-card error and stale states.**
   - Never render a failed request as an empty or positive state.
   - Show "تعذّر التحميل" with a retry button, and a "آخر تحديث" time when offline.
3. **One Nafaqah question in family mode.**
   - Hide "مين دفع / لمين" and show the three cards with real names.
   - Replace "الشريك" with the spouse's name everywhere in family mode.
   - Add a Nafaqah FAQ entry.
4. **Nafaqah and date context in the feed.**
   - Add badges "مستحق لسارة" and "من مصروف سارة".
   - Group rows by "اليوم / أمس / تاريخ".
   - Show amounts as `ر.س` in a neutral colour.
5. **Guided first-run setup.** After a household is created, show a checklist:
   - payday;
   - salary or income;
   - starter budgets (one tap from a template);
   - invite spouse or roommates;
   - choose the Nafaqah provider.

   The empty state also needs real buttons.
6. **Light-mode contrast token pass.**
   - Gold text → `#7A5C00`.
   - Text on `#00C896` → dark ink, or use a `#047857` fill with white text.
   - Cyan text → `#0369A1`.
   - Accounts hero text → white.
7. **Correctable, faster entry.**
   - Put the amount field first, with focus on open and a numeric keypad.
   - Make amount and category editable in the chat confirmation and the receipt review.
   - Add a date chip: "اليوم / أمس / اختيار".
   - Reduce the speed dial to 3 actions.
8. **Over-budget made visible.**
   - Show percent beyond 100% and the overspend amount ("تجاوز بـ 310 ر.س").
   - Sort categories by risk.
   - Lift the list above the secondary cards.
9. **Money, date and font localisation sweep.**
   - Route every amount through `context.sar`.
   - Use Arabic month names for cycle ranges.
   - Remove "(27th)", "ADMIN" and "SAR x.x".
   - Bundle Cairo or Tajawal (UI-22).
10. **Web landing: legibility and trust.**
    - Remove `tracking-*` and `font-mono` from Arabic text.
    - Write a concrete headline and add real app screenshots.
    - Make one primary CTA, "انضم لقائمة الانتظار".
    - Remove unverifiable numbers and claims.

---

## Mobile findings

### UX-01 (High). API failures look like empty or positive states. Screens: dashboard ([06](ux_screens/06_dashboard_api_down_ar.png)).

**What's wrong:**
- With FastAPI unreachable, the hero and accounts still render from Supabase. But:
  - the **Nafaqah card and the wife-allowance card disappear without a word**;
  - the salary-cycle card disappears;
  - Recurring Bills shows its first-time "إعداد" set-up state;
  - Installments says **"تم سداد كافة الأقساط"**.
- A husband checking whether he owes his wife sees nothing. That reads as "nothing owed".
- `FamilyReimbursementCard` "renders nothing outside family mode", and an error is treated the same way. The bills and installments providers fall back to empty lists.

**Recommendation:**
- Give every API-backed card three explicit states: loading (skeleton), **error** and empty.
- Error state: a compact card that keeps the card's title and says "تعذّر تحميل مستحقات الزوجة — تحقق من الاتصال". Give it a "إعادة المحاولة" button and the last known value, greyed, with "آخر تحديث 9:40 م".
- Installments: "لا توجد خطط تقسيط" when the list is empty; "تم سداد كافة الأقساط" only when plans exist and all are paid.

### UX-02 (High). A new household lands on a dead end. Screens: dashboard ([05](ux_screens/05_dashboard_new_household_ar.png)), onboarding ([01](ux_screens/01_onboarding_type_ar.png)).

**What's wrong:**
- After "إنشاء منزل" the user arrives at a hero showing **0.00 ر.س remaining**, "الصرف 0 (ضمن الخطة)" and a progress bar.
- The only guidance is at the very bottom, four screens down: "لا توجد مخصصات لدورة أكتوبر 2026 … يمكنك نسخ مخصصات الشهر السابق أو إضافة تصنيفات جديدة **أدناه**". There is nothing below it and no button.
- Payday, income, inviting the spouse and choosing the provider live deep in Settings.

**Recommendation:**
- Replace the hero for a household with no budgets with a setup card: "جهّز منزلك في دقيقتين", with a five-step checklist (✓ يوم الراتب ✓ الدخل ✓ الميزانيات ✓ دعوة الزوجة/الشركاء ✓ المكلّف بالنفقة).
- Each step opens the existing sheet.
- Add a "ميزانية مقترحة" button that pre-fills categories from income: groceries, bills, fuel and so on, editable.

### UX-03 (High). Family entry asks three overlapping questions and calls the wife "الشريك". Screens: chat ([10](ux_screens/10_chat_confirmation_ar.png)), Urdu ([11](ux_screens/11_chat_confirmation_ur.png)), edit ([12](ux_screens/12_edit_sheet_nafaqah_ar.png)), scanner ([14](ux_screens/14_receipt_review_ar.png)).

**What's wrong:**
- The chat confirmation shows three questions in a row:
  - "مين دفع؟ أنا / **للشريك**" ("للشريك" means *for* the partner, under a *who paid* question);
  - "لمين؟ كلانا / أنا / للشريك";
  - the Nafaqah cards "من دفع ولأي غرض؟".
- The edit sheet adds a fourth question (child) and uses a heart icon for "الشريك دفع".
- In Urdu, the "who paid" choice reads "**پارٹنر کے لیے**" ("for the partner").
- The choices are coupled: picking a Nafaqah card silently flips "who paid". A non-technical user cannot predict the result.
- The glossary in `translation_qa.md` says not to use "الشريك" for a spouse.

**Recommendation:**
- In family mode, show only the Nafaqah cards (plus the optional child chip), worded from the recorder's point of view:
  - husband viewing: "أنا دفعت (مصروف البيت)", "سارة دفعت للبيت — أردّها لها", "مشتريات سارة الشخصية — من مصروفها";
  - wife viewing: "زوجي دفع", "دفعتُ للبيت — يردّها لي", "لي شخصياً — من مصروفي".
- Keep "مين دفع / لمين" for roommates only.
- Fix the "who paid" option key so it is a payer label ("دفع الطرف الآخر"), not a beneficiary label.

### UX-04 (High). The feed hides who owes whom. Screen: feed ([09](ux_screens/09_transaction_feed_ar.png)).

**What's wrong:**
- Every row carries a green "**مشترك**" badge. That includes Sara's advance at الدانوب (a debt the husband owes) and her personal ساكو purchase (charged to her allowance).
- The feed is where a family checks "what did she pay for", and the Nafaqah class is invisible there.

**Recommendation:**
- In family mode, swap the badge by class: "مستحق لسارة" (gold), "من مصروف سارة" (cyan), "مصروف البيت" (neutral).
- Add a filter chip "مستحقات سارة".

### UX-05 (High). The help centre has no Nafaqah explanation, and its family answer contradicts the rule. Screen: help (`80_help_ar_light.png`, scratch).

**What's wrong:**
- The FAQ topics are salary, receipts, bills, BNPL and household. There is no Nafaqah or wife-allowance entry.
- `faq_household_a1` explains "لكل مصروف تحدد مين دفع (أنا أو الشريك) ولمين … ويحسب صافي التسوية المستحقة". That is the roommate model, presented to families. Rule 02 forbids splits between spouses.

**Recommendation:**
- Add a "النفقة ومصروف الزوجة" topic with three short Q&As:
  - "من يتحمل مصاريف البيت؟"
  - "دفعتُ من مالي للبيت، كيف أستردّه؟"
  - "ما هو مصروفي الشخصي ومن يحدده؟"
- Reword household Q1 to talk about roommates only.
- Add a "؟" link next to the Nafaqah card title that opens the topic.

### UX-06 (High). Light-mode contrast is too low on the key money figures and actions. Screens: [03](ux_screens/03_dashboard_cycle_nafaqah_ar.png), [15](ux_screens/15_accounts_ar.png), [17](ux_screens/17_roommates_settlement_ar.png), [01](ux_screens/01_onboarding_type_ar.png).

**What's wrong.** Measured against the theme tokens (WCAG, 4.5:1 needed):

| Element | Ratio |
|---|---|
| Owed-to-wife amount and badge, gold `#D4AF37` on white | 2.1:1 |
| White label on `#00C896` buttons ("إنشاء منزل", "الانضمام لمنزل") | 2.16:1 |
| "تعديل المصروف" and "هل أقدر أشتري؟", ice-cyan/sky on white or light cyan | 1.5–2.1:1 |
| Roommate debt amounts, teal on grey tile | 1.3:1 |
| Accounts hero: navy total on dark teal/blue gradient | 3.0–3.3:1 |
| Accounts hero: green caption on the same gradient | 2.5:1 |
| Pending-profile amber text | 2.1:1 |

- Flutter's `textContrastGuideline` flags 100 lines on the light dashboard and 60 on the dark one.
- The dark theme reads well ([19](ux_screens/19_dashboard_top_ar_dark.png)).

**Recommendation:**
- Add light-mode text tokens and use them: `goldText` `#7A5C00`, `infoText` `#0369A1`, `warnText` `#9A5B00`.
- Buttons filled with `#00C896` get dark ink `#0A0F1D` (≥8:1); or switch the fill to `#047857` with white.
- Make the accounts-hero text white (it is always on the dark gradient).

### UX-07 (High). Two engines give two verdicts on the same screen. Screens: [02](ux_screens/02_dashboard_top_ar.png), [03](ux_screens/03_dashboard_cycle_nafaqah_ar.png), budgets (`30_budgets_ar_light.png`, scratch).

**What's wrong:**
- The hero (client-side) says "الصرف 208 ر.س/يوم (**مرتفع**)" and "المتوقع: 7,102 ر.س (**تجاوز الميزانية**)".
- Two cards later, the salary-cycle card (server forecast) says "معدل الصرف اليومي: SAR **202.4**" with the badge "**ضمن الميزانية**".
- In this run the server figures come from fixtures, but the structure is real: two computations of the same metric, each with its own verdict badge.
- The budgets screen shows "عجز −859.50" (the account cannot fund its linked budgets) and "احتياطي الادخار (الفائض) +7,400" at the same time.
- "6 أيام على الراتب" appears twice.

**Recommendation:**
- Compute pace once (the server forecast, with a client fallback), and give it one verdict and one place.
- On the budgets screen, explain the relation in one line: "الدخل يغطي الميزانيات، لكن حساب الراجحي ناقص 859.50 — حوّل من STC Pay".

### UX-08 (Medium). Overspend is hidden. Screen: categories ([04](ux_screens/04_dashboard_categories_ar.png)).

**What's wrong:**
- Shopping spent 1,310 of 1,000, but shows "**100%**", because `Budget.usagePercent` clamps to 0..1 (`models.dart:408-409`).
- No "over by" amount is shown.
- The order is not by risk: Dining (115%) is last, below Fuel.
- The list starts about 3,000 px down the page.

**Recommendation:**
- Show "131%" and a red line, "تجاوز بـ 310.00 ر.س". Clamp only the bar.
- Sort by over first, then by % used.
- Show the top 3 at-risk categories right under the hero, with "عرض الكل".

### UX-09 (Medium). The dashboard is long and the hierarchy is flat. Screens: [02](ux_screens/02_dashboard_top_ar.png), full page `11_dash_family_full_ar_light.png` (scratch).

**What's wrong:**
- About 3,300 px (four phone screens) and 12 blocks:
  - cycle selector, hero;
  - quick-action dock (duplicates the FAB, bottom nav and AI tab);
  - accounts, salary cycle, Nafaqah, allowance;
  - bills, BNPL;
  - price/simulator links (a third time);
  - categories.
- For a family, the owed-to-wife card starts at about 1,550 px.
- "لوحة القيادة" / "SOVEREIGN HUD" is jargon used as a label.

**Recommendation:**
- Order: hero (remaining until payday, with the Nafaqah line) → alerts (overspent categories, bills due before payday) → categories → accounts → bills/BNPL → tools.
- Remove the quick-action dock, or keep only "مسح فاتورة" and "صوت".
- Drop the duplicate simulator and price tiles.

### UX-10 (Medium). Amount and date formatting is inconsistent in Arabic and Urdu. Screens: [03](ux_screens/03_dashboard_cycle_nafaqah_ar.png), [09](ux_screens/09_transaction_feed_ar.png), [14](ux_screens/14_receipt_review_ar.png), [15](ux_screens/15_accounts_ar.png), [16](ux_screens/16_settings_members_ar.png).

**What's wrong:**

| Where | Shows | Cause |
|---|---|---|
| Feed, scanner line items | "SAR 342.75" | `transaction_item_breakdown_card.dart:210,441,468` use `'$currency ${amount.toStringAsFixed(2)}'` |
| Salary card | "SAR 202.4" (one decimal) | `salary_cycle_widget.dart:226,235` |
| Account dropdown | "(SAR 6240.50)", no grouping | `manual_expense_sheet.dart` |
| Accounts deficit | "-SAR 859.50" | — |
| Salary card in Arabic and Urdu | "**(27th)**" | English ordinal |
| Household member badge | "**ADMIN**" in English, next to "مشرف" | — |
| Cycle range | "10-26 - 09-27" (MM-DD, reads backwards in RTL) | — |

The rest of the app correctly uses `context.sar` → "1,040.00 ر.س".

**Recommendation:**
- Route every SAR amount through `context.sar`.
- Use "دورة 27 سبتمبر – 26 أكتوبر" with Arabic month names.
- Payday: "يوم 27 من الشهر".
- Translate the role badge.

### UX-11 (Medium). The feed is hard to scan. Screen: [09](ux_screens/09_transaction_feed_ar.png).

**What's wrong:**
- No date or time on rows and no date grouping.
- Every amount is red (alarm fatigue).
- The PDF/CSV export chips take the prime slot under the filters; their tap targets are 27 dp tall.
- The header count "10 مصاريف …" is truncated.

**Recommendation:**
- Use section headers "اليوم / أمس / الأحد 19 أكتوبر" and show the time on each row.
- Use neutral ink for amounts; use red only for over-budget or flagged rows.
- Move export into the ⋯ menu.

### UX-12 (Medium). Entry cannot be corrected, and entry is slow. Screens: [10](ux_screens/10_chat_confirmation_ar.png), [13](ux_screens/13_manual_expense_ar.png), [14](ux_screens/14_receipt_review_ar.png).

**What's wrong:**
- *Chat confirmation:* the amount is a read-only chip (`pending_expense_confirmation_card.dart:241`). If voice heard 816 instead of 186, the user must cancel and retype.
- *Receipt review:* no amount or category field. Only the merchant and "مين صرف" can be changed before saving.
- *Manual sheet:*
  - the merchant comes before the amount;
  - the amount field has a **"$"** icon;
  - there is **no date field**, and neither in the edit sheet (`occurredAt: DateTime.now()`), so yesterday's cash purchase cannot be backdated.
- Tap counts:
  - manual entry: FAB → speed dial → manual → merchant → amount → category → save = **7 taps** plus typing;
  - chat: AI tab → type/speak → send → confirm = **4 taps**.

**Recommendation:**
- Make the amount editable in both review cards (tap the chip to edit) and add a category dropdown to the scan review.
- Manual sheet:
  - put the amount first, with focus on open and a decimal keypad;
  - remove the "$" icon (the label already says ر.س);
  - add a date row "اليوم ▾" with chips "اليوم / أمس / تاريخ…".
- Remember the last category and account.

### UX-13 (Medium). The speed dial has 7 actions and no scrim. Screen: [08](ux_screens/08_speed_dial_ar.png).

**What's wrong:**
- "إضافة مصروف" opens 7 options:
  - batch scan, scan, voice/AI;
  - income, transfer, simulator, manual.
- The labels sit on top of the dashboard text with no dimming.
- Rule 03 specifies 3 primary actions.
- The FAB label says "add expense", but the button opens a menu.

**Recommendation:**
- Three actions: "مصروف" (opens a sheet that offers manual / مسح / صوت at the top), "دخل" and "تحويل".
- Add a 40% scrim.
- Move the simulator and batch scan elsewhere.

### UX-14 (Medium). Large system text breaks the dashboard. Screen: [07](ux_screens/07_dashboard_textscale160_ar.png).

**What's wrong** at 160% text size (common among older users):
- The quick-action row overflows by 51 px (`dashboard_screen.dart:540`).
- The floating nav overflows (`dashboard_screen.dart:161`, `:210`, `:252`).
- The hero's three stat tiles truncate the **values** to "…7,100" and "208 ر…".
- An installments row overflows (`installment_plans_card.dart:596`).

**Recommendation:**
- Above a 1.3× text scale, stack the stat tiles vertically.
- Let the quick actions wrap onto two rows, or scroll horizontally.
- Hide the nav labels and keep the icons.
- Use `FittedBox` only for the big hero amount.

### UX-15 (Medium). Settings are long, duplicated and technical. Screen: [16](ux_screens/16_settings_members_ar.png).

**What's wrong:**
- The household card says "عضو نشط واحد" and lists Ahmed plus the children as "ملف مسبق (بانتظار الانضمام)". A child does not "join".
- The next card, "الأعضاء والمشرفون", lists Ahmed, Sara and Abdullah. Two member lists disagree.
- Member rows overflow by 26–40 px and clip the names (`household_management_card.dart:379`, a `Row` without `Flexible`).
- The settings page is about 4.5 screens long, with **three separate save buttons**: payday, rollover and the payday dropdown.
- Technical items: the household UUID with a copy button, the "معالجة المعاملات المكررة" strategy and ingestion-channel toggles.

**Recommendation:**
- One "أفراد المنزل" list: adults with role badges, then "المُعالون" (children) with their allowance and no "waiting to join".
- Split Settings into sub-pages: المنزل والأفراد / الراتب والدخل / الميزانيات والترحيل / الحسابات / المظهر واللغة / الخصوصية والصلاحيات / المساعدة.
- Save on change, with a toast.
- Hide the UUID and the dedup strategy under "متقدم".

### UX-16 (Medium). The roommates flow does not centre on "me". Screen: [17](ux_screens/17_roommates_settlement_ar.png).

**What's wrong:**
- Settlement lines say "أحمد مدين لـ فيصل" while Ahmed is the viewer. There is also a stray space after "لـ".
- The "تبسيط الديون" toggle is jargon.
- The amounts are teal on grey (1.3:1).
- The roommate dashboard still opens with the family-style budget hero; the settlement card is about 2,000 px down.

**Recommendation:**
- In roommate mode, the hero becomes "صافي حسابك: عليك 198.67 ر.س لفيصل" with "سدّد" / "أرسل تذكير".
- Rows read "أنت مدين لفيصل" / "عمران مدين لفيصل".
- Rename the toggle "أقل عدد تحويلات" with a one-line hint.

### UX-17 (Low). Onboarding: the empty name is ignored silently. Screen: [01](ux_screens/01_onboarding_type_ar.png).

**What's wrong:**
- `_createHousehold` returns silently when the name is empty (`household_screen.dart:99`). The type is validated with a message; the name is not.
- The family description itself is clear and correct.

**Recommendation:**
- Show an inline error, "اكتب اسم المنزل".
- Optionally pre-fill "بيت {اسم المستخدم}".

### UX-18 (Medium). Chat copy mixes languages. Screens: [10](ux_screens/10_chat_confirmation_ar.png), [11](ux_screens/11_chat_confirmation_ur.png).

**What's wrong:**
- The Arabic welcome message embeds the English example "'Dunkin 19 SAR: 16 latte and 3 donut'". The bidi algorithm scrambles the quotes and order. Urdu has the same problem.
- The suggestion chips include "Can I buy a 1200 SAR iPad?" in the Arabic UI.
- An in-chat ع/EN/اردو switch duplicates the app language and has 25–27 dp targets.

**Recommendation:**
- Use locale-matched examples only, each wrapped in its own bubble or chip.
- Remove the chat-level language switch; the assistant already understands both languages.

### UX-19 (Medium). Tap targets below 48 dp. Screens: feed, chat, settings.

**What's wrong.** `androidTapTargetGuideline` fails on:
- the feed's "الأحدث أولاً", "تصدير CSV" and "تصدير PDF" (27 dp tall);
- the chat language pills (25–27 dp);
- "+ إضافة عضو / مُعال" (21 dp).

The labelled-tap-target check passes everywhere except the modal barrier.

**Recommendation:**
- Raise the minimum height to 48 dp with `MaterialTapTargetSize.padded`, or add vertical padding.

### UX-20 (Medium). Typography: Arabic font and small sizes. Screens: all.

**What's wrong:**
- The theme uses Outfit, which has no Arabic glyphs. Arabic falls back to the system font, Noto Naskh on Android, which is a book face. Rule 03 asks for Cairo or Tajawal (still open as UI-22).
- Dropdown items use a plain `TextStyle(color: …)` and therefore the system font, a third typeface.
- Many labels are 10–11 px (hero tile captions, nav labels at 10 px, badges). Arabic at 10 px is hard to read.

**Recommendation:**
- Bundle Cairo (400/600/700) as assets, with `fontFamilyFallback: ['Cairo']` on the text theme.
- Merge dropdown styles with the theme (`Theme.of(context).textTheme.bodyLarge!.copyWith(...)`).
- Set a 12 px floor for Arabic and Urdu labels.

### UX-21 (Medium). Affordability verdicts are hard-coded in English and Arabic. Screen: simulator sheet.

**What's wrong:**
- `affordability_simulator_sheet.dart:196-213` builds the advice from inline English and Arabic strings ("SAR x.x", one decimal). There is no Urdu.

**Recommendation:**
- Move the advice to `trArgs` keys in all three locales and format with `context.sar`.

### UX-22 (Low). Accounts hero and quick transfer. Screen: [15](ux_screens/15_accounts_ar.png).

**What's wrong:**
- The "تحويل سريع 859.50" button is a full-width solid red, which reads as a destructive action.
- The amounts are "SAR".

**Recommendation:**
- An amber outlined button, "تغطية العجز (859.50 ر.س)".

### UX-23 (Low). The edit sheet shows a default Nafaqah class until the stored class loads. Screen: [12](ux_screens/12_edit_sheet_nafaqah_ar.png).

**What's wrong:**
- Until the extra `transactions` select returns, the cards show "دفعه الزوج".
- If the select fails, they keep showing it. The payload is guarded, so data is safe, but the UI is wrong.

**Recommendation:**
- Show a small skeleton over the Nafaqah section until it has loaded.
- On failure, show "تعذّر قراءة التصنيف".
- Better: select `nafaqah_class` with the feed query.

### UX-24 (Low). Doubled "+".

**What's wrong:**
- "+ إضافة خطة تقسيط" and "+ إضافة عضو / مُعال" show a + icon and a "+" character.

**Recommendation:**
- Drop the "+" from the strings.

### UX-25 (Low). Installments header when there are no plans. Screen: [05](ux_screens/05_dashboard_new_household_ar.png).

**What's wrong:**
- "تم سداد كافة الأقساط" when no plan exists.

**Recommendation:**
- "لا توجد أقساط".

### UX-26 (Low). All tabs load at launch.

**What's wrong:**
- `DashboardScreen` uses an `IndexedStack` of 5 screens, so chat, budgets and settings all build and fetch on start. That costs extra requests and battery on every launch.

**Recommendation:**
- Build tabs lazily: create each on first visit and keep it alive afterwards.

### UX-27 (Low). Dark/light parity.

**What's wrong:**
- Dark mode is the reference look and is consistent ([19](ux_screens/19_dashboard_top_ar_dark.png)).
- Light mode inherits the accent colours unchanged (see UX-06).
- The active bottom-nav colour `#008F7A` is hard-coded (4.0:1 for 10 px labels).

**Recommendation:**
- Use `context.accentText` for the nav label.

### UX-28 (Low). The walkthrough leads with the ZATCA scanner. Screen: `04_walkthrough_ar_light.png` (scratch).

**What's wrong:**
- Step 1 of 5 is "ماسح الفواتير الذكي وزاتكا", not the core promise.

**Recommendation:**
- Step 1: "اعرف كم بقي حتى الراتب".
- Step 2, family: "النفقة ومصروف الزوجة"; roommates: "التسوية".
- Then the entry methods.

### UX-29 (Low). Budget management row overflow and the archive icon. Screen: budgets (`30_budgets_ar_light.png`, scratch).

**What's wrong:**
- The allocated/spent row overflows by 8 px (`budget_management_screen.dart:1118`).
- The archive icon (gold) sits unlabelled next to the edit icon, one tap from hiding a category.

**Recommendation:**
- Wrap the row in `Flexible`.
- Move archive into a ⋯ menu with a confirmation.

---

## Web landing findings

### WEB-UX-01 (High). Arabic letters break apart in the hero cards. Screens: [20](ux_screens/20_web_mobile_ar.png), [21](ux_screens/21_web_desktop_ar.png).

**What's wrong:**
- The stat-card labels and captions in the first viewport render as "معدل الصرف الـيـومـي الآمن", "الـيـوم 12 من 30" and "دا ئن مستحق".
- `Hero.tsx:124,149,186` apply `font-mono uppercase tracking-wider` (and `Hero.tsx:70` the badge) to Arabic text. Letter-spacing breaks Arabic joining, and the monospace stack has no Arabic face.
- This is the first thing a Saudi visitor sees.

**Recommendation:**
- Apply tracking and mono only to Latin: `[dir=ltr]` / `:lang(en)`, or use `tracking-normal font-sans` when `lang === 'ar'`.

### WEB-UX-02 (Medium). Message and CTA. Screens: [20](ux_screens/20_web_mobile_ar.png), full page `90_web_ar_390_full.png` (scratch).

**What's wrong:**
- The headline "صفاء وانسيابية مالية تامة لأسرتك وشركاء سكنك." is abstract.
- The primary button "ابدأ المحاكي التفاعلي" scrolls to a demo.
- On mobile the VIP CTA is hidden in the hamburger menu. The only sign-up form is at about 10,500 px of an 11,261 px page (13 phone screens).

**Recommendation:**
- Headline: "اعرف كم بقي على راتبك، ومن يستحق ماذا في البيت".
- Sub-line: النفقة، مصروف الزوجة، تسوية شركاء السكن، مسح فواتير ZATCA.
- Primary CTA "انضم لقائمة الانتظار" with the email field inline in the hero. The simulator becomes the secondary button.
- Add a sticky bottom CTA bar on mobile.
- Show 2–3 real app screenshots, for example from `ux_screens/`.

### WEB-UX-03 (High). Unverifiable claims weaken trust. Screens: [21](ux_screens/21_web_desktop_ar.png), full page (scratch).

**What's wrong:**
- Figures presented as facts:
  - "دقة المعالجة الذكية 99.4%", "0.28 ث زمن المعالجة";
  - "100% خصوصية تامة", "انضم إلى أكثر من 1,500 أسرة";
  - a footer pill "النظام متصل ويعمل بكفاءة • تشفير AES-256".
- Privacy cards claim "معالجة محلية لحسابات الصرف" and "سجل تدقيق غير قابل للتعديل". Chat and receipt OCR are processed on the server by an LLM, and transactions are editable.
- The legal links (privacy, terms) go nowhere (WEB-10 is still open).
- For a finance app aimed at families, this reads as marketing filler and can backfire with careful buyers.

**Recommendation:**
- Remove the numbers that cannot be measured yet.
- Replace them with concrete, true statements: "لا نطلب كلمات مرور البنك", "لا نقرأ رسائلك النصية", "بياناتك على خوادم Supabase بصلاحيات منفصلة لكل منزل", "الفواتير تُحلَّل بالذكاء الاصطناعي على خوادمنا".
- Publish real privacy and terms pages before launch.

### WEB-UX-04 (Medium). Jargon. Screens: [20](ux_screens/20_web_mobile_ar.png), [21](ux_screens/21_web_desktop_ar.png).

**What's wrong:**
- "نظام مالي مستقل / SOVEREIGN OS", "الحوكمة المالية الذكية", "الركائز الـ 12", "ARCH // 01" and "أمان على مستوى الصف RLS".
- These speak to engineers, not to a Saudi family. `translation_qa.md` already flags "سيادي".

**Recommendation:**
- Use plain benefit language and 4–6 features at most: الراتب، النفقة، الفواتير، الشركاء، الخصوصية.
- Drop the ARCH codes.

### WEB-UX-05 (Low). Brand naming.

**What's wrong:**
- "BUDGET Tracker" on the web, "ميزانية وأكثر" in the footer and title, "ميزانية الأسرة" as the app title.

**Recommendation:**
- One Arabic name and one Latin name, used everywhere.

### WEB-UX-06 (Low). Page weight. Measured with Playwright, first load.

**What's wrong:**
- About 1.23 MB transferred:
  - JS 471 KB (144 KB gzip);
  - CSS 40 KB;
  - hero PNG 135 KB;
  - three Google Font families and a Material Symbols subset.
- Acceptable, but the hero is a PNG photo, and the particle canvas runs on mobile.

**Recommendation:**
- Serve the hero as WebP or AVIF with `srcset`.
- Load Inter only on the English page.
- Drop the canvas below 640 px.

### WEB-UX-07 (Low). Language.

**What's wrong:**
- Always Arabic on load (`useState('ar')`). The browser language is not detected and the choice is not remembered.
- There is no Urdu (known: WEB-11).

**Recommendation:**
- Use `navigator.language` on first visit and persist the choice in `localStorage`.

---

## What works well

- **The family type explanation at creation is clear and Islamically correct:** "الزوج يتكفل بالنفقة، وما تدفعه الزوجة للبيت من مالها يُسجَّل لها مستحقاً على الزوج". The Urdu version is equally clear ([01](ux_screens/01_onboarding_type_ar.png)).
- **The Nafaqah card shows the right three numbers:** owed, advanced and repaid. The wife-allowance card shows allocated, spent and remaining, with a clear "سداد مستحقات الزوجة" action ([03](ux_screens/03_dashboard_cycle_nafaqah_ar.png)).
- **Preview before save** for chat and receipts, and the one-line Nafaqah explainers under the cards.
- **RTL mirroring is correct overall:** chevrons, the send arrow, progress-bar fill direction, sheet layouts.
- **Dark mode is polished and consistent.**
- **The offline queue banner is clear:** "3 معاملات مسجلة دون اتصال — مزامنة الآن".
- **Web:** no horizontal scroll at 390 px; skip link, reduced-motion support and a localized title.

## Accessibility sweep (automated, report only)

The Flutter `meetsGuideline` checks were run with semantics on, in Arabic:

| Screen | 48 dp targets | Labelled targets | Text contrast (lines flagged) |
|---|---|---|---|
| Dashboard (light) | pass | pass | fail (100) |
| Dashboard (dark) | pass | pass | fail (60) |
| Feed | fail (3 chips, 27 dp) | pass | fail (45) |
| Settings | fail ("+ إضافة عضو", 21 dp) | pass | fail (55) |
| Chat | fail (3 language pills) | pass | fail (35) |
| Manual sheet | pass | modal barrier only | fail (25) |
| Onboarding | pass | pass | fail (15) |

The contrast guideline samples rendered pixels, so the counts are indicative. The token ratios in UX-06 are exact.

## Reproducing

The harness is throwaway and was not committed. To recreate it:
1. Copy `flutter_app` to a scratch folder.
2. Add local static font files for Outfit, Inter and JetBrains Mono (OFL, from google/fonts) under a `google_fonts/` asset folder.
3. Register Noto Naskh Arabic as the fallback family.
4. Initialise Supabase with a `MockClient` `httpClient` and a no-op realtime `transport`.
5. Run the screens inside `http.runWithClient`.
6. Alternate `tester.runAsync` and `pump` so that Supabase's isolate JSON decode completes.
7. Capture with `RenderRepaintBoundary.toImage(pixelRatio: 2)`.

Run with `--dart-define=FASTAPI_BASE_URL=http://api.fake --dart-define=SUPABASE_URL=http://supabase.fake`. Nothing contacts a live service.
