-- queries/sql/y_warehouse.sql
--
-- Runnable “Y Warehouse” query (forward-looking, 2025–2030)
--
-- Notes:
-- - One row per player, based on the “active contract + latest version” selector.
-- - Team assignment prefers active contract team_code; falls back to people.team_code.
-- - Trade-math columns are best-effort approximations.
-- - If you want to include *all* NBA players (not just active contracts), remove `WHERE ac.player_id IS NOT NULL`.

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
    ac.contract_id,
    ac.player_id,
    ac.signing_team_id,
    ac.team_code,
    lv.version_number,
    lv.contract_type_lk,
    lv.record_status_lk AS version_status_lk,
    lv.is_two_way,
    lv.is_poison_pill,
    lv.poison_pill_amount,
    lv.is_trade_bonus,
    lv.trade_bonus_percent,
    lv.trade_bonus_amount,
    lv.is_no_trade
  FROM active_contracts ac
  JOIN latest_versions lv
    ON lv.contract_id = ac.contract_id
   AND lv.rn = 1
  WHERE ac.rn = 1
),
sp AS (
  SELECT
    s.contract_id,
    s.version_number,

    -- cap (Sean’s primary “salary”)
    MAX(CASE WHEN s.salary_year = 2025 THEN s.contract_cap_salary END) AS cap_2025,
    MAX(CASE WHEN s.salary_year = 2026 THEN s.contract_cap_salary END) AS cap_2026,
    MAX(CASE WHEN s.salary_year = 2027 THEN s.contract_cap_salary END) AS cap_2027,
    MAX(CASE WHEN s.salary_year = 2028 THEN s.contract_cap_salary END) AS cap_2028,
    MAX(CASE WHEN s.salary_year = 2029 THEN s.contract_cap_salary END) AS cap_2029,
    MAX(CASE WHEN s.salary_year = 2030 THEN s.contract_cap_salary END) AS cap_2030,

    -- tax / apron
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

    -- options
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

    -- trade bonus amount (best-effort)
    MAX(CASE WHEN s.salary_year = 2025 THEN s.trade_bonus_amount_calc END) AS trade_bonus_amount_2025,

    -- totals
    SUM(CASE WHEN s.salary_year >= 2025 THEN s.total_salary ELSE 0 END) AS total_salary_from_2025
  FROM pcms.salaries s
  GROUP BY 1, 2
)
SELECT
  p.person_id AS player_id,
  p.last_name || ', ' || p.first_name AS player_name,
  p.league_lk AS league_lk,

  -- roster/team identity
  COALESCE(ac.team_code, p.team_code) AS team_code,
  ac.team_code AS contract_team_code,
  p.team_code AS person_team_code,
  ac.signing_team_id,

  -- bio / agent
  p.birth_date,
  DATE_PART('year', AGE(p.birth_date))::int AS age,
  ag.full_name AS agent_name,

  -- salary grid (cap)
  sp.cap_2025, sp.cap_2026, sp.cap_2027, sp.cap_2028, sp.cap_2029, sp.cap_2030,

  -- % of cap
  (sp.cap_2025::numeric / NULLIF(lsv_2025.salary_cap_amount, 0)) AS pct_cap_2025,
  (sp.cap_2026::numeric / NULLIF(lsv_2026.salary_cap_amount, 0)) AS pct_cap_2026,
  (sp.cap_2027::numeric / NULLIF(lsv_2027.salary_cap_amount, 0)) AS pct_cap_2027,
  (sp.cap_2028::numeric / NULLIF(lsv_2028.salary_cap_amount, 0)) AS pct_cap_2028,
  (sp.cap_2029::numeric / NULLIF(lsv_2029.salary_cap_amount, 0)) AS pct_cap_2029,
  (sp.cap_2030::numeric / NULLIF(lsv_2030.salary_cap_amount, 0)) AS pct_cap_2030,

  -- totals
  sp.total_salary_from_2025 AS total_salary_from_2025,

  -- options
  sp.option_2025, sp.option_2026, sp.option_2027, sp.option_2028, sp.option_2029, sp.option_2030,
  sp.option_decision_2025, sp.option_decision_2026, sp.option_decision_2027,
  sp.option_decision_2028, sp.option_decision_2029, sp.option_decision_2030,

  -- trade flags (best-effort)
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

  -- tax/apron grid
  sp.tax_2025, sp.tax_2026, sp.tax_2027, sp.tax_2028, sp.tax_2029, sp.tax_2030,
  sp.apron_2025, sp.apron_2026, sp.apron_2027, sp.apron_2028, sp.apron_2029, sp.apron_2030,

  -- trade-math (approx; see queries/AGENTS.md)
  sp.cap_2025 AS outgoing_buildup_2025,
  (sp.cap_2025 + COALESCE(sp.trade_bonus_amount_2025, 0)) AS incoming_buildup_2025,
  (sp.cap_2025 + COALESCE(sp.trade_bonus_amount_2025, 0)) AS incoming_salary_2025,
  sp.tax_2025 AS incoming_tax_2025,
  sp.apron_2025 AS incoming_apron_2025

FROM pcms.people p
LEFT JOIN ac
  ON ac.player_id = p.person_id
LEFT JOIN sp
  ON sp.contract_id = ac.contract_id
 AND sp.version_number = ac.version_number
LEFT JOIN pcms.agents ag
  ON ag.agent_id = p.agent_id

-- cap constants per year for % calcs
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
  AND p.league_lk IN ('NBA', 'DLG')
  AND ac.player_id IS NOT NULL
ORDER BY team_code NULLS LAST, sp.cap_2025 DESC NULLS LAST, player_name;
