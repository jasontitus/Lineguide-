-- Add voice_preset and locale columns to productions table.
-- voice_preset: organizer's chosen TTS voice style (e.g. 'victorian_english').
-- locale: BCP-47 dialect for STT (e.g. 'en-GB').
-- NULL means use defaults (locale → 'en-US', preset → locale-based).

ALTER TABLE public.productions
  ADD COLUMN IF NOT EXISTS voice_preset text,
  ADD COLUMN IF NOT EXISTS locale text NOT NULL DEFAULT 'en-US';

-- The lookup_production_by_join_code RPC already uses row_to_json(p),
-- so both new columns are automatically included in join lookups.
