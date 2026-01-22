-- 013_salary_book_warehouse.sql
--
-- Denormalized “salary book / playground” cache table.
--
-- Motivation:
-- - Sean’s tools expect a fast, wide, one-row-per-player lookup.
-- - Views are great for iteration, but a physical table lets us add targeted indexes
--   and do a predictable daily refresh (truncate/insert).
--
-- Source of truth for population is currently: pcms.vw_y_warehouse
-- (2025–2030 grid, active players).

BEGIN;

CREATE TABLE IF NOT EXISTS pcms.salary_book_warehouse (
  player_id integer PRIMARY KEY,
  player_name text,
  league_lk text,

  -- roster/team identity
  team_code text,
  contract_team_code text,
  person_team_code text,
  signing_team_id integer,

  -- contract identity
  contract_id integer,
  version_number integer,

  -- bio / agent
  birth_date date,
  age integer,
  agent_name text,
  agent_id integer,

  -- salary grid (cap)
  cap_2025 bigint,
  cap_2026 bigint,
  cap_2027 bigint,
  cap_2028 bigint,
  cap_2029 bigint,
  cap_2030 bigint,

  -- % of cap
  pct_cap_2025 numeric,
  pct_cap_2026 numeric,
  pct_cap_2027 numeric,
  pct_cap_2028 numeric,
  pct_cap_2029 numeric,
  pct_cap_2030 numeric,

  -- totals
  total_salary_from_2025 bigint,

  -- options
  option_2025 text,
  option_2026 text,
  option_2027 text,
  option_2028 text,
  option_2029 text,
  option_2030 text,

  option_decision_2025 text,
  option_decision_2026 text,
  option_decision_2027 text,
  option_decision_2028 text,
  option_decision_2029 text,
  option_decision_2030 text,

  -- trade flags
  is_two_way boolean,
  is_poison_pill boolean,
  poison_pill_amount bigint,
  is_no_trade boolean,
  is_trade_bonus boolean,
  trade_bonus_percent numeric,
  trade_kicker_amount_2025 bigint,
  trade_kicker_display text,

  -- tax/apron grid
  tax_2025 bigint,
  tax_2026 bigint,
  tax_2027 bigint,
  tax_2028 bigint,
  tax_2029 bigint,
  tax_2030 bigint,

  apron_2025 bigint,
  apron_2026 bigint,
  apron_2027 bigint,
  apron_2028 bigint,
  apron_2029 bigint,
  apron_2030 bigint,

  -- trade-math (approx)
  outgoing_buildup_2025 bigint,
  incoming_buildup_2025 bigint,
  incoming_salary_2025 bigint,
  incoming_tax_2025 bigint,
  incoming_apron_2025 bigint,

  -- refresh metadata
  refreshed_at timestamp with time zone NOT NULL DEFAULT now()
);

-- Targeted indexes for Salary Book style queries.
CREATE INDEX IF NOT EXISTS idx_salary_book_warehouse_team
  ON pcms.salary_book_warehouse (team_code);

CREATE INDEX IF NOT EXISTS idx_salary_book_warehouse_team_cap_2025
  ON pcms.salary_book_warehouse (team_code, cap_2025 DESC NULLS LAST);

CREATE INDEX IF NOT EXISTS idx_salary_book_warehouse_cap_2025
  ON pcms.salary_book_warehouse (cap_2025 DESC NULLS LAST);

CREATE INDEX IF NOT EXISTS idx_salary_book_warehouse_player_name
  ON pcms.salary_book_warehouse (player_name);

CREATE INDEX IF NOT EXISTS idx_salary_book_warehouse_player_name_lower
  ON pcms.salary_book_warehouse (lower(player_name));

-- Optional: quick access to contract id/version joins.
CREATE INDEX IF NOT EXISTS idx_salary_book_warehouse_contract
  ON pcms.salary_book_warehouse (contract_id, version_number);


-- Refresh routine: truncate/insert from vw_y_warehouse.
--
-- NOTE: TRUNCATE takes an ACCESS EXCLUSIVE lock; if that becomes a problem,
-- switch to a “swap table” pattern or use a materialized view with CONCURRENTLY.

CREATE OR REPLACE FUNCTION pcms.refresh_salary_book_warehouse()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
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
  SELECT
    y.player_id,
    y.player_name,
    y.league_lk,
    y.team_code,
    y.contract_team_code,
    y.person_team_code,
    y.signing_team_id,
    ac.contract_id,
    ac.version_number,
    y.birth_date,
    y.age,
    y.agent_name,
    p.agent_id,
    y.cap_2025, y.cap_2026, y.cap_2027, y.cap_2028, y.cap_2029, y.cap_2030,
    y.pct_cap_2025, y.pct_cap_2026, y.pct_cap_2027, y.pct_cap_2028, y.pct_cap_2029, y.pct_cap_2030,
    y.total_salary_from_2025::bigint,
    y.option_2025, y.option_2026, y.option_2027, y.option_2028, y.option_2029, y.option_2030,
    y.option_decision_2025, y.option_decision_2026, y.option_decision_2027,
    y.option_decision_2028, y.option_decision_2029, y.option_decision_2030,
    y.is_two_way,
    y.is_poison_pill,
    y.poison_pill_amount,
    y.is_no_trade,
    y.is_trade_bonus,
    y.trade_bonus_percent,
    y.trade_kicker_amount_2025,
    y.trade_kicker_display,
    y.tax_2025, y.tax_2026, y.tax_2027, y.tax_2028, y.tax_2029, y.tax_2030,
    y.apron_2025, y.apron_2026, y.apron_2027, y.apron_2028, y.apron_2029, y.apron_2030,
    y.outgoing_buildup_2025,
    y.incoming_buildup_2025,
    y.incoming_salary_2025,
    y.incoming_tax_2025,
    y.incoming_apron_2025,
    now()
  FROM pcms.vw_y_warehouse y
  JOIN pcms.vw_active_contract_versions ac
    ON ac.player_id = y.player_id
  JOIN pcms.people p
    ON p.person_id = y.player_id;
END;
$$;

COMMIT;
