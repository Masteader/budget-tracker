-- Migration: Add qr_code_raw column to transactions table for ZATCA Base64 TLV storage
ALTER TABLE public.transactions
  ADD COLUMN IF NOT EXISTS qr_code_raw TEXT;

COMMENT ON COLUMN public.transactions.qr_code_raw IS 'Raw Base64 TLV string from Saudi ZATCA e-invoicing QR code for audit and re-verification.';
