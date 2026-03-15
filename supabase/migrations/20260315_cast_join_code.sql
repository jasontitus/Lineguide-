-- ============================================================
-- Cast join codes: let actors join productions via a short code
-- ============================================================

-- 1. Add join_code to productions
ALTER TABLE public.productions ADD COLUMN join_code text UNIQUE;

-- Backfill existing productions with random codes
UPDATE public.productions
SET join_code = upper(substr(md5(random()::text), 1, 6))
WHERE join_code IS NULL;

-- Now make it NOT NULL
ALTER TABLE public.productions ALTER COLUMN join_code SET NOT NULL;

-- 2. Make user_id nullable (support invited-but-not-joined)
ALTER TABLE public.cast_members ALTER COLUMN user_id DROP NOT NULL;

-- Drop the unique constraint that requires user_id
ALTER TABLE public.cast_members DROP CONSTRAINT IF EXISTS cast_members_production_id_user_id_key;

-- 3. Add new columns to cast_members
ALTER TABLE public.cast_members ADD COLUMN IF NOT EXISTS display_name text DEFAULT '';
ALTER TABLE public.cast_members ADD COLUMN IF NOT EXISTS contact_info text;
ALTER TABLE public.cast_members ADD COLUMN IF NOT EXISTS invited_at timestamptz DEFAULT now();
ALTER TABLE public.cast_members ADD COLUMN IF NOT EXISTS joined_at timestamptz;

-- 4. RLS: allow any authenticated user to look up productions by join code
CREATE POLICY "Anyone can lookup by join code"
  ON public.productions FOR SELECT
  USING (auth.role() = 'authenticated');

-- 5. RLS: allow users to claim an invitation (set their user_id on a cast_member row)
CREATE POLICY "Users can claim invitation"
  ON public.cast_members FOR UPDATE
  USING (user_id IS NULL)  -- only unclaimed rows
  WITH CHECK (auth.uid() = user_id);  -- can only set to own user_id

-- 6. RLS: allow users to insert themselves (self-join via code)
CREATE POLICY "Users can self-join"
  ON public.cast_members FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- 7. Update membership check to handle nullable user_id
CREATE OR REPLACE FUNCTION public.is_production_member(p_production_id uuid, p_user_id uuid)
RETURNS boolean AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.cast_members
    WHERE production_id = p_production_id
      AND user_id = p_user_id
  );
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- 8. Helper to generate a join code (callable from client if needed)
CREATE OR REPLACE FUNCTION public.generate_join_code()
RETURNS text AS $$
DECLARE
  chars text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  result text := '';
  i integer;
BEGIN
  FOR i IN 1..6 LOOP
    result := result || substr(chars, floor(random() * length(chars) + 1)::int, 1);
  END LOOP;
  RETURN result;
END;
$$ LANGUAGE plpgsql;
