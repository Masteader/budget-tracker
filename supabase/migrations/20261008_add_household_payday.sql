-- Migration: Add configurable monthly payday day to households and users
-- Default: 27 (standard Saudi government / public sector payday)
-- Range: 1 to 31

ALTER TABLE public.households 
ADD COLUMN IF NOT EXISTS payday_day INTEGER NOT NULL DEFAULT 27 
CHECK (payday_day >= 1 AND payday_day <= 31);

COMMENT ON COLUMN public.households.payday_day IS 'Configured monthly salary day (1-31) that defines the budget rollover cycle.';

ALTER TABLE public.users 
ADD COLUMN IF NOT EXISTS payday_day INTEGER DEFAULT 27 
CHECK (payday_day >= 1 AND payday_day <= 31);

COMMENT ON COLUMN public.users.payday_day IS 'User-specific preferred salary payday (1-31).';
