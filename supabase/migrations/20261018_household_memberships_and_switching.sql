-- supabase/migrations/20261018_household_memberships_and_switching.sql
-- Description: Creates household_memberships junction table, backfills existing users, and adds switch_active_household RPC.

-- 1. Create household_memberships table
CREATE TABLE IF NOT EXISTS public.household_memberships (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id UUID NOT NULL REFERENCES public.households(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    role TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('admin', 'member')),
    is_default BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_household_user UNIQUE (household_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_memberships_user ON public.household_memberships(user_id);
CREATE INDEX IF NOT EXISTS idx_memberships_household ON public.household_memberships(household_id);

-- 2. Enable RLS
ALTER TABLE public.household_memberships ENABLE ROW LEVEL SECURITY;

-- 3. RLS Policies
DROP POLICY IF EXISTS "memberships_view_own" ON public.household_memberships;
CREATE POLICY "memberships_view_own" ON public.household_memberships
    FOR SELECT USING (user_id = auth.uid());

DROP POLICY IF EXISTS "memberships_admin_manage" ON public.household_memberships;
CREATE POLICY "memberships_admin_manage" ON public.household_memberships
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM public.household_memberships m
            WHERE m.household_id = household_memberships.household_id
              AND m.user_id = auth.uid()
              AND m.role = 'admin'
        )
    );

-- 4. Backfill existing user household assignments
INSERT INTO public.household_memberships (household_id, user_id, role, is_default)
SELECT household_id, id, role, true
FROM public.users
WHERE household_id IS NOT NULL
ON CONFLICT (household_id, user_id) DO NOTHING;

-- 5. RPC function to get all households for current user
CREATE OR REPLACE FUNCTION public.get_user_households()
RETURNS TABLE (
    household_id UUID,
    household_name TEXT,
    invite_code TEXT,
    role TEXT,
    is_active BOOLEAN
) LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    RETURN QUERY
    SELECT 
        h.id AS household_id,
        h.name AS household_name,
        h.invite_code,
        m.role,
        (h.id = u.household_id) AS is_active
    FROM public.household_memberships m
    JOIN public.households h ON h.id = m.household_id
    JOIN public.users u ON u.id = m.user_id
    WHERE m.user_id = auth.uid()
    ORDER BY is_active DESC, m.created_at ASC;
END;
$$;

-- 6. RPC function to switch active household context
CREATE OR REPLACE FUNCTION public.switch_active_household(p_household_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    v_role TEXT;
    v_name TEXT;
BEGIN
    SELECT role INTO v_role
    FROM public.household_memberships
    WHERE household_id = p_household_id AND user_id = auth.uid();

    IF v_role IS NULL THEN
        RAISE EXCEPTION 'Access denied: Not a member of household %', p_household_id;
    END IF;

    SELECT name INTO v_name
    FROM public.households
    WHERE id = p_household_id;

    UPDATE public.users
    SET household_id = p_household_id,
        role = v_role
    WHERE id = auth.uid();

    RETURN jsonb_build_object(
        'success', true,
        'household_id', p_household_id,
        'household_name', v_name,
        'role', v_role
    );
END;
$$;
