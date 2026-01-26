-- 052_salary_book_pct_cap_percentiles.sql
--
-- Add per-year percentile columns for pct_cap values to salary_book_warehouse.
-- These indicate where each player's % of cap falls relative to all other players
-- league-wide (0.0 = lowest, 1.0 = highest).
--
-- Used in the UI to show a visual indicator (filled/empty blocks) next to the
-- % of cap display.
--
-- Percentiles are computed as a second pass after the main INSERT, using
-- PERCENT_RANK() window function.

BEGIN;

-- Add percentile columns (one per year, matching pct_cap_YYYY pattern)
ALTER TABLE pcms.salary_book_warehouse
  ADD COLUMN IF NOT EXISTS pct_cap_percentile_2025 numeric,
  ADD COLUMN IF NOT EXISTS pct_cap_percentile_2026 numeric,
  ADD COLUMN IF NOT EXISTS pct_cap_percentile_2027 numeric,
  ADD COLUMN IF NOT EXISTS pct_cap_percentile_2028 numeric,
  ADD COLUMN IF NOT EXISTS pct_cap_percentile_2029 numeric,
  ADD COLUMN IF NOT EXISTS pct_cap_percentile_2030 numeric;

-- Create index for faster lookups (optional but helps with large datasets)
CREATE INDEX IF NOT EXISTS idx_salary_book_warehouse_pct_cap_2025 
  ON pcms.salary_book_warehouse (pct_cap_2025) 
  WHERE pct_cap_2025 IS NOT NULL;

-- Helper function to compute and update percentiles after the main warehouse refresh
CREATE OR REPLACE FUNCTION pcms.refresh_salary_book_percentiles()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  -- Compute percentile ranks for each year's pct_cap values
  -- Only consider rows with non-null, positive pct_cap values
  -- Players with NULL or 0 pct_cap get NULL percentile
  
  WITH percentiles AS (
    SELECT
      player_id,
      CASE WHEN pct_cap_2025 IS NOT NULL AND pct_cap_2025 > 0 
           THEN PERCENT_RANK() OVER (
             PARTITION BY (pct_cap_2025 IS NOT NULL AND pct_cap_2025 > 0)
             ORDER BY pct_cap_2025
           )
           ELSE NULL 
      END AS pctl_2025,
      CASE WHEN pct_cap_2026 IS NOT NULL AND pct_cap_2026 > 0 
           THEN PERCENT_RANK() OVER (
             PARTITION BY (pct_cap_2026 IS NOT NULL AND pct_cap_2026 > 0)
             ORDER BY pct_cap_2026
           )
           ELSE NULL 
      END AS pctl_2026,
      CASE WHEN pct_cap_2027 IS NOT NULL AND pct_cap_2027 > 0 
           THEN PERCENT_RANK() OVER (
             PARTITION BY (pct_cap_2027 IS NOT NULL AND pct_cap_2027 > 0)
             ORDER BY pct_cap_2027
           )
           ELSE NULL 
      END AS pctl_2027,
      CASE WHEN pct_cap_2028 IS NOT NULL AND pct_cap_2028 > 0 
           THEN PERCENT_RANK() OVER (
             PARTITION BY (pct_cap_2028 IS NOT NULL AND pct_cap_2028 > 0)
             ORDER BY pct_cap_2028
           )
           ELSE NULL 
      END AS pctl_2028,
      CASE WHEN pct_cap_2029 IS NOT NULL AND pct_cap_2029 > 0 
           THEN PERCENT_RANK() OVER (
             PARTITION BY (pct_cap_2029 IS NOT NULL AND pct_cap_2029 > 0)
             ORDER BY pct_cap_2029
           )
           ELSE NULL 
      END AS pctl_2029,
      CASE WHEN pct_cap_2030 IS NOT NULL AND pct_cap_2030 > 0 
           THEN PERCENT_RANK() OVER (
             PARTITION BY (pct_cap_2030 IS NOT NULL AND pct_cap_2030 > 0)
             ORDER BY pct_cap_2030
           )
           ELSE NULL 
      END AS pctl_2030
    FROM pcms.salary_book_warehouse
  )
  UPDATE pcms.salary_book_warehouse w
  SET
    pct_cap_percentile_2025 = p.pctl_2025,
    pct_cap_percentile_2026 = p.pctl_2026,
    pct_cap_percentile_2027 = p.pctl_2027,
    pct_cap_percentile_2028 = p.pctl_2028,
    pct_cap_percentile_2029 = p.pctl_2029,
    pct_cap_percentile_2030 = p.pctl_2030
  FROM percentiles p
  WHERE w.player_id = p.player_id;
