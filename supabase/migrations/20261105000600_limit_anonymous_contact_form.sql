-- ============================================================================
-- Migration: 20261105000600_limit_anonymous_contact_form.sql
--
-- Rule 04: no policy targets anon, and anon can execute no function in public. Tests 14
-- and 23 caught these, added by 20261024000000 and 20261026120000:
--
-- public.inquiries: an anon + authenticated INSERT policy WITH CHECK (true), and the
--   default grants, which include TRUNCATE. No client needs any of it. web_app posts to
--   POST /public/inquiries (web_app/src/lib/inquiries.ts), ai_service writes the row with
--   the service role (routes/inquiries.py), and neither the app nor any earlier web build
--   has written to the table directly. Service role only from here on. Rate limits and the
--   honeypot live on that route, so the policy was also a way around them.
--
-- public.cost_control_templates: an anon SELECT policy and default grants. Nothing reads
--   it from a client today. Signed-in users keep read-only access to this public catalog.
--
-- replace_household_category, seed_household_default_taxonomy: anon could execute both.
--   No client calls either; the app and ai_service never reference these RPCs, and creating
--   a household does not use them. Service role only. seed_household_default_taxonomy has no
--   membership check, so any signed-in user could write settings rows into any household.
--   Their search_path also gains pg_temp, listed last as rule 04's other functions do.
-- ============================================================================

BEGIN;

DROP POLICY IF EXISTS "Allow anonymous and authenticated insert into inquiries" ON public.inquiries;
REVOKE ALL ON public.inquiries FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.inquiries TO service_role;

DROP POLICY IF EXISTS cost_control_templates_select ON public.cost_control_templates;
CREATE POLICY cost_control_templates_select ON public.cost_control_templates
    FOR SELECT TO authenticated USING (true);
REVOKE ALL ON public.cost_control_templates FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.cost_control_templates TO authenticated;
GRANT ALL ON public.cost_control_templates TO service_role;

REVOKE ALL ON FUNCTION public.replace_household_category(UUID, VARCHAR, VARCHAR, VARCHAR, VARCHAR) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.seed_household_default_taxonomy(UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.replace_household_category(UUID, VARCHAR, VARCHAR, VARCHAR, VARCHAR) TO service_role;
GRANT EXECUTE ON FUNCTION public.seed_household_default_taxonomy(UUID) TO service_role;

ALTER FUNCTION public.replace_household_category(UUID, VARCHAR, VARCHAR, VARCHAR, VARCHAR) SET search_path = public, pg_temp;
ALTER FUNCTION public.seed_household_default_taxonomy(UUID) SET search_path = public, pg_temp;

COMMIT;
