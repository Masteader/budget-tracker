================================================================================
PART 1: SAVE THIS EXACT CONTENT AS `docs/STITCH_UI_PROMPTS.md` IN YOUR PROJECT ROOT
================================================================================

# Budget Tracker — Stitch & Flutter 3D UI Redesign Blueprint (Light & Dark Mode)

## 0. Mandatory Execution Pipeline for Antigravity
**CRITICAL RULE:** Do NOT generate or refactor all screens in one turn. Execute strictly in 3 sequential phases:

### Phase 1: Global Theme & 3D Atomic Widgets
1. Create `lib/core/theme/velvet_burgundy_theme.dart` supporting both **Light Mode** and **Dark Mode**.
2. Build reusable 3D atomic widgets in `lib/core/widgets/`:
   - `VelvetWaveHeader`: Curved burgundy top wave (`#4A0E1E` to `#2A050E`) with 3D circular action buttons.
   - `ThreeDSurfaceCard`: Uniform 3D squircle card (`22px` radius, `1.5px` top white/rose bevel highlight, `2.5px` bottom lip, deep drop shadow). *Light Mode uses Pure White (`#FFFFFF`) surfaces; Dark Mode uses Dark Plum-Charcoal (`#1E0B12`) surfaces.*
   - `ThreeDPillButton`: Extruded 3D Velvet Burgundy (`#4A0E1E`) pill button with top specular bevel and cast shadow.
   - `ThreeDIconPuck`: Raised `44px` circular/squircle burgundy or rose-gold icon puck casting a 45° diagonal drop shadow.
   - `GlassmorphicBottomDock`: Floating frosted capsule (`30px` radius, `backdrop-filter: blur(24px)`, `1.5px` specular glass border, active dot indicator, and raised 3D burgundy `+` center orb).
3. Run `flutter analyze` and fix all warnings before Phase 2.

### Phase 2: Sequential Screen-by-Screen & Widget-by-Widget Loop
For each screen (`Screen 1` to `Screen 12`) below:
1. **Stitch Generation (Dual Call):** Prepend `[MASTER DESIGN SYSTEM]` and generate **two separate versions** in Stitch for each screen:
   - *Call A (Light Mode):* Theme Surface `#FFFFFF` on Canvas `#F8F3F5`.
   - *Call B (Dark Mode):* Theme Surface `#1E0B12` on Canvas `#110509`.
2. **Widget-by-Widget Refactor:** Update the target Flutter screen and its child widgets one by one, preserving all existing Riverpod/Bloc providers, Supabase RPCs, SQLite offline queues, and Arabic RTL (`dir="rtl"`) bindings.
3. **Verify:** Run `flutter analyze` after each screen before advancing.

### Phase 3: Full-App Alignment & Consistency Audit
After completing all 12 screens, inspect the entire `lib/` UI tree and verify:
- [ ] **Surface Tokens by Mode:** Light Mode uses uniform `#FFFFFF` 3D cards; Dark Mode uses `#1E0B12` 3D cards.
- [ ] **3D Depth Consistency:** Every card, button-over-card, and icon puck has consistent bevel highlights and drop shadows.
- [ ] **Glass Dock & Header Parity:** All 5 main tabs share the exact `GlassmorphicBottomDock` and `VelvetWaveHeader` geometry.
- [ ] **RTL & Tabular Numerals:** All Arabic text uses `Tajawal`/`Cairo` and all SAR amounts use `Outfit` tabular numerals.
- [ ] **Clean Build:** `flutter analyze` and `flutter test` pass with zero errors.

---

## 1. Master Design System Block (Prepend to Every Stitch Call)

