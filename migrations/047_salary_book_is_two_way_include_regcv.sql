-- 047_salary_book_is_two_way_include_regcv.sql
--
-- DEPRECATED / SUPERSEDED:
-- This migration extended the two-way detection to include REGCV, but it still
-- used the simplified refresh function and regressed the multi-contract per-year
-- salary selection logic (see 034).
--
-- Kept for historical ordering only.
-- Use migration 048 instead:
--   048_salary_book_is_two_way_keep_multi_contract_year_selection.sql
--
-- Original intent:
-- - contract_type_lk='REGCV' is "Two-Way Contract (Converted NBA)" per pcms.lookups

BEGIN;

CREATE OR REPLACE FUNCTION pcms.refresh_salary_book_warehouse()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  -- We’d rather finish than fail due to client defaults.
  PERFORM set_config('statement_timeout', '0', true);
  -- Avoid hanging forever if another session holds locks.
  PERFORM set_config('lock_timeout', '5s', true);

  TRUNCATE TABLE pcms.salary_book_warehouse;

  INSERT INTO pcms.salary_book_warehouse (
    player_id,
    player_name,
    league_lk,
    team_code,
    contract_team_code,
    person_team_code,
    signing_team_id,
    contract_id,
    version_number,
    birth_date,
    age,
    agent_name,
    agent_id,
    cap_2025, cap_2026, cap_2027, cap_2028, cap_2029, cap_2030,
    pct_cap_2025, pct_cap_2026, pct_cap_2027, pct_cap_2028, pct_cap_2029, pct_cap_2030,
    total_salary_from_2025,
    option_2025, option_2026, option_2027, option_2028, option_2029, option_2030,
    option_decision_2025, option_decision_2026, option_decision_2027,
    option_decision_2028, option_decision_2029, option_decision_2030,
    is_two_way,
    is_poison_pill,
    poison_pill_amount,
    is_no_trade,
    is_trade_bonus,
    trade_bonus_percent,
    trade_kicker_amount_2025,
    trade_kicker_display,
    tax_2025, tax_2026, tax_2027, tax_2028, tax_2029, tax_2030,
    apron_2025, apron_2026, apron_2027, apron_2028, apron_2029, apron_2030,
    outgoing_buildup_2025,
    incoming_buildup_2025,
    incoming_salary_2025,
    incoming_tax_2025,
    incoming_apron_2025,
    refreshed_at
  )
  WITH active_contracts AS (
    SELECT
      c.*, 
      ROW_NUMBER() OVER (
        PARTITION BY c.player_id
        ORDER BY
          (c.record_status_lk = 'APPR') DESC,
          (c.record_status_lk = 'FUTR') DESC,
          c.signing_date DESC NULLS LAST,
          c.contract_id DESC
      ) AS rn
    FROM pcms.contracts c
    WHERE c.record_status_lk IN ('APPR', 'FUTR')
  ),
  latest_versions AS (
    SELECT
      cv.*, 
      ROW_NUMBER() OVER (
        PARTITION BY cv.contract_id
        ORDER BY cv.version_number DESC
      ) AS rn
    FROM pcms.contract_versions cv
  ),
  ac AS (
    SELECT
      a.contract_id,
      a.player_id,
      a.signing_team_id,
      a.team_code,
      lv.version_number,

      -- IMPORTANT:
      -- pcms.contract_versions.is_two_way is not populated by the ingest.
      -- Derive from contract type instead.
      -- Include REGCV, which is "Two-Way Contract (Converted NBA)".
      (lv.contract_type_lk IN ('2WCT', 'REGCV')) AS is_two_way,

      lv.is_poison_pill,
      lv.poison_pill_amount,
      lv.is_trade_bonus,
      lv.trade_bonus_percent,
      lv.trade_bonus_amount,
      lv.is_no_trade
    FROM active_contracts a
    JOIN latest_versions lv
      ON lv.contract_id = a.contract_id
     AND lv.rn = 1
    WHERE a.rn = 1
  ),
  sp AS (
    SELECT
      s.contract_id,
      s.version_number,

      MAX(CASE WHEN s.salary_year = 2025 THEN s.contract_cap_salary END) AS cap_2025,
      MAX(CASE WHEN s.salary_year = 2026 THEN s.contract_cap_salary END) AS cap_2026,
      MAX(CASE WHEN s.salary_year = 2027 THEN s.contract_cap_salary END) AS cap_2027,
      MAX(CASE WHEN s.salary_year = 2028 THEN s.contract_cap_salary END) AS cap_2028,
      MAX(CASE WHEN s.salary_year = 2029 THEN s.contract_cap_salary END) AS cap_2029,
      MAX(CASE WHEN s.salary_year = 2030 THEN s.contract_cap_salary END) AS cap_2030,

      MAX(CASE WHEN s.salary_year = 2025 THEN s.contract_tax_salary END) AS tax_2025,
      MAX(CASE WHEN s.salary_year = 2026 THEN s.contract_tax_salary END) AS tax_2026,
      MAX(CASE WHEN s.salary_year = 2027 THEN s.contract_tax_salary END) AS tax_2027,
      MAX(CASE WHEN s.salary_year = 2028 THEN s.contract_tax_salary END) AS tax_2028,
      MAX(CASE WHEN s.salary_year = 2029 THEN s.contract_tax_salary END) AS tax_2029,
      MAX(CASE WHEN s.salary_year = 2030 THEN s.contract_tax_salary END) AS tax_2030,

      MAX(CASE WHEN s.salary_year = 2025 THEN s.contract_tax_apron_salary END) AS apron_2025,
      MAX(CASE WHEN s.salary_year = 2026 THEN s.contract_tax_apron_salary END) AS apron_2026,
      MAX(CASE WHEN s.salary_year = 2027 THEN s.contract_tax_apron_salary END) AS apron_2027,
      MAX(CASE WHEN s.salary_year = 2028 THEN s.contract_tax_apron_salary END) AS apron_2028,
      MAX(CASE WHEN s.salary_year = 2029 THEN s.contract_tax_apron_salary END) AS apron_2029,
      MAX(CASE WHEN s.salary_year = 2030 THEN s.contract_tax_apron_salary END) AS apron_2030,

      MAX(CASE WHEN s.salary_year = 2025 THEN s.option_lk END) AS option_2025,
      MAX(CASE WHEN s.salary_year = 2026 THEN s.option_lk END) AS option_2026,
      MAX(CASE WHEN s.salary_year = 2027 THEN s.option_lk END) AS option_2027,
      MAX(CASE WHEN s.salary_year = 2028 THEN s.option_lk END) AS option_2028,
      MAX(CASE WHEN s.salary_year = 2029 THEN s.option_lk END) AS option_2029,
      MAX(CASE WHEN s.salary_year = 2030 THEN s.option_lk END) AS option_2030,

      MAX(CASE WHEN s.salary_year = 2025 THEN s.option_decision_lk END) AS option_decision_2025,
      MAX(CASE WHEN s.salary_year = 2026 THEN s.option_decision_lk END) AS option_decision_2026,
      MAX(CASE WHEN s.salary_year = 2027 THEN s.option_decision_lk END) AS option_decision_2027,
      MAX(CASE WHEN s.salary_year = 2028 THEN s.option_decision_lk END) AS option_decision_2028,
      MAX(CASE WHEN s.salary_year = 2029 THEN s.option_decision_lk END) AS option_decision_2029,
      MAX(CASE WHEN s.salary_year = 2030 THEN s.option_decision_lk END) AS option_decision_2030,

      MAX(CASE WHEN s.salary_year = 2025 THEN s.trade_bonus_amount_calc END) AS trade_bonus_amount_2025,

      -- sum(bigint) returns numeric in Postgres
      SUM(CASE WHEN s.salary_year >= 2025 THEN s.total_salary ELSE 0 END) AS total_salary_from_2025

    FROM pcms.salaries s
    GROUP BY 1,2
  )
  SELECT
    p.person_id AS player_id,
    p.last_name || ', ' || p.first_name AS player_name,
    p.league_lk,

    COALESCE(ac.team_code, p.team_code) AS team_code,
    ac.team_code AS contract_team_code,
    p.team_code AS person_team_code,
    ac.signing_team_id,

    ac.contract_id,
    ac.version_number,

    p.birth_date,
    DATE_PART('year', AGE(p.birth_date))::int AS age,
    ag.full_name AS agent_name,
    p.agent_id,

    sp.cap_2025, sp.cap_2026, sp.cap_2027, sp.cap_2028, sp.cap_2029, sp.cap_2030,

    (sp.cap_2025::numeric / NULLIF(lsv_2025.salary_cap_amount, 0)) AS pct_cap_2025,
    (sp.cap_2026::numeric / NULLIF(lsv_2026.salary_cap_amount, 0)) AS pct_cap_2026,
    (sp.cap_2027::numeric / NULLIF(lsv_2027.salary_cap_amount, 0)) AS pct_cap_2027,
    (sp.cap_2028::numeric / NULLIF(lsv_2028.salary_cap_amount, 0)) AS pct_cap_2028,
    (sp.cap_2029::numeric / NULLIF(lsv_2029.salary_cap_amount, 0)) AS pct_cap_2029,
    (sp.cap_2030::numeric / NULLIF(lsv_2030.salary_cap_amount, 0)) AS pct_cap_2030,

    sp.total_salary_from_2025::bigint AS total_salary_from_2025,

    sp.option_2025, sp.option_2026, sp.option_2027, sp.option_2028, sp.option_2029, sp.option_2030,
    sp.option_decision_2025, sp.option_decision_2026, sp.option_decision_2027,
    sp.option_decision_2028, sp.option_decision_2029, sp.option_decision_2030,

    ac.is_two_way,
    ac.is_poison_pill,
    ac.poison_pill_amount,
    ac.is_no_trade,
    ac.is_trade_bonus,
    ac.trade_bonus_percent,

    sp.trade_bonus_amount_2025 AS trade_kicker_amount_2025,
    CASE
      WHEN ac.is_trade_bonus AND ac.trade_bonus_percent IS NOT NULL THEN (ac.trade_bonus_percent::text || '%')
      WHEN ac.is_trade_bonus THEN 'TK'
      ELSE NULL
    END AS trade_kicker_display,

    sp.tax_2025, sp.tax_2026, sp.tax_2027, sp.tax_2028, sp.tax_2029, sp.tax_2030,
    sp.apron_2025, sp.apron_2026, sp.apron_2027, sp.apron_2028, sp.apron_2029, sp.apron_2030,

    sp.cap_2025 AS outgoing_buildup_2025,
    (sp.cap_2025 + COALESCE(sp.trade_bonus_amount_2025, 0)) AS incoming_buildup_2025,
    (sp.cap_2025 + COALESCE(sp.trade_bonus_amount_2025, 0)) AS incoming_salary_2025,
    sp.tax_2025 AS incoming_tax_2025,
    sp.apron_2025 AS incoming_apron_2025,

    now() AS refreshed_at

  FROM pcms.people p
  JOIN ac
    ON ac.player_id = p.person_id
  LEFT JOIN sp
    ON sp.contract_id = ac.contract_id
   AND sp.version_number = ac.version_number
  LEFT JOIN pcms.agents ag
    ON ag.agent_id = p.agent_id

  LEFT JOIN pcms.league_system_values lsv_2025
    ON lsv_2025.league_lk = 'NBA' AND lsv_2025.salary_year = 2025
  LEFT JOIN pcms.league_system_values lsv_2026
    ON lsv_2026.league_lk = 'NBA' AND lsv_2026.salary_year = 2026
  LEFT JOIN pcms.league_system_values lsv_2027
    ON lsv_2027.league_lk = 'NBA' AND lsv_2027.salary_year = 2027
  LEFT JOIN pcms.league_system_values lsv_2028
    ON lsv_2028.league_lk = 'NBA' AND lsv_2028.salary_year = 2028
  LEFT JOIN pcms.league_system_values lsv_2029
    ON lsv_2029.league_lk = 'NBA' AND lsv_2029.salary_year = 2029
  LEFT JOIN pcms.league_system_values lsv_2030
    ON lsv_2030.league_lk = 'NBA' AND lsv_2030.salary_year = 2030

  WHERE p.person_type_lk = 'PLYR'
    AND p.league_lk IN ('NBA', 'DLG');
END;
$$;

COMMIT;
