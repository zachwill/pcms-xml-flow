-- 017_remove_unused_two_way_daily_statuses_columns.sql
--
-- Remove unused columns from pcms.two_way_daily_statuses.
-- These columns don't exist in the source data (they were season-level aggregates from player_day_counts).
-- The actual daily values come from two_way_seasons which has day_of_season, contract_team_id, signing_team_id.
--
-- Originally created as: migrations/simplify_two_way_daily_statuses.sql

BEGIN;

ALTER TABLE pcms.two_way_daily_statuses
  DROP COLUMN IF EXISTS nba_service_days,
  DROP COLUMN IF EXISTS nba_service_limit,
  DROP COLUMN IF EXISTS nba_days_remaining,
  DROP COLUMN IF EXISTS nba_earned_salary,
  DROP COLUMN IF EXISTS glg_earned_salary,
  DROP COLUMN IF EXISTS nba_salary_days,
  DROP COLUMN IF EXISTS glg_salary_days,
  DROP COLUMN IF EXISTS unreported_days,
  DROP COLUMN IF EXISTS season_active_nba_game_days,
  DROP COLUMN IF EXISTS season_with_nba_days,
  DROP COLUMN IF EXISTS season_travel_with_nba_days,
  DROP COLUMN IF EXISTS season_non_nba_days,
  DROP COLUMN IF EXISTS season_non_nba_glg_days,
  DROP COLUMN IF EXISTS season_total_days;

COMMIT;
