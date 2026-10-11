-- Migration: 20261011_household_dependents_and_subcategories.sql
-- Description: Creates household_dependents table with RLS and enriches subcategory keywords.

-- 1. Create household_dependents table
CREATE TABLE IF NOT EXISTS public.household_dependents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id UUID NOT NULL REFERENCES public.households(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    avatar_icon TEXT DEFAULT 'child',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_dependents_household ON public.household_dependents(household_id);

-- 2. Enable RLS
ALTER TABLE public.household_dependents ENABLE ROW LEVEL SECURITY;

-- 3. RLS Policies
DROP POLICY IF EXISTS "dependents_select_household" ON public.household_dependents;
CREATE POLICY "dependents_select_household" ON public.household_dependents
    FOR SELECT USING (
        household_id IN (
            SELECT household_id FROM public.users WHERE id = auth.uid()
        )
    );

DROP POLICY IF EXISTS "dependents_insert_household" ON public.household_dependents;
CREATE POLICY "dependents_insert_household" ON public.household_dependents
    FOR INSERT WITH CHECK (
        household_id IN (
            SELECT household_id FROM public.users WHERE id = auth.uid()
        )
    );

DROP POLICY IF EXISTS "dependents_update_household" ON public.household_dependents;
CREATE POLICY "dependents_update_household" ON public.household_dependents
    FOR UPDATE USING (
        household_id IN (
            SELECT household_id FROM public.users WHERE id = auth.uid()
        )
    );

DROP POLICY IF EXISTS "dependents_delete_household" ON public.household_dependents;
CREATE POLICY "dependents_delete_household" ON public.household_dependents
    FOR DELETE USING (
        household_id IN (
            SELECT household_id FROM public.users WHERE id = auth.uid()
        )
    );

-- 4. Update cost_control_sub_categories dining keywords with Saudi vernacular & plurals
UPDATE public.cost_control_sub_categories
SET keywords = ARRAY['restaurant', 'dinner', 'lunch', 'burger', 'مطعم', 'مطاعم', 'شاورما', 'بروستد', 'وجبة', 'غداء', 'عشاء', 'سندويش', 'مشويات', 'فطور', 'كبسة', 'بخاري', 'برجر', 'بيت الشاورما', 'البيك']
WHERE parent_code = 'OPEX-DINING' AND sub_code = 'restaurants_dinners';

UPDATE public.cost_control_sub_categories
SET keywords = ARRAY['coffee', 'cafe', 'starbucks', 'dunkin', 'قهوة', 'كافيه', 'مخبز', 'حلا', 'كيك', 'كرواسون', 'شاهي', 'شاي', 'دونات', 'لاتيه', 'سبانش']
WHERE parent_code = 'OPEX-DINING' AND sub_code = 'coffee_bakeries';
