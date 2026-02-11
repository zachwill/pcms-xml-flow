-- Team roster coaches: normalize assistant semantics.
--
-- The upstream payload key is named `isAssistant`, but in practice it is a
-- role code (not a strict boolean). Preserve that integer as
-- `assistant_role_code`, and expose a true boolean `is_assistant` for
-- downstream consumers.

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'nba'
      AND table_name = 'team_roster_coaches'
      AND column_name = 'is_assistant'
      AND data_type = 'integer'
  )
  AND NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'nba'
      AND table_name = 'team_roster_coaches'
      AND column_name = 'assistant_role_code'
  ) THEN
    ALTER TABLE nba.team_roster_coaches
      RENAME COLUMN is_assistant TO assistant_role_code;
  END IF;
END $$;

ALTER TABLE nba.team_roster_coaches
  ADD COLUMN IF NOT EXISTS assistant_role_code integer;

ALTER TABLE nba.team_roster_coaches
  ADD COLUMN IF NOT EXISTS is_assistant boolean;

UPDATE nba.team_roster_coaches
SET is_assistant = CASE
  WHEN assistant_role_code IN (2, 4, 9, 12, 13) THEN TRUE
  WHEN assistant_role_code IN (1, 3, 5, 10, 15) THEN FALSE
  WHEN coach_type ILIKE '%assistant%' THEN TRUE
  ELSE NULL
END
WHERE is_assistant IS NULL;

COMMENT ON COLUMN nba.team_roster_coaches.assistant_role_code IS
  'Raw NBA API role code from coaches[].isAssistant (not a strict boolean).';

COMMENT ON COLUMN nba.team_roster_coaches.is_assistant IS
  'Derived boolean assistant flag (from assistant_role_code/coach_type).';
