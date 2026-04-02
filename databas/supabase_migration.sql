-- ============================================
-- Moodly Supabase Migration
-- Run this in Supabase SQL Editor (supabase.com > your project > SQL Editor)
-- ============================================

-- ==========================================
-- PART 1: CREATE ALL TABLES
-- ==========================================

-- 1. PROFILES
CREATE TABLE profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  user_name TEXT NOT NULL DEFAULT '',
  ai_name TEXT NOT NULL DEFAULT 'Luna',
  personality TEXT NOT NULL DEFAULT 'warm' CHECK (personality IN ('warm', 'direct', 'coach')),
  xp INTEGER NOT NULL DEFAULT 0,
  level INTEGER NOT NULL DEFAULT 1,
  points INTEGER NOT NULL DEFAULT 0,
  streak INTEGER NOT NULL DEFAULT 0,
  selected_avatar TEXT NOT NULL DEFAULT 'default',
  unlocked_avatars TEXT[] NOT NULL DEFAULT ARRAY['default'],
  daily_reward_claimed TIMESTAMPTZ,
  onboarded TIMESTAMPTZ,
  alerts_seen TEXT[] NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 2. PLACES
CREATE TABLE places (
  id TEXT PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('school', 'work', 'home', 'sport', 'hobby', 'other')),
  osm_id TEXT,
  address TEXT,
  lat DOUBLE PRECISION,
  lng DOUBLE PRECISION,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_places_user ON places(user_id);
CREATE INDEX idx_places_osm ON places(osm_id) WHERE osm_id IS NOT NULL;

-- 3. PLACE CHECK-INS
CREATE TABLE place_checkins (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  place_id TEXT NOT NULL REFERENCES places(id) ON DELETE CASCADE,
  score SMALLINT NOT NULL CHECK (score BETWEEN 1 AND 5),
  comment TEXT,
  checked_at DATE NOT NULL DEFAULT CURRENT_DATE,
  ts TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(user_id, place_id, checked_at)
);

CREATE INDEX idx_checkins_user ON place_checkins(user_id);
CREATE INDEX idx_checkins_place ON place_checkins(place_id);
CREATE INDEX idx_checkins_date ON place_checkins(checked_at);

-- 4. CHAT SESSIONS (no transcripts — privacy)
CREATE TABLE chat_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  score INTEGER NOT NULL CHECK (score BETWEEN 0 AND 100),
  emotion TEXT NOT NULL,
  duration_seconds INTEGER,
  ts TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_chat_user ON chat_sessions(user_id);

