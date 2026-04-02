-- Security fixes for Moodly
-- Run this in Supabase SQL Editor

-- 1. Increase invite code length from 4 bytes (8 hex chars) to 8 bytes (16 hex chars)
-- This changes from ~65k possible codes to ~18 quintillion
ALTER TABLE families
ALTER COLUMN invite_code SET DEFAULT encode(gen_random_bytes(8), 'hex');

-- Update any existing short invite codes
UPDATE families
SET invite_code = encode(gen_random_bytes(8), 'hex')
WHERE length(invite_code) < 12;

-- 2. Add rate limiting function for parent reactions
CREATE OR REPLACE FUNCTION check_reaction_rate_limit()
RETURNS TRIGGER AS $$
BEGIN
    IF (SELECT count(*) FROM parent_reactions
        WHERE from_user_id = NEW.from_user_id
        AND created_at > now() - interval '1 hour') >= 20 THEN
        RAISE EXCEPTION 'Rate limit exceeded: max 20 reactions per hour';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS reaction_rate_limit ON parent_reactions;
CREATE TRIGGER reaction_rate_limit
    BEFORE INSERT ON parent_reactions
    FOR EACH ROW EXECUTE FUNCTION check_reaction_rate_limit();

-- 3. Add moodis_data column to profiles (for syncing Moodis state)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name = 'profiles' AND column_name = 'moodis_data') THEN
        ALTER TABLE profiles ADD COLUMN moodis_data jsonb DEFAULT '{}';
    END IF;
END $$;
