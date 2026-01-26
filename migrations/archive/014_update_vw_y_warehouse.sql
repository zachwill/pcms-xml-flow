-- 014_update_vw_y_warehouse.sql
--
-- Improve vw_y_warehouse so downstream refreshes don't need to re-join
-- active contract/version selection.
--
-- IMPORTANT: Postgres only allows CREATE OR REPLACE VIEW if the *existing*
-- columns keep the same order/names/types. So we APPEND new columns at the end.
--
-- Adds:
-- - contract_id
-- - version_number
-- - agent_id

BEGIN;

CREATE OR REPLACE VIEW pcms.vw_y_warehouse AS
SELECT
  p.person_id AS player_id,
  p.last_name || ', ' || p.first_name AS player_name,
  p.league_lk,

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
  sp.total_salary_from_2025,

  -- options
  sp.option_2025, sp.option_2026, sp.option_2027, sp.option_2028, sp.option_2029, sp.option_2030,
  sp.option_decision_2025, sp.option_decision_2026, sp.option_decision_2027,
  sp.option_decision_2028, sp.option_decision_2029, sp.option_decision_2030,

  -- trade flags
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

  -- trade-math (approx)
  sp.cap_2025 AS outgoing_buildup_2025,
  (sp.cap_2025 + COALESCE(sp.trade_bonus_amount_2025, 0)) AS incoming_buildup_2025,
  (sp.cap_2025 + COALESCE(sp.trade_bonus_amount_2025, 0)) AS incoming_salary_2025,
  sp.tax_2025 AS incoming_tax_2025,
  sp.apron_2025 AS incoming_apron_2025,

  -- appended columns (new)
  ac.contract_id,
  ac.version_number,
  p.agent_id

FROM pcms.people p
JOIN pcms.vw_active_contract_versions ac
  ON ac.player_id = p.person_id
LEFT JOIN pcms.vw_salary_pivot_2024_2030 sp
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
  AND p.league_lk IN ('NBA', 'DLG');

COMMIT;
