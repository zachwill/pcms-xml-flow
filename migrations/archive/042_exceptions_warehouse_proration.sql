-- 042_exceptions_warehouse_proration_use_league_system_values.sql
--
-- Replace hard-coded proration calendar values used by
-- pcms.refresh_exceptions_warehouse() with NBA calendar values from
-- pcms.league_system_values.
--
-- We intentionally do NOT create a separate league_calendar table yet, because
-- pcms.league_system_values already contains the relevant fields:
-- - days_in_season (NBA=174)
-- - trade_deadline_at
-- - exception_prorate_at (Jan 10)
--

BEGIN;

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

    is_expired,
    proration_applies,
    jan10_salary_year,
    jan10_date,
    trade_deadline_date,
    proration_days,
    proration_factor,
    prorated_remaining_amount,

    refreshed_at
  )
  WITH nba_cal AS (
    SELECT
      lsv.salary_year,
      lsv.days_in_season,
      (lsv.exception_prorate_at AT TIME ZONE 'UTC')::date AS exception_prorate_date,
      (lsv.trade_deadline_at AT TIME ZONE 'UTC')::date AS trade_deadline_date
    FROM pcms.league_system_values lsv
    WHERE lsv.league_lk = 'NBA'
  )
  SELECT
    te.team_exception_id,

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

    (te.expiration_date IS NOT NULL AND te.expiration_date < CURRENT_DATE) AS is_expired,

    (
      te.exception_type_lk IN ('NTMDL','TMDLE','BIEXC','RMEXC','CNTMD')
      AND COALESCE(te.remaining_amount, 0) > 0
    ) AS proration_applies,

    te.salary_year AS jan10_salary_year,
    cal.exception_prorate_date AS jan10_date,
    cal.trade_deadline_date AS trade_deadline_date,

    CASE
      WHEN te.exception_type_lk IN ('NTMDL','TMDLE','BIEXC','RMEXC','CNTMD')
       AND cal.trade_deadline_date IS NOT NULL
       AND CURRENT_DATE > cal.trade_deadline_date
      THEN GREATEST((CURRENT_DATE - cal.trade_deadline_date)::int, 0)
      ELSE 0
    END AS proration_days,

    CASE
      WHEN te.exception_type_lk IN ('NTMDL','TMDLE','BIEXC','RMEXC','CNTMD')
       AND cal.trade_deadline_date IS NOT NULL
       AND cal.days_in_season IS NOT NULL
       AND cal.days_in_season > 0
       AND CURRENT_DATE > cal.trade_deadline_date
      THEN GREATEST(
        0::numeric,
        1::numeric - (GREATEST((CURRENT_DATE - cal.trade_deadline_date)::int, 0)::numeric / cal.days_in_season::numeric)
      )
      ELSE 1::numeric
    END AS proration_factor,

    CASE
      WHEN te.exception_type_lk IN ('NTMDL','TMDLE','BIEXC','RMEXC','CNTMD')
       AND cal.trade_deadline_date IS NOT NULL
       AND cal.days_in_season IS NOT NULL
       AND cal.days_in_season > 0
       AND CURRENT_DATE > cal.trade_deadline_date
      THEN FLOOR(
        COALESCE(te.remaining_amount,0)::numeric
        * GREATEST(
            0::numeric,
            1::numeric - (GREATEST((CURRENT_DATE - cal.trade_deadline_date)::int, 0)::numeric / cal.days_in_season::numeric)
          )
      )::bigint
      ELSE te.remaining_amount
    END AS prorated_remaining_amount,

    now() AS refreshed_at
  FROM pcms.team_exceptions te
  LEFT JOIN pcms.teams t
    ON t.team_id = te.team_id
  LEFT JOIN pcms.lookups l
    ON l.lookup_type = 'lk_exception_types'
   AND l.lookup_code = te.exception_type_lk
  LEFT JOIN pcms.people p
    ON p.person_id = te.trade_exception_player_id
  LEFT JOIN nba_cal cal
    ON cal.salary_year = te.salary_year
  WHERE te.record_status_lk = 'APPR'
    AND COALESCE(te.remaining_amount, 0) > 0
    AND (te.expiration_date IS NULL OR te.expiration_date >= CURRENT_DATE);
END;
$$;

COMMIT;
