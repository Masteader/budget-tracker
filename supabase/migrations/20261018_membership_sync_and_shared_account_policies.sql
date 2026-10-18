-- Migration: 20261018_membership_sync_and_shared_account_policies.sql
-- Description:
-- 1. Adds RLS policy for household members to update shared pool accounts.
-- 2. Adds trigger on public.users to automatically synchronize household memberships.
-- 3. Updates create_household_and_claim and join_household_by_code RPCs to insert memberships.

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'accounts' AND policyname = 'Household members can update shared pool accounts'
  ) THEN
    CREATE POLICY "Household members can update shared pool accounts"
    ON public.accounts
    FOR UPDATE
    TO authenticated
    USING (
      is_shared_pool = true 
      AND household_id IN (SELECT household_id FROM public.users WHERE id = auth.uid())
    )
    WITH CHECK (
      is_shared_pool = true 
      AND household_id IN (SELECT household_id FROM public.users WHERE id = auth.uid())
    );
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.sync_user_household_membership()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    IF NEW.household_id IS NOT NULL THEN
        INSERT INTO public.household_memberships (household_id, user_id, role, is_default)
        VALUES (
            NEW.household_id, 
            NEW.id, 
            COALESCE(NEW.role, 'member'), 
            NOT EXISTS (SELECT 1 FROM public.household_memberships WHERE user_id = NEW.id)
        )
        ON CONFLICT (household_id, user_id) 
        DO UPDATE SET role = COALESCE(EXCLUDED.role, public.household_memberships.role);
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_user_household_membership ON public.users;
CREATE TRIGGER trg_sync_user_household_membership
AFTER INSERT OR UPDATE OF household_id, role ON public.users
FOR EACH ROW EXECUTE FUNCTION public.sync_user_household_membership();

CREATE OR REPLACE FUNCTION public.create_household_and_claim(p_name TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    v_hh public.households%ROWTYPE;
BEGIN
    INSERT INTO public.households (name)
    VALUES (p_name)
    RETURNING * INTO v_hh;

    UPDATE public.users
    SET household_id = v_hh.id,
        role = 'admin'
    WHERE id = auth.uid();

    INSERT INTO public.household_memberships (household_id, user_id, role, is_default)
    VALUES (v_hh.id, auth.uid(), 'admin', true)
    ON CONFLICT (household_id, user_id) DO UPDATE SET role = 'admin';

    RETURN to_jsonb(v_hh);
END;
$$;

CREATE OR REPLACE FUNCTION public.join_household_by_code(p_invite_code TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    v_hh public.households%ROWTYPE;
BEGIN
    SELECT * INTO v_hh
    FROM public.households
    WHERE lower(invite_code) = lower(trim(p_invite_code));

    IF v_hh.id IS NULL THEN
        RAISE EXCEPTION 'Invalid invite code';
    END IF;

    UPDATE public.users
    SET household_id = v_hh.id,
        role = 'member'
    WHERE id = auth.uid();

    INSERT INTO public.household_memberships (household_id, user_id, role, is_default)
    VALUES (v_hh.id, auth.uid(), 'member', false)
    ON CONFLICT (household_id, user_id) DO NOTHING;

    RETURN to_jsonb(v_hh);
END;
$$;
