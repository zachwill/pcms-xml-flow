-- 079_dead_money_warehouse_current_term_only.sql
--
-- Rebuild dead_money_warehouse as a tool-facing "what currently counts" cache.
--
-- Why:
-- - transaction_waiver_amounts can contain superseded waiver transaction streams
--   for the same player/contract/team.
-- - For Salary Book + Team views we only want the latest stream that is
--   actually counting in TEAM_BUDGET_SNAPSHOTS TERM rows.

BEGIN;

CREATE OR REPLACE FUNCTION pcms.refresh_dead_money_warehouse()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM set_config('statement_timeout', '0', true);
  PERFORM set_config('lock_timeout', '5s', true);

  TRUNCATE TABLE pcms.dead_money_warehouse;

  WITH twa_enriched AS (
    SELECT
      twa.transaction_waiver_amount_id,

      twa.team_id,
      COALESCE(twa.team_code, tm.team_code) AS team_code,
      twa.salary_year,

      twa.transaction_id,
      twa.player_id,
      COALESCE(
        NULLIF(BTRIM(CONCAT_WS(', ', p.last_name, p.first_name)), ''),
        twa.player_id::text
      ) AS player_name,
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

      twa.option_decision_lk
    FROM pcms.transaction_waiver_amounts twa
    JOIN pcms.teams tm
      ON tm.team_id = twa.team_id
     AND tm.league_lk = 'NBA'
    LEFT JOIN pcms.people p
      ON p.person_id = twa.player_id
    WHERE twa.salary_year >= 2025
      AND COALESCE(twa.team_code, tm.team_code) IS NOT NULL
  ),
  ranked AS (
    SELECT
      e.*,
      DENSE_RANK() OVER (
        PARTITION BY e.team_code, e.player_id, e.contract_id
        ORDER BY
          e.waive_date DESC NULLS LAST,
          e.transaction_id DESC,
          e.version_number DESC NULLS LAST
      ) AS contract_tx_rank
    FROM twa_enriched e
  ),
  current_rows AS (
    SELECT *
    FROM ranked r
    WHERE r.contract_tx_rank = 1
  ),
  counting_rows AS (
    SELECT r.*
    FROM current_rows r
    WHERE EXISTS (
      SELECT 1
      FROM pcms.team_budget_snapshots tbs
      WHERE tbs.team_code = r.team_code
        AND tbs.salary_year = r.salary_year
        AND tbs.player_id = r.player_id
        AND tbs.contract_id = r.contract_id
        AND tbs.budget_group_lk = 'TERM'
        AND COALESCE(tbs.cap_amount, 0) = COALESCE(r.cap_value, 0)
    )
  )
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
    c.transaction_waiver_amount_id,

    c.team_id,
    c.team_code,
    c.salary_year,

    c.transaction_id,
    c.player_id,
    c.player_name,
    c.contract_id,
    c.version_number,

    c.waive_date,

    c.cap_value,
    c.cap_change_value,
    c.is_cap_calculated,

    c.tax_value,
    c.tax_change_value,
    c.is_tax_calculated,

    c.apron_value,
    c.apron_change_value,
    c.is_apron_calculated,

    c.mts_value,
    c.mts_change_value,

    c.two_way_salary,
    c.two_way_nba_salary,
    c.two_way_dlg_salary,

    c.option_decision_lk,

    now() AS refreshed_at
  FROM counting_rows c;
END;
$$;

-- Backfill with new semantics immediately.
SELECT pcms.refresh_dead_money_warehouse();

COMMIT;
