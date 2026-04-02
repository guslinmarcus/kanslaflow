-- ============================================
-- Moodly Analytics Views & Functions
-- Kör detta i Supabase SQL Editor
-- Tabeller: profiles, places, place_checkins,
--           families, family_members, chat_sessions
-- ============================================

-- 1. Antal signups per dag
CREATE OR REPLACE VIEW analytics_signups_daily AS
SELECT
  DATE(created_at) AS day,
  COUNT(*) AS signups
FROM auth.users
GROUP BY DATE(created_at)
ORDER BY day DESC;

-- 2. Totalt antal användare
CREATE OR REPLACE VIEW analytics_users_total AS
SELECT
  COUNT(*) AS total_users,
  COUNT(*) FILTER (WHERE created_at > NOW() - INTERVAL '7 days') AS new_last_7d,
  COUNT(*) FILTER (WHERE created_at > NOW() - INTERVAL '30 days') AS new_last_30d
FROM auth.users;

-- 3. Dagliga check-ins (baserat på place_checkins)
CREATE OR REPLACE VIEW analytics_checkins_daily AS
SELECT
  DATE(checked_at) AS day,
  COUNT(*) AS checkins,
  COUNT(DISTINCT user_id) AS unique_users
FROM place_checkins
GROUP BY DATE(checked_at)
ORDER BY day DESC;

-- 4. Veckovis aktiva användare (WAU)
CREATE OR REPLACE VIEW analytics_wau AS
SELECT
  DATE_TRUNC('week', checked_at)::date AS week_start,
  COUNT(DISTINCT user_id) AS active_users
FROM place_checkins
GROUP BY DATE_TRUNC('week', checked_at)
ORDER BY week_start DESC;

-- 5. Månadsvis aktiva användare (MAU)
CREATE OR REPLACE VIEW analytics_mau AS
SELECT
  DATE_TRUNC('month', checked_at)::date AS month_start,
  COUNT(DISTINCT user_id) AS active_users
FROM place_checkins
GROUP BY DATE_TRUNC('month', checked_at)
ORDER BY month_start DESC;

-- 6. Aktiva kommuner
CREATE OR REPLACE VIEW analytics_kommuner AS
SELECT
  p.kommun,
  COUNT(DISTINCT p.id) AS families,
  COUNT(pc.id) AS total_checkins,
  MAX(pc.checked_at) AS last_activity
FROM profiles p
LEFT JOIN place_checkins pc ON pc.user_id = p.id
WHERE p.kommun IS NOT NULL AND p.kommun != ''
GROUP BY p.kommun
ORDER BY families DESC;

-- 7. Familjestatistik
CREATE OR REPLACE VIEW analytics_families AS
SELECT
  COUNT(DISTINCT f.id) AS total_families,
  COUNT(DISTINCT fm.user_id) AS total_members,
  ROUND(AVG(member_count), 1) AS avg_family_size
FROM families f
LEFT JOIN (
  SELECT family_id, COUNT(*) AS member_count
  FROM family_members
  GROUP BY family_id
) mc ON mc.family_id = f.id
LEFT JOIN family_members fm ON fm.family_id = f.id;

-- 8. Retention: användare som kom tillbaka dag 1, 7, 30
CREATE OR REPLACE FUNCTION analytics_retention()
RETURNS TABLE(cohort_day date, d1_pct numeric, d7_pct numeric, d30_pct numeric)
LANGUAGE sql STABLE AS $$
  WITH cohorts AS (
    SELECT
      id AS user_id,
      DATE(created_at) AS signup_day
    FROM auth.users
  ),
  activity AS (
    SELECT DISTINCT user_id, DATE(checked_at) AS active_day
    FROM place_checkins
  )
  SELECT
    c.signup_day AS cohort_day,
    ROUND(100.0 * COUNT(DISTINCT a1.user_id) / NULLIF(COUNT(DISTINCT c.user_id), 0), 1) AS d1_pct,
    ROUND(100.0 * COUNT(DISTINCT a7.user_id) / NULLIF(COUNT(DISTINCT c.user_id), 0), 1) AS d7_pct,
    ROUND(100.0 * COUNT(DISTINCT a30.user_id) / NULLIF(COUNT(DISTINCT c.user_id), 0), 1) AS d30_pct
  FROM cohorts c
  LEFT JOIN activity a1 ON a1.user_id = c.user_id AND a1.active_day = c.signup_day + 1
  LEFT JOIN activity a7 ON a7.user_id = c.user_id AND a7.active_day = c.signup_day + 7
  LEFT JOIN activity a30 ON a30.user_id = c.user_id AND a30.active_day = c.signup_day + 30
  GROUP BY c.signup_day
  ORDER BY c.signup_day DESC;
$$;

-- 9. Genomsnittligt MoodScore per dag (alla användare)
CREATE OR REPLACE VIEW analytics_mood_trend AS
SELECT
  DATE(checked_at) AS day,
  ROUND(AVG(score), 2) AS avg_score,
  COUNT(*) AS total_checkins
FROM place_checkins
WHERE score IS NOT NULL
GROUP BY DATE(checked_at)
ORDER BY day DESC;

-- 10. Plats-checkins fördelning (join med places för platsnamn)
CREATE OR REPLACE VIEW analytics_places AS
SELECT
  pl.name AS place_name,
  pl.type AS place_type,
  COUNT(pc.id) AS checkins,
  ROUND(AVG(pc.score), 2) AS avg_score,
  COUNT(DISTINCT pc.user_id) AS unique_users
FROM place_checkins pc
JOIN places pl ON pl.id = pc.place_id
GROUP BY pl.name, pl.type
ORDER BY checkins DESC;

-- ============================================
-- RPC: Dashboard-sammanfattning (kalla från admin)
-- ============================================
CREATE OR REPLACE FUNCTION analytics_dashboard()
RETURNS json
LANGUAGE sql STABLE AS $$
  SELECT json_build_object(
    'total_users', (SELECT COUNT(*) FROM auth.users),
    'new_users_7d', (SELECT COUNT(*) FROM auth.users WHERE created_at > NOW() - INTERVAL '7 days'),
    'checkins_today', (SELECT COUNT(*) FROM place_checkins WHERE DATE(checked_at) = CURRENT_DATE),
    'checkins_7d', (SELECT COUNT(*) FROM place_checkins WHERE checked_at > NOW() - INTERVAL '7 days'),
    'wau', (SELECT COUNT(DISTINCT user_id) FROM place_checkins WHERE checked_at > NOW() - INTERVAL '7 days'),
    'mau', (SELECT COUNT(DISTINCT user_id) FROM place_checkins WHERE checked_at > NOW() - INTERVAL '30 days'),
    'total_families', (SELECT COUNT(*) FROM families),
    'active_kommuner', (SELECT COUNT(DISTINCT kommun) FROM profiles WHERE kommun IS NOT NULL AND kommun != ''::text),
    'avg_mood_7d', (SELECT ROUND(AVG(score), 2) FROM place_checkins WHERE checked_at > NOW() - INTERVAL '7 days' AND score IS NOT NULL)
  );
$$;
