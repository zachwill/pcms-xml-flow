-- 076_representation_and_team_percentiles.sql
--
-- Extend percentile coverage:
-- - agents_warehouse: add book percentiles for 2026/2027
-- - agencies_warehouse: add book percentiles for 2026/2027
-- - team_salary_warehouse: add cap_total percentile per salary_year

BEGIN;

ALTER TABLE pcms.agents_warehouse
  ADD COLUMN IF NOT EXISTS cap_2026_total_percentile numeric,
  ADD COLUMN IF NOT EXISTS cap_2027_total_percentile numeric;

ALTER TABLE pcms.agencies_warehouse
  ADD COLUMN IF NOT EXISTS cap_2026_total_percentile numeric,
  ADD COLUMN IF NOT EXISTS cap_2027_total_percentile numeric;

ALTER TABLE pcms.team_salary_warehouse
  ADD COLUMN IF NOT EXISTS cap_total_percentile numeric;


CREATE OR REPLACE FUNCTION pcms.refresh_agents_warehouse_percentiles()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  WITH ranked AS (
    SELECT
      agent_id,
      PERCENT_RANK() OVER (ORDER BY cap_2025_total) AS p25,
      PERCENT_RANK() OVER (ORDER BY cap_2026_total) AS p26,
      PERCENT_RANK() OVER (ORDER BY cap_2027_total) AS p27,
      PERCENT_RANK() OVER (ORDER BY client_count) AS p_clients,
      PERCENT_RANK() OVER (ORDER BY max_contract_count) AS p_max
    FROM pcms.agents_warehouse
  )
  UPDATE pcms.agents_warehouse w
  SET
    cap_2025_total_percentile = r.p25,
    cap_2026_total_percentile = r.p26,
    cap_2027_total_percentile = r.p27,
    client_count_percentile = r.p_clients,
    max_contract_count_percentile = r.p_max
  FROM ranked r
  WHERE w.agent_id = r.agent_id;
END;
$$;


CREATE OR REPLACE FUNCTION pcms.refresh_agencies_warehouse_percentiles()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  WITH ranked AS (
    SELECT
      agency_id,
      PERCENT_RANK() OVER (ORDER BY cap_2025_total) AS p25,
      PERCENT_RANK() OVER (ORDER BY cap_2026_total) AS p26,
      PERCENT_RANK() OVER (ORDER BY cap_2027_total) AS p27,
      PERCENT_RANK() OVER (ORDER BY client_count) AS p_clients,
      PERCENT_RANK() OVER (ORDER BY max_contract_count) AS p_max,
      PERCENT_RANK() OVER (ORDER BY agent_count) AS p_agents
    FROM pcms.agencies_warehouse
  )
  UPDATE pcms.agencies_warehouse w
  SET
    cap_2025_total_percentile = r.p25,
    cap_2026_total_percentile = r.p26,
    cap_2027_total_percentile = r.p27,
    client_count_percentile = r.p_clients,
    max_contract_count_percentile = r.p_max,
    agent_count_percentile = r.p_agents
  FROM ranked r
  WHERE w.agency_id = r.agency_id;
END;
$$;


CREATE OR REPLACE FUNCTION pcms.refresh_team_salary_percentiles()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  WITH ranked AS (
    SELECT
      team_code,
      salary_year,
      PERCENT_RANK() OVER (
        PARTITION BY salary_year
        ORDER BY cap_total
      ) AS p_cap_total
    FROM pcms.team_salary_warehouse
  )
  UPDATE pcms.team_salary_warehouse t
  SET cap_total_percentile = r.p_cap_total
  FROM ranked r
  WHERE t.team_code = r.team_code
    AND t.salary_year = r.salary_year;
END;
$$;

-- Backfill percentiles now
SELECT pcms.refresh_agents_warehouse_percentiles();
SELECT pcms.refresh_agencies_warehouse_percentiles();
SELECT pcms.refresh_team_salary_percentiles();

COMMIT;
