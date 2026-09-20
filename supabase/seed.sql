-- =============================================================================
-- BUDGET TRACKER — SEED DATA: cost_control_codes
-- Run AFTER schema.sql.
-- Covers the most common merchants seen in Saudi bank (SNB / Al Rajhi) SMS.
-- Keywords are lowercase; matching is done case-insensitively in the agent.
-- =============================================================================

INSERT INTO public.cost_control_codes (code, category, keywords, is_flexible)
VALUES

-- ─── GROCERY ──────────────────────────────────────────────────────────────
(
    'OPEX-GROCERY',
    'Grocery',
    ARRAY[
        'tamimi', 'تميمي',
        'danube', 'دانوب',
        'panda', 'باندا',
        'carrefour', 'كارفور',
        'lulu', 'lulu hypermarket', 'لولو',
        'othaim', 'العثيم',
        'bin dawood', 'بن داود',
        'farm superstores', 'فارم',
        'al meera',
        'nesto'
    ],
    false
),

-- ─── DINING / RESTAURANTS ─────────────────────────────────────────────────
(
    'OPEX-DINING',
    'Dining',
    ARRAY[
        'starbucks', 'ستاربكس',
        'mcdonald', 'ماكدونالدز', 'macs',
        'al baik', 'البيك',
        'kfc', 'كنتاكي',
        'burger king', 'برغر كينج',
        'herfy', 'هرفي',
        'pizza hut', 'بيتزا هت',
        'dominos', 'دومينوز',
        'subway',
        'hardees',
        'kudu', 'كودو',
        'jahez', 'جاهز',
        'hungerstation', 'هنقرستيشن',
        'toyor al janah',
        'shake shack'
    ],
    true   -- flexible: dining is first priority for reallocation
),

-- ─── FUEL / TRANSPORT ─────────────────────────────────────────────────────
(
    'OPEX-FUEL',
    'Fuel & Transport',
    ARRAY[
        'aramco', 'أرامكو',
        'sahel', 'ساحل',
        'naft', 'نفط',
        'gas station',
        'uber', 'اوبر',
        'careem', 'كريم',
        'saudi railways', 'سار',
        'saptco', 'سابتكو',
        'hafilat'
    ],
    false
),

-- ─── UTILITIES / BILLS ────────────────────────────────────────────────────
(
    'OPEX-UTILITIES',
    'Utilities & Bills',
    ARRAY[
        'stc', 'اس تي سي',
        'mobily', 'موبايلي',
        'zain', 'زين',
        'se', 'saudi electricity', 'الكهرباء',
        'nwc', 'national water', 'المياه',
        'saudi telecom',
        'du',
        'virgin mobile',
        'internet'
    ],
    false
),

-- ─── SHOPPING / RETAIL ────────────────────────────────────────────────────
(
    'OPEX-SHOPPING',
    'Shopping',
    ARRAY[
        'noon', 'نون',
        'amazon', 'أمازون',
        'saco', 'ساكو',
        'home centre', 'هوم سنتر',
        'ikea', 'ايكيا',
        'extra', 'اكسترا',
        'jarir', 'جرير',
        'virgin megastore',
        'the body shop',
        'h&m',
        'zara',
        'sport depot',
        'namshi'
    ],
    false
),

-- ─── ENTERTAINMENT ────────────────────────────────────────────────────────
(
    'OPEX-ENTERTAINMENT',
    'Entertainment',
    ARRAY[
        'netflix', 'نتفليكس',
        'spotify', 'سبوتيفاي',
        'apple', 'ابل',
        'google play', 'جوجل بلاي',
        'viu',
        'shahid', 'شاهد',
        'cinema', 'سينما',
        'muvi', 'موفي',
        'wow cinema',
        'playstation', 'ps store',
        'xbox',
        'steam',
        'youtube premium',
        'tidal'
    ],
    true   -- flexible: entertainment is second priority for reallocation
),

-- ─── HEALTH / PHARMACY ────────────────────────────────────────────────────
(
    'OPEX-HEALTH',
    'Health & Pharmacy',
    ARRAY[
        'nahdi', 'النهدي',
        'al dawaa', 'الدواء',
        'white pharmacy', 'الصيدلية البيضاء',
        'pharmacy', 'صيدلية',
        'clinic', 'عيادة',
        'hospital', 'مستشفى',
        'dr', 'doctor',
        'lab', 'مختبر',
        'watson'
    ],
    false
),

-- ─── EDUCATION ────────────────────────────────────────────────────────────
(
    'CAPEX-EDUCATION',
    'Education',
    ARRAY[
        'school', 'مدرسة',
        'university', 'جامعة',
        'college', 'كلية',
        'udemy',
        'coursera',
        'jarir bookstore', 'مكتبة جرير',
        'virgin books',
        'tuition',
        'رسوم دراسية'
    ],
    false
),

-- ─── GOVERNMENT / FEES ────────────────────────────────────────────────────
(
    'OPEX-GOV',
    'Government & Fees',
    ARRAY[
        'absher', 'أبشر',
        'sadad', 'سداد',
        'traffic', 'مرور',
        'iqama',
        'istimara',
        'mukhalafat', 'مخالفات',
        'bayah', 'بيئة',
        'municipality', 'بلدية'
    ],
    false
),

-- ─── MISCELLANEOUS ────────────────────────────────────────────────────────
(
    'OPEX-MISC',
    'Miscellaneous',
    ARRAY[
        'misc', 'متنوع',
        'transfer', 'تحويل',
        'payment', 'دفع',
        'purchase', 'شراء',
        'pos',
        'atm',
        'withdrawal'
    ],
    true   -- flexible: misc is third priority for reallocation
);


-- =============================================================================
-- VERIFY SEED
-- =============================================================================
-- Run this SELECT after seeding to confirm all rows inserted correctly:
--
-- SELECT code, category, is_flexible, array_length(keywords, 1) AS keyword_count
-- FROM public.cost_control_codes
-- ORDER BY is_flexible DESC, code;
