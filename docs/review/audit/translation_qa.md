# Arabic and Urdu translation QA

Branch `audit/claude-comprehensive-review`, base commit `952098d`. This is a report only; no app code was changed.

## What was reviewed

| Source | Locales | Size |
|---|---|---|
| `flutter_app/lib/l10n/app_localizations.dart` (`_localizedValues`, `_categoryCodes`, `_subCategoryValues`) | en / ar / ur | 1,283 keys × 3, plus 48 category and sub-category entries |
| `web_app/src/i18n/translations.ts` | en / ar (no Urdu) | about 200 strings per locale |
| `ai_service/_build_landing.py` (the `T.ar` / `T.en` dictionary and the `data-i18n` HTML defaults) | en / ar | about 190 keys |
| `landing_page/index.html` | ar only (the `عربي \| EN` button has no English strings behind it) | static page |

**Which landing copy is live.** `ai_service/landing_page.py` serves `ai_service/static/index.html` when that file exists, and that file is the built `web_app`. So the copy visitors see at budget.fmsco.com.sa comes from **`web_app/src/i18n/translations.ts`**. The `LANDING_HTML` in `_build_landing.py` is only used when the static build is missing, and `landing_page/index.html` is a separate older page. All three were reviewed because all three are public-facing or can become so.

**How the review was done.** Every key was read in all three locales against the English. On top of that, automated checks covered:

- placeholder parity (`{amount}`, `{name}` and so on are all present in ar/ur);
- Arabic-only letters (ي ك ى ة) in Urdu values;
- Urdu-only letters in Arabic values;
- currency labels;
- Latin-script leftovers;
- button-length outliers (ar/ur over about 30 characters where the English is short);
- how the code actually builds each string. Concatenations that break right-to-left word order were traced in the `.dart` call sites.

**Placeholders and keys are clean.** All placeholders are present in every ar and ur value; there are no missing or extra keys between locales.

## Totals

| Severity | Count | Meaning |
|---|---|---|
| High | 53 | Wrong meaning, offensive or alarming wording, or text that can cause a legal, financial or Islamic-compliance misunderstanding |
| Medium | 186 | Unnatural wording, inconsistent terms, wrong grammar, false technical claims |
| Low | 150 | Polish: spelling, word choice, length, English typos |
| **Total** | **389** | ar 159 · ur 207 · en (source) 23 |

The machine-readable list is `docs/review/audit/translation_fixes.json`: `[{file, key, locale, current, suggested, severity}]`.

- `current` is the decoded string value (real newlines, unescaped quotes).
- For `.dart` and `.ts` files, `key` is the map key or object path, for example `ar.simulator.zatcaGrand` or `ar.faq.items[3].a`.
- For `_build_landing.py`, `key` is `T.<locale>.<key>`. The same Arabic text also appears as the `data-i18n` default in the HTML part of the file; update both.
- For `landing_page/index.html` there are no keys. `key` is a label (`html:...`) and `current` is an exact substring of the file to replace.
- For category maps, `key` is `_subCategoryValues.<code>`.

## The 10 most important fixes

1. **About 40 Urdu strings are still in Arabic** (High). Every `nafaqah_*` and `allowance_*` key, `psc_family_household`, `pay_method_urpay/iban/other`. An Urdu-speaking wife or husband sees the whole Nafaqah and allowance flow in Arabic. Urdu versions are given for every key.
2. **`web_app` `ar.simulator.zatcaGrand` = "الإجمالي الصافي للفاتورة"** (High). "Net" is used for the gross total including VAT, on the live landing tax-invoice demo. The fix is `إجمالي الفاتورة (شامل الضريبة):`.
3. **Family-mode copy describes a spousal cost split, against the app's Nafaqah rule** (High):
   - web `en/ar.faq.items[3].a` ("proportional income allocation", "تكامل ميزانية الأب والأم");
   - web `en.simulator.splitDesc` ("salary-weighted contributions");
   - landing builder `T.ar.t4/spt/spy/spp`, a 60/40 "partner" split under the "توزيع الأسرة" tab;
   - `landing_page` pillar 4 ("بنسب مئوية عادلة" for families).
4. **The Arabic privacy policy contradicts the English** (High). `_build_landing.py` `T.ar.lp2p`: "ولا تُستخدم لتدريب نماذج عامة دون موافقة" implies training is allowed with consent, while the English says the data is never kept for training. "تُعالج الرسائل النصية" also reads as "your SMS messages are processed", which contradicts the no-SMS promise.
5. **`landing_page` FAQ 5 makes a false security claim** (High): "ولا يستطيع حتى مسؤولو النظام فك تشفير ميزانياتك". Row-level security is access control, not encryption, and the backend service role can read the data.
6. **Urdu `leave_household` / `leave_household_confirm` = "خاندان چھوڑیں"** (High). It literally means "abandon your family". Use گھرانہ (household), which the rest of the app already uses.
7. **Urdu financial status words are wrong** (High):
   - `overdue` = "واجب الادا" means *due*, not *overdue*;
   - `allowable_daily` = "روزانہ کی اجازت" means *daily permission*, not *daily spendable amount*.
8. **`monthly_allowance_masroof` (ar) = "المصروف الشهري / النفقة"** (High). It treats a member's pocket money as النفقة. Nafaqah is the husband's whole maintenance duty, and roommates have no Nafaqah at all. The sister key `ahm_allowance_caps` already says just "المصروف الشهري".
9. **"سيادي / السيادية" across the Arabic web landing** (High for `ar.hero.badge` and `ar.brand.sovereignBadge`, Medium for the rest). In Saudi usage "سيادي" means state or sovereign (as in الصندوق السيادي), so a finance product calling itself "نظام سيادي" or "الحوكمة المالية السيادية" suggests government backing.
10. **"تعويض" for paying the wife back** (Medium, but it reaches bank records). Keys: `reimburse_wife`, `settle_reimbursement_owed`, `settle_nafaqah_note` (pasted into STC Pay transfer notes), `settle_wife_desc`, `rid_spouse_desc`. تعويض means compensation for harm or damages; paying back what she advanced is **سداد / استرداد**, which `husband_owes_wife` already uses.

## Problems that repeat across many keys

1. **Arabic copied into Urdu.** Fix item 1 above. Add a unit test that fails when a `ur` value contains ي، ك، ى or ة; the only exception is the deliberate Arabic sample sentence in `chat_welcome`.
2. **Several words for one concept.** The canonical choice is in the glossary below. Main offenders:
   - transaction: العملية vs المعاملة in about 20 Arabic keys; ٹرانزیکشن vs لین دین in about 20 Urdu keys;
   - admin: مسؤول vs مشرف;
   - household: المنزل / الأسرة / منزل; گھرانہ / گھر / خاندان;
   - cycle in Urdu: چکر / سائیکل / ادوار. چکر is colloquial and can read as "runaround/trick";
   - category in Urdu: کیٹیگری vs زمرہ (about 30 keys);
   - wife in Urdu: اہلیہ vs بیوی;
   - allowance in Urdu: جیب خرچ / الاؤنس / مصروف;
   - sync in Urdu: ہم آہنگ (which means "harmonise") vs سنک;
   - settings in Urdu: ترتیبات vs سیٹنگز;
   - QR in Arabic: الرمز المربع vs رمز QR;
   - ZATCA: four different Arabic names, two of them outdated (هيئة الزكاة والدخل, هيئة الزكاة والضريبة). In Urdu, زکوٰۃ و ٹیکس / زکوٰۃ کیو آر reads as a zakat-payment QR code.
3. **Currency labels.**
   - Arabic puts ر.س after the number (correct), but `enter_amount` uses "ريال".
   - Urdu uses ریال, but `amount`, `initial_allocation` and `total_price` use the Arabic ر.س.
   - No rupee wording anywhere (good).
   - Digits are Western everywhere, matching `sar()` and Saudi banking apps (good; keep it).
4. **Arabic plurals.** Many strings put a number next to a fixed noun form (`{days} يوم`, `{count} أشهر`, `{count} بند`, `{count} أعضاء نشطين`, `عبر {count} حسابات`), which is wrong grammar for 1, 2, 3–10 or 11+. The table suggests count-label rewordings ("الأيام المتبقية: {days}") that are always correct. The proper fix is ICU plurals (`Intl.plural` with zero/one/two/few/many/other for ar; one/other for ur).
5. **Code that glues strings together breaks right-to-left word order.** These need a code change, not only a translation change. The table gives interim wording that reads correctly with today's code.

   | Key | Call site | Problem |
   |---|---|---|
   | `take_shot_n` | `multi_page_receipt_scanner_screen.dart:449` | `tr('take_shot_n') + n` turns into "تصویر نمبر لیں2" in Urdu |
   | `allocations_exceed_salary` | `budget_management_screen.dart:1058` | `"$text $amount."`; Urdu verb ends up before the number |
   | `no_allocations_for_cycle` | `dashboard_screen.dart:702` | cycle key appended after a full Urdu sentence |
   | `queued_offline`, `transactions_count`/`transaction_singular`, `items` | `dashboard_screen.dart:478`, `sub_budget_breakdown_sheet.dart:483`, `transaction_item_breakdown_card.dart:387` | number + noun without plural rules |
   | `cycle_alert_burn_high` with `before_payday` fallback | `salary_cycle_widget.dart:260` | produces "يُتوقع نفاد الميزانية حوالي قبل الراتب" |

   Recommendation: switch to `{n}` / `{amount}` / `{cycle}` placeholders and `trArgs`.
6. **Arabic register.** Saudi dialect (تبي، بيتم، عشان، ما فيه) is fine and pleasant in chat, onboarding and FAQ. It reads as careless in destructive confirmations, validation errors and money decisions (`tx_delete_confirm_long`, `sba_remove_confirm`, `set_are_sure_want_remove_from`, `scan_duplicate_found_msg`, `isc_negative`, `ats_same_account`). Recommendation: standard Arabic for UI chrome, errors, confirmations and legal text; light dialect only in conversational surfaces. Only the money-affecting cases are listed as fixes.
7. **Gender.**
   - Arabic follows the accepted masculine-default form of address. The wife-facing Nafaqah strings correctly use the feminine (المستحق لكِ، تستطيع).
   - Urdu "کیا میں یہ خرید سکتا ہوں؟" is masculine only; a neutral rewording is given.
   - Arabic "ابن" (son) is used where "child/dependent" is meant.
8. **Factual problem in the English source, carried into ar and ur.** "400 SAR monthly Iqama fee" is really the **dependants' levy** (المقابل المالي للمرافقين / رسوم المرافقين). Iqama renewal is a separate yearly fee. Affected keys: `support_chip_iqama`, `faq_bills_q2`, `faq_bills_a2`.
9. **False or overstated technical claims on the public sites** (Medium): "end-to-end encrypted", "تشفير RLS 256-BIT", "cryptographic row-level security", "مشفّر محلياً". RLS is access control and the server reads data for AI processing.
10. **No Urdu on the web.** `web_app` and both landing pages are Arabic and English only, while the mobile app is trilingual and many Saudi residents read Urdu. That is a product gap rather than a translation fix, so it has no row.
11. **Leftover English in ar and ur.** Brand names and standard acronyms (STC Pay, BNPL, Base64, TLV, VAT, PDF, CSV) are acceptable. Real leftovers fixed in the table: `hero_tag` (ur "سوورن HUD"), `language_ur` (ar "(Urdu)"), "الاؤنس", "فیملی ممبر", "فلیگ کریں".
12. **Strings too long for buttons** (Low): `bnpl_convert_title` (ar, 45 characters), `bm_option_rollover` (ur, 41), `caution_reallocation` (ur, 40), `daily_allowance_impact` (ar, 37), `rollover_send_to_savings_title` (ur, 36), `set_join_create_household` (ur, 33), `invite_linked_profile` (ur, 31). Lengths are character counts, not measured on a device.

## Glossary of recommended terms

| English | Arabic (Saudi) | Urdu | Notes |
|---|---|---|---|
| Household (the shared group) | المنزل | گھرانہ | Neutral for family and roommates; majority usage in both locales. Not منزل جديد/الأسرة for actions, not گھر/خاندان |
| Family (mode) | الأسرة (النفقة الشرعية) | خاندان (اسلامی نفقہ) | Only for the family-mode label, never for "household" actions |
| Roommate | شريك السكن | روم میٹ | |
| Wife / Husband | الزوجة / الزوج | اہلیہ / شوہر | Not "الشريك" for a spouse; not بیوی |
| Dependent / Child | مُعال / طفل | زیرِ کفالت / بچہ | Not ابن (son only) |
| Member | عضو | رکن | Not ممبر |
| Admin / Primary admin | مشرف / المشرف الرئيسي | ایڈمن / مرکزی ایڈمن | مسؤول clashes with مسؤولية النفقة and suggests guardianship |
| Nafaqah | النفقة (النفقة الشرعية) | نفقہ | The husband's maintenance duty, never a member's allowance |
| Advance (wife paid for the household) | دفعته الزوجة مقدماً | پیشگی ادائیگی | |
| Reimburse / reimbursement | سداد / استرداد | واپس ادائیگی / واپسی | Not تعويض (compensation for harm) |
| Personal allowance | المصروف الشخصي | ذاتی جیب خرچ | Not الاؤنس / مصروف in Urdu |
| Allowable daily / daily allowance | المتاح يومياً / المصروف اليومي | روزانہ قابلِ خرچ رقم / یومیہ خرچ کی حد | |
| Settlement / settle up | تسوية | تصفیہ / حساب چکائیں | Not تسویہ (not an Urdu word); not التسوية for reconciliation |
| Debt simplification | تبسيط الديون | قرضوں کو آسان بنانا | |
| Salary cycle / cycle | دورة الراتب / الدورة | تنخواہ کا سائیکل / سائیکل | Not چکر or ادوار |
| Payday | يوم الراتب (يوم نزول الراتب) | تنخواہ کا دن | 27th = government payday only |
| Transaction | معاملة / المعاملات | لین دین | Not العملية / ٹرانزیکشن |
| Expense | مصروف / مصاريف | خرچ / اخراجات | |
| Category / Sub-category | تصنيف / تصنيف فرعي | کیٹیگری / ذیلی کیٹیگری | The landing page's "فئة" should also move to تصنيف |
| Allocation | المخصص / المخصصات | تخصیص / مختص رقم | |
| Rollover | ترحيل | رول اوور (منتقلی) | |
| Surplus / Deficit | فائض / عجز | فاضل / خسارہ | |
| Savings reserve | احتياطي الادخار | بچت کا ذخیرہ | |
| Shared pool (joint balance) | الصندوق المشترك | مشترکہ فنڈ | |
| Reconcile / reconciliation difference | مطابقة الرصيد / فرق المطابقة | بیلنس کی مطابقت / ایڈجسٹمنٹ | |
| Installments / BNPL | الأقساط / الشراء الآجل | اقساط / BNPL | |
| Interest-free | بدون فوائد | بغیر سود | Keep it in Urdu too (riba sensitivity) |
| Overdue / Due / Pending | متأخر / مستحق / معلق | تاریخ گزر چکی / واجب الادا / زیرِ التوا | |
| Recurring bills | الفواتير المتكررة | باقاعدہ بل | Not "بار بار آنے والے" or "ماہانہ" |
| ZATCA | هيئة الزكاة والضريبة والجمارك (زاتكا) | زاتکا | Never هيئة الزكاة والدخل / زکوٰۃ و ٹیکس |
| QR code | رمز QR | کیو آر کوڈ / QR کوڈ | Not الرمز المربع |
| VAT / Tax invoice | ضريبة القيمة المضافة / فاتورة ضريبية | VAT / ٹیکس انوائس | |
| Dependants' levy | رسوم المرافقين (المقابل المالي للمرافقين) | مرافقین فیس | The 400 SAR monthly charge; not "Iqama fee" |
| Sync | مزامنة | سنک | Not ہم آہنگ |
| Settings | الإعدادات | ترتیبات | Not سیٹنگز |
| Edit | تعديل | ترمیم کریں | |
| SAR amount | `1,250.00 ر.س` (unit after the number) | `1,250.00 ریال` | Never روپے; Western digits |
| Tabarru' / Takaful | تبرّع / تكافل | تبرع / تکافل | The app has no Takaful feature, so do not use تكافلي for bill-splitting (landing_page does). The "Gifts & Donations" category (هدايا وتبرعات / تحائف اور عطیات) is correct |
| Zakat | الزكاة | زکوٰۃ | Only for zakat itself, never as shorthand for ZATCA |