-- 5. FAMILIES
CREATE TABLE families (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL DEFAULT 'Min familj',
  invite_code TEXT UNIQUE NOT NULL DEFAULT encode(gen_random_bytes(4), 'hex'),
  created_by UUID NOT NULL REFERENCES profiles(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 6. FAMILY MEMBERS
CREATE TABLE family_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id UUID NOT NULL REFERENCES families(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  role TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('parent', 'child', 'member')),
  display_name TEXT,
  age_group TEXT,
  joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(family_id, user_id)
);

CREATE INDEX idx_fam_members_family ON family_members(family_id);
CREATE INDEX idx_fam_members_user ON family_members(user_id);

-- ==========================================
-- PART 2: ENABLE RLS + CREATE ALL POLICIES
-- (all tables exist now, so cross-references work)
-- ==========================================

-- Profiles RLS
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view own profile" ON profiles FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Users can update own profile" ON profiles FOR UPDATE USING (auth.uid() = id);
CREATE POLICY "Users can insert own profile" ON profiles FOR INSERT WITH CHECK (auth.uid() = id);

-- Places RLS
ALTER TABLE places ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view own places" ON places FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert own places" ON places FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update own places" ON places FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can delete own places" ON places FOR DELETE USING (auth.uid() = user_id);
CREATE POLICY "Family can view member places" ON places FOR SELECT
  USING (user_id IN (
    SELECT fm2.user_id FROM family_members fm1
    JOIN family_members fm2 ON fm1.family_id = fm2.family_id
    WHERE fm1.user_id = auth.uid()
  ));

-- Place checkins RLS
ALTER TABLE place_checkins ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view own checkins" ON place_checkins FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert own checkins" ON place_checkins FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update own checkins" ON place_checkins FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Family can view member checkins" ON place_checkins FOR SELECT
  USING (user_id IN (
    SELECT fm2.user_id FROM family_members fm1
    JOIN family_members fm2 ON fm1.family_id = fm2.family_id
    WHERE fm1.user_id = auth.uid()
  ));

-- Chat sessions RLS
ALTER TABLE chat_sessions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view own chats" ON chat_sessions FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert own chats" ON chat_sessions FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Families RLS
ALTER TABLE families ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Family members can view" ON families FOR SELECT
  USING (id IN (SELECT family_id FROM family_members WHERE user_id = auth.uid()));
CREATE POLICY "Creator can update" ON families FOR UPDATE
  USING (created_by = auth.uid());
CREATE POLICY "Any authed user can create" ON families FOR INSERT
  WITH CHECK (auth.uid() = created_by);

-- Family members RLS
ALTER TABLE family_members ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Family members can view members" ON family_members FOR SELECT
  USING (family_id IN (SELECT family_id FROM family_members fm WHERE fm.user_id = auth.uid()));
CREATE POLICY "Users can insert self" ON family_members FOR INSERT
  WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Parents can delete members" ON family_members FOR DELETE
  USING (family_id IN (
    SELECT family_id FROM family_members fm
    WHERE fm.user_id = auth.uid() AND fm.role = 'parent'
  ));

-- ==========================================
-- PART 3: VIEWS, FUNCTIONS, TRIGGERS
-- ==========================================

-- Anonymous benchmark view
CREATE MATERIALIZED VIEW osm_benchmarks AS
SELECT
  p.osm_id,
  p.name,
  p.type,
  COUNT(DISTINCT pc.user_id) AS user_count,
  ROUND(AVG(pc.score)::numeric, 1) AS avg_score,
  COUNT(pc.id) AS checkin_count,
  MAX(pc.checked_at) AS last_checkin
FROM places p
JOIN place_checkins pc ON pc.place_id = p.id
WHERE p.osm_id IS NOT NULL
  AND p.osm_id != ''
GROUP BY p.osm_id, p.name, p.type
HAVING COUNT(DISTINCT pc.user_id) >= 3
WITH DATA;

CREATE UNIQUE INDEX idx_osm_bench ON osm_benchmarks(osm_id);
CREATE INDEX idx_osm_bench_type ON osm_benchmarks(type);

GRANT SELECT ON osm_benchmarks TO authenticated;

-- RPC: Get area benchmarks
CREATE OR REPLACE FUNCTION get_area_benchmarks(
  p_lat DOUBLE PRECISION,
  p_lng DOUBLE PRECISION,
  p_type TEXT,
  p_radius_km DOUBLE PRECISION DEFAULT 15.0,
  p_exclude_osm_id TEXT DEFAULT NULL
)
RETURNS TABLE(
  osm_id TEXT,
  name TEXT,
  type TEXT,
  avg_score NUMERIC,
  user_count BIGINT
)
LANGUAGE sql STABLE SECURITY DEFINER
AS $$
  SELECT ob.osm_id, ob.name, ob.type, ob.avg_score, ob.user_count
  FROM osm_benchmarks ob
  JOIN places p ON p.osm_id = ob.osm_id
  WHERE ob.type = p_type
    AND (p_exclude_osm_id IS NULL OR ob.osm_id != p_exclude_osm_id)
    AND p.lat IS NOT NULL AND p.lng IS NOT NULL
    AND p.lat BETWEEN p_lat - (p_radius_km * 0.009) AND p_lat + (p_radius_km * 0.009)
    AND p.lng BETWEEN p_lng - (p_radius_km * 0.009) AND p_lng + (p_radius_km * 0.009)
  ORDER BY ob.avg_score DESC
  LIMIT 8
$$;

-- RPC: Join family by invite code
CREATE OR REPLACE FUNCTION join_family(p_invite_code TEXT, p_role TEXT DEFAULT 'member', p_age_group TEXT DEFAULT NULL)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_family_id UUID;
  v_user_id UUID := auth.uid();
BEGIN
  SELECT id INTO v_family_id FROM families WHERE invite_code = p_invite_code;
  IF v_family_id IS NULL THEN
    RAISE EXCEPTION 'Invalid invite code';
  END IF;

  INSERT INTO family_members (family_id, user_id, role, age_group)
  VALUES (v_family_id, v_user_id, p_role, p_age_group)
  ON CONFLICT (family_id, user_id) DO NOTHING;

  RETURN v_family_id;
END;
$$;

-- Auto-create profile on signup
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO profiles (id) VALUES (NEW.id);
  RETURN NEW;
END;
$$;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- ==========================================
-- PART 4: KOMMUN BENCHMARKS
-- ==========================================

-- Add kommun column to profiles
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS kommun TEXT NOT NULL DEFAULT '';
CREATE INDEX IF NOT EXISTS idx_profiles_kommun ON profiles(kommun) WHERE kommun != '';

-- RPC: Get kommun-level mood statistics
-- Returns aggregated wellbeing data for all users in a given kommun
CREATE OR REPLACE FUNCTION get_kommun_stats(p_kommun TEXT)
RETURNS TABLE(
  avg_score NUMERIC,
  total_users BIGINT,
  total_checkins BIGINT,
  week_avg NUMERIC,
  prev_week_avg NUMERIC
)
LANGUAGE sql STABLE SECURITY DEFINER
AS $$
  SELECT
    ROUND(AVG(pc.score)::numeric, 1) as avg_score,
    COUNT(DISTINCT pr.id) as total_users,
    COUNT(pc.id) as total_checkins,
    ROUND(AVG(CASE WHEN pc.checked_at >= CURRENT_DATE - 7 THEN pc.score END)::numeric, 1) as week_avg,
    ROUND(AVG(CASE WHEN pc.checked_at >= CURRENT_DATE - 14 AND pc.checked_at < CURRENT_DATE - 7 THEN pc.score END)::numeric, 1) as prev_week_avg
  FROM profiles pr
  JOIN places pl ON pl.user_id = pr.id
  JOIN place_checkins pc ON pc.place_id = pl.id
  WHERE LOWER(TRIM(pr.kommun)) = LOWER(TRIM(p_kommun))
    AND pr.kommun != ''
    AND pc.checked_at >= CURRENT_DATE - 30
$$;

-- RPC: Get kommun user count (lightweight check)
CREATE OR REPLACE FUNCTION get_kommun_user_count(p_kommun TEXT)
RETURNS BIGINT
LANGUAGE sql STABLE SECURITY DEFINER
AS $$
  SELECT COUNT(DISTINCT id)
  FROM profiles
  WHERE LOWER(TRIM(kommun)) = LOWER(TRIM(p_kommun))
    AND kommun != ''
    AND onboarded IS NOT NULL
$$;
