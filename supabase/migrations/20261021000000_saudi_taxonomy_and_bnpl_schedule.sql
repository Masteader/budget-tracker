-- ============================================================================
-- Migration: 20261021000000_saudi_taxonomy_and_bnpl_schedule.sql
--
-- Product review R4 + R10 (docs/review/audit/product_review.md §1.3, §2.5).
--
-- A. Saudi household taxonomy (R4). Eight new SYSTEM categories in
--    public.cost_control_codes (household_id NULL, is_system true, the same
--    columns as the seeded codes: code, category, keywords, is_flexible), each
--    with system sub-categories in public.cost_control_sub_categories:
--      OPEX-HOUSING         housing_rent, annual_rent, housing_services
--      OPEX-EDUCATION       tuition_fees, school_transport, school_uniforms, books_supplies
--      OPEX-DOMESTIC-HELP   maid_salary, driver_salary, recruitment_visa
--      OPEX-FAMILY-SUPPORT  parents_support, relatives_support
--      OPEX-CHARITY         sadaqah, zakat
--      OPEX-TRANSPORT       car_installment, ride_hailing, public_transport, car_maintenance
--      OPEX-INSURANCE       car_insurance, health_insurance, home_insurance
--      OPEX-REMITTANCE      family_remittance, transfer_fees
--    * Nothing existing is moved, renamed or deleted. OPEX-FUEL keeps its
--      sub-categories; OPEX-UTILITIES keeps `housing_rent` (transactions and
--      sub-allocations reference it, and sub-categories have no lifecycle
--      column to deprecate it). A new `housing_rent` is added under
--      OPEX-HOUSING with the same names, so new rent goes there and old rows
--      stay valid. CAPEX-EDUCATION stays (university / courses); the new
--      OPEX-EDUCATION is the recurring school cost.
--    * Top-level keywords of the new codes never overlap a keyword of the ten
--      seeded codes (merchant matching is substring/word based and iterates
--      codes in table order): no existing merchant changes category. Proof:
--      supabase/tests/27_taxonomy_and_bnpl.sql.
--    * Existing households: no household_category_settings and no budget rows
--      are written. The API (salary_cycle.get_household_categories) lists a
--      system category without a setting or budget row as inactive unless it
--      is one of the ten original core codes, so the new categories appear in
--      every household's category library ("available") and are budgeted only
--      when the household activates them / adds a budget.
--    * Guard: aborts when a household already owns a custom code with one of
--      the eight codes (a system row with the same code would make that
--      household's own sub-categories globally visible), or when
--      sub-categories already hang under one of the eight codes other than
--      the ones this file adds.
--
-- B. BNPL schedule (R10). public.installment_plans gains
--      frequency   text NOT NULL DEFAULT 'monthly'
--                  CHECK (frequency IN ('monthly', 'biweekly'))
--      next_due_at date NULL
--    Schedule: installment k (0-based) is due on start_date + k * 14 days
--    (biweekly: Tabby / Tamara "Pay in 4") or start_date + k months (monthly:
--    bank plans, Tamara 3 monthly; PostgreSQL month arithmetic from the anchor,
--    so 31 Jan -> 28/29 Feb -> 31 Mar, no drift). next_due_at is the due date
--    of the first unpaid installment while the plan is ACTIVE, NULL otherwise.
--    * public.installment_next_due_at(start, frequency, paid, count, status):
--      IMMUTABLE helper (EXECUTE: authenticated, service_role).
--    * Trigger trg_installment_plans_schedule keeps next_due_at derived on every
--      INSERT / schedule-relevant UPDATE (clients may INSERT this table; the
--      value can never be forged or go stale).
--    * pay_installment_plan (20261020900000 version, CREATE OR REPLACE): same
--      signature, grants (service_role only) and ACTIVE-only rule; it now also
--      advances next_due_at by one interval (14 days / 1 month).
--    * Clients get no UPDATE on frequency / next_due_at (the 10-column client
--      UPDATE list of 900000 is unchanged).
--    * Backfill: existing rows become 'monthly' (the column default); ACTIVE
--      rows get their next_due_at. Live has 0 plans.
--
-- Live safety: one transaction, idempotent (a re-run inserts nothing, changes
-- no row and re-creates the same functions / trigger). Applies AFTER
-- 20261020700000, 750000, 800000 and 900000 (guard checks 900000's ACTIVE-only
-- pay_installment_plan and its paid_installments CHECK). No existing row of
-- any table changes except installment_plans gaining the two columns (0 rows
-- on live). Locks: ACCESS EXCLUSIVE on installment_plans for the ALTER
-- (metadata only: constant default) and ROW EXCLUSIVE on the two category
-- tables for the inserts.
-- Compatibility: the deployed backend keeps working (it never names the new
-- columns; inserts get the default 'monthly' and a derived next_due_at); the
-- deployed app reads categories by code and shows unknown codes by stripping
-- the OPEX- prefix until its l10n map has them.
--
-- Proof test: supabase/tests/27_taxonomy_and_bnpl.sql
-- Rollback: docs/review/rollback/20261021_taxonomy_bnpl_rollback.sql
-- ============================================================================

BEGIN;

-- 0. Guard ---------------------------------------------------------------------------
DO $$
DECLARE
    v_bad text;
    v_n int;
BEGIN
    -- Prerequisites: 20261020900000 (ACTIVE-only payments, paid_installments CHECK).
    IF to_regprocedure('public.pay_installment_plan(uuid, uuid, uuid)') IS NULL
       OR NOT EXISTS (SELECT 1 FROM pg_constraint
                      WHERE conrelid = 'public.installment_plans'::regclass
                        AND conname = 'installment_plans_paid_installments_range')
       OR NOT EXISTS (SELECT 1 FROM information_schema.columns
                      WHERE table_schema = 'public' AND table_name = 'households'
                        AND column_name = 'household_type') THEN
        RAISE EXCEPTION 'guard: apply 20261020700000, 750000, 800000 and 900000 first';
    END IF;

    -- A household-owned custom code that equals one of the new system codes.
    SELECT string_agg(DISTINCT c.code, ', ') INTO v_bad
    FROM public.cost_control_codes c
    WHERE c.household_id IS NOT NULL
      AND c.code IN ('OPEX-HOUSING', 'OPEX-EDUCATION', 'OPEX-DOMESTIC-HELP', 'OPEX-FAMILY-SUPPORT',
                     'OPEX-CHARITY', 'OPEX-TRANSPORT', 'OPEX-INSURANCE', 'OPEX-REMITTANCE');
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION 'guard: household custom categories already use the code(s) %; rename them before adding the system categories', v_bad;
    END IF;

    -- Sub-categories already under one of the new parents, other than the ones added here.
    SELECT count(*) INTO v_n
    FROM public.cost_control_sub_categories s
    WHERE s.parent_code IN ('OPEX-HOUSING', 'OPEX-EDUCATION', 'OPEX-DOMESTIC-HELP', 'OPEX-FAMILY-SUPPORT',
                            'OPEX-CHARITY', 'OPEX-TRANSPORT', 'OPEX-INSURANCE', 'OPEX-REMITTANCE')
      AND (s.parent_code, s.sub_code) NOT IN (VALUES
            ('OPEX-HOUSING', 'housing_rent'), ('OPEX-HOUSING', 'annual_rent'), ('OPEX-HOUSING', 'housing_services'),
            ('OPEX-EDUCATION', 'tuition_fees'), ('OPEX-EDUCATION', 'school_transport'),
            ('OPEX-EDUCATION', 'school_uniforms'), ('OPEX-EDUCATION', 'books_supplies'),
            ('OPEX-DOMESTIC-HELP', 'maid_salary'), ('OPEX-DOMESTIC-HELP', 'driver_salary'),
            ('OPEX-DOMESTIC-HELP', 'recruitment_visa'),
            ('OPEX-FAMILY-SUPPORT', 'parents_support'), ('OPEX-FAMILY-SUPPORT', 'relatives_support'),
            ('OPEX-CHARITY', 'sadaqah'), ('OPEX-CHARITY', 'zakat'),
            ('OPEX-TRANSPORT', 'car_installment'), ('OPEX-TRANSPORT', 'ride_hailing'),
            ('OPEX-TRANSPORT', 'public_transport'), ('OPEX-TRANSPORT', 'car_maintenance'),
            ('OPEX-INSURANCE', 'car_insurance'), ('OPEX-INSURANCE', 'health_insurance'),
            ('OPEX-INSURANCE', 'home_insurance'),
            ('OPEX-REMITTANCE', 'family_remittance'), ('OPEX-REMITTANCE', 'transfer_fees'));
    IF v_n > 0 THEN
        RAISE EXCEPTION 'guard: % sub-categor(y/ies) already exist under the new parent codes; they would become visible to every household', v_n;
    END IF;

    SELECT count(*) INTO v_n FROM public.installment_plans;
    RAISE NOTICE 'guard: % installment plan(s) get frequency monthly', v_n;
END;
$$;

-- 1. System categories (A) --------------------------------------------------------------
INSERT INTO public.cost_control_codes (code, category, keywords, is_flexible, is_system, household_id)
SELECT v.code, v.category, v.keywords, false, true, NULL
FROM (VALUES
    ('OPEX-HOUSING', 'Housing & Rent',
     ARRAY['ejar', 'إيجار', 'ايجار', 'apartment rent', 'house rent', 'إيجار شقة', 'سكن']),
    ('OPEX-EDUCATION', 'School Costs',
     ARRAY['stationery', 'قرطاسية', 'uniforms', 'زي مدرسي', 'مريول', 'نقل مدرسي', 'madrasati', 'مدرستي']),
    ('OPEX-DOMESTIC-HELP', 'Domestic Help',
     ARRAY['musaned', 'مساند', 'housemaid', 'خادمة', 'شغالة', 'عاملة منزلية', 'استقدام', 'private driver', 'سائق خاص']),
    ('OPEX-FAMILY-SUPPORT', 'Family Support',
     ARRAY['family support', 'parents support', 'الوالدين', 'بر الوالدين', 'مصروف الوالدة', 'مصروف الوالد']),
    ('OPEX-CHARITY', 'Charity & Zakat',
     ARRAY['zakat', 'zakah', 'زكاة', 'sadaqah', 'sadaqa', 'صدقة', 'donation', 'تبرع', 'ehsan', 'إحسان', 'جود الإسكان']),
    ('OPEX-TRANSPORT', 'Car & Transport',
     ARRAY['car installment', 'قسط السيارة', 'jeeny', 'bolt', 'riyadh metro', 'مترو الرياض', 'petromin', 'بترومين']),
    ('OPEX-INSURANCE', 'Insurance',
     ARRAY['insurance', 'تأمين', 'tawuniya', 'التعاونية للتأمين', 'bupa', 'بوبا', 'medgulf', 'ميدغلف', 'najm']),
    ('OPEX-REMITTANCE', 'Remittances Abroad',
     ARRAY['remittance', 'remit', 'حوالة دولية', 'حوالة خارجية', 'enjaz', 'western union', 'ويسترن يونيون',
           'moneygram', 'ترسیلات'])
) AS v(code, category, keywords)
WHERE NOT EXISTS (SELECT 1 FROM public.cost_control_codes c
                  WHERE c.code = v.code AND c.household_id IS NULL);

-- 2. System sub-categories (A) ------------------------------------------------------
INSERT INTO public.cost_control_sub_categories (parent_code, sub_code, name_en, name_ar, keywords)
VALUES
    -- Housing
    ('OPEX-HOUSING', 'housing_rent', 'Housing Rent', 'إيجار السكن',
     ARRAY['rent', 'apartment', 'housing', 'lease', 'ejar', 'إيجار', 'ايجار', 'شقة', 'سكن']),
    ('OPEX-HOUSING', 'annual_rent', 'Annual / Semi-annual Rent', 'الإيجار السنوي ونصف السنوي',
     ARRAY['annual rent', 'yearly rent', 'semi-annual', 'rent contract', 'إيجار سنوي', 'عقد إيجار', 'دفعة الإيجار']),
    ('OPEX-HOUSING', 'housing_services', 'Building Services & Home Repairs', 'خدمات السكن والصيانة',
     ARRAY['building services', 'maintenance fee', 'plumber', 'electrician', 'خدمات العمارة', 'حارس', 'سباك', 'كهربائي', 'صيانة المنزل']),
    -- Education
    ('OPEX-EDUCATION', 'tuition_fees', 'School Fees', 'الرسوم المدرسية',
     ARRAY['tuition', 'school fees', 'رسوم مدرسية', 'رسوم دراسية', 'قسط المدرسة']),
    ('OPEX-EDUCATION', 'school_transport', 'School Transport', 'النقل المدرسي',
     ARRAY['school bus', 'school transport', 'باص المدرسة', 'نقل مدرسي', 'توصيل المدرسة']),
    ('OPEX-EDUCATION', 'school_uniforms', 'School Uniforms', 'الزي المدرسي',
     ARRAY['uniform', 'school uniform', 'زي مدرسي', 'مريول']),
    ('OPEX-EDUCATION', 'books_supplies', 'Books & School Supplies', 'الكتب والقرطاسية',
     ARRAY['books', 'stationery', 'school supplies', 'كتب', 'قرطاسية', 'دفاتر', 'أدوات مدرسية']),
    -- Domestic help
    ('OPEX-DOMESTIC-HELP', 'maid_salary', 'Housemaid Salary', 'راتب العاملة المنزلية',
     ARRAY['maid', 'housemaid', 'nanny', 'عاملة', 'خادمة', 'شغالة', 'مربية']),
    ('OPEX-DOMESTIC-HELP', 'driver_salary', 'Driver Salary', 'راتب السائق',
     ARRAY['driver salary', 'private driver', 'راتب السائق', 'سائق خاص']),
    ('OPEX-DOMESTIC-HELP', 'recruitment_visa', 'Recruitment & Visa Fees', 'رسوم الاستقدام والتأشيرات',
     ARRAY['musaned', 'recruitment', 'work visa', 'مساند', 'استقدام', 'تأشيرة عمالة', 'نقل كفالة']),
    -- Family support
    ('OPEX-FAMILY-SUPPORT', 'parents_support', 'Support for Parents', 'مصروف الوالدين',
     ARRAY['parents', 'mother', 'father', 'الوالدين', 'الوالدة', 'الوالد', 'أمي', 'ابوي']),
    ('OPEX-FAMILY-SUPPORT', 'relatives_support', 'Support for Relatives', 'مساعدة الأقارب',
     ARRAY['relatives', 'brother', 'sister', 'الأقارب', 'اخوي', 'اختي', 'أخي', 'أختي']),
    -- Charity
    ('OPEX-CHARITY', 'sadaqah', 'Sadaqah & Donations', 'الصدقات والتبرعات',
     ARRAY['sadaqah', 'sadaqa', 'charity', 'donation', 'ehsan', 'صدقة', 'تبرع', 'إحسان']),
    ('OPEX-CHARITY', 'zakat', 'Zakat', 'الزكاة',
     ARRAY['zakat', 'zakah', 'زكاة', 'زكاه']),
    -- Transport (OPEX-FUEL keeps gas_fuel / car_maintenance / ride_hailing; shared sub-codes keep their names)
    ('OPEX-TRANSPORT', 'car_installment', 'Car Installment & Lease', 'قسط السيارة والتأجير التمويلي',
     ARRAY['car installment', 'car loan', 'car lease', 'قسط السيارة', 'تمويل سيارة', 'تأجير منتهي بالتمليك']),
    ('OPEX-TRANSPORT', 'ride_hailing', 'Ride Hailing (Uber/Bolt)', 'تطبيقات النقل والتوصيل',
     ARRAY['uber', 'careem', 'bolt', 'jeeny', 'أوبر', 'كريم', 'جيني']),
    ('OPEX-TRANSPORT', 'public_transport', 'Public Transport', 'النقل العام',
     ARRAY['metro', 'train', 'saptco', 'hafilat', 'مترو', 'قطار', 'حافلة', 'سابتكو']),
    ('OPEX-TRANSPORT', 'car_maintenance', 'Car Maintenance & Oil', 'صيانة وتغيير الزيت',
     ARRAY['oil change', 'mechanic', 'tires', 'workshop', 'petromin', 'صيانة', 'ورشة', 'كفرات', 'زيت']),
    -- Insurance
    ('OPEX-INSURANCE', 'car_insurance', 'Car Insurance', 'تأمين السيارة',
     ARRAY['car insurance', 'motor insurance', 'najm', 'تأمين سيارة', 'تأمين المركبة', 'تأمين السيارة']),
    ('OPEX-INSURANCE', 'health_insurance', 'Health Insurance', 'التأمين الصحي',
     ARRAY['health insurance', 'medical insurance', 'bupa', 'تأمين طبي', 'تأمين صحي', 'بوبا']),
    ('OPEX-INSURANCE', 'home_insurance', 'Home Insurance', 'تأمين المنزل',
     ARRAY['home insurance', 'property insurance', 'تأمين المنزل', 'تأمين منزل']),
    -- Remittances
    ('OPEX-REMITTANCE', 'family_remittance', 'Money Sent Home', 'حوالات للأهل',
     ARRAY['remittance', 'send money', 'western union', 'enjaz', 'حوالة', 'حوالات', 'انجاز', 'ترسیلات']),
    ('OPEX-REMITTANCE', 'transfer_fees', 'Transfer Fees', 'رسوم التحويل',
     ARRAY['transfer fee', 'remittance fee', 'رسوم تحويل', 'رسوم الحوالة'])
ON CONFLICT (parent_code, sub_code) DO NOTHING;

-- 3. installment_plans.frequency / next_due_at (B) ---------------------------------------
ALTER TABLE public.installment_plans
    ADD COLUMN IF NOT EXISTS frequency text NOT NULL DEFAULT 'monthly',
    ADD COLUMN IF NOT EXISTS next_due_at date;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conrelid = 'public.installment_plans'::regclass
                     AND conname = 'installment_plans_frequency_check') THEN
        ALTER TABLE public.installment_plans
            ADD CONSTRAINT installment_plans_frequency_check CHECK (frequency IN ('monthly', 'biweekly'));
    END IF;