Urdu punctuation: the values use ۔ ، ؟ correctly throughout. The "..." ellipsis on progress labels is acceptable and was not flagged.

## Findings

Each table lists key, locale, current, suggested, reason and severity, grouped by severity and then by file. Newlines inside a value are shown as `\n`.


### High (53)


#### `flutter_app/lib/l10n/app_localizations.dart` (43)

| key | locale | current | suggested | reason | severity |
|---|---|---|---|---|---|
| `monthly_allowance_masroof` | ar | المصروف الشهري / النفقة (اختياري) | المصروف الشهري (اختياري) | Treats a member's allowance (مصروف) as النفقة. Nafaqah is the husband's whole maintenance duty, not a member's pocket money, and roommates have no Nafaqah at all. | High |
| `allowable_daily` | ur | روزانہ کی اجازت | روزانہ قابلِ خرچ رقم | "روزانہ کی اجازت" means "daily permission", not the amount you can spend per day. | High |
| `allowance_allocated` | ur | المخصص | مختص شدہ | Arabic text left in the Urdu locale. | High |
| `allowance_amount_label` | ur | المبلغ لكل دورة | فی سائیکل رقم | Arabic text left in the Urdu locale. | High |
| `allowance_edit` | ur | تعديل المصروف | جیب خرچ تبدیل کریں | Arabic text left in the Urdu locale. | High |
| `allowance_not_set` | ur | لم يُحدَّد مصروف لهذه الدورة بعد. | اس سائیکل کے لیے ابھی جیب خرچ مقرر نہیں ہوا۔ | Arabic text left in the Urdu locale. | High |
| `allowance_overspent` | ur | تجاوز المصروف بمبلغ {amount} | جیب خرچ سے {amount} زیادہ | Arabic text left in the Urdu locale. | High |
| `allowance_remaining` | ur | المتبقي | باقی | Arabic text left in the Urdu locale. | High |
| `allowance_save` | ur | حفظ | محفوظ کریں | Arabic text left in the Urdu locale. | High |
| `allowance_save_failed` | ur | تعذّر حفظ المصروف | جیب خرچ محفوظ نہیں ہو سکا | Arabic text left in the Urdu locale. | High |
| `allowance_saved` | ur | تم حفظ المصروف | جیب خرچ محفوظ ہو گیا | Arabic text left in the Urdu locale. | High |
| `allowance_set` | ur | تحديد المصروف | جیب خرچ مقرر کریں | Arabic text left in the Urdu locale. | High |
| `allowance_set_by_husband` | ur | يحدده الزوج أو مشرف الأسرة. | شوہر یا گھرانے کا ایڈمن مقرر کرتا ہے۔ | Arabic text left in the Urdu locale. | High |
| `allowance_set_title` | ur | المصروف الشخصي لدورة {cycle} | {cycle} کے لیے ذاتی جیب خرچ | Arabic text left in the Urdu locale. | High |
| `allowance_spent` | ur | المصروف | خرچ شدہ | Arabic text left in the Urdu locale. | High |
| `allowance_subtitle` | ur | المشتريات الشخصية في دورة الراتب {cycle} | تنخواہ کے سائیکل {cycle} میں ذاتی خریداری | Arabic text left in the Urdu locale. | High |
| `allowance_title` | ur | مصروف الزوجة الشخصي | اہلیہ کا ذاتی جیب خرچ | Arabic text left in the Urdu locale. | High |
| `allowance_title_mine` | ur | مصروفي الشخصي | میرا ذاتی جیب خرچ | Arabic text left in the Urdu locale. | High |
| `leave_household` | ur | خاندان چھوڑیں | گھرانہ چھوڑیں | "خاندان چھوڑیں" literally means "abandon your family". The app calls the household گھرانہ elsewhere. | High |
| `leave_household_confirm` | ur | کیا آپ واقعی اس خاندان کو چھوڑنا چاہتے ہیں؟ آپ مشترکہ بجٹ تک رسائی کھو دیں گے۔ | کیا آپ واقعی یہ گھرانہ چھوڑنا چاہتے ہیں؟ دوبارہ مدعو کیے جانے تک آپ اس کے مشترکہ بجٹ اور لین دین تک رسائی کھو دیں گے۔ | "اس خاندان کو چھوڑنا" means abandoning the family. Also leaves out "until you are re-invited". | High |
| `nafaqah_advanced_total` | ur | دفعته الزوجة: {amount} | پیشگی ادا کیا: {amount} | Arabic text left in the Urdu locale. | High |
| `nafaqah_banner_husband` | ur | مصروف البيت: من نفقة الزوج، ولا دين على أحد. | گھریلو خرچ: شوہر کا نفقہ، کسی پر کوئی قرض نہیں۔ | Arabic text left in the Urdu locale. | High |
| `nafaqah_banner_personal` | ur | شخصي: يُحتسب {amount} من مصروف الزوجة. | ذاتی: {amount} اہلیہ کے جیب خرچ میں شمار ہوں گے۔ | Arabic text left in the Urdu locale. | High |
| `nafaqah_banner_shared` | ur | مشترك للأسرة: يستحق للزوجة على زوجها {amount}. | خاندان کے لیے مشترکہ: شوہر کے ذمے اہلیہ کے {amount} ہیں۔ | Arabic text left in the Urdu locale. | High |
| `nafaqah_choice_title` | ur | من دفع ولأي غرض؟ | ادائیگی کس نے کی، اور کس مقصد کے لیے؟ | Arabic text left in the Urdu locale. | High |
| `nafaqah_confirm_received` | ur | تسجيل مبلغ مستلم | وصول شدہ رقم درج کریں | Arabic text left in the Urdu locale. | High |
| `nafaqah_err_forbidden` | ur | هذا الإجراء للزوج أو الزوجة أو مشرف الأسرة فقط. | یہ کام صرف شوہر، اہلیہ یا گھرانے کا ایڈمن کر سکتا ہے۔ | Arabic text left in the Urdu locale. | High |
| `nafaqah_err_overpayment` | ur | المبلغ أكبر من الرصيد المستحق ({amount}). | یہ رقم واجب الادا بقایا ({amount}) سے زیادہ ہے۔ | Arabic text left in the Urdu locale. | High |
| `nafaqah_history` | ur | السجل | ریکارڈ | Arabic text left in the Urdu locale. | High |
| `nafaqah_history_advance` | ur | دفعت الزوجة: {merchant} | اہلیہ نے ادا کیا: {merchant} | Arabic text left in the Urdu locale. | High |
| `nafaqah_history_empty` | ur | لا توجد مبالغ مدفوعة أو مسددة بعد. | ابھی تک کوئی پیشگی ادائیگی یا واپسی نہیں ہوئی۔ | Arabic text left in the Urdu locale. | High |
| `nafaqah_history_reimbursement` | ur | سداد عبر {method} | {method} کے ذریعے واپس ادا کیا گیا | Arabic text left in the Urdu locale. | High |
| `nafaqah_history_title` | ur | سجل المستحقات والسداد | واپسی کی ادائیگیوں کا ریکارڈ | Arabic text left in the Urdu locale. | High |
| `nafaqah_opt_husband` | ur | دفعه الزوج (مصروف البيت) | شوہر نے ادا کیا (گھریلو خرچ) | Arabic text left in the Urdu locale. | High |
| `nafaqah_opt_personal_hers` | ur | شخصي (من مصروفها) | ذاتی (اس کے جیب خرچ سے) | Arabic text left in the Urdu locale. | High |
| `nafaqah_opt_personal_mine` | ur | شخصي (من مصروفي) | ذاتی (میرے جیب خرچ سے) | Arabic text left in the Urdu locale. | High |
| `nafaqah_opt_shared` | ur | مشترك للأسرة (يسدده الزوج) | خاندان کے لیے مشترکہ (شوہر واپس ادا کرے گا) | Arabic text left in the Urdu locale. | High |
| `nafaqah_owed_to_you` | ur | المستحق لكِ على زوجك | آپ کے شوہر کے ذمے واجب الادا رقم | Arabic text left in the Urdu locale. | High |
| `nafaqah_reimbursed_total` | ur | تم سداده: {amount} | واپس ادا ہوا: {amount} | Arabic text left in the Urdu locale. | High |
| `nafaqah_wife_personal_hint` | ur | ليس ديناً: يُخصم من مصروف الزوجة الشخصي لهذه الدورة. | قرض نہیں: اس تنخواہ کے سائیکل میں اہلیہ کے ذاتی جیب خرچ سے منہا ہوگا۔ | Arabic text left in the Urdu locale; Urdu users see Arabic. | High |
| `overdue` | ur | واجب الادا | تاریخ گزر چکی | "واجب الادا" means "due/payable", not "overdue"; users cannot tell a bill that is late from one that is simply due. | High |
| `pay_method_other` | ur | أخرى | دیگر | Arabic word left in the Urdu locale. | High |
| `psc_family_household` | ur | مصروف البيت (نفقة الزوج): {amount} | گھریلو خرچ (شوہر کا نفقہ): {amount} | Arabic text left in the Urdu locale. | High |

#### `ai_service/_build_landing.py` (3)

| key | locale | current | suggested | reason | severity |
|---|---|---|---|---|---|
| `T.ar.lp2p` | ar | تُعالج الرسائل النصية والصوتية بواسطة نماذج الذكاء الاصطناعي لاستخراج بيانات المصروف فقط ولا تُستخدم لتدريب نماذج عامة دون موافقة. | تُعالج المدخلات النصية والصوتية بواسطة نماذج الذكاء الاصطناعي لاستخراج بيانات المصروف فقط، ولا يُحتفظ بها لتدريب نماذج عامة. | Privacy-policy text that disagrees with the English. "دون موافقة" implies data may be used for training with consent, while the English says it is never kept for training. "الرسائل النصية" also reads as "SMS messages are processed", which contradicts the no-SMS promise. Also update the data-i18n default in the HTML (line ~784). | High |
| `T.ar.spt` | ar | محاكاة توزيع المصاريف بين الشركاء والأبناء | محاكاة توزيع المصاريف بين شركاء السكن | The demo shows a 60/40 "partner" split inside the family (توزيع الأسرة) tab, which reads as a proportional husband/wife split; the Nafaqah rule forbids that. Move the demo to roommates. Also update the HTML default (line ~553). | High |
| `T.ar.t4` | ar | توزيع الأسرة | توزيع السكن المشترك | Same Nafaqah problem: the percentage split is shown as a family feature. Also update the HTML default (line ~469). | High |

#### `landing_page/index.html` (1)

| key | locale | current | suggested | reason | severity |
|---|---|---|---|---|---|
| `html:faq-5-answer` | ar | ولا يستطيع حتى مسؤولو النظام فك تشفير ميزانياتك الشخصية. | ولا يطّلع عليها إلا أعضاء منزلك المصرّح لهم. | False privacy claim: RLS is access control, not encryption, and backend admins (service role) can read the data. | High |

#### `web_app/src/i18n/translations.ts` (6)