[MASTER DESIGN SYSTEM: VELVET BURGUNDY 3D & GLASSMORPHISM]
- Viewport & RTL: Mobile 390x844px, Native Arabic RTL (dir="rtl"). Fonts: 'Tajawal' Bold/Medium (Arabic), 'Outfit' tabular (SAR/numerals).
- Strict 3D Physical Elevation (3 Tiers):
  1. Uniform 3D Cards: 3D squircle tiles (22px radius, 1.5px top bevel, 2.5px bottom thickness lip, soft drop shadow). Light Mode uses Pure White (#FFFFFF) cards on Blush-Alabaster (#F8F3F5) canvas; Dark Mode uses Dark Plum-Charcoal (#1E0B12) cards on Obsidian Wine (#110509) canvas.
  2. 3D Buttons Over Cards: Extruded Velvet Burgundy (#4A0E1E to #2A050E) pill buttons with 1.5px top bevel highlight, 3px bottom lip, and cast shadow (0 6px 14px rgba(74,14,30,0.35)).
  3. 3D Icon Pucks: Circular/squircle 3D burgundy (#4A0E1E) and glossy rose-gold (#E598B0) icon pucks casting a 45-degree diagonal shadow.
- Color Tokens:
  - Top Wave Header & Primary Accent: Velvet Burgundy (#4A0E1E to #2A050E).
  - Secondary Accent: Glossy Rose-Gold (#E598B0).
  - Semantic Pills: Emerald Safe (#10B981), Amber Caution (#F59E0B), Coral Rose Over-Budget (#F43F5E).
  - Bottom Dock: Frosted Glassmorphism capsule (Light: rgba(255,255,255,0.65) | Dark: rgba(45,12,24,0.65), blur 24px, 30px radius, 1.5px specular border).

---

## 2. Screen-by-Screen Stitch Prompts

### Screen 1: Main Dashboard & Cockpit HUD (Family Mode)
[SCREEN 1: MAIN DASHBOARD HUD — UNIFORM 3D CARDS]
1. Curved Velvet Burgundy Top Wave Header (#4A0E1E):
   - Right: 3D circular menu/tools button ('▦'). Center: 3D shield logo + 'راصد الميزانية'. Left: 3D circular notification/switch buttons ('⇄', '🔔 3').
2. Overlapping Hero Payday 3D Card (Theme Surface #FFFFFF in Light / #1E0B12 in Dark, 24px radius):
   - Right: 3D layered burgundy & rose-gold circular ring gauge ('76% • 12 يوم').
   - Left: 'المتبقي حتى الراتب القادم', bold amount, and 3D emerald pill '• آمن ومتزن ✨'.
3. Cycle & Daily Burn 3D Pill Card (Theme Surface card):
   - Displays '📅 دورة 27 أكتوبر - 26 نوفمبر | الصرف اليومي: 401.70 ر.س/يوم' with a 3D circular burgundy filter puck on the left.
4. Dual 3D Bento Row (Two Theme Surface Squircle Cards, 22px radius):
   - Right Card (Liquid Worth): 3D rose-gold lock puck with 45° shadow, 'السيولة النقدية', bold amount, 'في 3 حسابات بنكية', and 3D emerald pill '• نشط'.
   - Left Card (Wife Nafaqah Debt): 'مستحق للزوجة (نفقة)', bold amount, 3D amber pill '⚠️ تسوية مطلوبة', and extruded 3D burgundy pill button '[سداد المستحق ←]'.
5. Quick Access 3D Pills (4 Theme Surface Mini-Pills):
   - '💳 الحسابات (3)', '⚖️ مصروف الزوجة (420)', '📅 الفواتير (4)', '🛒 السلة الذكية'.
6. Category Budgets List (Theme Surface Slot Cards):
   - Row 1: 3D burgundy cart puck, 'البقالة والتموينات (1,200 / 2,000 ر.س)', progress bar, and 3D emerald pill '[60% آمن]'.
   - Row 2: 3D burgundy dining puck, 'المطاعم والكافيهات (1,120 / 1,000 ر.س)', coral bar, and 3D coral pill '[112% تجاوز]'.
7. Glassmorphic Bottom Nav Dock:
   - Frosted glass capsule with 5 tabs ('الرئيسية' active dot, 'العمليات', 'الميزانية', 'حسابي') and a raised 3D Velvet Burgundy '+' center orb.

### Screen 2: Roommates Mode Dashboard Variant (`MultiRoommateSettlementCard`)
[SCREEN 2: ROOMMATES SETTLEMENT 3D MODULE]
Design the Roommates Mode section using Theme Surface cards:
1. Header: '⚖️ تسويات الزملاء والمسبح المشترك'.
2. 3-Node Debt Simplification 3D Card: Theme Surface card showing 3 raised avatar pucks (Fahad, Saad, Khaled) connected by rose-gold directional arrows and a 3D emerald pill 'أنت دائن بـ SAR 320.00'.
3. Shared Apartment Pool 3D Card: Theme Surface card with 3D burgundy pool icon puck, 'المسبح المشترك للشقة: SAR 1,850.00', and two extruded 3D buttons: '[تسوية المستحقات]' (burgundy) and '[مساهمة في المسبح]' (rose-gold).

### Screen 3: Transaction Feed & Ledger (`TransactionFeedScreen`)
[SCREEN 3: TRANSACTION FEED & ZATCA LEDGER]
1. Curved Burgundy Wave Header: Title '🧾 سجل العمليات' with two pill buttons '[📥 PDF]' and '[📊 CSV]'.
2. 3D Search & Filter Deck:
   - Theme Surface search bar ('🔍 بحث بالمتجر أو الصنف...') with 3D burgundy search icon puck.
   - 3 horizontal rows of selectable filter pills (active pill uses extruded Velvet Burgundy #4A0E1E; inactive uses Theme Surface):
     - Categories: 'الكل', '🛒 بقالة', '🍔 مطاعم', '⚡ فواتير'.
     - Period: 'الكل', 'اليوم', 'هذا الأسبوع', '📅 مخصص'.
     - Nafaqah/Payer: 'نفقة مستردة للزوجة', 'مصروف الزوجة', 'مدفوع من الزوج', and sort '[🔽 الأحدث]'.
3. Expanded 3D Transaction Card (Theme Surface card, 22px radius):
   - Top row: 3D burgundy cart puck, 'أسواق التميمي (Tamimi Markets)', '24 أكتوبر • مدى الراجحي', and bold amount.
   - Badges row: 3D emerald pill '🟢 زاتكا معتمد' and 3D rose-gold pill '🏷️ نفقة: مستردة للزوجة'.
   - Inner Itemized Breakdown Box: Inset well listing 4 items ('حليب نادك 18.50', 'دجاج اليوم 42.00', 'خبز 5.00', 'خضار 183.00'), receipt thumbnail puck, and 3D buttons '[✏️ تعديل]' and '[🗑️ حذف]'.
4. Glassmorphic Bottom Nav Dock with 'العمليات' active.

### Screen 4: AI Financial Assistant & Voice Chat (`ChatEntryScreen`)
[SCREEN 4: AI FINANCIAL CO-PILOT & VOICE CHAT]
1. Curved Burgundy Wave Header: '🤖 المساعد المالي الذكي' and language pill '[🇸🇦 العربية ▾]'.
2. Quick Prompt Chips: Scrollable Theme Surface pills ('هل أقدر أشتري جوال بـ 3,200؟', 'سجلت غداء بـ 45 ريال').
3. Chat Stream:
   - User Bubble (Right): Extruded Velvet Burgundy (#4A0E1E) bubble with text 'هل أقدر أشتري جوال بـ 3,200 ريال اليوم؟'.
   - AI Affordability Verdict Widget (Left): Theme Surface card (22px radius) with 3D amber badge '⚠️ تقييم القدرة: بحذر (Caution)', semicircular gauge, text 'ينخفض الصرف اليومي من 180 إلى 74 ر.س/يوم حتى يوم 27', and 3D burgundy button '[تسجيل العملية الآن]'.
   - AI Pending Expense Card (Left): Theme Surface card showing '☕ قهوة مختصة - SAR 24.00 • STC Pay' with 3D buttons '[✅ تأكيد]', '[✏️ تعديل]', '[❌ إلغاء]'.
4. Bottom Glassmorphic Voice Dock: Frosted glass input bar with soundwave visualizer and a raised Velvet Burgundy microphone orb.

### Screen 5: Zero-Based Budget Management (`BudgetManagementScreen`)
[SCREEN 5: ZERO-BASED BUDGET WORKBENCH]
1. Curved Burgundy Wave Header: '📊 إدارة الميزانيات' and cycle stepper '27 أكتوبر - 26 نوفمبر'.
2. Zero-Based Health Hero Card (Theme Surface card):
   - Displays 'إجمالي الدخل: SAR 15,000 • المخصص: SAR 15,000' and 3D emerald pill '🟢 ميزانية صفرية 100%'.
3. Action Row: Two pill buttons '[📋 نسخ من الدورة السابقة]' and '[🏷️ مكتبة البنود]'.
4. Category Allocation 3D Cards (Theme Surface cards):
   - Card 1: 3D burgundy cart puck, 'التموينات والسوبرماركت', 3D numeric box 'SAR 2,500', linked pill '[الراجحي ▾]', slider track with raised spherical thumb, and 3D button '[📂 البنود الفرعية (3)]'.
   - Card 2: 3D burgundy car puck, 'الوقود والصيانة', 'SAR 800', linked '[STC Pay ▾]', and slider.
5. Glassmorphic Bottom Nav Dock with 'الميزانية' active.

### Screen 6: Household & App Settings (`SettingsScreen`)
[SCREEN 6: HOUSEHOLD & NAFQAH SETTINGS]
1. Curved Burgundy Wave Header: '⚙️ الإعدادات وإدارة البيت' with 3D admin profile card overlapping the wave ('فهد العتيبي • مشرف البيت').
2. Household Card (Theme Surface): Invite code box 'FAHAD2026' with 3D burgundy buttons '[📋 نسخ]' and '[🔗 مشاركة]'. Member pucks ('فهد', 'نورة', 'خالد') and 3D button '[+ دعوة عضو]'.
3. Islamic Nafaqah Card (Theme Surface): 3D scale icon puck, dropdown 'المنفق القانوني: [فهد العتيبي ▾]', and input 'مصروف الزوجة الشهري: [SAR 1,500]'.
4. Payday & Rollover Card (Theme Surface): Payday stepper '[يوم 27 ▾]', income 'SAR 18,000', and radio pills for rollover ('تحويل للمدخرات' active in Velvet Burgundy, 'تدوير للبنود', 'تصفير').
5. Preferences Card (Theme Surface): Toggle switches for Dark Mode, Notifications, Language, and 3D coral button '[🚪 تسجيل الخروج]'.

### Screen 7: ZATCA QR Scanner & Expense Review Sheet (`ReceiptScannerSheet`)
[SCREEN 7: ZATCA QR SCANNER & 3D REVIEW SHEET]
1. Top 35% Camera Viewfinder: Dark viewfinder with laser reticle scanning a QR code, floating 3D emerald pill '🟢 زاتكا معتمد - ZATCA Phase 2', and pills '[🖼️ المعرض]' and '[📑 متعدد الصفحات]'.
2. Bottom 65% Modal Sheet (Theme Canvas sheet with 28px top radius):
   - Merchant Card: 'أسواق التميمي', VAT number, bold amount, and category pill '🛒 بقالة'.
   - 3D Nafaqah Segmented Control: Tray containing 3 pills: 'مدفوع للبيت من الزوج', 'مستردة للزوجة (دين)' (active extruded Velvet Burgundy #4A0E1E pill), and 'مصروف شخصي للزوجة'.
   - Itemized Card: 4 extracted items and full-width extruded Velvet Burgundy button '[✅ حفظ العملية]'.

### Screen 8: Manual Expense Sheet & Speed Dial (`ManualExpenseSheet`)
[SCREEN 8: MANUAL EXPENSE ENTRY 3D SHEET]
1. Top Backdrop: Shows floating 3D burgundy Speed Dial fan ('📷 مسح فاتورة', '🎙️ صوتي', '✍️ يدوي').
2. Bottom Sheet (Theme Canvas, 28px radius):
   - Amount Card: Huge tabular text '145.00 ر.س'.
   - Merchant Input + autocomplete pills ('البيك', 'التميمي', 'جرير', 'STC').
   - 2-Row Icon Puck Grid: 8 circular icon pucks with 45° shadows ('مطاعم' active in Velvet Burgundy).
   - Date, Account ('STC Pay') & 3-way Nafaqah pills.
   - Full-width Velvet Burgundy button '[💾 تسجيل المصروف]'.

### Screen 9: Tools Hub & Affordability Simulator (`ToolsScreen` & `AffordabilitySimulatorSheet`)
[SCREEN 9: TOOLS HUB & AFFORDABILITY SIMULATOR]
1. Background Tools Grid: Curved burgundy wave header '🧰 مركز الأدوات المالية' and a 2-column Bento grid of 7 Theme Surface squircle cards, each with an icon puck casting a 45° shadow.
2. Foreground 3D Bottom Sheet ('🎯 هل أقدر أشتري؟'):
   - Input cards for 'iPhone 16 Pro', 'SAR 4,499', and button '[⚡ محاكاة التأثير]'.
   - Verdict Card: 3D amber badge '🟡 بحذر (Caution)', gauge, text 'ينخفض الصرف اليومي من 150 إلى 65 ر.س/يوم', and burgundy CTA '[📝 المتابعة وتسجيل المصروف]'.

### Screen 10: Liquid Accounts & 1-Tap Payday Distribution (`AccountsOverviewScreen` & `SalaryDistributionAssistantSheet`)
[SCREEN 10: ACCOUNTS OVERVIEW & PAYDAY 1-TAP SPLIT]
1. Top Section: Curved burgundy header '💳 حسابات السيولة' and 3 Theme Surface account cards ('مصرف الراجحي: 12,000 🟢 صفرية', 'STC Pay: 4,200 🔵 فائض', 'الأهلي: 2,250 🔴 عجز').
2. Bottom Sheet ('🚀 توزيع الراتب الذكي'): Card showing 'صافي الراتب: SAR 18,000' connected by flow lines to 4 transfer slots ('👩 مصروف الزوجة 1,500', '🛡️ الادخار 3,000', '⚡ الفواتير 5,500', '☕ المعيشة 8,000') and a full-width Velvet Burgundy button '[🚀 تنفيذ التوزيع بضغطة واحدة]'.

### Screen 11: Grocery Price Tracker & Smart Basket (`GroceryPriceIntelligenceScreen`)
[SCREEN 11: GROCERY PRICE TRACKER & SMART BASKET]
1. Curved Burgundy Header: '📈 متتبع أسعار السلع' and item pills ('حليب' active in Velvet Burgundy, 'دجاج', 'بيض', 'أرز').
2. Trend Chart Card: Smooth spline chart comparing Tamimi (#4A0E1E), Panda (#10B981), Lulu (#F59E0B), and Carrefour (#E598B0).
3. Smart Basket Optimizer Card: 3D emerald badge '🏆 الأوفر اليوم: بنده — وفر 45.20 ر.س', store total comparison rows, and Velvet Burgundy button '[🔍 مقارنة وتحسين السلة]'.

### Screen 12: Auth, Onboarding, Walkthrough & Household Switcher (`LoginScreen`, `HouseholdScreen`, `HouseholdSwitchSheet`)
[SCREEN 12: AUTH & HOUSEHOLD ONBOARDING]
1. Login Screen: Curved Velvet Burgundy header with a large rose-gold & burgundy shield/lock centerpiece illustration, Theme Surface form card with segmented toggle ('تسجيل الدخول' / 'إنشاء حساب'), inputs, and full-width Velvet Burgundy button '[تأكيد الدخول ←]'.
2. Household Setup & Switcher Sheet: Theme Surface mode cards for '👨‍👩‍👧‍👦 أسرة (Family Mode)' (with 3D emerald badge 'وفق الضوابط الشرعية للنفقة' and burgundy selection border) and '👥 سكن مشترك (Roommates Mode)', plus Velvet Burgundy CTA '[متابعة وإنشاء البيت]'.


================================================================================
PART 2: COPY-PASTE THIS EXACT PROMPT INTO ANTIGRAVTIY WITH YOUR SCREENSHOT
================================================================================

We are executing Stage 1 of our Velvet Burgundy 3D & Glassmorphism Redesign using the updated `docs/STITCH_UI_PROMPTS.md` and the attached reference screenshot (image_0954b0.png).

CRITICAL RULE FOR STAGE 1: DO NOT modify any Flutter/Dart files in `lib/` yet. You are ONLY generating and organizing UI screens inside my Google Stitch project so I can visually inspect and approve all screens first.

Follow these exact steps for Stage 1:
1. Locate my active Stitch project via the Stitch MCP server and inspect the layout of Screen 1 ("راصد الميزانية") matching the attached screenshot (uniform 3D Light Mode surface, curved Velvet Burgundy #4A0E1E top wave header, 3D icon pucks, and frosted glassmorphic bottom dock).
2. Read `docs/STITCH_UI_PROMPTS.md` and generate both Light Mode and Dark Mode variants for Screens 2 through 12 sequentially inside THIS SAME Stitch project (`project_id`):
   - For Light Mode: Theme Surface #FFFFFF on Canvas #F8F3F5.
   - For Dark Mode: Theme Surface #1E0B12 on Canvas #110509.
3. Ensure every generated screen strictly matches the 3D card depth, typography, uniform surface cards, and glassmorphic navbar of Screen 1.
4. As soon as all screens are generated on the Stitch canvas, list all generated `screen_id`s and STOP. Wait for my visual inspection and explicit confirmation before writing any Flutter code.