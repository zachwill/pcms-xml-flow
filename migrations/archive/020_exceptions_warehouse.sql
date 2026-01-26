-- 020_exceptions_warehouse.sql
--
-- Denormalized cache for team exceptions used in Give/Get + Trade Machine.
--
-- Source of truth: pcms.team_exceptions
-- Enrich:
-- - pcms.lookups (exception type description)
-- - pcms.people (trade exception player name)

BEGIN;

CREATE TABLE IF NOT EXISTS pcms.exceptions_warehouse (
  team_exception_id integer PRIMARY KEY,

  team_code text,
  team_id integer,
  salary_year integer,

  exception_type_lk text,
  exception_type_name text,

  effective_date date,
  expiration_date date,

  original_amount bigint,
  remaining_amount bigint,

  trade_exception_player_id integer,
  trade_exception_player_name text,

  record_status_lk text,

  refreshed_at timestamp with time zone NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_exceptions_warehouse_team_year
  ON pcms.exceptions_warehouse (team_code, salary_year);

CREATE INDEX IF NOT EXISTS idx_exceptions_warehouse_team_remaining_desc
  ON pcms.exceptions_warehouse (team_code, remaining_amount DESC NULLS LAST);


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
    te.team_code,
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
  LEFT JOIN pcms.lookups l
    ON l.lookup_type = 'EXCEPTION_TYPE'
   AND l.lookup_code = te.exception_type_lk
  LEFT JOIN pcms.people p
    ON p.person_id = te.trade_exception_player_id
  WHERE te.record_status_lk = 'APPR'
    AND COALESCE(te.remaining_amount, 0) > 0;
END;
$$;

COMMIT;