END $$;

COMMENT ON COLUMN public.installment_plans.frequency IS
    'Payment interval: biweekly (Tabby/Tamara Pay in 4, every 14 days) or monthly (bank plans). Installment k (0-based) is due on start_date + k intervals.';
COMMENT ON COLUMN public.installment_plans.next_due_at IS
    'Due date of the first unpaid installment while ACTIVE, NULL otherwise. Derived (trg_installment_plans_schedule); not client-writable.';

CREATE OR REPLACE FUNCTION public.installment_next_due_at(
    p_start_date date,
    p_frequency text,
    p_paid_installments integer,
    p_installment_count integer,
    p_status text
)
RETURNS date
LANGUAGE sql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
    SELECT CASE
        WHEN p_start_date IS NULL OR p_status IS DISTINCT FROM 'ACTIVE'
             OR coalesce(p_paid_installments, 0) >= coalesce(p_installment_count, 0) THEN NULL
        WHEN p_frequency = 'biweekly' THEN p_start_date + 14 * greatest(coalesce(p_paid_installments, 0), 0)
        ELSE (p_start_date + make_interval(months => greatest(coalesce(p_paid_installments, 0), 0)))::date
    END;
$$;

COMMENT ON FUNCTION public.installment_next_due_at(date, text, integer, integer, text) IS
    'Due date of installment number p_paid_installments (0-based) of an ACTIVE plan: start + n*14 days (biweekly) or start + n months (monthly); NULL when not ACTIVE or paid up.';

