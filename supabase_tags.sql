-- ============================================
-- Moodly: Add tags column to place_checkins
-- Kör detta i Supabase SQL Editor
-- ============================================

-- Add tags column (JSONB array, e.g. ["Kompisar","Trött"])
ALTER TABLE place_checkins
ADD COLUMN IF NOT EXISTS tags JSONB DEFAULT NULL;

-- GIN index for tag querying
CREATE INDEX IF NOT EXISTS idx_checkins_tags
ON place_checkins USING GIN (tags)
WHERE tags IS NOT NULL;

-- Analytics view: most common tags
CREATE OR REPLACE VIEW analytics_tags AS
SELECT
  tag,
  COUNT(*) AS times_used,
  COUNT(DISTINCT user_id) AS unique_users,
  ROUND(AVG(score), 2) AS avg_score_with_tag
FROM place_checkins,
  jsonb_array_elements_text(tags) AS tag
WHERE tags IS NOT NULL
GROUP BY tag
ORDER BY times_used DESC;
