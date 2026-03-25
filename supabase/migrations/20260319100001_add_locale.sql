-- Add locale column to productions for syncing dialect to cast members.
ALTER TABLE public.productions
  ADD COLUMN IF NOT EXISTS locale text NOT NULL DEFAULT 'en-US';
