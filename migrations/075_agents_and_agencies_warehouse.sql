-- 075_agents_and_agencies_warehouse.sql
--
-- Add tool-facing rollup caches for representation analytics:
-- - pcms.agents_warehouse   (one row per agent)
-- - pcms.agencies_warehouse (one row per agency)
--
-- Why:
-- - Agent/agency pages and Salary Book sidebar currently compute many rollups ad hoc.
-- - We want stable, refreshable aggregates with percentile columns.
-- - This centralizes definitions for "book", max-level counts, options, expirings, etc.

BEGIN;

CREATE TABLE IF NOT EXISTS pcms.agents_warehouse (
  agent_id integer PRIMARY KEY,

  full_name text,
  agency_id integer,
  agency_name text,
  is_active boolean,
  is_certified boolean,

  client_count integer NOT NULL DEFAULT 0,
  standard_count integer NOT NULL DEFAULT 0,
  two_way_count integer NOT NULL DEFAULT 0,
  team_count integer NOT NULL DEFAULT 0,

  cap_2025_total bigint NOT NULL DEFAULT 0,
  cap_2026_total bigint NOT NULL DEFAULT 0,
  cap_2027_total bigint NOT NULL DEFAULT 0,
  total_salary_from_2025 bigint NOT NULL DEFAULT 0,

  max_contract_count integer NOT NULL DEFAULT 0,
  rookie_scale_count integer NOT NULL DEFAULT 0,
  min_contract_count integer NOT NULL DEFAULT 0,

  no_trade_count integer NOT NULL DEFAULT 0,
  trade_kicker_count integer NOT NULL DEFAULT 0,
  trade_restricted_count integer NOT NULL DEFAULT 0,

  expiring_2025 integer NOT NULL DEFAULT 0,
  expiring_2026 integer NOT NULL DEFAULT 0,
  expiring_2027 integer NOT NULL DEFAULT 0,

  player_option_count integer NOT NULL DEFAULT 0,
  team_option_count integer NOT NULL DEFAULT 0,

  -- Players represented by this agent who had NBA salary last year and
  -- have no APPR/FUTR NBA salary in the current year.
  prior_year_nba_now_free_agent_count integer NOT NULL DEFAULT 0,

  cap_2025_total_percentile numeric,
  client_count_percentile numeric,
  max_contract_count_percentile numeric,

  refreshed_at timestamp with time zone NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_agents_warehouse_agency
  ON pcms.agents_warehouse (agency_id);

CREATE INDEX IF NOT EXISTS idx_agents_warehouse_cap_2025_total
  ON pcms.agents_warehouse (cap_2025_total DESC);


CREATE TABLE IF NOT EXISTS pcms.agencies_warehouse (
  agency_id integer PRIMARY KEY,

  agency_name text,
  is_active boolean,

  agent_count integer NOT NULL DEFAULT 0,
  client_count integer NOT NULL DEFAULT 0,
  standard_count integer NOT NULL DEFAULT 0,
  two_way_count integer NOT NULL DEFAULT 0,
  team_count integer NOT NULL DEFAULT 0,

  cap_2025_total bigint NOT NULL DEFAULT 0,
  cap_2026_total bigint NOT NULL DEFAULT 0,
  cap_2027_total bigint NOT NULL DEFAULT 0,
  total_salary_from_2025 bigint NOT NULL DEFAULT 0,

  max_contract_count integer NOT NULL DEFAULT 0,
  rookie_scale_count integer NOT NULL DEFAULT 0,
  min_contract_count integer NOT NULL DEFAULT 0,

  no_trade_count integer NOT NULL DEFAULT 0,
  trade_kicker_count integer NOT NULL DEFAULT 0,
  trade_restricted_count integer NOT NULL DEFAULT 0,

  expiring_2025 integer NOT NULL DEFAULT 0,
  expiring_2026 integer NOT NULL DEFAULT 0,
  expiring_2027 integer NOT NULL DEFAULT 0,

  player_option_count integer NOT NULL DEFAULT 0,
  team_option_count integer NOT NULL DEFAULT 0,

  prior_year_nba_now_free_agent_count integer NOT NULL DEFAULT 0,

  cap_2025_total_percentile numeric,
  client_count_percentile numeric,
  max_contract_count_percentile numeric,
  agent_count_percentile numeric,

  refreshed_at timestamp with time zone NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_agencies_warehouse_cap_2025_total
  ON pcms.agencies_warehouse (cap_2025_total DESC);


CREATE OR REPLACE FUNCTION pcms.refresh_agents_warehouse()
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_current_year integer;
BEGIN
  PERFORM set_config('statement_timeout', '0', true);
  PERFORM set_config('lock_timeout', '5s', true);

  SELECT MIN(salary_year) INTO v_current_year FROM pcms.team_budget_snapshots;
  IF v_current_year IS NULL THEN
    v_current_year := 2025;
  END IF;

  TRUNCATE TABLE pcms.agents_warehouse;

  INSERT INTO pcms.agents_warehouse (
    agent_id,
    full_name,
    agency_id,
    agency_name,
    is_active,
    is_certified,

    client_count,
    standard_count,
    two_way_count,
    team_count,

    cap_2025_total,
    cap_2026_total,
    cap_2027_total,
    total_salary_from_2025,

    max_contract_count,
    rookie_scale_count,
    min_contract_count,

    no_trade_count,
    trade_kicker_count,
    trade_restricted_count,

    expiring_2025,
    expiring_2026,
    expiring_2027,

    player_option_count,
    team_option_count,

    prior_year_nba_now_free_agent_count,

    cap_2025_total_percentile,
    client_count_percentile,
    max_contract_count_percentile,

    refreshed_at
  )
  WITH latest_contract_versions AS (
    SELECT DISTINCT ON (cv.contract_id)
      cv.contract_id,
      cv.version_number
    FROM pcms.contract_versions cv
    ORDER BY cv.contract_id, cv.version_number DESC
  ),
  prev_year_paid AS (
    SELECT DISTINCT c.player_id
    FROM pcms.contracts c
    JOIN latest_contract_versions lv
      ON lv.contract_id = c.contract_id
    JOIN pcms.salaries s
      ON s.contract_id = c.contract_id
     AND s.version_number = lv.version_number
    WHERE s.salary_year = (v_current_year - 1)
      AND COALESCE(s.contract_cap_salary, 0) > 0
  ),
  current_year_active_paid AS (
    SELECT DISTINCT c.player_id
    FROM pcms.contracts c
    JOIN latest_contract_versions lv
      ON lv.contract_id = c.contract_id
    JOIN pcms.salaries s
      ON s.contract_id = c.contract_id
     AND s.version_number = lv.version_number
    WHERE c.record_status_lk IN ('APPR', 'FUTR')
      AND s.salary_year = v_current_year
      AND COALESCE(s.contract_cap_salary, 0) > 0
  ),
  prior_year_nba_now_fa_by_agent AS (
    SELECT
      p.agent_id,
      COUNT(DISTINCT p.person_id)::integer AS prior_year_nba_now_free_agent_count
    FROM pcms.people p
    JOIN prev_year_paid py
      ON py.player_id = p.person_id
    LEFT JOIN current_year_active_paid cy
      ON cy.player_id = p.person_id
    WHERE p.person_type_lk = 'PLYR'
      AND p.league_lk = 'NBA'
      AND p.agent_id IS NOT NULL
      AND cy.player_id IS NULL
    GROUP BY p.agent_id
  ),
  base AS (
    SELECT
      a.agent_id,
      a.full_name,
      a.agency_id,
      a.agency_name,
      a.is_active,
      a.is_certified,

      COUNT(sb.player_id)::integer AS client_count,
      COUNT(sb.player_id) FILTER (WHERE NOT COALESCE(sb.is_two_way, false))::integer AS standard_count,
      COUNT(sb.player_id) FILTER (WHERE COALESCE(sb.is_two_way, false))::integer AS two_way_count,
      COUNT(DISTINCT sb.team_code)::integer AS team_count,

      COALESCE(SUM(sb.cap_2025) FILTER (WHERE NOT COALESCE(sb.is_two_way, false)), 0)::bigint AS cap_2025_total,
      COALESCE(SUM(sb.cap_2026) FILTER (WHERE NOT COALESCE(sb.is_two_way, false)), 0)::bigint AS cap_2026_total,
      COALESCE(SUM(sb.cap_2027) FILTER (WHERE NOT COALESCE(sb.is_two_way, false)), 0)::bigint AS cap_2027_total,
      COALESCE(SUM(sb.total_salary_from_2025) FILTER (WHERE NOT COALESCE(sb.is_two_way, false)), 0)::bigint AS total_salary_from_2025,

      COUNT(sb.player_id) FILTER (WHERE NOT COALESCE(sb.is_two_way, false) AND sb.pct_cap_2025 >= 0.25)::integer AS max_contract_count,
      COUNT(sb.player_id) FILTER (WHERE p.years_of_service <= 3 AND NOT COALESCE(sb.is_two_way, false))::integer AS rookie_scale_count,
      COUNT(sb.player_id) FILTER (WHERE COALESCE(sb.is_min_contract, false) AND NOT COALESCE(sb.is_two_way, false))::integer AS min_contract_count,

      COUNT(sb.player_id) FILTER (WHERE COALESCE(sb.is_no_trade, false))::integer AS no_trade_count,
      COUNT(sb.player_id) FILTER (WHERE COALESCE(sb.is_trade_bonus, false))::integer AS trade_kicker_count,
      COUNT(sb.player_id) FILTER (WHERE COALESCE(sb.is_trade_restricted_now, false))::integer AS trade_restricted_count,

      COUNT(sb.player_id) FILTER (
        WHERE NOT COALESCE(sb.is_two_way, false)
          AND sb.cap_2025 > 0
          AND COALESCE(sb.cap_2026, 0) = 0
      )::integer AS expiring_2025,
      COUNT(sb.player_id) FILTER (
        WHERE NOT COALESCE(sb.is_two_way, false)
          AND sb.cap_2026 > 0
          AND COALESCE(sb.cap_2027, 0) = 0
      )::integer AS expiring_2026,
      COUNT(sb.player_id) FILTER (
        WHERE NOT COALESCE(sb.is_two_way, false)
          AND sb.cap_2027 > 0
          AND COALESCE(sb.cap_2028, 0) = 0
      )::integer AS expiring_2027,

      COUNT(sb.player_id) FILTER (
        WHERE sb.option_2026 IN ('PLYR', 'PLYTF')
           OR sb.option_2027 IN ('PLYR', 'PLYTF')
           OR sb.option_2028 IN ('PLYR', 'PLYTF')
      )::integer AS player_option_count,
      COUNT(sb.player_id) FILTER (
        WHERE sb.option_2026 = 'TEAM'
           OR sb.option_2027 = 'TEAM'
           OR sb.option_2028 = 'TEAM'
      )::integer AS team_option_count,

      COALESCE(py.prior_year_nba_now_free_agent_count, 0)::integer AS prior_year_nba_now_free_agent_count

    FROM pcms.agents a
    LEFT JOIN pcms.salary_book_warehouse sb
      ON sb.agent_id = a.agent_id
    LEFT JOIN pcms.people p
      ON p.person_id = sb.player_id
    LEFT JOIN prior_year_nba_now_fa_by_agent py
      ON py.agent_id = a.agent_id
    GROUP BY
      a.agent_id,
      a.full_name,
      a.agency_id,
      a.agency_name,
      a.is_active,
      a.is_certified,
      py.prior_year_nba_now_free_agent_count
  ),
  ranked AS (
    SELECT
      b.*,
      PERCENT_RANK() OVER (ORDER BY b.cap_2025_total) AS cap_2025_total_percentile,
      PERCENT_RANK() OVER (ORDER BY b.client_count) AS client_count_percentile,
      PERCENT_RANK() OVER (ORDER BY b.max_contract_count) AS max_contract_count_percentile
    FROM base b
  )
  SELECT
    r.agent_id,
    r.full_name,
    r.agency_id,
    r.agency_name,
    r.is_active,
    r.is_certified,

    r.client_count,
    r.standard_count,
    r.two_way_count,
    r.team_count,

    r.cap_2025_total,
    r.cap_2026_total,
    r.cap_2027_total,
    r.total_salary_from_2025,

    r.max_contract_count,
    r.rookie_scale_count,
    r.min_contract_count,

    r.no_trade_count,
    r.trade_kicker_count,
    r.trade_restricted_count,

    r.expiring_2025,
    r.expiring_2026,
    r.expiring_2027,

    r.player_option_count,
    r.team_option_count,

    r.prior_year_nba_now_free_agent_count,

    r.cap_2025_total_percentile,
    r.client_count_percentile,
    r.max_contract_count_percentile,

    now() AS refreshed_at
  FROM ranked r
  ORDER BY r.cap_2025_total DESC, r.full_name;
END;
$$;


CREATE OR REPLACE FUNCTION pcms.refresh_agencies_warehouse()
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_current_year integer;
BEGIN
  PERFORM set_config('statement_timeout', '0', true);
  PERFORM set_config('lock_timeout', '5s', true);

  SELECT MIN(salary_year) INTO v_current_year FROM pcms.team_budget_snapshots;
  IF v_current_year IS NULL THEN
    v_current_year := 2025;
  END IF;

  TRUNCATE TABLE pcms.agencies_warehouse;

  INSERT INTO pcms.agencies_warehouse (
    agency_id,
    agency_name,
    is_active,

    agent_count,
    client_count,
    standard_count,
    two_way_count,
    team_count,

    cap_2025_total,
    cap_2026_total,
    cap_2027_total,
    total_salary_from_2025,

    max_contract_count,
    rookie_scale_count,
    min_contract_count,

    no_trade_count,
    trade_kicker_count,
    trade_restricted_count,

    expiring_2025,
    expiring_2026,
    expiring_2027,

    player_option_count,
    team_option_count,

    prior_year_nba_now_free_agent_count,

    cap_2025_total_percentile,
    client_count_percentile,
    max_contract_count_percentile,
    agent_count_percentile,

    refreshed_at
  )
  WITH latest_contract_versions AS (
    SELECT DISTINCT ON (cv.contract_id)
      cv.contract_id,
      cv.version_number
    FROM pcms.contract_versions cv
    ORDER BY cv.contract_id, cv.version_number DESC
  ),
  prev_year_paid AS (
    SELECT DISTINCT c.player_id
    FROM pcms.contracts c
    JOIN latest_contract_versions lv
      ON lv.contract_id = c.contract_id
    JOIN pcms.salaries s
      ON s.contract_id = c.contract_id
     AND s.version_number = lv.version_number
    WHERE s.salary_year = (v_current_year - 1)
      AND COALESCE(s.contract_cap_salary, 0) > 0
  ),
  current_year_active_paid AS (
    SELECT DISTINCT c.player_id
    FROM pcms.contracts c
    JOIN latest_contract_versions lv
      ON lv.contract_id = c.contract_id
    JOIN pcms.salaries s
      ON s.contract_id = c.contract_id
     AND s.version_number = lv.version_number
    WHERE c.record_status_lk IN ('APPR', 'FUTR')
      AND s.salary_year = v_current_year
      AND COALESCE(s.contract_cap_salary, 0) > 0
  ),
  prior_year_nba_now_fa_by_agency AS (
    SELECT
      a.agency_id,
      COUNT(DISTINCT p.person_id)::integer AS prior_year_nba_now_free_agent_count
    FROM pcms.people p
    JOIN pcms.agents a
      ON a.agent_id = p.agent_id
    JOIN prev_year_paid py
      ON py.player_id = p.person_id
    LEFT JOIN current_year_active_paid cy
      ON cy.player_id = p.person_id
    WHERE p.person_type_lk = 'PLYR'
      AND p.league_lk = 'NBA'
      AND a.agency_id IS NOT NULL
      AND cy.player_id IS NULL
    GROUP BY a.agency_id
  ),
  base AS (
    SELECT
      ag.agency_id,
      ag.agency_name,
      ag.is_active,

      COUNT(DISTINCT a.agent_id)::integer AS agent_count,
      COUNT(sb.player_id)::integer AS client_count,
      COUNT(sb.player_id) FILTER (WHERE NOT COALESCE(sb.is_two_way, false))::integer AS standard_count,
      COUNT(sb.player_id) FILTER (WHERE COALESCE(sb.is_two_way, false))::integer AS two_way_count,
      COUNT(DISTINCT sb.team_code)::integer AS team_count,

      COALESCE(SUM(sb.cap_2025) FILTER (WHERE NOT COALESCE(sb.is_two_way, false)), 0)::bigint AS cap_2025_total,
      COALESCE(SUM(sb.cap_2026) FILTER (WHERE NOT COALESCE(sb.is_two_way, false)), 0)::bigint AS cap_2026_total,
      COALESCE(SUM(sb.cap_2027) FILTER (WHERE NOT COALESCE(sb.is_two_way, false)), 0)::bigint AS cap_2027_total,
      COALESCE(SUM(sb.total_salary_from_2025) FILTER (WHERE NOT COALESCE(sb.is_two_way, false)), 0)::bigint AS total_salary_from_2025,

      COUNT(sb.player_id) FILTER (WHERE NOT COALESCE(sb.is_two_way, false) AND sb.pct_cap_2025 >= 0.25)::integer AS max_contract_count,
      COUNT(sb.player_id) FILTER (WHERE p.years_of_service <= 3 AND NOT COALESCE(sb.is_two_way, false))::integer AS rookie_scale_count,
      COUNT(sb.player_id) FILTER (WHERE COALESCE(sb.is_min_contract, false) AND NOT COALESCE(sb.is_two_way, false))::integer AS min_contract_count,

      COUNT(sb.player_id) FILTER (WHERE COALESCE(sb.is_no_trade, false))::integer AS no_trade_count,
      COUNT(sb.player_id) FILTER (WHERE COALESCE(sb.is_trade_bonus, false))::integer AS trade_kicker_count,
      COUNT(sb.player_id) FILTER (WHERE COALESCE(sb.is_trade_restricted_now, false))::integer AS trade_restricted_count,

      COUNT(sb.player_id) FILTER (
        WHERE NOT COALESCE(sb.is_two_way, false)
          AND sb.cap_2025 > 0
          AND COALESCE(sb.cap_2026, 0) = 0
      )::integer AS expiring_2025,
      COUNT(sb.player_id) FILTER (
        WHERE NOT COALESCE(sb.is_two_way, false)
          AND sb.cap_2026 > 0
          AND COALESCE(sb.cap_2027, 0) = 0
      )::integer AS expiring_2026,
      COUNT(sb.player_id) FILTER (
        WHERE NOT COALESCE(sb.is_two_way, false)
          AND sb.cap_2027 > 0
          AND COALESCE(sb.cap_2028, 0) = 0
      )::integer AS expiring_2027,

      COUNT(sb.player_id) FILTER (
        WHERE sb.option_2026 IN ('PLYR', 'PLYTF')
           OR sb.option_2027 IN ('PLYR', 'PLYTF')
           OR sb.option_2028 IN ('PLYR', 'PLYTF')
      )::integer AS player_option_count,
      COUNT(sb.player_id) FILTER (
        WHERE sb.option_2026 = 'TEAM'
           OR sb.option_2027 = 'TEAM'
           OR sb.option_2028 = 'TEAM'
      )::integer AS team_option_count,

      COALESCE(py.prior_year_nba_now_free_agent_count, 0)::integer AS prior_year_nba_now_free_agent_count

    FROM pcms.agencies ag
    LEFT JOIN pcms.agents a
      ON a.agency_id = ag.agency_id
    LEFT JOIN pcms.salary_book_warehouse sb
      ON sb.agent_id = a.agent_id
    LEFT JOIN pcms.people p
      ON p.person_id = sb.player_id
    LEFT JOIN prior_year_nba_now_fa_by_agency py
      ON py.agency_id = ag.agency_id
    GROUP BY
      ag.agency_id,
      ag.agency_name,
      ag.is_active,
      py.prior_year_nba_now_free_agent_count
  ),
  ranked AS (
    SELECT
      b.*,
      PERCENT_RANK() OVER (ORDER BY b.cap_2025_total) AS cap_2025_total_percentile,
      PERCENT_RANK() OVER (ORDER BY b.client_count) AS client_count_percentile,
      PERCENT_RANK() OVER (ORDER BY b.max_contract_count) AS max_contract_count_percentile,
      PERCENT_RANK() OVER (ORDER BY b.agent_count) AS agent_count_percentile
    FROM base b
  )
  SELECT
    r.agency_id,
    r.agency_name,
    r.is_active,

    r.agent_count,
    r.client_count,
    r.standard_count,
    r.two_way_count,
    r.team_count,

    r.cap_2025_total,
    r.cap_2026_total,
    r.cap_2027_total,
    r.total_salary_from_2025,

    r.max_contract_count,
    r.rookie_scale_count,
    r.min_contract_count,

    r.no_trade_count,
    r.trade_kicker_count,
    r.trade_restricted_count,

    r.expiring_2025,
    r.expiring_2026,
    r.expiring_2027,

    r.player_option_count,
    r.team_option_count,

    r.prior_year_nba_now_free_agent_count,

    r.cap_2025_total_percentile,
    r.client_count_percentile,
    r.max_contract_count_percentile,
    r.agent_count_percentile,

    now() AS refreshed_at
  FROM ranked r
  ORDER BY r.cap_2025_total DESC, r.agency_name;
END;
$$;


COMMIT;
