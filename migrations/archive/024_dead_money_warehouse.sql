-- 024_dead_money_warehouse.sql
--
-- Denormalized cache for dead money / waived amounts used in Team Master.
--
-- Source of truth: pcms.transaction_waiver_amounts
-- Note: transaction_waiver_amounts currently has NULL team_code in our ingests,
-- so we resolve it via pcms.teams using team_id.

BEGIN;

CREATE TABLE IF NOT EXISTS pcms.dead_money_warehouse (
  transaction_waiver_amount_id integer PRIMARY KEY,

  team_id integer,
  team_code text,
  salary_year integer,

  transaction_id integer,
  player_id integer,
  player_name text,
  contract_id integer,
  version_number integer,

  waive_date date,

  cap_value bigint,
  cap_change_value bigint,
  is_cap_calculated boolean,

  tax_value bigint,
  tax_change_value bigint,
  is_tax_calculated boolean,

  apron_value bigint,
  apron_change_value bigint,
  is_apron_calculated boolean,

  mts_value bigint,
  mts_change_value bigint,

  two_way_salary bigint,
  two_way_nba_salary bigint,
  two_way_dlg_salary bigint,

  option_decision_lk text,

  refreshed_at timestamp with time zone NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_dead_money_warehouse_team_year
  ON pcms.dead_money_warehouse (team_code, salary_year);

CREATE INDEX IF NOT EXISTS idx_dead_money_warehouse_player
  ON pcms.dead_money_warehouse (player_id);


CREATE OR REPLACE FUNCTION pcms.refresh_dead_money_warehouse()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM set_config('statement_timeout', '0', true);
  PERFORM set_config('lock_timeout', '5s', true);

  TRUNCATE TABLE pcms.dead_money_warehouse;

  INSERT INTO pcms.dead_money_warehouse (
    transaction_waiver_amount_id,

    team_id,
    team_code,
    salary_year,

    transaction_id,
    player_id,
    player_name,
    contract_id,
    version_number,

    waive_date,

    cap_value,
    cap_change_value,
    is_cap_calculated,

    tax_value,
    tax_change_value,
    is_tax_calculated,

    apron_value,
    apron_change_value,
    is_apron_calculated,

    mts_value,
    mts_change_value,

    two_way_salary,
    two_way_nba_salary,
    two_way_dlg_salary,

    option_decision_lk,

    refreshed_at
  )
  SELECT
    twa.transaction_waiver_amount_id,

    twa.team_id,
    COALESCE(twa.team_code, tm.team_code) AS team_code,
    twa.salary_year,

    twa.transaction_id,
    twa.player_id,
    (p.last_name || ', ' || p.first_name) AS player_name,
    twa.contract_id,
    twa.version_number,

    (twa.waive_date::date) AS waive_date,

    twa.cap_value,
    twa.cap_change_value,
    twa.is_cap_calculated,

    twa.tax_value,
    twa.tax_change_value,
    twa.is_tax_calculated,

    twa.apron_value,
    twa.apron_change_value,
    twa.is_apron_calculated,

    twa.mts_value,
    twa.mts_change_value,

    twa.two_way_salary,
    twa.two_way_nba_salary,
    twa.two_way_dlg_salary,

    twa.option_decision_lk,

    now() AS refreshed_at

  FROM pcms.transaction_waiver_amounts twa
  JOIN pcms.teams tm
    ON tm.team_id = twa.team_id
   AND tm.league_lk = 'NBA'
  LEFT JOIN pcms.people p
    ON p.person_id = twa.player_id
  WHERE twa.salary_year >= 2025
    AND COALESCE(twa.team_code, tm.team_code) IS NOT NULL;
END;
$$;

COMMIT;
