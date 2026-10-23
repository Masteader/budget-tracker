-- ============================================================================
-- Migration: 20261024000000_create_inquiries_table.sql
--
-- Persistent lead capture and support inquiry storage:
-- Records VIP early-access signups, contact messages, and support inquiries
-- directly into PostgreSQL with RLS.
--
-- Security:
-- 1. Anonymous and authenticated users can INSERT new inquiries.
-- 2. Public SELECT is DENIED (protects customer contact lists and emails from scrapers).
-- 3. Only service-role backend (ai_service) can read/update delivery status.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.inquiries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    type TEXT NOT NULL CHECK (type IN ('vip_early_access', 'support', 'contact')),
    email TEXT NOT NULL,
    name TEXT,
    message TEXT,
    locale TEXT DEFAULT 'ar',
    source TEXT DEFAULT 'web',
    reference TEXT NOT NULL UNIQUE,
    status TEXT NOT NULL DEFAULT 'captured' CHECK (status IN ('captured', 'delivered', 'failed')),
    delivery_provider TEXT,
    error_detail TEXT
);

-- Indexes for rapid deduplication and audit sorting
CREATE INDEX IF NOT EXISTS idx_inquiries_email_type ON public.inquiries (email, type);
CREATE INDEX IF NOT EXISTS idx_inquiries_created_at ON public.inquiries (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_inquiries_reference ON public.inquiries (reference);

-- Enable Row Level Security
ALTER TABLE public.inquiries ENABLE ROW LEVEL SECURITY;

-- Drop policy if exists for idempotent re-runs
DROP POLICY IF EXISTS "Allow anonymous and authenticated insert into inquiries" ON public.inquiries;

-- Anonymous and authenticated visitors can submit inquiries
CREATE POLICY "Allow anonymous and authenticated insert into inquiries"
    ON public.inquiries
    FOR INSERT
    TO anon, authenticated
    WITH CHECK (true);
