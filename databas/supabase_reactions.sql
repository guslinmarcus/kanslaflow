-- ============================================
-- Moodly: Parent Reactions Table
-- Kör detta i Supabase SQL Editor
-- ============================================

CREATE TABLE parent_reactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id UUID REFERENCES families(id) ON DELETE CASCADE,
  from_user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  to_user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  checkin_id UUID REFERENCES place_checkins(id) ON DELETE SET NULL,
  reaction_type TEXT NOT NULL DEFAULT 'emoji' CHECK (reaction_type IN ('emoji','message','cheer','high_five')),
  emoji TEXT,
  message TEXT CHECK (char_length(message) <= 80),
  seen BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_reactions_to_user ON parent_reactions(to_user_id);
CREATE INDEX idx_reactions_unseen ON parent_reactions(to_user_id, seen) WHERE seen = FALSE;
CREATE INDEX idx_reactions_family ON parent_reactions(family_id);

-- Row Level Security
ALTER TABLE parent_reactions ENABLE ROW LEVEL SECURITY;

-- Family members can send reactions
CREATE POLICY "Family members can insert reactions" ON parent_reactions
  FOR INSERT WITH CHECK (
    auth.uid() = from_user_id
    AND family_id IN (SELECT family_id FROM family_members WHERE user_id = auth.uid())
  );

-- Users can view reactions sent to them
CREATE POLICY "Users can view reactions to them" ON parent_reactions
  FOR SELECT USING (auth.uid() = to_user_id);

-- Users can view reactions they sent
CREATE POLICY "Users can view reactions from them" ON parent_reactions
  FOR SELECT USING (auth.uid() = from_user_id);

-- Users can mark their own reactions as seen
CREATE POLICY "Users can update own reactions" ON parent_reactions
  FOR UPDATE USING (auth.uid() = to_user_id)
  WITH CHECK (auth.uid() = to_user_id);
