-- 025_cap_holds_warehouse.sql
--
-- Denormalized cache for cap holds / non-contract amounts used in Team Master.
--
-- Source of truth: pcms.non_contract_amounts

BEGIN;

CREATE TABLE IF NOT EXISTS pcms.cap_holds_warehouse (
  non_contract_amount_id bigint PRIMARY KEY,

  team_id integer,
  team_code text,
  salary_year integer,

  player_id integer,
  player_name text,

  amount_type_lk text,

  cap_amount bigint,
  tax_amount bigint,
  apron_amount bigint,

  fa_amount bigint,
  fa_amount_calc bigint,
  salary_fa_amount bigint,

  qo_amount bigint,
  rofr_amount bigint,
  rookie_scale_amount bigint,

  carry_over_fa_flg boolean,

  fa_amount_type_lk text,
  fa_amount_type_lk_calc text,
  free_agent_designation_lk text,
  free_agent_status_lk text,
  min_contract_lk text,

  contract_id integer,
  contract_type_lk text,
  transaction_id integer,
  version_number text,
  years_of_service integer,

  refreshed_at timestamp with time zone NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_cap_holds_warehouse_team_year
  ON pcms.cap_holds_warehouse (team_code, salary_year);

CREATE INDEX IF NOT EXISTS idx_cap_holds_warehouse_team_type
  ON pcms.cap_holds_warehouse (team_code, amount_type_lk);


CREATE OR REPLACE FUNCTION pcms.refresh_cap_holds_warehouse()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM set_config('statement_timeout', '0', true);
  PERFORM set_config('lock_timeout', '5s', true);

  TRUNCATE TABLE pcms.cap_holds_warehouse;

  INSERT INTO pcms.cap_holds_warehouse (
    non_contract_amount_id,

    team_id,
    team_code,
    salary_year,

    player_id,
    player_name,

    amount_type_lk,

    cap_amount,
    tax_amount,
    apron_amount,

    fa_amount,
    fa_amount_calc,
    salary_fa_amount,

    qo_amount,
    rofr_amount,
    rookie_scale_amount,

    carry_over_fa_flg,

    fa_amount_type_lk,
    fa_amount_type_lk_calc,
    free_agent_designation_lk,
    free_agent_status_lk,
    min_contract_lk,

    contract_id,
    contract_type_lk,
    transaction_id,
    version_number,
    years_of_service,

    refreshed_at
  )
  SELECT
    nca.non_contract_amount_id,

    nca.team_id,
    nca.team_code,
    nca.salary_year,

    nca.player_id,
    (p.last_name || ', ' || p.first_name) AS player_name,

    nca.amount_type_lk,

    nca.cap_amount,
    nca.tax_amount,
    nca.apron_amount,

    nca.fa_amount,
    nca.fa_amount_calc,
    nca.salary_fa_amount,

    nca.qo_amount,
    nca.rofr_amount,
    nca.rookie_scale_amount,

    nca.carry_over_fa_flg,

    nca.fa_amount_type_lk,
    nca.fa_amount_type_lk_calc,
    nca.free_agent_designation_lk,
    nca.free_agent_status_lk,
    nca.min_contract_lk,

    nca.contract_id,
    nca.contract_type_lk,
    nca.transaction_id,
    nca.version_number,
    nca.years_of_service,

    now() AS refreshed_at

  FROM pcms.non_contract_amounts nca
  -- Filter to holds that actually contribute to team totals:
  -- only keep non-contract rows that appear in team_budget_snapshots FA buckets.
  JOIN pcms.team_budget_snapshots tbs
    ON tbs.team_code = nca.team_code
   AND tbs.salary_year = nca.salary_year
   AND tbs.player_id = nca.player_id
   AND tbs.budget_group_lk IN ('FA', 'QO', 'DRFPK', 'PR10D')
  LEFT JOIN pcms.people p
    ON p.person_id = nca.player_id
  WHERE nca.salary_year >= 2025
    AND nca.team_code IS NOT NULL;
END;
$$;

COMMIT;