END;
$$;

-- Update the main refresh function to call percentile refresh at the end
-- We need to get the current function definition and append to it
CREATE OR REPLACE FUNCTION pcms.refresh_salary_book_warehouse()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM set_config('statement_timeout', '0', true);
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

    guaranteed_amount_2025, guaranteed_amount_2026, guaranteed_amount_2027,
    guaranteed_amount_2028, guaranteed_amount_2029, guaranteed_amount_2030,

    is_fully_guaranteed_2025, is_fully_guaranteed_2026, is_fully_guaranteed_2027,
    is_fully_guaranteed_2028, is_fully_guaranteed_2029, is_fully_guaranteed_2030,

    is_partially_guaranteed_2025, is_partially_guaranteed_2026, is_partially_guaranteed_2027,
    is_partially_guaranteed_2028, is_partially_guaranteed_2029, is_partially_guaranteed_2030,

    is_non_guaranteed_2025, is_non_guaranteed_2026, is_non_guaranteed_2027,
    is_non_guaranteed_2028, is_non_guaranteed_2029, is_non_guaranteed_2030,

    likely_bonus_2025, likely_bonus_2026, likely_bonus_2027,
    likely_bonus_2028, likely_bonus_2029, likely_bonus_2030,

    unlikely_bonus_2025, unlikely_bonus_2026, unlikely_bonus_2027,
    unlikely_bonus_2028, unlikely_bonus_2029, unlikely_bonus_2030,

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

    player_consent_lk,
    player_consent_end_date,
    is_trade_consent_required_now,
    is_trade_preconsented,

    refreshed_at
  )
  WITH ac AS (
    SELECT
      c.player_id,
      c.contract_id,
      c.version_number,
      c.signing_team_id,
      c.contract_type_lk,
      COALESCE(c.contract_type_lk IN ('2WAY', '2WAYC', '2WAYN'), false) AS is_two_way,
      COALESCE(cv.is_poison_pill, false) AS is_poison_pill,
      cv.poison_pill_amount,
      COALESCE(cv.is_no_trade, false) AS is_no_trade,
      COALESCE(cv.is_trade_bonus, false) AS is_trade_bonus,
      cv.trade_bonus_percent,
      cv.player_consent_lk,
      cv.player_consent_end_date,
      ROW_NUMBER() OVER (
        PARTITION BY c.player_id
        ORDER BY
          c.contract_status_lk = 'ACTVE' DESC,
          c.contract_status_lk = 'FUTAC' DESC,
          c.version_number DESC
      ) AS rn
    FROM pcms.contracts c
    LEFT JOIN pcms.contract_versions cv
      ON cv.contract_id = c.contract_id
     AND cv.version_number = c.version_number
    WHERE c.league_lk = 'NBA'
      AND c.contract_status_lk IN ('ACTVE', 'FUTAC')
  ),
  sp AS (
    SELECT
      cs.player_id,
      MAX(CASE WHEN cs.salary_year = 2025 THEN cs.contract_cap_salary END) AS cap_2025,
      MAX(CASE WHEN cs.salary_year = 2026 THEN cs.contract_cap_salary END) AS cap_2026,
      MAX(CASE WHEN cs.salary_year = 2027 THEN cs.contract_cap_salary END) AS cap_2027,
      MAX(CASE WHEN cs.salary_year = 2028 THEN cs.contract_cap_salary END) AS cap_2028,
      MAX(CASE WHEN cs.salary_year = 2029 THEN cs.contract_cap_salary END) AS cap_2029,
      MAX(CASE WHEN cs.salary_year = 2030 THEN cs.contract_cap_salary END) AS cap_2030,

      MAX(CASE WHEN cs.salary_year = 2025 THEN cs.contract_cap_salary::numeric / NULLIF(lsv.salary_cap_amount, 0) END) AS pct_cap_2025,
      MAX(CASE WHEN cs.salary_year = 2026 THEN cs.contract_cap_salary::numeric / NULLIF(lsv.salary_cap_amount, 0) END) AS pct_cap_2026,
      MAX(CASE WHEN cs.salary_year = 2027 THEN cs.contract_cap_salary::numeric / NULLIF(lsv.salary_cap_amount, 0) END) AS pct_cap_2027,
      MAX(CASE WHEN cs.salary_year = 2028 THEN cs.contract_cap_salary::numeric / NULLIF(lsv.salary_cap_amount, 0) END) AS pct_cap_2028,
      MAX(CASE WHEN cs.salary_year = 2029 THEN cs.contract_cap_salary::numeric / NULLIF(lsv.salary_cap_amount, 0) END) AS pct_cap_2029,
      MAX(CASE WHEN cs.salary_year = 2030 THEN cs.contract_cap_salary::numeric / NULLIF(lsv.salary_cap_amount, 0) END) AS pct_cap_2030,

      SUM(CASE WHEN cs.salary_year >= 2025 THEN cs.contract_cap_salary ELSE 0 END) AS total_salary_from_2025,

      MAX(CASE WHEN cs.salary_year = 2025 THEN co.option_type_lk END) AS option_2025,
      MAX(CASE WHEN cs.salary_year = 2026 THEN co.option_type_lk END) AS option_2026,
      MAX(CASE WHEN cs.salary_year = 2027 THEN co.option_type_lk END) AS option_2027,
      MAX(CASE WHEN cs.salary_year = 2028 THEN co.option_type_lk END) AS option_2028,
      MAX(CASE WHEN cs.salary_year = 2029 THEN co.option_type_lk END) AS option_2029,
      MAX(CASE WHEN cs.salary_year = 2030 THEN co.option_type_lk END) AS option_2030,

      MAX(CASE WHEN cs.salary_year = 2025 THEN co.option_decision_lk END) AS option_decision_2025,
      MAX(CASE WHEN cs.salary_year = 2026 THEN co.option_decision_lk END) AS option_decision_2026,
      MAX(CASE WHEN cs.salary_year = 2027 THEN co.option_decision_lk END) AS option_decision_2027,
      MAX(CASE WHEN cs.salary_year = 2028 THEN co.option_decision_lk END) AS option_decision_2028,
      MAX(CASE WHEN cs.salary_year = 2029 THEN co.option_decision_lk END) AS option_decision_2029,
      MAX(CASE WHEN cs.salary_year = 2030 THEN co.option_decision_lk END) AS option_decision_2030,

      MAX(CASE WHEN cs.salary_year = 2025 THEN COALESCE(cp.effective_protection_amount, cp.protection_amount) END) AS guaranteed_amount_2025,
      MAX(CASE WHEN cs.salary_year = 2026 THEN COALESCE(cp.effective_protection_amount, cp.protection_amount) END) AS guaranteed_amount_2026,
      MAX(CASE WHEN cs.salary_year = 2027 THEN COALESCE(cp.effective_protection_amount, cp.protection_amount) END) AS guaranteed_amount_2027,
      MAX(CASE WHEN cs.salary_year = 2028 THEN COALESCE(cp.effective_protection_amount, cp.protection_amount) END) AS guaranteed_amount_2028,
      MAX(CASE WHEN cs.salary_year = 2029 THEN COALESCE(cp.effective_protection_amount, cp.protection_amount) END) AS guaranteed_amount_2029,
      MAX(CASE WHEN cs.salary_year = 2030 THEN COALESCE(cp.effective_protection_amount, cp.protection_amount) END) AS guaranteed_amount_2030,

      MAX(CASE WHEN cs.salary_year = 2025 THEN
        CASE WHEN COALESCE(cp.effective_protection_amount, cp.protection_amount) >= cs.contract_cap_salary THEN true
             WHEN cp.protection_coverage_lk = 'FULL' THEN true
             ELSE false END
      END) AS is_fully_guaranteed_2025,
      MAX(CASE WHEN cs.salary_year = 2026 THEN
        CASE WHEN COALESCE(cp.effective_protection_amount, cp.protection_amount) >= cs.contract_cap_salary THEN true
             WHEN cp.protection_coverage_lk = 'FULL' THEN true
             ELSE false END
      END) AS is_fully_guaranteed_2026,
      MAX(CASE WHEN cs.salary_year = 2027 THEN
        CASE WHEN COALESCE(cp.effective_protection_amount, cp.protection_amount) >= cs.contract_cap_salary THEN true
             WHEN cp.protection_coverage_lk = 'FULL' THEN true
             ELSE false END
      END) AS is_fully_guaranteed_2027,
      MAX(CASE WHEN cs.salary_year = 2028 THEN
        CASE WHEN COALESCE(cp.effective_protection_amount, cp.protection_amount) >= cs.contract_cap_salary THEN true
             WHEN cp.protection_coverage_lk = 'FULL' THEN true
             ELSE false END
      END) AS is_fully_guaranteed_2028,
      MAX(CASE WHEN cs.salary_year = 2029 THEN
        CASE WHEN COALESCE(cp.effective_protection_amount, cp.protection_amount) >= cs.contract_cap_salary THEN true
             WHEN cp.protection_coverage_lk = 'FULL' THEN true
             ELSE false END
      END) AS is_fully_guaranteed_2029,
      MAX(CASE WHEN cs.salary_year = 2030 THEN
        CASE WHEN COALESCE(cp.effective_protection_amount, cp.protection_amount) >= cs.contract_cap_salary THEN true
             WHEN cp.protection_coverage_lk = 'FULL' THEN true
             ELSE false END
      END) AS is_fully_guaranteed_2030,

      MAX(CASE WHEN cs.salary_year = 2025 THEN
        CASE WHEN COALESCE(cp.effective_protection_amount, cp.protection_amount, 0) > 0
              AND COALESCE(cp.effective_protection_amount, cp.protection_amount) < cs.contract_cap_salary
             THEN true ELSE false END
      END) AS is_partially_guaranteed_2025,
      MAX(CASE WHEN cs.salary_year = 2026 THEN
        CASE WHEN COALESCE(cp.effective_protection_amount, cp.protection_amount, 0) > 0
              AND COALESCE(cp.effective_protection_amount, cp.protection_amount) < cs.contract_cap_salary
             THEN true ELSE false END
      END) AS is_partially_guaranteed_2026,
      MAX(CASE WHEN cs.salary_year = 2027 THEN
        CASE WHEN COALESCE(cp.effective_protection_amount, cp.protection_amount, 0) > 0
              AND COALESCE(cp.effective_protection_amount, cp.protection_amount) < cs.contract_cap_salary
             THEN true ELSE false END
      END) AS is_partially_guaranteed_2027,
      MAX(CASE WHEN cs.salary_year = 2028 THEN
        CASE WHEN COALESCE(cp.effective_protection_amount, cp.protection_amount, 0) > 0
              AND COALESCE(cp.effective_protection_amount, cp.protection_amount) < cs.contract_cap_salary
             THEN true ELSE false END
      END) AS is_partially_guaranteed_2028,
      MAX(CASE WHEN cs.salary_year = 2029 THEN
        CASE WHEN COALESCE(cp.effective_protection_amount, cp.protection_amount, 0) > 0
              AND COALESCE(cp.effective_protection_amount, cp.protection_amount) < cs.contract_cap_salary
             THEN true ELSE false END
      END) AS is_partially_guaranteed_2029,
      MAX(CASE WHEN cs.salary_year = 2030 THEN
        CASE WHEN COALESCE(cp.effective_protection_amount, cp.protection_amount, 0) > 0
              AND COALESCE(cp.effective_protection_amount, cp.protection_amount) < cs.contract_cap_salary
             THEN true ELSE false END
      END) AS is_partially_guaranteed_2030,

      MAX(CASE WHEN cs.salary_year = 2025 THEN
        CASE WHEN COALESCE(cp.effective_protection_amount, cp.protection_amount, 0) = 0
              AND cp.protection_coverage_lk = 'NONE'
             THEN true ELSE false END
      END) AS is_non_guaranteed_2025,
      MAX(CASE WHEN cs.salary_year = 2026 THEN
        CASE WHEN COALESCE(cp.effective_protection_amount, cp.protection_amount, 0) = 0
              AND cp.protection_coverage_lk = 'NONE'
             THEN true ELSE false END
      END) AS is_non_guaranteed_2026,
      MAX(CASE WHEN cs.salary_year = 2027 THEN
        CASE WHEN COALESCE(cp.effective_protection_amount, cp.protection_amount, 0) = 0
              AND cp.protection_coverage_lk = 'NONE'
             THEN true ELSE false END
      END) AS is_non_guaranteed_2027,
      MAX(CASE WHEN cs.salary_year = 2028 THEN
        CASE WHEN COALESCE(cp.effective_protection_amount, cp.protection_amount, 0) = 0
              AND cp.protection_coverage_lk = 'NONE'
             THEN true ELSE false END
      END) AS is_non_guaranteed_2028,
      MAX(CASE WHEN cs.salary_year = 2029 THEN
        CASE WHEN COALESCE(cp.effective_protection_amount, cp.protection_amount, 0) = 0
              AND cp.protection_coverage_lk = 'NONE'
             THEN true ELSE false END
      END) AS is_non_guaranteed_2029,
      MAX(CASE WHEN cs.salary_year = 2030 THEN
        CASE WHEN COALESCE(cp.effective_protection_amount, cp.protection_amount, 0) = 0
              AND cp.protection_coverage_lk = 'NONE'
             THEN true ELSE false END
      END) AS is_non_guaranteed_2030,

      MAX(CASE WHEN cs.salary_year = 2025 THEN cb_likely.bonus_amount END) AS likely_bonus_2025,
      MAX(CASE WHEN cs.salary_year = 2026 THEN cb_likely.bonus_amount END) AS likely_bonus_2026,
      MAX(CASE WHEN cs.salary_year = 2027 THEN cb_likely.bonus_amount END) AS likely_bonus_2027,
      MAX(CASE WHEN cs.salary_year = 2028 THEN cb_likely.bonus_amount END) AS likely_bonus_2028,
      MAX(CASE WHEN cs.salary_year = 2029 THEN cb_likely.bonus_amount END) AS likely_bonus_2029,
      MAX(CASE WHEN cs.salary_year = 2030 THEN cb_likely.bonus_amount END) AS likely_bonus_2030,

      MAX(CASE WHEN cs.salary_year = 2025 THEN cb_unlikely.bonus_amount END) AS unlikely_bonus_2025,
      MAX(CASE WHEN cs.salary_year = 2026 THEN cb_unlikely.bonus_amount END) AS unlikely_bonus_2026,
      MAX(CASE WHEN cs.salary_year = 2027 THEN cb_unlikely.bonus_amount END) AS unlikely_bonus_2027,
      MAX(CASE WHEN cs.salary_year = 2028 THEN cb_unlikely.bonus_amount END) AS unlikely_bonus_2028,
      MAX(CASE WHEN cs.salary_year = 2029 THEN cb_unlikely.bonus_amount END) AS unlikely_bonus_2029,
      MAX(CASE WHEN cs.salary_year = 2030 THEN cb_unlikely.bonus_amount END) AS unlikely_bonus_2030,

      MAX(CASE WHEN cs.salary_year = 2025 THEN cs.contract_tax_salary END) AS tax_2025,
      MAX(CASE WHEN cs.salary_year = 2026 THEN cs.contract_tax_salary END) AS tax_2026,
      MAX(CASE WHEN cs.salary_year = 2027 THEN cs.contract_tax_salary END) AS tax_2027,
      MAX(CASE WHEN cs.salary_year = 2028 THEN cs.contract_tax_salary END) AS tax_2028,
      MAX(CASE WHEN cs.salary_year = 2029 THEN cs.contract_tax_salary END) AS tax_2029,
      MAX(CASE WHEN cs.salary_year = 2030 THEN cs.contract_tax_salary END) AS tax_2030,

      MAX(CASE WHEN cs.salary_year = 2025 THEN cs.contract_apron_salary END) AS apron_2025,
      MAX(CASE WHEN cs.salary_year = 2026 THEN cs.contract_apron_salary END) AS apron_2026,
      MAX(CASE WHEN cs.salary_year = 2027 THEN cs.contract_apron_salary END) AS apron_2027,
      MAX(CASE WHEN cs.salary_year = 2028 THEN cs.contract_apron_salary END) AS apron_2028,
      MAX(CASE WHEN cs.salary_year = 2029 THEN cs.contract_apron_salary END) AS apron_2029,
      MAX(CASE WHEN cs.salary_year = 2030 THEN cs.contract_apron_salary END) AS apron_2030,

      MAX(CASE WHEN cs.salary_year = 2025 THEN cs.trade_bonus_amount END) AS trade_bonus_amount_2025

    FROM pcms.contract_salaries cs
    JOIN ac ON ac.player_id = cs.player_id AND ac.rn = 1
           AND ac.contract_id = cs.contract_id
           AND ac.version_number = cs.version_number
    LEFT JOIN pcms.league_system_values lsv
      ON lsv.league_lk = 'NBA' AND lsv.salary_year = cs.salary_year
    LEFT JOIN pcms.contract_options co
      ON co.contract_id = cs.contract_id
     AND co.version_number = cs.version_number
     AND co.salary_year = cs.salary_year
    LEFT JOIN pcms.contract_protections cp
      ON cp.contract_id = cs.contract_id
     AND cp.version_number = cs.version_number
     AND cp.salary_year = cs.salary_year
    LEFT JOIN pcms.contract_bonuses cb_likely
      ON cb_likely.contract_id = cs.contract_id
     AND cb_likely.version_number = cs.version_number
     AND cb_likely.salary_year = cs.salary_year
     AND cb_likely.bonus_likelihood_lk = 'LIKELY'
    LEFT JOIN pcms.contract_bonuses cb_unlikely
      ON cb_unlikely.contract_id = cs.contract_id
     AND cb_unlikely.version_number = cs.version_number
     AND cb_unlikely.salary_year = cs.salary_year
     AND cb_unlikely.bonus_likelihood_lk = 'UNLKLY'
    WHERE cs.salary_year BETWEEN 2025 AND 2030
    GROUP BY cs.player_id
  )
  SELECT
    p.person_id AS player_id,
    COALESCE(p.display_last_name || ', ' || p.display_first_name, p.display_name) AS player_name,
    p.league_lk,

    COALESCE(
      (SELECT t.team_code FROM pcms.teams t WHERE t.team_id = ac.signing_team_id LIMIT 1),
      p.team_code
    ) AS team_code,

    (SELECT t.team_code FROM pcms.teams t WHERE t.team_id = ac.signing_team_id LIMIT 1) AS contract_team_code,
    p.team_code AS person_team_code,
    ac.signing_team_id,

    ac.contract_id,
    ac.version_number,
    p.birth_date,

    CASE WHEN p.birth_date IS NOT NULL
         THEN ROUND(EXTRACT(EPOCH FROM (current_date - p.birth_date)) / 31557600, 1)
         ELSE NULL
    END AS age,

    ag.agent_name,
    ag.agent_id,

    sp.cap_2025, sp.cap_2026, sp.cap_2027, sp.cap_2028, sp.cap_2029, sp.cap_2030,
    sp.pct_cap_2025, sp.pct_cap_2026, sp.pct_cap_2027, sp.pct_cap_2028, sp.pct_cap_2029, sp.pct_cap_2030,
    sp.total_salary_from_2025,

    NULLIF(sp.option_2025, 'NONE') AS option_2025,
    NULLIF(sp.option_2026, 'NONE') AS option_2026,
    NULLIF(sp.option_2027, 'NONE') AS option_2027,
    NULLIF(sp.option_2028, 'NONE') AS option_2028,
    NULLIF(sp.option_2029, 'NONE') AS option_2029,
    NULLIF(sp.option_2030, 'NONE') AS option_2030,

    sp.option_decision_2025,
    sp.option_decision_2026,
    sp.option_decision_2027,
    sp.option_decision_2028,
    sp.option_decision_2029,
    sp.option_decision_2030,

    sp.guaranteed_amount_2025,
    sp.guaranteed_amount_2026,
    sp.guaranteed_amount_2027,
    sp.guaranteed_amount_2028,
    sp.guaranteed_amount_2029,
    sp.guaranteed_amount_2030,

    sp.is_fully_guaranteed_2025,
    sp.is_fully_guaranteed_2026,
    sp.is_fully_guaranteed_2027,
    sp.is_fully_guaranteed_2028,
    sp.is_fully_guaranteed_2029,
    sp.is_fully_guaranteed_2030,

    sp.is_partially_guaranteed_2025,
    sp.is_partially_guaranteed_2026,
    sp.is_partially_guaranteed_2027,
    sp.is_partially_guaranteed_2028,
    sp.is_partially_guaranteed_2029,
    sp.is_partially_guaranteed_2030,

    sp.is_non_guaranteed_2025,
    sp.is_non_guaranteed_2026,
    sp.is_non_guaranteed_2027,
    sp.is_non_guaranteed_2028,
    sp.is_non_guaranteed_2029,
    sp.is_non_guaranteed_2030,

    sp.likely_bonus_2025,
    sp.likely_bonus_2026,
    sp.likely_bonus_2027,
    sp.likely_bonus_2028,
    sp.likely_bonus_2029,
    sp.likely_bonus_2030,

    sp.unlikely_bonus_2025,
    sp.unlikely_bonus_2026,
    sp.unlikely_bonus_2027,
    sp.unlikely_bonus_2028,
    sp.unlikely_bonus_2029,
    sp.unlikely_bonus_2030,

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

    ac.player_consent_lk AS player_consent_lk,
    ac.player_consent_end_date,

    COALESCE(
      (
        ac.player_consent_lk IN ('YEARK', 'ROFRE')
        AND (
          ac.player_consent_end_date IS NULL
          OR ac.player_consent_end_date >= current_date
        )
      ),
      false
    ) AS is_trade_consent_required_now,

    COALESCE((ac.player_consent_lk = 'YRKPC'), false) AS is_trade_preconsented,

    now() AS refreshed_at

  FROM pcms.people p
  JOIN ac
    ON ac.player_id = p.person_id
   AND ac.rn = 1
  LEFT JOIN sp
    ON sp.player_id = p.person_id
  LEFT JOIN pcms.agents ag
    ON ag.agent_id = p.agent_id

  WHERE p.person_type_lk = 'PLYR'
    AND p.league_lk IN ('NBA', 'DLG');

  -- Compute percentile ranks as a second pass
  PERFORM pcms.refresh_salary_book_percentiles();
END;
$$;

-- Run the percentile refresh now to populate existing data
SELECT pcms.refresh_salary_book_percentiles();

COMMIT;
