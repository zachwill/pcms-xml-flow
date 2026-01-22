-- 028_fix_exceptions_warehouse_team_code_and_lookups.sql
--
-- Fixes for pcms.exceptions_warehouse:
-- - pcms.team_exceptions.team_code is often blank; derive team_code via pcms.teams (team_id).
-- - lookup_type for exception types is `lk_exception_types` (not `EXCEPTION_TYPE`).
-- - Preserve missingness: store raw team_code in team_code_source + has_source_team_code.

BEGIN;

ALTER TABLE pcms.exceptions_warehouse
  ADD COLUMN IF NOT EXISTS team_code_source text;

ALTER TABLE pcms.exceptions_warehouse
  ADD COLUMN IF NOT EXISTS has_source_team_code boolean;

CREATE OR REPLACE FUNCTION pcms.refresh_exceptions_warehouse()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM set_config('statement_timeout', '0', true);
  PERFORM set_config('lock_timeout', '5s', true);

  TRUNCATE TABLE pcms.exceptions_warehouse;

  INSERT INTO pcms.exceptions_warehouse (
    team_exception_id,
    team_code,
    team_code_source,
    has_source_team_code,
    team_id,
    salary_year,
    exception_type_lk,
    exception_type_name,
    effective_date,
    expiration_date,
    original_amount,
    remaining_amount,
    trade_exception_player_id,
    trade_exception_player_name,
    record_status_lk,
    refreshed_at
  )
  SELECT
    te.team_exception_id,

    -- Team code in PCMS is frequently blank; fall back to teams.team_code.
    COALESCE(NULLIF(BTRIM(te.team_code), ''), t.team_code) AS team_code,
    te.team_code AS team_code_source,
    (NULLIF(BTRIM(te.team_code), '') IS NOT NULL) AS has_source_team_code,

    te.team_id,
    te.salary_year,
    te.exception_type_lk,
    l.description AS exception_type_name,
    te.effective_date,
    te.expiration_date,
    te.original_amount,
    te.remaining_amount,
    te.trade_exception_player_id,
    CASE
      WHEN p.person_id IS NULL THEN NULL
      ELSE (p.last_name || ', ' || p.first_name)
    END AS trade_exception_player_name,
    te.record_status_lk,
    now() AS refreshed_at
  FROM pcms.team_exceptions te
  LEFT JOIN pcms.teams t
    ON t.team_id = te.team_id
  LEFT JOIN pcms.lookups l
    ON l.lookup_type = 'lk_exception_types'
   AND l.lookup_code = te.exception_type_lk
  LEFT JOIN pcms.people p
    ON p.person_id = te.trade_exception_player_id
  WHERE te.record_status_lk = 'APPR'
    AND COALESCE(te.remaining_amount, 0) > 0;
END;
$$;

COMMIT;
