-- ============================================
-- Moodly: Feedback Table
-- Kör detta i Supabase SQL Editor
-- ============================================

CREATE TABLE feedback (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  rating SMALLINT CHECK (rating BETWEEN 1 AND 5),
  text TEXT,
  role TEXT,
  kommun TEXT,
  children_count SMALLINT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for querying
CREATE INDEX idx_feedback_created ON feedback(created_at DESC);

-- RLS
ALTER TABLE feedback ENABLE ROW LEVEL SECURITY;

-- Anyone authenticated can insert feedback
CREATE POLICY "Users can insert feedback" ON feedback
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Only service role can read (admin dashboard)
-- No SELECT policy = users can't read others' feedback
