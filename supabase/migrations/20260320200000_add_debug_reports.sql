-- Debug reports table for remote log viewing
CREATE TABLE IF NOT EXISTS debug_reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users(id),
  user_email text,
  label text NOT NULL DEFAULT 'full',
  content text NOT NULL,
  entry_count integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE debug_reports ENABLE ROW LEVEL SECURITY;

-- Anyone authenticated can insert
CREATE POLICY "Authenticated users can insert debug reports"
  ON debug_reports FOR INSERT TO authenticated
  WITH CHECK (true);

-- Anyone can read (so developer can pull without auth)
CREATE POLICY "Anyone can read debug reports"
  ON debug_reports FOR SELECT
  USING (true);
