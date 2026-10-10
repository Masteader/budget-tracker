-- Migration: Add monthly_income to households
-- Allows tracking monthly household salary / income in SAR for zero-based budget allocation and savings reserve calculations.

ALTER TABLE public.households
ADD COLUMN IF NOT EXISTS monthly_income NUMERIC(12, 2) NOT NULL DEFAULT 0
CHECK (monthly_income >= 0);

COMMENT ON COLUMN public.households.monthly_income IS 'Configured monthly household salary or income in SAR.';
