-- Migration: 20261015_manual_members_and_claim_merge.sql
-- Description: Extends household_dependents with linked_user_id and household_invites with target_member_id for pre-created manual member claim-and-merge.

-- 1. Add linked_user_id to household_dependents
ALTER TABLE public.household_dependents
ADD COLUMN IF NOT EXISTS linked_user_id UUID REFERENCES public.users(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_household_dependents_linked_user ON public.household_dependents(linked_user_id);

-- 2. Add target_member_id to household_invites
ALTER TABLE public.household_invites
ADD COLUMN IF NOT EXISTS target_member_id UUID REFERENCES public.household_dependents(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_household_invites_target_member ON public.household_invites(target_member_id);