REVOKE ALL ON FUNCTION public.installment_next_due_at(date, text, integer, integer, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.installment_next_due_at(date, text, integer, integer, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.installment_next_due_at(date, text, integer, integer, text) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.installment_plans_schedule()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
    NEW.next_due_at := public.installment_next_due_at(
        NEW.start_date, NEW.frequency, NEW.paid_installments, NEW.installment_count, NEW.status);
    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.installment_plans_schedule() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.installment_plans_schedule() FROM anon, authenticated;

DROP TRIGGER IF EXISTS trg_installment_plans_schedule ON public.installment_plans;
CREATE TRIGGER trg_installment_plans_schedule
    BEFORE INSERT OR UPDATE OF start_date, frequency, paid_installments, installment_count, status, next_due_at
    ON public.installment_plans
    FOR EACH ROW EXECUTE FUNCTION public.installment_plans_schedule();

-- Backfill (existing rows are 'monthly' through the column default; 0 rows on live).
UPDATE public.installment_plans p
SET next_due_at = public.installment_next_due_at(p.start_date, p.frequency, p.paid_installments,
                                                 p.installment_count, p.status)
WHERE p.next_due_at IS DISTINCT FROM public.installment_next_due_at(p.start_date, p.frequency, p.paid_installments,
                                                                    p.installment_count, p.status);

CREATE INDEX IF NOT EXISTS idx_installment_plans_next_due
    ON public.installment_plans (next_due_at)
    WHERE status = 'ACTIVE';

-- 4. pay_installment_plan: 20261020900000 rules + next_due_at advance (B) ---------------
CREATE OR REPLACE FUNCTION public.pay_installment_plan(
    p_plan_id uuid,
    p_household_id uuid,
    p_actor_user_id uuid
)
RETURNS SETOF public.installment_plans
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_row public.installment_plans;
BEGIN
    IF p_plan_id IS NULL OR p_household_id IS NULL OR p_actor_user_id IS NULL THEN
        RAISE EXCEPTION 'plan, household and actor are required' USING ERRCODE = '22023';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.household_memberships m
        WHERE m.household_id = p_household_id
          AND m.user_id = p_actor_user_id
    ) THEN
        RAISE EXCEPTION 'Only a member of the household can record an installment payment'
            USING ERRCODE = '42501';
    END IF;

    -- One conditional increment; next_due_at moves one interval (14 days / 1 month from
    -- the start_date anchor), NULL once the plan is paid up.
    UPDATE public.installment_plans AS p
       SET paid_installments = p.paid_installments + 1,
           status = CASE WHEN p.paid_installments + 1 >= p.installment_count THEN 'COMPLETED' ELSE p.status END,
           next_due_at = public.installment_next_due_at(
               p.start_date, p.frequency, p.paid_installments + 1, p.installment_count,
               CASE WHEN p.paid_installments + 1 >= p.installment_count THEN 'COMPLETED' ELSE p.status END)
     WHERE p.id = p_plan_id
       AND p.household_id = p_household_id
       AND p.status = 'ACTIVE'
       AND p.paid_installments < p.installment_count
    RETURNING p.* INTO v_row;

    IF FOUND THEN
        RETURN NEXT v_row;
        RETURN;
    END IF;

    SELECT p.* INTO v_row
    FROM public.installment_plans AS p
    WHERE p.id = p_plan_id
      AND p.household_id = p_household_id;

    IF NOT FOUND THEN
        RETURN;  -- not in this household: no row
    END IF;

    IF v_row.status NOT IN ('ACTIVE', 'COMPLETED') THEN
        RAISE EXCEPTION 'This installment plan is % and takes no payments', v_row.status
            USING ERRCODE = '22023', HINT = 'plan_not_active';
    END IF;

    RETURN NEXT v_row;  -- already paid up: unchanged
END;
$$;

REVOKE ALL ON FUNCTION public.pay_installment_plan(uuid, uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.pay_installment_plan(uuid, uuid, uuid) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.pay_installment_plan(uuid, uuid, uuid) TO service_role;

-- 5. Post-checks ------------------------------------------------------------------------
DO $$
DECLARE
    v_n int;
BEGIN
    SELECT count(*) INTO v_n
    FROM public.cost_control_codes c
    WHERE c.household_id IS NULL AND c.is_system
      AND c.code IN ('OPEX-HOUSING', 'OPEX-EDUCATION', 'OPEX-DOMESTIC-HELP', 'OPEX-FAMILY-SUPPORT',
                     'OPEX-CHARITY', 'OPEX-TRANSPORT', 'OPEX-INSURANCE', 'OPEX-REMITTANCE');
    IF v_n <> 8 THEN
        RAISE EXCEPTION 'post-check: % of 8 new system categories present', v_n;
    END IF;

    SELECT count(*) INTO v_n
    FROM public.cost_control_sub_categories s
    WHERE s.parent_code IN ('OPEX-HOUSING', 'OPEX-EDUCATION', 'OPEX-DOMESTIC-HELP', 'OPEX-FAMILY-SUPPORT',
                            'OPEX-CHARITY', 'OPEX-TRANSPORT', 'OPEX-INSURANCE', 'OPEX-REMITTANCE');
    IF v_n <> 23 THEN
        RAISE EXCEPTION 'post-check: % of 23 new system sub-categories present', v_n;
    END IF;

    SELECT count(*) INTO v_n
    FROM public.cost_control_codes c, unnest(c.keywords) k
    WHERE c.household_id IS NULL
      AND c.code IN ('OPEX-HOUSING', 'OPEX-EDUCATION', 'OPEX-DOMESTIC-HELP', 'OPEX-FAMILY-SUPPORT',
                     'OPEX-CHARITY', 'OPEX-TRANSPORT', 'OPEX-INSURANCE', 'OPEX-REMITTANCE')
      AND char_length(btrim(k)) < 3;
    IF v_n > 0 THEN
        RAISE EXCEPTION 'post-check: % keyword(s) shorter than 3 characters', v_n;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.cost_control_sub_categories
                   WHERE parent_code = 'OPEX-UTILITIES' AND sub_code = 'housing_rent') THEN
        RAISE NOTICE 'post-check: OPEX-UTILITIES/housing_rent is absent (it was not removed by this migration)';
    END IF;

    SELECT count(*) INTO v_n FROM public.installment_plans
    WHERE frequency NOT IN ('monthly', 'biweekly')
       OR next_due_at IS DISTINCT FROM public.installment_next_due_at(start_date, frequency, paid_installments,
                                                                      installment_count, status);
    IF v_n > 0 THEN
        RAISE EXCEPTION 'post-check: % installment plan(s) with an invalid frequency or a stale next_due_at', v_n;
    END IF;

    IF has_column_privilege('authenticated', 'public.installment_plans', 'frequency', 'UPDATE')
       OR has_column_privilege('authenticated', 'public.installment_plans', 'next_due_at', 'UPDATE')
       OR has_column_privilege('authenticated', 'public.installment_plans', 'paid_installments', 'UPDATE')
       OR has_column_privilege('anon', 'public.installment_plans', 'next_due_at', 'UPDATE')
       OR has_function_privilege('authenticated', 'public.pay_installment_plan(uuid, uuid, uuid)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.pay_installment_plan(uuid, uuid, uuid)', 'EXECUTE')
       OR NOT has_function_privilege('service_role', 'public.pay_installment_plan(uuid, uuid, uuid)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.installment_next_due_at(date, text, integer, integer, text)', 'EXECUTE')
       OR has_function_privilege('authenticated', 'public.installment_plans_schedule()', 'EXECUTE') THEN
        RAISE EXCEPTION 'post-check: installment privileges are wrong';
    END IF;

    SELECT count(*) INTO v_n FROM public.household_category_settings
    WHERE category_code IN ('OPEX-HOUSING', 'OPEX-EDUCATION', 'OPEX-DOMESTIC-HELP', 'OPEX-FAMILY-SUPPORT',
                            'OPEX-CHARITY', 'OPEX-TRANSPORT', 'OPEX-INSURANCE', 'OPEX-REMITTANCE');
    RAISE NOTICE 'post-check: 8 system categories, 23 sub-categories; % household setting(s) for them', v_n;
END;
$$;

COMMIT;