| key | locale | current | suggested | reason | severity |
|---|---|---|---|---|---|
| `ar.brand.sovereignBadge` | ar | نظام سيادي مستقل | نظام مالي مستقل | Same "سيادي" problem: it suggests a state-backed system. | High |
| `ar.faq.items[3].a` | ar | وضع الأسرة يركز على تكامل ميزانية الأب والأم، والمصروفات التضامنية والادخار المشترك. أما وضع الزملاء فيتعامل مع كل فرد كشريك مستقل، مع احتساب دقيق للمبالغ المدفوعة وصافي المديونيات وتسويتها بضغطة زر. | وضع الأسرة يتبع مبدأ النفقة الشرعية: الزوج يتكفل بمصاريف البيت، وما تدفعه الزوجة من مالها للبيت يُسجَّل لها مستحقاً على الزوج، مع ادخار مشترك للأسرة. أما وضع الزملاء فيتعامل مع كل فرد كشريك مستقل، مع احتساب دقيق للمبالغ المدفوعة وصافي المديونيات وتسويتها بضغطة زر. | Describes Family Mode as merging the father's and mother's budgets (a shared spousal budget). That contradicts the app's Nafaqah rule (the husband provides; the wife's payments are owed back to her). | High |
| `ar.hero.badge` | ar | الحوكمة المالية السيادية • للأسر الحديثة وشركاء السكن | الإدارة المالية الذكية • للأسر الحديثة وشركاء السكن | In Saudi usage "سيادي" means state or sovereign (as in الصندوق السيادي). On a finance product it suggests government backing; this is a misleading claim in a regulated area. | High |
| `ar.simulator.zatcaGrand` | ar | الإجمالي الصافي للفاتورة: | إجمالي الفاتورة (شامل الضريبة): | "الصافي" means net (before VAT), but the field is the gross total including VAT ("Grand Invoice Total"). On a tax-invoice demo this reverses the meaning. | High |
| `en.faq.items[3].a` | en | Family Mode focuses on proportional income allocation, household reserve buffers, and collective child allocations. Roommates Mode treats each person as an autonomous counterparty, keeping clean peer-to-peer debit/credit records with instant 1-click settlements. | Family Mode follows the Islamic Nafaqah principle: the husband covers household expenses, and anything the wife pays for the household from her own money is tracked as owed back to her. Roommates Mode treats each person as an autonomous counterparty, keeping clean peer-to-peer debit/credit records with instant 1-click settlements. | "Proportional income allocation" tells a married couple to split household costs by salary, which the product's own Nafaqah rule forbids. | High |
| `en.simulator.splitDesc` | en | Eliminate awkward financial discussions. Switch smoothly between proportional household budgeting (fair salary-weighted contributions) and roommate mode with zero-friction one-click settlements. | Eliminate awkward financial discussions. Switch smoothly between Nafaqah-based family budgeting (the husband provides; the wife's household payments are tracked as owed back to her) and roommate mode with zero-friction one-click settlements. | "Salary-weighted contributions" for a family is a spousal cost split, which goes against the Nafaqah rule. | High |

### Medium (186)


#### `flutter_app/lib/l10n/app_localizations.dart` (147)

| key | locale | current | suggested | reason | severity |
|---|---|---|---|---|---|
| `_subCategoryValues.ride_hailing` | ar | تطبيقات النقل والتوصيل | تطبيقات النقل (أوبر/بولت) | "تطبيقات النقل والتوصيل" overlaps with delivery_apps ("تطبيقات التوصيل"), so users cannot tell which one to pick. | Medium |
| `across_accounts` | ar | عبر {count} حسابات | عدد الحسابات: {count} | "عبر {count} حسابات" is wrong grammar for 1, 2 and 11 or more (Arabic plural rules). A count label avoids it. | Medium |
| `adjustment` | ar | التسوية | فرق المطابقة | "التسوية" is the app's word for settling debts between members. Using it for a balance-reconciliation adjustment mixes up two money concepts. | Medium |
| `admin` | ar | مسؤول | مشرف | The app uses both مسؤول and مشرف for admin. مشرف is the familiar word (as in WhatsApp groups), and مسؤول clashes with مسؤولية النفقة. | Medium |
| `ahm_spouse_desc` | ar | تقدر تدفع مصاريف المنزل مقدماً وتسترد النفقة. | تقدر تدفع مصاريف المنزل مقدماً وتستردها من الزوج. | "وتسترد النفقة" says the wife takes back the Nafaqah itself. What she gets back is what she advanced, from the husband. | Medium |
| `all_nafaqah_settled` | ar | جميع نفقات الأسرة مسواة بالكامل | تمت تسوية جميع مستحقات النفقة | "مسواة" is wrong here (it means levelled); the standard word is تسوية. | Medium |
| `all_roommates_settled` | ar | لا توجد مستحقات معلقة بين شركاء السكن. الجميع متساوون! | لا توجد مستحقات معلقة بين شركاء السكن. كل الحسابات مسوّاة! | "الجميع متساوون" means "everyone is equal", not "everyone is settled up". | Medium |
| `chat_parse_failed` | ar | تعذر فهم تفاصيل العملية. | تعذر فهم تفاصيل المعاملة. | Use المعاملة for transaction, as elsewhere. | Medium |
| `chat_recent_match` | ar | لقينا عملية مطابقة حديثة. | وجدنا معاملة مطابقة حديثة. | Uses العملية for transaction; the app's term is المعاملة. | Medium |
| `chat_save_failed` | ar | تعذر حفظ العملية. | تعذر حفظ المعاملة. | Use المعاملة for transaction, as elsewhere. | Medium |
| `chat_title` | ar | محادثة العمليات الذكية | محادثة المعاملات الذكية | Use المعاملات for transactions, as elsewhere. | Medium |
| `chat_tx_recorded` | ar | تم تسجيل العملية بنجاح! | تم تسجيل المعاملة بنجاح! | Use المعاملة for transaction, as elsewhere. | Medium |
| `days_to_payday_badge` | ar | {days} يوم على الراتب | الأيام المتبقية للراتب: {days} | "{days} يوم" is wrong grammar for 3 to 10 (أيام) and 11 or more (يوماً). A count label avoids it. | Medium |
| `dcc_attach` | ar | إرفاق {count} بند بالعملية | إرفاق البنود ({count}) بالمعاملة | Use المعاملة for transaction; "{count} بند" is also wrong grammar for 3 to 10. | Medium |
| `dcc_title` | ar | لقينا عملية مطابقة | وجدنا معاملة مطابقة | Use المعاملة for transaction, as elsewhere. | Medium |
| `drc_enrich` | ar | إكمال العملية الحالية | إكمال المعاملة الحالية | Use المعاملة for transaction, as elsewhere. | Medium |
| `drc_log_new` | ar | تسجيل كعملية جديدة | تسجيل كمعاملة جديدة | Use المعاملة for transaction, as elsewhere. | Medium |
| `enter_amount` | ar | السعر التقديري (ريال) | أدخل السعر (ر.س) | Uses "ريال" where every other amount label uses ر.س, and "التقديري" (estimated) is not in the source. | Medium |
| `faq_bills_a2` | ar | رسوم الإقامة 400 ريال تُتابع ضمن تصنيف الخدمات الحكومية كبند احتياطي مستقل، عشان تحمي المبالغ الأساسية من الصرف على التسوق العام. | رسوم المرافقين (400 ريال شهرياً) تُتابع ضمن تصنيف الخدمات الحكومية كبند احتياطي مستقل، عشان تحمي المبالغ الأساسية من الصرف على التسوق العام. | Same factual point: the 400 SAR monthly charge is رسوم المرافقين. | Medium |
| `faq_bills_q2` | ar | وين تُتابع رسوم الإقامة الشهرية 400 ريال؟ | وين تُتابع رسوم المرافقين الشهرية (400 ريال)؟ | Same factual point: the 400 SAR monthly charge is رسوم المرافقين. | Medium |
| `hmc_active_members` | ar | {count} أعضاء نشطين | الأعضاء النشطون: {count} | "أعضاء نشطين" has the wrong case and wrong number agreement for 11 or more. | Medium |
| `icr_question` | ar | تبي تعيد تفعيل "{category}" لمتابعة ميزانيته، أو تسجل العملية تحت تصنيف آخر؟ | هل تريد إعادة تفعيل "{category}" لمتابعة ميزانيته، أم تسجيل المعاملة تحت تصنيف آخر؟ | Use المعاملة for transaction, as elsewhere. | Medium |
| `join_household` | ar | الانضمام لأسرة | الانضمام لمنزل | Use the same household term as the rest of the app (المنزل). | Medium |
| `leave_household` | ar | مغادرة الأسرة | مغادرة المنزل | "مغادرة الأسرة" reads as "leave the family", which is alarming for a spouse. The app calls the household المنزل everywhere else (set_leave_household_error). | Medium |
| `leave_household_confirm` | ar | هل أنت متأكد من مغادرة هذه الأسرة؟ ستفقد الوصول للميزانيات والمعاملات المشتركة حتى تتم دعوتك مجدداً. | هل أنت متأكد من مغادرة هذا المنزل؟ ستفقد الوصول للميزانيات والمعاملات المشتركة حتى تتم دعوتك مجدداً. | Same term problem: الأسرة should be المنزل. | Medium |
| `pds_title` | ar | الراتب ودورة الصرف | يوم الراتب ودورة الراتب | "دورة الصرف" brings in a new term; the app's term is دورة الراتب. | Medium |
| `pec_both_family` | ar | الاثنين / العائلة | كلانا / العائلة | "الاثنين" also means "Monday", and as a label it should be nominative. | Medium |
| `perm_pool_admin_only` | ar | سحب الأموال من الصندوق المشترك متاح لمسؤولي المنزل فقط. | سحب الأموال من الصندوق المشترك متاح لمشرفي المنزل فقط. | Use one word for admin (مشرف). | Medium |
| `perm_pool_hidden_hint` | ar | الصناديق المشتركة مخفية: السحب منها للمسؤولين فقط. | الصناديق المشتركة مخفية: السحب منها للمشرفين فقط. | Use one word for admin (مشرف). | Medium |
| `perm_tx_admin_only` | ar | تعديل أو حذف مصاريف الأعضاء الآخرين متاح لمسؤولي المنزل فقط. | تعديل أو حذف مصاريف الأعضاء الآخرين متاح لمشرفي المنزل فقط. | Use one word for admin (مشرف recommended; see glossary). | Medium |
| `perm_tx_locked_note` | ar | أضافها عضو آخر · التعديل للمسؤولين فقط | أضافها عضو آخر · التعديل للمشرفين فقط | Use one word for admin (مشرف). | Medium |
| `photo_or_qr_required` | ar | يرجى التقاط صورة واحدة على الأقل أو مسح الرمز المربع لفاتورة هيئة الزكاة والضريبة. | يرجى التقاط صورة واحدة على الأقل أو مسح رمز QR الضريبي (زاتكا). | Outdated authority name and "الرمز المربع". | Medium |
| `psim_days_to_payday` | ar | باقي على الراتب: {days} يوم | الأيام المتبقية للراتب: {days} | "{days} يوم" is wrong grammar for 3 to 10 and 11 or more. | Medium |
| `reimburse_wife` | ar | تعويض الزوجة | سداد مستحقات الزوجة | "تعويض" means compensation for harm or damages. Here the husband is paying back what his wife advanced, which is سداد / استرداد; "تعويض" invites the wrong legal reading. | Medium |
| `rid_spouse_desc` | ar | منزل النفقة الشرعية: الزوج ينفق ويعوّض الزوجة عن أي مصاريف منزلية دفعتها. | أسرة بنظام النفقة الشرعية: الزوج ينفق ويردّ للزوجة ما دفعته من مصاريف المنزل. | "منزل النفقة الشرعية" is unnatural, and "يعوّض" carries the compensation sense. | Medium |
| `roles_last_admin` | ar | يجب أن يبقى للمنزل مسؤول واحد على الأقل. | يجب أن يبقى للمنزل مشرف واحد على الأقل. | Use one word for admin (مشرف). | Medium |
| `roles_make_admin` | ar | تعيين كمسؤول | تعيين كمشرف | Use one word for admin (مشرف). | Medium |
| `roles_make_primary` | ar | تعيين كمسؤول رئيسي | تعيين كمشرف رئيسي | Use one word for admin (مشرف). | Medium |
| `roles_primary_admin` | ar | المسؤول الرئيسي | المشرف الرئيسي | Use one word for admin (مشرف). | Medium |
| `roles_remove_admin` | ar | إلغاء صلاحية المسؤول | إلغاء صلاحية المشرف | Use one word for admin (مشرف). | Medium |
| `roles_subtitle` | ar | المسؤولون يعدّلون مصاريف الجميع ويحوّلون من الصندوق المشترك. لا يستطيع مسؤول آخر إلغاء صلاحية المسؤول الرئيسي. | المشرفون يعدّلون مصاريف الجميع ويحوّلون من الصندوق المشترك. لا يستطيع مشرف آخر إلغاء صلاحية المشرف الرئيسي. | Use one word for admin (مشرف). | Medium |
| `roles_title` | ar | الأعضاء والمسؤولون | الأعضاء والمشرفون | Use one word for admin (مشرف). | Medium |
| `roles_transfer_msg` | ar | سيصبح {name} المسؤول الرئيسي. ستبقى مسؤولاً لكن لن تستطيع إلغاء صلاحيته. | سيصبح {name} المشرف الرئيسي. ستبقى مشرفاً لكن لن تستطيع إلغاء صلاحيته. | Use one word for admin (مشرف). | Medium |
| `roles_transfer_title` | ar | نقل صلاحية المسؤول الرئيسي؟ | نقل صلاحية المشرف الرئيسي؟ | Use one word for admin (مشرف). | Medium |
| `roommate_partner_desc` | ar | مشاركة الفواتير والمعيشة والتسوية البينية التبسيطية. | يتقاسم مصاريف السكن ويشارك في تبسيط الديون. | "التسوية البينية التبسيطية" is not natural Arabic. | Medium |
| `saudi_zatca_vat_qr` | ar | رمز QR الضريبي لهيئة الزكاة والدخل | رمز QR الضريبي (زاتكا) | "هيئة الزكاة والدخل" is the authority's pre-2021 name (GAZT); it is now ZATCA, هيئة الزكاة والضريبة والجمارك. | Medium |
| `scan_duplicate_found_msg` | ar | فيه عملية بمبلغ {amount} في '{merchant}' مسجلة من قبل. تبي ترفق البنود فيها أو تسجلها كعملية منفصلة؟ | توجد معاملة بمبلغ {amount} لدى '{merchant}' مسجلة مسبقاً. هل تريد إرفاق البنود بها أم تسجيلها كمعاملة منفصلة؟ | Uses العملية for transaction; and this is a money-affecting choice (a possible double charge), so it should be clear standard Arabic, not dialect. | Medium |
| `scan_instructions` | ar | وجّه الكاميرا نحو الرمز المربع لفاتورة هيئة الزكاة والضريبة | ضع رمز QR الخاص بفاتورة هيئة الزكاة والضريبة والجمارك داخل الإطار | The authority's official name is هيئة الزكاة والضريبة والجمارك (ZATCA); the shortened name is outdated. | Medium |
| `scan_invoice_desc` | ar | للإيصالات الطويلة، التقط صوراً متعددة أو امسح الرمز المربع لهيئة الزكاة والضريبة. | للإيصالات الطويلة، التقط عدة صور (أعلى ووسط وأسفل)، أو امسح رمز QR الضريبي (زاتكا). | Outdated authority name and "الرمز المربع". | Medium |
| `scan_invoice_saved_msg` | ar | تم حفظ عملية الفاتورة بنجاح! | تم حفظ معاملة الفاتورة بنجاح! | Use المعاملة for transaction, as elsewhere. | Medium |
| `set_all_transactions_synchronized` | ar | تمت مزامنة جميع العمليات | تمت مزامنة جميع المعاملات | Use المعاملات for transactions, as elsewhere. | Medium |
| `set_transaction_s_pending_sync` | ar | {count} عملية بانتظار المزامنة | بانتظار المزامنة: {count} | "{count} عملية" is wrong grammar for 3 to 10, and the app's term for a transaction is المعاملة. A count label avoids both. | Medium |
| `settle_nafaqah_note` | ar | تعويض نفقة - {amount} ريال | استرداد نفقة - {amount} ريال | Same تعويض problem. This text is pasted into STC Pay transfer notes, so it reaches banking records. | Medium |
| `settle_reimbursement_owed` | ar | مستحق للتعويض | مبلغ مستحق السداد | "مستحق للتعويض" means "eligible for compensation" (damages), not "owed back". | Medium |
| `settle_wife_desc` | ar | سجّل تعويضاً كاملاً أو جزئياً عن مصاريف المنزل المدفوعة مقدماً. | سجّل سداداً كاملاً أو جزئياً لمصاريف المنزل التي دفعتها الزوجة مقدماً. | Same تعويض problem. | Medium |
| `support_chip_iqama` | ar | كيف أضيف رسوم الإقامة 400 ريال؟ | كيف أضيف رسوم المرافقين (400 ريال)؟ | Factual: the 400 SAR monthly charge is the dependants' fee (المقابل المالي للمرافقين), not an "Iqama fee". Iqama renewal is a separate yearly fee. | Medium |
| `transfer_out` | ar | تحويل منه | تحويل صادر | "تحويل منه" is unclear: it does not say from which account. | Medium |
| `tx_delete_confirm_long` | ar | متأكد إنك تبي تحذف عملية {amount} في {merchant}؟\nبيتم تعديل المصروف من ميزانيتك تلقائياً. | هل أنت متأكد من حذف معاملة {amount} في {merchant}؟\nسيتم تعديل المصروف من ميزانيتك تلقائياً. | Uses العملية for transaction, and a destructive confirmation should be in clear standard Arabic, not dialect ("متأكد إنك تبي"). | Medium |
| `tx_delete_failed_err` | ar | تعذر حذف العملية: {error} | تعذر حذف المعاملة: {error} | Use المعاملة for transaction, as elsewhere. | Medium |
| `tx_delete_failed_msg` | ar | تعذر حذف العملية. تأكد من اتصالك بالإنترنت. | تعذر حذف المعاملة. تأكد من اتصالك بالإنترنت. | The tx_* keys say العملية; the navigation and the rest of the app say المعاملة. | Medium |
| `tx_deleted` | ar | تم حذف العملية | تم حذف المعاملة | Use المعاملة for transaction, as elsewhere. | Medium |
| `tx_removed` | ar | تم حذف العملية | تم حذف المعاملة | Use المعاملة for transaction, as elsewhere. | Medium |
| `tx_restore_failed_msg` | ar | تعذرت استعادة العملية. يرجى إضافتها مرة أخرى. | تعذرت استعادة المعاملة. يرجى إضافتها مرة أخرى. | Use المعاملة for transaction, as elsewhere. | Medium |
| `tx_restored` | ar | تمت استعادة العملية | تمت استعادة المعاملة | Use المعاملة for transaction, as elsewhere. | Medium |
| `tx_update_failed_msg` | ar | تعذر تحديث العملية: {error} | تعذر تحديث المعاملة: {error} | Use المعاملة for transaction, as elsewhere. | Medium |
| `tx_updated_msg` | ar | تم تحديث العملية وإعادة حساب الميزانية. | تم تحديث المعاملة وإعادة حساب الميزانية. | Use المعاملة for transaction, as elsewhere. | Medium |
| `wife_spouse_title` | ar | الزوجة / الشريك | الزوجة | "الشريك" is masculine and generic; the role is the wife, as in invite_role_spouse. | Medium |
| `zatca_qr_code_data` | ar | بيانات الرمز المربع لهيئة الزكاة والضريبة | بيانات رمز QR (زاتكا) | Uses the outdated authority name and the uncommon term "الرمز المربع" (Saudi apps say رمز QR). | Medium |
| `faq_bills_a2` | en | The 400 SAR Iqama fee is tracked under the Government (OPEX-GOV) category as a dedicated sub-budget reserve, protecting your essential funds from being spent on general shopping. | The 400 SAR monthly dependant fee is tracked under the Government (OPEX-GOV) category as a dedicated sub-budget reserve, protecting your essential funds from being spent on general shopping. | English source: same factual point. | Medium |
| `faq_bills_q2` | en | Where is the 400 SAR monthly Iqama fee tracked? | Where is the 400 SAR monthly dependant fee tracked? | English source: the 400 SAR monthly charge is the dependant (Murafiq) levy, not an Iqama fee. | Medium |
| `support_chip_iqama` | en | How to add 400 SAR Iqama fee? | How to add the 400 SAR dependant fee? | English source: the 400 SAR monthly charge is the dependant (Murafiq) levy, not an Iqama fee. Update ur to match: "400 ریال مرافقین فیس کیسے شامل کریں؟". | Medium |
| `active_salary_cycle` | ur | فعال تنخواہ کا چکر | فعال تنخواہ کا سائیکل | Use سائیکل consistently instead of چکر. | Medium |
| `affordability_simulator` | ur | کیا میں یہ خرید سکتا ہوں؟ | کیا یہ خریداری میرے بجٹ میں ہے؟ | "خرید سکتا ہوں" is masculine only; wives use this screen too. Gender-neutral wording. | Medium |
| `ahm_allowance_caps` | ur | ماہانہ الاؤنس / مصروف (اختیاری) | ماہانہ جیب خرچ (اختیاری) | "مصروف" is Arabic and "الاؤنس" is English; the app's Urdu term is جیب خرچ. | Medium |
| `allocations_exceed_salary` | ur | تخصیصات آپ کی ماہانہ تنخواہ سے زیادہ ہیں | تخصیصات آپ کی اس ماہانہ تنخواہ سے زیادہ ہیں (ریال): | The code appends the salary amount, which gives "...زیادہ ہیں 15,000." with the number left hanging. Better: an {amount} placeholder (code change). | Medium |
| `amount` | ur | رقم (ر.س) | رقم (ریال) | Uses the Arabic abbreviation ر.س; Urdu elsewhere uses ریال (and the sar key is ریال). | Medium |
| `budgets_auto_rollover_desc` | ur | تنخواہ کے دن بجٹ خودکار طور پر اگلے چکر میں منتقل ہو جاتا ہے۔ آپ پچھلے مہینے کی تخصیصات نقل کر سکتے ہیں۔ | تنخواہ کے دن بجٹ خودکار طور پر اگلے سائیکل میں منتقل ہو جاتا ہے۔ آپ پچھلے سائیکل کی تخصیصات نقل کر سکتے ہیں یا نیچے نئی کیٹیگریز شامل کر سکتے ہیں۔ | Uses چکر, and leaves out the second option ("or add custom categories below"). | Medium |
| `camera_access_desc` | ur | کاغذی رسیدیں اور زکوٰۃ کیو آر کوڈ اسکین کرنے کے لیے درکار ہے۔ | کاغذی رسیدیں اور سعودی زاتکا کیو آر کوڈ اسکین کرنے کے لیے درکار ہے۔ | "زکوٰۃ کیو آر کوڈ" suggests a zakat-payment QR code; it is the ZATCA tax-invoice QR code. | Medium |
| `can_i_afford_this` | ur | کیا میں یہ خرید سکتا ہوں؟ | کیا یہ خریداری میرے بجٹ میں ہے؟ | Masculine only ("سکتا"); gender-neutral wording. | Medium |
| `chat_parse_failed` | ur | ٹرانزیکشن کی تفصیلات سمجھ نہیں آ سکیں۔ | لین دین کی تفصیلات سمجھ نہیں آ سکیں۔ | Use لین دین for transaction, as elsewhere. | Medium |
| `chat_recent_match` | ur | حال ہی کی ملتی جلتی ٹرانزیکشن ملی ہے۔ | حال ہی کا ملتا جلتا لین دین ملا ہے۔ | Use لین دین for transaction, as elsewhere. | Medium |
| `chat_save_failed` | ur | ٹرانزیکشن محفوظ نہیں ہو سکی۔ | لین دین محفوظ نہیں ہو سکا۔ | Use لین دین for transaction, as elsewhere. | Medium |
| `chat_title` | ur | اے آئی ٹرانزیکشن چیٹ | اے آئی لین دین چیٹ | Use لین دین for transaction, as elsewhere. | Medium |
| `chat_tx_recorded` | ur | ٹرانزیکشن کامیابی سے درج ہو گئی! | لین دین کامیابی سے درج ہو گیا! | Use لین دین for transaction, as elsewhere. | Medium |
| `child_dependent_desc_long` | ur | بغیر قرض یا تسویہ کے ذاتی اخراجات اور جیب خرچ کا انتظام۔ | قرض یا تصفیے کے بغیر ذاتی اخراجات اور جیب خرچ کا ریکارڈ۔ | "تسویہ" is not an Urdu word; use تصفیہ. | Medium |
| `copy_previous` | ur | پچھلے چکر کی تخصیصات نقل کریں | پچھلے سائیکل کی تخصیصات نقل کریں | Use سائیکل consistently instead of چکر. | Medium |
| `create_new_household` | ur | نیا گھر بنائیں | نیا گھرانہ بنائیں | Should be گھرانہ ("نیا گھر بنائیں" means "build a new house"). | Medium |
| `cycle` | ur | چکر | سائیکل | Use سائیکل consistently instead of چکر. | Medium |
| `dcc_attach` | ur | {count} آئٹمز ٹرانزیکشن سے منسلک کریں | {count} آئٹمز لین دین سے منسلک کریں | Use لین دین for transaction, as elsewhere. | Medium |
| `dcc_title` | ur | ملتی جلتی ٹرانزیکشن ملی | ملتا جلتا لین دین ملا | Use لین دین for transaction, as elsewhere. | Medium |
| `deductions_gosi` | ur | کٹوتیاں (انشورنس / ٹیکس) | کٹوتیاں (گوسی / ٹیکس) | GOSI is Saudi social insurance, not generic "انشورنس"; users may think it is a private insurance premium. | Medium |
| `drc_enrich` | ur | موجودہ ٹرانزیکشن مکمل کریں | موجودہ لین دین مکمل کریں | Use لین دین for transaction, as elsewhere. | Medium |
| `drc_log_new` | ur | نئی کے طور پر درج کریں | نئے لین دین کے طور پر درج کریں | Use لین دین for transaction; the current wording has a feminine adjective with no noun. | Medium |
| `family_nafaqah_subtitle` | ur | اسلامی نفقہ کے تحت خاندانی ذمہ داری | اسلامی نفقہ کے تحت شوہر کی کفالت کی ذمہ داری | Says "family responsibility"; the English (and the Nafaqah rule) puts the duty on the husband. | Medium |
| `faq_bills_a2` | ur | 400 ریال اقامہ فیس سرکاری خدمات کے زمرے میں ایک الگ ذیلی بجٹ ریزرو کے طور پر ٹریک ہوتی ہے، تاکہ ضروری رقم عام خریداری میں خرچ نہ ہو۔ | 400 ریال ماہانہ مرافقین فیس سرکاری خدمات کی کیٹیگری میں ایک الگ ذیلی بجٹ ریزرو کے طور پر ٹریک ہوتی ہے، تاکہ ضروری رقم عام خریداری میں خرچ نہ ہو۔ | Factual: it is the dependants' levy. Also use کیٹیگری, as elsewhere. | Medium |
| `faq_bills_q2` | ur | 400 ریال ماہانہ اقامہ فیس کہاں ٹریک ہوتی ہے؟ | 400 ریال ماہانہ مرافقین فیس کہاں ٹریک ہوتی ہے؟ | Factual: the 400 SAR monthly charge is the dependants' levy (مرافقین فیس), not an Iqama fee. | Medium |
| `hero_tag` | ur | سوورن HUD | ڈیش بورڈ | English left in the value ("HUD") plus a meaningless transliteration ("سوورن"). | Medium |
| `household_switched_success` | ur | فعال گھر کامیابی کے ساتھ تبدیل کر دیا گیا! | فعال گھرانہ کامیابی سے تبدیل ہو گیا! | Should be گھرانہ, as elsewhere. | Medium |
| `icr_question` | ur | کیا آپ "{category}" کو دوبارہ فعال کر کے اس کا بجٹ ٹریک کرنا چاہتے ہیں، یا اس ٹرانزیکشن کو کسی اور زمرے میں درج کرنا چاہتے ہیں؟ | کیا آپ "{category}" کو دوبارہ فعال کر کے اس کا بجٹ ٹریک کرنا چاہتے ہیں، یا اس لین دین کو کسی اور کیٹیگری میں درج کرنا چاہتے ہیں؟ | Use لین دین and کیٹیگری, as elsewhere. | Medium |
| `initial_allocation` | ur | مختص رقم (ر.س) | ابتدائی مختص رقم (ریال) | Uses the Arabic abbreviation ر.س; Urdu uses ریال. Also leaves out "initial". | Medium |
| `join_another_household` | ur | کسی دوسرے گھر میں شامل ہوں | کسی دوسرے گھرانے میں شامل ہوں | Should be گھرانہ, as elsewhere. | Medium |
| `join_household` | ur | خاندان میں شامل ہوں | گھرانے میں شامل ہوں | "خاندان" (family) is wrong for roommate households; use گھرانہ. | Medium |
| `join_household_desc` | ur | 8 ہندسوں کا دعوتی کوڈ درج کریں: | 8 حروف کا دعوتی کوڈ درج کریں: | "ہندسوں" means digits; the invite code is made of characters, not just numbers. | Medium |
| `member` | ur | ممبر | رکن | ممبر here, رکن in most other keys. | Medium |
| `no_allocations_for_cycle` | ur | اس چکر کے لیے کوئی تخصیص نہیں | کوئی تخصیص نہیں، سائیکل: | The code appends the cycle key, which gives "اس چکر کے لیے کوئی تخصیص نہیں 2026-11"; the sentence breaks. | Medium |
| `no_allocations_set` | ur | اس چکر کے لیے کوئی تخصیص مقرر نہیں کی گئی | اس سائیکل کے لیے کوئی تخصیص مقرر نہیں کی گئی | Use سائیکل consistently instead of چکر. | Medium |
| `open_settings` | ur | سیٹنگز کھولیں | ترتیبات کھولیں | Settings is ترتیبات everywhere else (nav_settings); سیٹنگز is inconsistent. | Medium |
| `pay_method_iban` | ur | آيبان | آئی بین | Arabic spelling left in the Urdu locale. | Medium |
| `pay_method_urpay` | ur | يور باي | یور پے | Arabic spelling (ي، ا) left in the Urdu locale; Urdu uses ی and پے. | Medium |
| `payday_banner_title` | ur | تنخواہ کا چکر شروع ہو گیا! 🎉 | تنخواہ کا نیا سائیکل شروع ہو گیا! 🎉 | Use سائیکل consistently instead of چکر. | Medium |
| `rb_manage_empty` | ur | بجٹ والی کوئی ذیلی زمرہ نہیں ملی۔ پہلے بجٹ مینجمنٹ میں رقم مختص کریں۔ | بجٹ والی کوئی ذیلی کیٹیگری نہیں ملی۔ پہلے بجٹ مینجمنٹ میں رقم مختص کریں۔ | Gender mismatch: "زمرہ" is masculine but the verb ("ملی") is feminine. | Medium |
| `rid_spouse_desc` | ur | اسلامی نفقہ والا گھرانہ: شوہر خرچ اٹھاتا ہے اور بیوی کو گھریلو اخراجات کی پیشگی ادائیگی واپس کرتا ہے۔ | اسلامی نفقہ والا گھرانہ: شوہر خرچ اٹھاتا ہے اور اہلیہ کو گھریلو اخراجات کی پیشگی ادائیگی واپس کرتا ہے۔ | Use اہلیہ, as elsewhere. | Medium |
| `rolled_over_overspend` | ur | پچھلے چکر کا اضافی خرچ | پچھلے سائیکل کا اضافی خرچ | Use سائیکل consistently instead of چکر. | Medium |
| `rolled_over_surplus` | ur | پچھلے چکر کا بچا ہوا فاضل | پچھلے سائیکل کا بچا ہوا فاضل | Use سائیکل consistently instead of چکر. | Medium |
| `roommate_partner_desc` | ur | مشترکہ اخراجات تقسیم اور بقایا جات کی آسان تسویہ۔ | رہائش کے اخراجات بانٹتا ہے اور قرضوں کو آسان بنانے میں شامل ہوتا ہے۔ | "تسویہ" is not an Urdu word (the Urdu word is تصفیہ), and the sentence has no verb. | Medium |
| `roommate_split_personal_hint` | ur | ادائیگی کرنے والے کا ذاتی خرچ۔ | صرف ادائیگی کرنے والے کا ذاتی خرچ۔ کوئی قرض نہیں بنے گا۔ | Leaves out "No debt created", which is the point of the option. | Medium |
| `salary_cycle` | ur | تنخواہ کا چکر | تنخواہ کا سائیکل | "چکر" is colloquial and can mean "a hassle", "a trick" or "dizziness" ("تنخواہ کا چکر" can read as "the salary runaround"). Most Urdu keys already use سائیکل. | Medium |
| `saudi_zatca_vat_qr` | ur | سعودی زکوٰۃ و ٹیکس کیو آر کوڈ | سعودی زاتکا VAT کیو آر کوڈ | "زکوٰۃ و ٹیکس" is not the authority's name; use زاتکا as in faq_receipts_a2. | Medium |
| `scan_duplicate_found_msg` | ur | '{merchant}' پر {amount} کی ٹرانزیکشن پہلے سے درج ہے۔ آئٹمز اس کے ساتھ منسلک کریں یا الگ درج کریں؟ | '{merchant}' پر {amount} کا لین دین پہلے سے درج ہے۔ آئٹمز اس کے ساتھ منسلک کریں یا الگ درج کریں؟ | Use لین دین for transaction, as elsewhere. | Medium |
| `scan_instructions` | ur | کیمرہ کو زکوٰۃ و ٹیکس انوائس کے کیو آر کوڈ پر سیدھا رکھیں | اسکین کرنے کے لیے زاتکا کیو آر کوڈ کو فریم کے اندر رکھیں | "زکوٰۃ و ٹیکس" is not the authority's name; use زاتکا as in other Urdu keys. | Medium |
| `scan_invoice_desc` | ur | طویل رسیدوں کے لیے متعدد تصاویر لیں یا زکوٰۃ و ٹیکس کا کیو آر کوڈ اسکین کریں۔ | طویل رسیدوں کے لیے کئی تصاویر لیں (اوپر، درمیان، نیچے) یا زاتکا VAT کیو آر کوڈ اسکین کریں۔ | "زکوٰۃ و ٹیکس" is not the authority's name. | Medium |
| `scan_invoice_saved_msg` | ur | انوائس کی ٹرانزیکشن کامیابی سے محفوظ ہو گئی! | انوائس کا لین دین کامیابی سے محفوظ ہو گیا! | Use لین دین for transaction, as elsewhere. | Medium |
| `set_all_transactions_synchronized` | ur | تمام ٹرانزیکشنز ہم آہنگ ہیں | تمام لین دین سنک ہو چکے ہیں | Use لین دین for transactions and سنک for sync. | Medium |
| `set_transaction_s_pending_sync` | ur | {count} ٹرانزیکشنز ہم آہنگی کی منتظر | سنک کے منتظر لین دین: {count} | Mixes ٹرانزیکشنز with لین دین (the app's term) and uses ہم آہنگی for sync. | Medium |
| `settle_nafaqah_all_settled` | ur | نفقہ کے تمام اخراجات ادا ہو چکے ہیں! بیوی کی کوئی رقم واجب الادا نہیں۔ | نفقہ کے تمام اخراجات ادا ہو چکے ہیں! اہلیہ کی کوئی رقم واجب الادا نہیں۔ | Use اہلیہ, as elsewhere. | Medium |
| `settle_wife_advanced` | ur | بیوی نے گھر کے اخراجات اپنی ذاتی رقم سے ادا کیے | اہلیہ نے گھر کے اخراجات اپنی ذاتی رقم سے ادا کیے | بیوی here, اہلیہ (the more respectful word) in all the other keys. | Medium |
| `settle_wife_amount` | ur | بیوی: {amount} | اہلیہ: {amount} | Use اہلیہ, as elsewhere. | Medium |
| `settle_wife_title` | ur | بیوی کی واجب الادا رقم ادا کریں | اہلیہ کی واجب الادا رقم ادا کریں | Use اہلیہ, as elsewhere. | Medium |
| `split_with_bnpl` | ur | یا 4 اقساط میں تقسیم کریں (تابی / تمارا) | یا تابی / تمارا کے ذریعے بغیر سود کی 4 اقساط میں تقسیم کریں | Leaves out "interest-free" (بغیر سود), which matters to Muslim users. | Medium |
| `strict_isolation` | ur | سخت چینل تنہائی | چینلز کی مکمل علیحدگی | "تنہائی" means loneliness. | Medium |
| `support_chip_iqama` | ur | 400 ریال اقامہ فیس کیسے شامل کریں؟ | 400 ریال مرافقین فیس کیسے شامل کریں؟ | Same factual point (the dependants' levy). | Medium |
| `switch_household` | ur | گھر تبدیل کریں | گھرانہ تبدیل کریں | Uses گھر (house) where the rest of the app says گھرانہ. | Medium |
| `switch_household_desc` | ur | وہ گھر منتخب کریں جس کا آپ انتظام یا جائزہ لینا چاہتے ہیں۔ | وہ گھرانہ منتخب کریں جس کا آپ انتظام یا جائزہ لینا چاہتے ہیں۔ | Should be گھرانہ, as elsewhere. | Medium |
| `sync_complete_msg` | ur | {count} آف لائن قطار والی ٹرانزیکشنز کلاؤڈ کے ساتھ ہم آہنگ ہو گئیں۔ | {count} آف لائن محفوظ لین دین کلاؤڈ کے ساتھ سنک ہو گئے۔ | Mixes ٹرانزیکشن with لین دین (the app's term) and uses ہم آہنگ for sync. | Medium |
| `sync_now` | ur | ابھی ہم آہنگ کریں | ابھی سنک کریں | "ہم آہنگ کریں" means harmonise; Urdu apps use سنک for sync. | Medium |
| `take_shot_n` | ur | تصویر نمبر لیں | تصویر لیں # | The code appends the shot number to this text, so the result reads "تصویر نمبر لیں2". This way it reads "تصویر لیں #2", like the Arabic and English. Better: a {n} placeholder (code change). | Medium |
| `total_net_worth` | ur | کل مالیاتی حجم اور لیکویڈیٹی | کل خالص مالیت اور نقدی | "مالیاتی حجم" means financial volume, not net worth. | Medium |
| `tx_delete_confirm_long` | ur | کیا آپ واقعی {merchant} پر {amount} کی یہ ٹرانزیکشن حذف کرنا چاہتے ہیں؟\nآپ کے بجٹ کی خرچ شدہ رقم خود بخود ایڈجسٹ ہو جائے گی۔ | کیا آپ واقعی {merchant} پر {amount} کا یہ لین دین حذف کرنا چاہتے ہیں؟\nآپ کے بجٹ کی خرچ شدہ رقم خود بخود ایڈجسٹ ہو جائے گی۔ | Use لین دین for transaction, as elsewhere. | Medium |
| `tx_delete_failed_err` | ur | ٹرانزیکشن حذف نہیں ہو سکی: {error} | لین دین حذف نہیں ہو سکا: {error} | Use لین دین for transaction, as elsewhere. | Medium |
| `tx_delete_failed_msg` | ur | ٹرانزیکشن حذف نہیں ہو سکی۔ براہ کرم اپنا نیٹ ورک کنکشن چیک کریں۔ | لین دین حذف نہیں ہو سکا۔ براہ کرم اپنا نیٹ ورک کنکشن چیک کریں۔ | ٹرانزیکشن here, لین دین in the navigation and the rest of the app. | Medium |
| `tx_deleted` | ur | ٹرانزیکشن حذف ہو گئی | لین دین حذف ہو گیا | Use لین دین for transaction, as elsewhere. | Medium |
| `tx_removed` | ur | ٹرانزیکشن حذف ہو گئی | لین دین حذف ہو گیا | Use لین دین for transaction, as elsewhere. | Medium |
| `tx_restore_failed_msg` | ur | ٹرانزیکشن بحال نہیں ہو سکی۔ براہ کرم اسے دوبارہ شامل کریں۔ | لین دین بحال نہیں ہو سکا۔ براہ کرم اسے دوبارہ شامل کریں۔ | Use لین دین for transaction, as elsewhere. | Medium |
| `tx_restored` | ur | ٹرانزیکشن بحال ہو گئی | لین دین بحال ہو گیا | Use لین دین for transaction, as elsewhere. | Medium |
| `tx_update_failed_msg` | ur | ٹرانزیکشن اپ ڈیٹ نہیں ہو سکی: {error} | لین دین اپ ڈیٹ نہیں ہو سکا: {error} | Use لین دین for transaction, as elsewhere. | Medium |
| `tx_updated_msg` | ur | ٹرانزیکشن اپ ڈیٹ ہو گئی اور بجٹ دوبارہ شمار کر لیا گیا۔ | لین دین اپ ڈیٹ ہو گیا اور بجٹ دوبارہ شمار کر لیا گیا۔ | Use لین دین for transaction, as elsewhere. | Medium |
| `zatca_qr_code_data` | ur | زکوٰۃ و ٹیکس کیو آر کوڈ ڈیٹا | زاتکا کیو آر کوڈ ڈیٹا | "زکوٰۃ و ٹیکس" is not the authority's name. | Medium |

#### `ai_service/_build_landing.py` (15)

| key | locale | current | suggested | reason | severity |
|---|---|---|---|---|---|
| `T.ar.b10c1` | ar | الشريك | الزوجة | Saudi users do not call a spouse "الشريك", and the app's family model is husband/wife. | Medium |
| `T.ar.b4c3` | ar | توزيع نسبي | من دفع ولمن | "توزيع نسبي" (proportional split) presents a percentage split between family members, which goes against the Nafaqah rule. | Medium |
| `T.ar.b4d` | ar | حدد من دفع ولمن — الشريك أو الأبناء المسجلون. توزيع عادل وشفاف يمنحك ووضوحاً كاملاً حول حصة كل فرد في ميزانية الأسرة. | حدد من دفع ولمن — الزوجة أو الأبناء المسجلون. توزيع عادل وشفاف يمنحك وضوحاً كاملاً حول حصة كل فرد في ميزانية الأسرة. | Typo on a public page ("يمنحك ووضوحاً", an extra و), which the HTML default does not have. "الشريك" for a spouse is unnatural in Saudi Arabic. | Medium |
| `T.ar.fa3` | ar | من إعدادات التطبيق تحت "هوية المنزل"، أضف أسماء الشريك والأبناء. عند تسجيل أي مصروف تختار بضغطة زر "لصالح من" لتقسيم النفقات بدقة وشفافية. | من إعدادات التطبيق تحت "المنزل والعضوية"، أضف الزوجة والأبناء. عند تسجيل أي مصروف تختار بضغطة زر "لصالح من" لتوزيع المصاريف بدقة وشفافية. | Points to a settings section ("هوية المنزل") that does not exist in the app (it is "المنزل والعضوية"). Also "تقسيم النفقات" sounds like splitting the Nafaqah itself. In the Python source the quotes are escaped as \\". | Medium |
| `T.ar.fq3` | ar | كيف أُضيف أسماء أبنائي وشريكي لتوزيع المصاريف؟ | كيف أُضيف زوجتي وأبنائي لتوزيع المصاريف؟ | Same "الشريك" problem. Also update the HTML default (line ~769). | Medium |
| `T.ar.lt3p` | ar | تحتفظ إدارة منصة Budget بحق تحديث المزايا والشروط دورياً لتحسين جودة وأمان الخدمة مع إشعار المستخدمين. | تحتفظ إدارة منصة Budget بحق تحديث المزايا والشروط دورياً لتحسين جودة وأمان الخدمة مع إشعار المستخدمين مسبقاً. | Terms-of-service text: the English promises prior notice, the Arabic leaves out "مسبقاً". The HTML default also says "FMSCO" where T.ar says "Budget"; pick one. | Medium |
| `T.ar.spp` | ar | حصة الشريك الثاني | حصة شريك السكن الثاني | Make the 60/40 demo explicitly about roommates. Also update the HTML default. | Medium |
| `T.ar.spy` | ar | حصة الشريك الأول (أنت) | حصة شريك السكن الأول (أنت) | Make the 60/40 demo explicitly about roommates. Also update the HTML default. | Medium |
| `T.en.b8d` | en | No SMS reading permissions requested and no bank scraping required. All data is end-to-end encrypted in your dedicated Supabase instance. | No SMS reading permissions requested and no bank scraping required. All data is encrypted in transit and at rest in Supabase. | The "end-to-end encrypted" and "dedicated instance" claims are not accurate. | Medium |
| `T.en.lp3p` | en | Users may request instantaneous permanent deletion of their account and all associated ledgers directly from settings. | Users may request full deletion of their account and records at any time from the app settings or by contacting support. | Privacy text disagrees with the Arabic, which says "request via settings or support". "Instantaneous" is a promise that may not hold. | Medium |
| `T.en.p3h` | en | End-to-End Encrypted Storage | Encrypted Storage | The "end-to-end" claim is not accurate; the Arabic (تشفير متطور للبيانات) already avoids it. | Medium |
| `T.en.spp` | en | Partner 2 Share | Roommate 2 Share | English counterpart of the Nafaqah fix. | Medium |
| `T.en.spt` | en | Simulated Expense Allocation Across Household | Simulated Expense Split Between Roommates | English counterpart of the Nafaqah fix. | Medium |
| `T.en.spy` | en | Partner 1 Share (You) | Roommate 1 Share (You) | English counterpart of the Nafaqah fix. | Medium |
| `T.en.t4` | en | Household Split | Roommate Split | English counterpart of the Nafaqah fix. | Medium |

#### `landing_page/index.html` (9)

| key | locale | current | suggested | reason | severity |
|---|---|---|---|---|---|
| `html:ai-demo-sentence` | ar | مناصفة، ودفعت | بالتساوي، ودفعت | "مناصفة" means halves (50/50), but the demo splits the bill three ways (143.33 each), so the demo contradicts itself. | Medium |
| `html:family-demo-status` | ar | تكامل الميزانية: 100% | مستحق لها على الزوج: 1,600 ر.س | In the Nafaqah model, the wife's household payment is owed back to her. | Medium |
| `html:faq-2-answer` | ar | يوم 27 المعتمد للقطاع الحكومي والخاص في السعودية بسهولة. | يوم 27 المعتمد لرواتب القطاع الحكومي في السعودية بسهولة. | Factual error: the 27th is the government payday; private-sector paydays vary. | Medium |
| `html:pillar-4-desc` | ar | والمستلزمات بنسب مئوية عادلة دون نزاع. | والمستلزمات بين شركاء السكن، ومتابعة النفقة الشرعية للأسرة دون نزاع. | Promises percentage splits for families as well, which goes against the Nafaqah rule. | Medium |
| `html:pillar-4-title` | ar | 4. التوزيع التكافلي للأسرة والسكن | 4. توزيع مصاريف الأسرة والسكن | Misuse of "تكافلي" (Takaful). | Medium |
| `html:privacy-aes-card` | ar | تشفير كامل لكافة المدخلات الحسابية محلياً وسحابياً عبر أرقى | تشفير بياناتك أثناء النقل وفي التخزين السحابي وفق أرقى | "محلياً" claims on-device encryption that does not exist. | Medium |
| `html:privacy-sms-card` | ar | تظل مشفرة في جهازك دون مساس | تبقى في جهازك ولا يطّلع عليها التطبيق | The app does not encrypt the user's SMS. The real promise is that it never reads them. | Medium |
| `html:split-title` | ar | التوزيع التكافلي العادل للمصاريف | التوزيع العادل للمصاريف | "تكافلي" is the Islamic-insurance (Takaful/Tabarru') term; using it for bill-splitting confuses the concept. | Medium |
| `html:vip-blurb` | ar | واحصل على وصول مجاني دائم للخصائص | واحصل على وصول مبكر للخصائص | "وصول مجاني دائم" (permanent free access) is a binding commercial promise that the English site does not make. | Medium |

#### `web_app/src/i18n/translations.ts` (15)

| key | locale | current | suggested | reason | severity |
|---|---|---|---|---|---|
| `ar.earlyAccess.headline` | ar | اختبر الحوكمة المالية السيادية والصفاء المعيشي | اختبر الإدارة المالية الذكية وراحة البال | "سيادي" suggests state backing; "الصفاء المعيشي" is unnatural. | Medium |
| `ar.faq.items[5].a` | ar | النسخة الحالية متاحة كتطبيق ويب فوري PWA، ونعمل حالياً على إتاحة النسخ الرسمية للمسجلين في قائمة الوصول المبكر VIP لأجهزة iPhone و Android و Huawei قريباً. | نحن حالياً في مرحلة تجريبية مغلقة (VIP)، وسيحصل المسجلون في قائمة الانتظار على أولوية الدعوة لتطبيقات iPhone و Android و Huawei AppGallery. | Says something different from the English: the Arabic says a PWA is available now, the English says private closed beta. Align them with whichever is true. | Medium |
| `ar.footer.links[0]` | ar | سياسة الخصوصية السيادية | سياسة الخصوصية | A legal document title should be the plain, standard name. | Medium |
| `ar.footer.rights` | ar | © 2025 BUDGET Tracker \| ميزانية وأكثر. الحوكمة المالية السيادية. جميع الحقوق محفوظة. | © 2026 BUDGET Tracker \| ميزانية وأكثر. جميع الحقوق محفوظة. | "سيادي" suggests state backing; the year is out of date. | Medium |
| `ar.footer.status` | ar | النظام متصل ويعمل بكفاءة • تشفير RLS 256-BIT | النظام متصل ويعمل بكفاءة • تشفير AES-256 | Wrong technical claim: RLS (row-level security) is access control, not encryption, and has no bit strength. | Medium |
| `ar.metrics.metric1Title` | ar | خصوصية سيادية تامة | خصوصية تامة | "سيادي" suggests state backing. | Medium |
| `ar.nav.security` | ar | الخصوصية السيادية | الخصوصية التامة | "سيادي" suggests state backing. | Medium |
| `ar.pillars.items[7].desc` | ar | سياسات تشفير صارمة تضمن عدم اطلاع أي طرف إلا على السجلات المصرح له بها. | سياسات وصول صارمة على مستوى الصف تضمن عدم اطلاع أي طرف إلا على السجلات المصرح له بها. | RLS is access control, not encryption ("تشفير"). | Medium |
| `ar.security.title` | ar | بياناتك ملكك وحدك. سيادة رقمية بمستويات بنكية. | بياناتك ملكك وحدك. تحكم كامل وحماية متقدمة. | "سيادة" suggests state backing, and "بمستويات بنكية" (bank-grade) is a claim that cannot be backed up. | Medium |
| `ar.simulator.countdownDays` | ar | {val} يوماً متبقية | الأيام المتبقية: {val} | "يوماً" is only correct for 11 to 99; for 3 to 10 it must be أيام. A count label avoids it. | Medium |
| `ar.simulator.familyRows[1].status` | ar | تكامل الميزانية 100% | مستحق لها على الزوج | In the Nafaqah model, the wife's 1,600 SAR household payment is owed back to her by the husband; "تكامل الميزانية" hides that. | Medium |
| `en.footer.status` | en | SYSTEM ONLINE • 256-BIT RLS | SYSTEM ONLINE • AES-256 ENCRYPTION | Wrong technical claim: RLS is access control, not 256-bit encryption. | Medium |
| `en.pillars.items[7].desc` | en | Strict cryptographic row-level security policies ensure only authorized participants view each specific record. | Strict row-level access policies ensure only authorized participants view each specific record. | RLS policies are not cryptographic. | Medium |
| `en.security.cards[2].desc` | en | End-to-end encryption in transit and at rest with isolated row-level tenant access controls. | Encryption in transit and at rest with isolated row-level tenant access controls. | "End-to-end" is a specific claim the system does not meet: the server reads the data for AI processing. The Arabic version already avoids it. | Medium |
| `en.simulator.familyRows[1].status` | en | Budget 100% reconciled | Owed back by husband | Same Nafaqah point: the wife's payment is owed back to her. | Medium |

### Low (150)


#### `flutter_app/lib/l10n/app_localizations.dart` (135)

| key | locale | current | suggested | reason | severity |
|---|---|---|---|---|---|
| `_subCategoryValues.sub-district-cooling` | ar | تبريد المناطق | التبريد المركزي | Saudi usage is التبريد المركزي; "تبريد المناطق" is a literal calque. | Low |
| `ahm_creating` | ar | جارِ إنشاء الملف... | جارٍ إنشاء الملف... | Spelling: جارٍ, not جارِ. | Low |
| `allowance_set_by_husband` | ar | يحدده الزوج أو مشرف الأسرة. | يحدده الزوج أو مشرف المنزل. | Household is المنزل elsewhere in the app. | Low |
| `apply_qr_code` | ar | تطبيق الرمز المربع | تطبيق رمز QR | Use رمز QR consistently instead of الرمز المربع. | Low |
| `ats_same_account` | ar | ما يصير حساب المصدر والوجهة نفس الحساب. | لا يمكن أن يكون حساب المصدر والوجهة نفس الحساب. | A validation message in dialect is too casual. | Low |
| `basket_optimizing` | ar | جارِ تحسين أسعار السلة... | جارٍ تحسين أسعار السلة... | Spelling: جارٍ, not جارِ. | Low |
| `bir_analyzing` | ar | جارِ تحليل الإيصال... | جارٍ تحليل الإيصال... | Spelling: جارٍ, not جارِ. | Low |
| `bm_copying` | ar | جارِ النسخ... | جارٍ النسخ... | Spelling: جارٍ, not جارِ. | Low |
| `bnpl_convert_desc` | ar | وزّع قيمة هذه المشتريات على أقساط شهرية عشان ما تنضرب ميزانيتك. | وزّع قيمة هذه المشتريات على أقساط شهرية حتى لا تتجاوز ميزانيتك. | "عشان ما تنضرب ميزانيتك" is slang, too casual for a financial explanation. | Low |
| `bnpl_convert_title` | ar | تحويل إلى خطة تقسيط (اشترِ الآن وادفع لاحقاً) | تحويل إلى خطة تقسيط | At 45 characters it is too long for a button or sheet title; the bracketed BNPL gloss can stay in the FAQ. | Low |
| `both_shared` | ar | كلينا (مشترك) | كلانا (مشترك) | Grammar: as a standalone label it should be the nominative كلانا, not كلينا. | Low |
| `budgeted` | ar | محدد بالميزانية | المُخطط | "محدد بالميزانية" is clumsy. | Low |
| `camera_permission_msg` | ar | صلاحية الكاميرا مطلوبة لمسح الرمز المربع للفواتير الضريبية.\n\nيرجى النقر على "فتح الإعدادات" لتفعيل الكاميرا لتطبيق ميزانية الأسرة. | صلاحية الكاميرا مطلوبة لمسح رمز QR في الفواتير الضريبية.\n\nيرجى الضغط على "فتح الإعدادات" لتفعيل الكاميرا لتطبيق ميزانية الأسرة. | "الرمز المربع" is not what Saudi users call it; use رمز QR consistently. | Low |
| `chat_thinking` | ar | جارِ التحليل... | جارٍ التحليل... | Spelling: جارٍ, not جارِ. | Low |
| `child_dependent` | ar | ابن / معال | طفل / مُعال | "ابن" means son only; dependents include daughters. | Low |
| `cls_deactivate_desc` | ar | إيقاف هذا التصنيف يحذفه من ميزانيتك الشهرية النشطة ويرجع المبالغ غير المصروفة إلى احتياطي المدخرات.\n\nسجل العمليات السابقة يبقى محفوظاً بالكامل. | إيقاف هذا التصنيف يحذفه من ميزانيتك الشهرية النشطة ويرجع المبالغ غير المصروفة إلى احتياطي المدخرات.\n\nسجل المعاملات السابقة يبقى محفوظاً بالكامل. | Use المعاملات for transactions, as elsewhere. | Low |
| `daily_allowance_impact` | ar | التأثير على المصروف اليومي حتى الراتب | الأثر على المصروف اليومي | At 37 characters it is too long for a card label. | Low |
| `faq_receipts_a3` | ar | إذا طابقت الفاتورة عملية مسجلة، بتظهر لك بطاقة حماية من التكرار تقدر منها تكمّل بيانات العملية الحالية، أو تسجلها كمصروف منفصل، أو تتجاهلها. | إذا طابقت الفاتورة معاملة مسجلة، بتظهر لك بطاقة حماية من التكرار تقدر منها تكمّل بيانات المعاملة الحالية، أو تسجلها كمصروف منفصل، أو تتجاهلها. | Use المعاملة for transaction, as elsewhere. | Low |
| `hmc_allowance_per_month` | ar | •  {amount} ر.س/شهرياً | •  {amount} ر.س/شهر | "/شهرياً" puts an adverb inside a unit; use /شهر. | Low |
| `inst_x_of_y_paid` | ar | تم سداد {paid} من {count} | تم سداد القسط {paid} من {count} | Leaves out "installment". | Low |
| `invite_role_spouse` | ar | الزوجة / شريكة الأسرة | الزوجة | "شريكة الأسرة" is not natural Saudi Arabic and blurs the role, which drives the Nafaqah rules. | Low |
| `isc_negative` | ar | الدخل ما يكون بالسالب | لا يمكن أن يكون الدخل بالسالب | A validation message in dialect is too casual. | Low |
| `language_ur` | ar | اردو (Urdu) | اردو (الأوردية) | English left in an Arabic value. | Low |
| `map_budget_account_desc` | ar | اختر الحساب البنكي أو المحفظة أو الصندوق المشترك لتمويل هذا التصنيف. ستخصم العمليات من هذا الرصيد تلقائياً. | اختر الحساب البنكي أو المحفظة أو الصندوق المشترك لتمويل هذا التصنيف. ستُخصم المعاملات من هذا الرصيد تلقائياً. | Use المعاملات for transactions, as elsewhere. | Low |
| `n_months` | ar | {count} أشهر | المدة: {count} أشهر | "{count} أشهر" is wrong grammar for 2 (شهران) and 11 or more (شهراً). This at least reads as a label; the real fix is ICU plurals. | Low |
| `nafaqah_err_forbidden` | ar | هذا الإجراء للزوج أو الزوجة أو مشرف الأسرة فقط. | هذا الإجراء للزوج أو الزوجة أو مشرف المنزل فقط. | Household is المنزل elsewhere in the app (not الأسرة). | Low |
| `nafaqah_wife_reimbursable_hint` | ar | دفعت الزوجة لمصروفات الأسرة. يسترد لها بالكامل 100% من الزوج. | دفعت الزوجة لمصروفات البيت، ويستردها كاملة من الزوج. | "بالكامل 100%" says the same thing twice; the verb should agree with the money, not the wife. | Low |
| `paid_by_partner` | ar | دفع بواسطة الشريك | دفعه الشريك | "دفع بواسطة" is a calque of the English passive. | Low |
| `pay_method_cash` | ar | نقداً | نقد | An option label should be a noun, not the adverb نقداً. | Low |
| `pdf_desc` | ar | كشف حساب شهري متكامل شامل توزيع الشريك، وضريبة القيمة المضافة 15%، والميزانيات. | كشف حساب شهري متكامل يشمل توزيع الشريك، وضريبة القيمة المضافة 15%، والميزانيات. | Grammar: "شامل" should be the verb "يشمل". | Low |
| `pds_saving` | ar | جارِ الحفظ... | جارٍ الحفظ... | Spelling: جارٍ, not جارِ. | Low |
| `reports_offline_queue` | ar | التقارير وطابور العمل دون اتصال | التقارير وقائمة الانتظار دون اتصال | "طابور العمل" is a literal calque. | Low |
| `scan_ai_scanning` | ar | جارِ مسح الإيصال الطويل بالذكاء الاصطناعي... | جارٍ مسح الإيصال الطويل بالذكاء الاصطناعي... | Spelling: جارٍ, not جارِ. | Low |
| `scan_confirm_save_items` | ar | تأكيد وحفظ {count} بند ({amount}) | تأكيد وحفظ البنود ({count}) ({amount}) | "{count} بند" is wrong grammar for 3 to 10. | Low |
| `scan_items_logged` | ar | تم تسجيل {count} بند باسم {merchant} ({amount}) | تم تسجيل البنود ({count}) لدى {merchant} ({amount}) | "{count} بند" is wrong grammar for 3 to 10, and "باسم" (in the name of) is the wrong preposition for a merchant. | Low |
| `scan_reading_items` | ar | جارِ قراءة جميع البنود واحداً واحداً من {count} صورة | جارٍ قراءة جميع البنود واحداً واحداً من {count} صورة | Spelling: جارٍ, not جارِ. | Low |
| `settle_owes` | ar | {from} عليه لـ {to} | {from} مدين لـ {to} | "عليه لـ" with no object is clumsy. | Low |
| `support_thinking` | ar | جارِ التفكير... | جارٍ التفكير... | Spelling: "جارٍ" (with tanween) as in other keys, not "جارِ". | Low |
| `support_welcome` | ar | مرحباً بك في مركز المساعدة والدعم الذكي! 👋\nأنا مساعدك التقني، كيف أقدر أساعدك اليوم في إدارة الميزانية، دورة الرواتب، أو مسح الفواتير؟ | مرحباً بك في مركز المساعدة والدعم الذكي! 👋\nأنا مساعدك التقني، كيف أقدر أساعدك اليوم في إدارة الميزانية، أو دورة الراتب، أو مسح الفواتير؟ | "دورة الرواتب" (plural) should be the app's term دورة الراتب. | Low |
| `sync_complete_msg` | ar | تمت مزامنة {count} من العمليات المحفوظة دون اتصال مع السحابة. | تمت مزامنة {count} من المعاملات المحفوظة دون اتصال مع السحابة. | Uses العمليات; the app's term for a transaction is المعاملة. | Low |
| `total_breakdown` | ar | إجمالي التفصيل | تفصيل الإجمالي | Wrong order: "إجمالي التفصيل" means the total of the breakdown. | Low |
| `vlb_listening` | ar | 🎙️ جاري الاستماع باللغة العربية... تحدث الآن | 🎙️ جارٍ الاستماع باللغة العربية... تحدث الآن | Spelling: جارٍ, not جاري. | Low |
| `cls_deactivate_desc` | en | Inactivating this category removes it from your active monthly budget and returns unspent funds to your Savings Reserve.\n\nAll past transaction history remains safe and intact. | Deactivating this category removes it from your active monthly budget and returns unspent funds to your Savings Reserve.\n\nAll past transaction history remains safe and intact. | English: "Inactivating" is not standard; the UI says "Deactivate". | Low |
| `psim_days_to_payday` | en | Days to Payday: {days} days away | Days to payday: {days} | English: "{days} days away" repeats "days". | Low |
| `sac_spent_by_caps` | en | SPENT BY WHO? | SPENT BY WHOM? | English grammar: "by whom", not "by who". | Low |
| `wife_personal_budget` | en | Wife Monthly Allowance | Wife's Monthly Allowance | English: missing possessive. | Low |
| `add_household_member` | ur | گھر یا رہائشی گروپ کا رکن شامل کریں | گھرانے کا رکن شامل کریں | Use گھرانہ, as elsewhere (ahm_title is already this). | Low |
| `ahm_child_desc` | ur | ذاتی اخراجات اور الاؤنس کی نگرانی، تصفیے کے بیلنس کے بغیر۔ | ذاتی اخراجات اور جیب خرچ کا ریکارڈ، تصفیے کے بیلنس کے بغیر۔ | "الاؤنس" is English; use جیب خرچ. | Low |
| `ahm_peer_desc` | ur | رہائشی اخراجات میں شریک ہوتا ہے اور قرضوں کی سادہ تقسیم میں حصہ لیتا ہے۔ | رہائشی اخراجات میں شریک ہوتا ہے اور قرضوں کو آسان بنانے میں حصہ لیتا ہے۔ | "قرضوں کی سادہ تقسیم" is a different idea from debt simplification. | Low |
| `all_cycles` | ur | تمام ادوار | تمام سائیکلز | "ادوار" is a third term for cycles; use سائیکل consistently. | Low |
| `allowance` | ur | یومیہ الاؤنس | یومیہ قابلِ خرچ | "الاؤنس" is English; the key is the daily spendable amount. | Low |
| `appearance` | ur | ایپ کا منظر | ظاہری شکل | "ایپ کا منظر" (the app's scenery) is unnatural for the theme setting. | Low |
| `appearance_language` | ur | منظر اور زبان | ظاہری شکل اور زبان | Same "منظر" problem as appearance. | Low |
| `attributed_to` | ur | کی طرف منسوب: | کس کے لیے: | Unnatural word order for a label. | Low |
| `batch_scan_desc` | ur | مسلسل کئی رسیدیں محفوظ کریں اور ایک ایک کر کے جائزہ لیں۔ | کئی رسیدوں کی تصاویر ترتیب سے لیں اور ایک ایک کر کے جائزہ لیں۔ | "محفوظ کریں" (save) is wrong for "capture". | Low |
| `bm_add_category_failed_msg` | ur | زمرہ شامل نہیں ہو سکا: {error} | کیٹیگری شامل نہیں ہو سکی: {error} | Use کیٹیگری, not زمرہ. | Low |
| `bm_add_sub_failed_msg` | ur | ذیلی زمرہ شامل نہیں ہو سکا: {error} | ذیلی کیٹیگری شامل نہیں ہو سکی: {error} | Use کیٹیگری, not زمرہ. | Low |
| `bm_add_tooltip` | ur | زمرہ یا ذیلی زمرہ شامل کریں | کیٹیگری یا ذیلی کیٹیگری شامل کریں | Use کیٹیگری, not زمرہ. | Low |
| `bm_cat_activated` | ur | زمرہ "{name}" فعال ہو گیا۔ | کیٹیگری "{name}" فعال ہو گئی۔ | Use کیٹیگری, not زمرہ. | Low |
| `bm_cat_deactivated` | ur | زمرہ "{name}" غیر فعال ہو گیا۔ | کیٹیگری "{name}" غیر فعال ہو گئی۔ | Use کیٹیگری, not زمرہ. | Low |
| `bm_category_added_msg` | ur | زمرہ "{name}" شامل ہو گیا ({amount})! | کیٹیگری "{name}" شامل ہو گئی ({amount})! | Use کیٹیگری, not زمرہ (feminine verb). | Low |
| `bm_category_created` | ur | زمرہ بن گیا | کیٹیگری بن گئی | Use کیٹیگری, not زمرہ. | Low |
| `bm_create_category` | ur | زمرہ بنائیں | کیٹیگری بنائیں | Use کیٹیگری, not زمرہ. | Low |
| `bm_deactivate_desc` | ur | اس سے {category} غیر فعال ہو کر زمروں کی لائبریری میں چلا جائے گا۔ زمرے کبھی حذف نہیں ہوتے، اس لیے آپ کی مالی تاریخ محفوظ رہتی ہے اور آپ اسے کسی بھی وقت دوبارہ فعال کر سکتے ہیں۔ | اس سے {category} غیر فعال ہو کر کیٹیگری لائبریری میں چلی جائے گی۔ کیٹیگریز کبھی حذف نہیں ہوتیں، اس لیے آپ کی مالی تاریخ محفوظ رہتی ہے اور آپ اسے کسی بھی وقت دوبارہ فعال کر سکتے ہیں۔ | Use کیٹیگری, not زمرہ. | Low |
| `bm_deactivate_failed_msg` | ur | زمرہ غیر فعال نہیں ہو سکا: {error} | کیٹیگری غیر فعال نہیں ہو سکی: {error} | Use کیٹیگری, not زمرہ. | Low |
| `bm_deactivated_msg` | ur | زمرہ "{name}" زمروں کی لائبریری میں منتقل ہو گیا (غیر فعال)۔ | کیٹیگری "{name}" کیٹیگری لائبریری میں منتقل ہو گئی (غیر فعال)۔ | Use کیٹیگری, not زمرہ. | Low |
| `bm_deactivated_title` | ur | زمرہ غیر فعال ہو گیا | کیٹیگری غیر فعال ہو گئی | Use کیٹیگری, not زمرہ. | Low |
| `bm_option_rollover` | ur | آپشن A: اضافی گنجائش کے طور پر منتقل کریں | آپشن A: گنجائش میں منتقل کریں | At 41 characters it is too long for a dialog action button. | Low |
| `bm_sub_added_msg` | ur | ذیلی زمرہ "{name}" بجٹ میں شامل ہو گیا! | ذیلی کیٹیگری "{name}" بجٹ میں شامل ہو گئی! | Use کیٹیگری, not زمرہ. | Low |
| `bm_sub_added_title` | ur | ذیلی زمرہ شامل ہو گیا | ذیلی کیٹیگری شامل ہو گئی | Use کیٹیگری, not زمرہ. | Low |
| `bm_unspent_desc` | ur | پچھلے سائیکل سے آپ کے پاس {amount} بچے ہیں۔\n\n• آپشن A: غیر خرچ شدہ رقم کو اس سائیکل کے زمروں میں اضافی گنجائش کے طور پر منتقل کریں۔\n• آپشن C: بچی ہوئی رقم بچت میں ڈالیں اور نئے ہدف بجٹ سے شروع کریں۔ | پچھلے سائیکل سے آپ کے پاس {amount} بچے ہیں۔\n\n• آپشن A: غیر خرچ شدہ رقم کو اس سائیکل کی کیٹیگریز میں اضافی گنجائش کے طور پر منتقل کریں۔\n• آپشن C: بچی ہوئی رقم بچت میں ڈالیں اور نئے ہدف بجٹ سے شروع کریں۔ | Use کیٹیگری, not زمرہ. | Low |
| `camera_permission_msg` | ur | انوائس کیو آر کوڈ اسکین کرنے کے لیے کیمرہ کی اجازت درکار ہے۔\n\nبراہ کرم سیٹنگز میں کیمرہ فعال کریں۔ | انوائس کے کیو آر کوڈ اسکین کرنے کے لیے کیمرے کی اجازت درکار ہے۔\n\nبجٹ ٹریکر کے لیے کیمرہ فعال کرنے کے لیے براہِ کرم "ترتیبات کھولیں" دبائیں۔ | Leaves out the button name the English points to; سیٹنگز and ترتیبات are mixed. | Low |
| `caution_reallocation` | ur | احتیاط (دوسری مد سے رقم منتقل کرنی ہوگی) | احتیاط (رقم منتقل کرنی ہوگی) | At 40 characters it is too long for a status label. | Low |
| `chat_offline_queued` | ur | 📶 آف لائن: مقامی قطار میں محفوظ کر لیا گیا۔ نیٹ ورک بحال ہوتے ہی خود بخود ہم آہنگ ہو جائے گا۔ | 📶 آف لائن: مقامی قطار میں محفوظ کر لیا گیا۔ نیٹ ورک بحال ہوتے ہی خود بخود سنک ہو جائے گا۔ | "ہم آہنگ" means harmonise; use سنک for sync. | Low |
| `child_dependent_desc` | ur | چیٹ اور لین دین میں انفرادی اخراجات کو منسوب کرنے کے لیے بچہ یا فیملی ممبر شامل کریں۔ | چیٹ اور لین دین میں انفرادی اخراجات منسوب کرنے کے لیے بچہ یا خاندان کا زیرِ کفالت فرد شامل کریں۔ | "فیملی ممبر" is English. | Low |
| `cls_all_active` | ur | تمام زمرے اس وقت فعال ہیں | تمام کیٹیگریز اس وقت فعال ہیں | Use کیٹیگری, not زمرہ. | Low |
| `cls_deactivate_desc` | ur | اس زمرے کو غیر فعال کرنے سے یہ ماہانہ بجٹ سے ہٹ جائے گا اور غیر خرچ شدہ رقم بچت ریزرو میں واپس چلی جائے گی۔\n\nپچھلی تمام ٹرانزیکشنز محفوظ رہیں گی۔ | اس کیٹیگری کو غیر فعال کرنے سے یہ ماہانہ بجٹ سے ہٹ جائے گی اور غیر خرچ شدہ رقم بچت کے ذخیرے میں واپس چلی جائے گی۔\n\nپچھلا تمام لین دین محفوظ رہے گا۔ | Use کیٹیگری and لین دین, as elsewhere. | Low |
| `cls_no_active` | ur | کوئی فعال زمرہ نہیں | کوئی فعال کیٹیگری نہیں | Use کیٹیگری, not زمرہ. | Low |
| `dismiss` | ur | خارج کریں | نظر انداز کریں | "خارج کریں" means "expel/remove". | Low |
| `faq_bills_a1` | ur | ڈیش بورڈ کے بار بار آنے والے بلوں کے کارڈ میں "بل منظم کریں" پر ٹیپ کریں، کسی بھی ذیلی بجٹ کو بار بار آنے والا بنائیں اور اس کی ماہانہ تاریخ مقرر کریں۔ | ڈیش بورڈ کے باقاعدہ بلوں والے کارڈ میں "ترتیب دیں" پر ٹیپ کریں، کسی بھی ذیلی بجٹ کو باقاعدہ بل بنائیں اور اس کی ماہانہ تاریخ مقرر کریں۔ | Clumsy wording for "recurring", and the button name does not match the real button (rb_configure is "ترتیب دیں"). The English names a "Manage Bills" button, but the UI says "Configure". | Low |
| `faq_bills_q1` | ur | بار بار آنے والے بل (کرایہ، یوٹیلیٹیز، فائبر) کیسے شامل کروں؟ | باقاعدہ بل (کرایہ، یوٹیلیٹیز، فائبر) کیسے شامل کروں؟ | Clumsy wording for "recurring". | Low |
| `faq_bills_q3` | ur | بار بار آنے والے بل کو ادا شدہ کیسے نشان زد کروں؟ | باقاعدہ بل کو ادا شدہ کیسے نشان زد کروں؟ | Clumsy wording for "recurring". | Low |
| `faq_cat_bills` | ur | بار بار آنے والے بل اور اقامہ ریزرو | باقاعدہ بل اور اقامہ ریزرو | "بار بار آنے والے" (keeps coming again and again) is clumsy for "recurring". | Low |
| `faq_receipts_a3` | ur | اگر انوائس کسی موجودہ ٹرانزیکشن سے ملتی ہے تو ڈپلیکیٹ تحفظ کارڈ ظاہر ہوگا جس سے آپ موجودہ ٹرانزیکشن مکمل کر سکتے ہیں، الگ خرچ کے طور پر درج کر سکتے ہیں یا اسے مسترد کر سکتے ہیں۔ | اگر انوائس کسی موجودہ لین دین سے ملتی ہے تو ڈپلیکیٹ تحفظ کارڈ ظاہر ہوگا جس سے آپ موجودہ لین دین مکمل کر سکتے ہیں، الگ خرچ کے طور پر درج کر سکتے ہیں یا اسے مسترد کر سکتے ہیں۔ | Use لین دین for transaction, as elsewhere. | Low |
| `faq_salary_q3` | ur | یومیہ الاؤنس کیسے شمار کیا جاتا ہے؟ | یومیہ خرچ کی حد کیسے شمار کی جاتی ہے؟ | "الاؤنس" is English. | Low |
| `grocery_touch` | ur | تفصیل کے لیے ٹچ کریں | تفصیل کے لیے ٹیپ کریں | Elsewhere the app says ٹیپ کریں. | Low |
| `hmc_one_active_member` | ur | 1 فعال رکن | ایک فعال رکن | Unnatural word order with the digit. | Low |
| `icr_desc` | ur | "{merchant}" پر {amount} کا یہ خرچ زمرہ "{category}" سے متعلق ہے، جو اس وقت آپ کے گھرانے کے لیے غیر فعال ہے۔ | "{merchant}" پر {amount} کا یہ خرچ کیٹیگری "{category}" سے متعلق ہے، جو اس وقت آپ کے گھرانے کے لیے غیر فعال ہے۔ | Use کیٹیگری, not زمرہ. | Low |
| `icr_other_category` | ur | کسی اور زمرے میں درج کریں | کسی اور کیٹیگری میں درج کریں | Use کیٹیگری, not زمرہ. | Low |
| `icr_reactivate` | ur | زمرہ دوبارہ فعال کریں | کیٹیگری دوبارہ فعال کریں | Use کیٹیگری, not زمرہ. | Low |
| `icr_title` | ur | غیر فعال زمرہ | غیر فعال کیٹیگری | Use کیٹیگری, not زمرہ. | Low |
| `invite_linked_profile` | ur | منسلک پروفائل کے ساتھ دعوت نامہ | پروفائل کے ساتھ مدعو کریں | Too long for a button (31 characters). | Low |
| `language_en` | ur | English | English (انگریزی) | Other language entries show the native name with the localized name in brackets. | Low |
| `manage` | ur | انتظام | انتظام کریں | A button label needs a verb. | Low |
| `mes_saved_offline` | ur | آف لائن محفوظ: {merchant} پر {amount}۔ خود بخود ہم آہنگ ہو جائے گا۔ | آف لائن محفوظ: {merchant} پر {amount}۔ خود بخود سنک ہو جائے گا۔ | Use سنک for sync. | Low |
| `monthly_allowance_masroof` | ur | ماہانہ جیب خرچ / خرچہ (اختیاری) | ماہانہ جیب خرچ (اختیاری) | Keep this the same as ahm_allowance_caps (same field). | Low |
| `mp_queued_offline_msg` | ur | رسید کی تصاویر مقامی آف لائن قطار میں محفوظ ہو گئیں۔ کنکشن بحال ہوتے ہی خود بخود ہم آہنگ ہو جائیں گی۔ | رسید کی تصاویر مقامی آف لائن قطار میں محفوظ ہو گئیں۔ کنکشن بحال ہوتے ہی خود بخود سنک ہو جائیں گی۔ | Use سنک for sync. | Low |
| `new_item` | ur | نئی آئٹم | نیا آئٹم | آئٹم is normally masculine in Urdu. | Low |
| `no_matching_tx_desc` | ur | مطلوبہ نتیجہ تلاش کرنے کے لیے فلٹرز، تاریخ کی حد یا زمرہ تبدیل کر کے دیکھیں۔ | مطلوبہ نتیجہ تلاش کرنے کے لیے فلٹرز، تاریخ کی حد یا کیٹیگری تبدیل کر کے دیکھیں۔ | Use کیٹیگری, not زمرہ. | Low |
| `pdf_statement_desc` | ur | ماہانہ ایگزیکٹو اسٹیٹمنٹ جس میں شراکت داروں کی تقسیم، 15% VAT اور زمرہ وار بجٹ شامل ہیں۔ | ماہانہ ایگزیکٹو اسٹیٹمنٹ جس میں شراکت داروں کی تقسیم، 15% VAT اور کیٹیگری وار بجٹ شامل ہیں۔ | Use کیٹیگری (the term on the budget screens), not زمرہ. | Low |
| `pds_title` | ur | تنخواہ اور تنخواہ کا سائیکل | تنخواہ کا دن اور سائیکل | "تنخواہ اور تنخواہ کا سائیکل" repeats "salary". | Low |
| `perm_pool_admin_only` | ur | مشترکہ پول سے رقم نکالنا صرف گھر کے ایڈمن کر سکتے ہیں۔ | مشترکہ پول سے رقم نکالنا صرف گھرانے کے ایڈمن کر سکتے ہیں۔ | Use گھرانہ, not گھر. | Low |
| `perm_tx_admin_only` | ur | دوسرے ارکان کے اخراجات میں ترمیم یا حذف صرف گھر کے ایڈمن کر سکتے ہیں۔ | دوسرے ارکان کے اخراجات میں ترمیم یا حذف صرف گھرانے کے ایڈمن کر سکتے ہیں۔ | Use گھرانہ, not گھر. | Low |
| `process` | ur | پروسیس | پروسیس کریں | A button label needs a verb. | Low |
| `prompt_on_conflict` | ur | تنازع پر پوچھیں | ٹکراؤ کی صورت میں پوچھیں | "تنازع" means a dispute between people. | Low |
| `psim_daily_now` | ur | موجودہ یومیہ الاؤنس | موجودہ یومیہ قابلِ خرچ رقم | "الاؤنس" is English. | Low |
| `rb_all_paid` | ur | اس سائیکل کے تمام بار بار آنے والے بل ادا ہو چکے ہیں! | اس سائیکل کے تمام باقاعدہ بل ادا ہو چکے ہیں! | Clumsy wording for "recurring". | Low |
| `rb_manage_desc` | ur | منتخب کریں کہ کون سی ذیلی آئٹمز (یوٹیلیٹیز، اقامہ فیس، کرایہ، سبسکرپشنز) ماہانہ بار بار آنے والی ذمہ داریوں کے طور پر ٹریک ہوں اور تنخواہ سے مختص کی جائیں۔ | منتخب کریں کہ کون سی ذیلی آئٹمز (یوٹیلیٹیز، اقامہ فیس، کرایہ، سبسکرپشنز) ماہانہ باقاعدہ ادائیگیوں کے طور پر ٹریک ہوں اور ان کی رقم تنخواہ سے مختص کی جائے۔ | Clumsy wording for "recurring". | Low |
| `rb_manage_title` | ur | بار بار آنے والے بلوں کا انتظام | باقاعدہ بلوں کا انتظام | Clumsy wording for "recurring". | Low |
| `receipt_n_of_m` | ur | رسید {current} از {total} | رسید {current} (کل {total}) | "از" is Persian. | Low |
| `recurring_bills` | ur | ماہانہ بلز اور ریزرو | باقاعدہ بلز اور ریزرو | "Recurring" is not the same as "monthly" (ماہانہ); bills can be yearly or quarterly. | Low |
| `rid_family_desc` | ur | زیرِ کفالت فرد: ذاتی الاؤنس کی نگرانی اور انفرادی اخراجات کی رپورٹ۔ | زیرِ کفالت فرد: ذاتی جیب خرچ کی نگرانی اور انفرادی اخراجات کی رپورٹ۔ | "الاؤنس" is English; the app's Urdu term for allowance is جیب خرچ. | Low |
| `rid_peer_desc` | ur | مشترکہ رہائش کا کھاتہ: متعدد روم میٹس کے درمیان تصفیہ اور قرضوں کی سادہ تقسیم۔ | مشترکہ رہائش کا کھاتہ: متعدد روم میٹس کے درمیان تصفیہ اور قرضوں کو آسان بنانا۔ | "قرضوں کی سادہ تقسیم" (simple division of debts) is a different idea from debt simplification. | Low |
| `roles_last_admin` | ur | گھر میں کم از کم ایک ایڈمن ہونا ضروری ہے۔ | گھرانے میں کم از کم ایک ایڈمن ہونا ضروری ہے۔ | Use گھرانہ, not گھر. | Low |
| `rollover_recommended` | ur | تجویز کردہ پہلے سے طے شدہ | تجویز کردہ (ڈیفالٹ) | Word-for-word calque. | Low |
| `rollover_send_to_savings_title` | ur | تمام رقم بچت کے ذخیرے میں منتقل کریں | سب بچت میں منتقل کریں | At 36 characters it is too long for an option title. | Low |
| `save_and_next` | ur | محفوظ کریں اور آگے → | محفوظ کریں اور آگے ← | In right-to-left Urdu, "next" points left (the Arabic already uses ←). | Low |
| `sba_add_sub_for` | ur | {category} کے لیے ذیلی زمرہ شامل کریں | {category} کے لیے ذیلی کیٹیگری شامل کریں | Use کیٹیگری, not زمرہ. | Low |
| `sba_remove_title` | ur | ذیلی زمرہ ہٹائیں؟ | ذیلی کیٹیگری ہٹائیں؟ | Use کیٹیگری, not زمرہ. | Low |
| `sba_removed_title` | ur | ذیلی زمرہ ہٹا دیا گیا | ذیلی کیٹیگری ہٹا دی گئی | Use کیٹیگری, not زمرہ. | Low |
| `sba_renamed_to` | ur | ذیلی زمرے کا نام "{name}" کر دیا گیا۔ | ذیلی کیٹیگری کا نام "{name}" کر دیا گیا۔ | Use کیٹیگری, not زمرہ. | Low |
| `sbb_pct_of_category` | ur | زمرے کا {percent}% | کیٹیگری کا {percent}% | Use کیٹیگری, not زمرہ. | Low |
| `set_generate_standard_csv_date_merchant` | ur | تاریخ، دکان، زمرہ اور آئٹمز کے ساتھ معیاری CSV بنائیں | تاریخ، دکان، کیٹیگری اور آئٹمز کے ساتھ معیاری CSV بنائیں | Use کیٹیگری, not زمرہ. | Low |
| `set_join_create_household` | ur | گھرانے میں شامل ہوں یا نیا بنائیں | گھرانہ بنائیں یا شامل ہوں | At 33 characters it is too long for a button. | Low |
| `settle_pays` | ur | {from} {to} کو ادا کرے گا | {from}، {to} کو ادا کرے گا | Two names side by side with no separator read as one name. | Low |
| `shared_pool_desc` | ur | مشترکہ اخراجات کے لیے گھر کے تمام افراد کو نظر آئے گا | مشترکہ اخراجات کے لیے گھرانے کے تمام ارکان کو نظر آئے گا | Should be گھرانہ, as elsewhere. | Low |
| `sim_advice_caution` | ur | لچکدار بجٹ سے رقم منتقل کر کے ہی ممکن ہے؛ آپ کا یومیہ الاؤنس کم ہو جائے گا۔ | لچکدار بجٹ سے رقم منتقل کر کے ہی ممکن ہے؛ آپ کی یومیہ خرچ کی حد کم ہو جائے گی۔ | "الاؤنس" is English. | Low |
| `sim_advice_comfortable` | ur | یہ اس زمرے کے بجٹ میں آسانی سے پورا ہو جاتا ہے۔ | یہ اس کیٹیگری کے بجٹ میں آسانی سے پورا ہو جاتا ہے۔ | Use کیٹیگری, not زمرہ. | Low |
| `single_expense` | ur | واحد خرچ | ایک خرچ | "واحد خرچ" sounds odd in Urdu. | Low |
| `strict_desc` | ur | رسید اسکین اور چیٹ کے درمیان یکساں رقم اور دکان کے اندراج کو فلیگ کریں۔ | رسید اسکین اور اے آئی چیٹ کے درمیان ایک ہی دکان اور رقم کے دہرے اندراج کو نشان زد کریں۔ | "فلیگ کریں" is English; "یکساں" is vaguer than "duplicate". | Low |
| `sync_complete` | ur | ہم آہنگی مکمل | سنک مکمل | "ہم آہنگی" means harmony. | Low |
| `theme_system` | ur | سسٹم کا پہلے سے طے شدہ | سسٹم کے مطابق | "سسٹم کا پہلے سے طے شدہ" is a word-for-word calque. | Low |
| `wt3_desc` | ur | 27 تاریخ کی تنخواہ سے ہم آہنگ خودکار سائیکلز، یومیہ الاؤنس اور سائیکل رول اوور کے ساتھ اپنی مالی صحت پر نظر رکھیں۔ | 27 تاریخ کی تنخواہ سے ہم آہنگ خودکار سائیکلز، یومیہ خرچ کی حد اور سائیکل رول اوور کے ساتھ اپنی مالی صحت پر نظر رکھیں۔ | "الاؤنس" is English. | Low |
| `wt4_title` | ur | بار بار آنے والے بل اور اقساط | باقاعدہ بل اور اقساط | Clumsy wording for "recurring". | Low |
| `wt_feature_x_of_y` | ur | خصوصیت {current} از {total} | {total} میں سے {current} خصوصیت | "از" is Persian; Urdu says میں سے. | Low |

#### `ai_service/_build_landing.py` (2)

| key | locale | current | suggested | reason | severity |
|---|---|---|---|---|---|
| `T.ar.cu` | ar | "عشاء عائلي في البيك بـ 68 ريال، دفعتها أنا للأسرة" | "عشاء عائلي في البيك بـ 68 ريال، دفعته أنا للأسرة" | Agreement: عشاء is masculine (دفعته). In the Python source the quotes are escaped as \\". | Low |
| `T.ar.simB` | ar | ✓ موازنة العطلات تلقائياً | ✓ تعديل تلقائي عند العطلات | "موازنة العطلات" (balancing the holidays) is unclear. | Low |

#### `landing_page/index.html` (5)

| key | locale | current | suggested | reason | severity |
|---|---|---|---|---|---|
| `html:ai-demo-result` | ar | تم التفكيك بنجاح إلى بندين ومشاركين 2 | تم التفكيك بنجاح إلى بندين ومشاركَين اثنين | Mixes a digit with the dual form. | Low |
| `html:footer-rights` | ar | © 2025 BUDGET Tracker | © 2026 BUDGET Tracker | The year is out of date. | Low |
| `html:footer-status` | ar | النظام يعمل بكفاءة 100% • مشفر محلياً | النظام يعمل بكفاءة | "مشفر محلياً" is a claim that cannot be backed up. | Low |
| `html:privacy-local-card` | ar | دون إرسال لهيئات | دون إرسالها لجهات | Wrong word: "هيئات" means government authorities; the meaning is marketing companies (جهات). | Low |
| `html:zatca-demo-seller` | ar | شركة بندة للتجزئة ش.م.م | شركة بنده للتجزئة | The brand is spelled بنده (as in the app), and "ش.م.م" is a Levantine/Egyptian abbreviation not used in Saudi company names. | Low |

#### `web_app/src/i18n/translations.ts` (8)

| key | locale | current | suggested | reason | severity |
|---|---|---|---|---|---|
| `ar.metrics.metric1Desc` | ar | صفر قراءة للرسائل النصية، صفر ربط بنكي إجباري. بياناتك تظل ملكك وحدك. | لا نقرأ رسائلك النصية ولا نشترط أي ربط بنكي. بياناتك تظل ملكك وحدك. | "صفر قراءة" is a calque. | Low |
| `ar.nav.securitySub` | ar | صفر ربط بنكي | بدون ربط بنكي | "صفر ربط" is a literal calque of "zero bank-link". | Low |
| `ar.security.cards[1].title` | ar | صفر قراءة للرسائل النصية والـ OTP | لا نقرأ رسائلك النصية ولا رموز التحقق | "صفر قراءة" is a calque. | Low |
| `ar.simulator.aiImpactVal` | ar | 42% متبقي • في النطاق الآمن | متبقٍ 42% • في النطاق الآمن | Spelling (متبقٍ) and word order. | Low |
| `ar.simulator.aiNoteRooms` | ar | (غرفتين) | (غرفتان) | Grammar: a standalone label takes the nominative. | Low |
| `en.faq.items[0].a` | en | We leverage ultra-fast AI input modalities: conversational voice parsing, natural text interpretation, and instantaneous ZATCA QR decoding. By avoiding traditional open-banking integrations, you never expose bank account passwords, card pins, or personal SMS text records to any cloud aggregator. | We leverage ultra-fast AI input modalities: conversational voice parsing, natural text interpretation, and instantaneous ZATCA QR decoding. By avoiding traditional open-banking integrations, you never expose bank account passwords, card PINs, or personal SMS text records to any cloud aggregator. | English typo: PINs. | Low |
| `en.footer.rights` | en | © 2025 BUDGET Tracker Sovereign Financial Architecture. All rights reserved. Built for clarity and equitable shared living. | © 2026 BUDGET Tracker. All rights reserved. Built for clarity and equitable shared living. | The year is out of date. | Low |
| `en.simulator.day27Label` | en | Day 27 (GCC Public) | Day 27 (Saudi Public Sector) | The 27th payday is a Saudi public-sector rule, not a GCC-wide one; the Arabic says الراتب الحكومي. | Low |
