-- result_collection=last_statement_all_rows

ATTACH '$res:f/env/postgres' AS pg (TYPE postgres);
SET TimeZone='UTC';

--
-- contracts.inline_script.duckdb.sql
--
-- Imports (upserts) from contracts.json (deeply nested):
--   - pg.pcms.contracts
--   - pg.pcms.contract_versions
--   - pg.pcms.salaries
--   - pg.pcms.contract_bonuses
--   - pg.pcms.contract_bonus_criteria
--   - pg.pcms.contract_bonus_maximums
--   - pg.pcms.contract_protections
--   - pg.pcms.contract_protection_conditions
--   - pg.pcms.payment_schedules
--   - pg.pcms.payment_schedule_details
--
-- Source files (hard-coded):
--   ./shared/pcms/nba_pcms_full_extract/contracts.json
--   ./shared/pcms/nba_pcms_full_extract/lookups.json
--
-- Notes:
--   - Deduplication with QUALIFY is mandatory prior to each Postgres upsert.
--   - PCMS sometimes represents version_number as a decimal (e.g. 1.01). We normalize
--     to an integer (1.01 -> 101) to match the schema.
--   - Nested structures may be arrays or single objects depending on extract; we
--     defensively "force" them into arrays before json_each().
--

-- 1) Team lookup (reused for contracts.team_code and sign_and_trade_to_team_code)
CREATE OR REPLACE TEMP VIEW v_teams AS
SELECT
  TRY_CAST(team_json->>'$.team_id' AS BIGINT) AS team_id,
  COALESCE(team_json->>'$.team_code', team_json->>'$.team_name_short') AS team_code,
FROM (
  SELECT
    to_json(r) AS team_json,
  FROM read_json_auto('./shared/pcms/nba_pcms_full_extract/lookups.json') AS lookups,
  UNNEST(lookups.lk_teams.lk_team) AS t(r)
)
WHERE team_json->>'$.team_id' IS NOT NULL;

-- 2) Read contracts.json as JSON per-row (gives us uniform json_extract access)
CREATE OR REPLACE TEMP VIEW v_contract_json AS
SELECT
  to_json(c) AS c_json,
FROM read_json_auto('./shared/pcms/nba_pcms_full_extract/contracts.json') AS c;

-- ─────────────────────────────────────────────────────────────────────────────
-- contracts
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TEMP VIEW v_contracts_source AS
SELECT
  TRY_CAST(c_json->>'$.contract_id' AS INTEGER) AS contract_id,
  TRY_CAST(c_json->>'$.player_id' AS INTEGER) AS player_id,

  TRY_CAST(c_json->>'$.signing_team_id' AS INTEGER) AS signing_team_id,
  signing_team.team_code AS team_code,

  TRY_CAST(c_json->>'$.signing_date' AS DATE) AS signing_date,
  TRY_CAST(c_json->>'$.contract_end_date' AS DATE) AS contract_end_date,

  NULLIF(trim(c_json->>'$.record_status_lk'), '') AS record_status_lk,
  NULLIF(trim(c_json->>'$.signed_method_lk'), '') AS signed_method_lk,
  TRY_CAST(c_json->>'$.team_exception_id' AS INTEGER) AS team_exception_id,

  TRY_CAST(COALESCE(c_json->>'$.sign_and_trade_flg', c_json->>'$.is_sign_and_trade') AS BOOLEAN) AS is_sign_and_trade,
  TRY_CAST(c_json->>'$.sign_and_trade_date' AS DATE) AS sign_and_trade_date,

  TRY_CAST(c_json->>'$.sign_and_trade_to_team_id' AS INTEGER) AS sign_and_trade_to_team_id,
  sat_team.team_code AS sign_and_trade_to_team_code,

  TRY_CAST(c_json->>'$.sign_and_trade_id' AS INTEGER) AS sign_and_trade_id,

  -- WNBA-only; NBA rows will be NULL.
  TRY_CAST(c_json->>'$.start_year' AS INTEGER) AS start_year,
  COALESCE(NULLIF(trim(c_json->>'$.contract_length_wnba'), ''), NULLIF(trim(c_json->>'$.contract_length'), '')) AS contract_length_wnba,

  TRY_CAST(c_json->>'$.convert_date' AS DATE) AS convert_date,
  TRY_CAST(c_json->>'$.two_way_service_limit' AS INTEGER) AS two_way_service_limit,

  TRY_CAST(c_json->>'$.create_date' AS TIMESTAMPTZ) AS created_at,
  TRY_CAST(c_json->>'$.last_change_date' AS TIMESTAMPTZ) AS updated_at,
  TRY_CAST(c_json->>'$.record_change_date' AS TIMESTAMPTZ) AS record_changed_at,

  now() AS ingested_at,
FROM v_contract_json
LEFT JOIN v_teams AS signing_team
  ON signing_team.team_id = TRY_CAST(c_json->>'$.signing_team_id' AS BIGINT)
LEFT JOIN v_teams AS sat_team
  ON sat_team.team_id = TRY_CAST(c_json->>'$.sign_and_trade_to_team_id' AS BIGINT)
WHERE c_json->>'$.contract_id' IS NOT NULL;

CREATE OR REPLACE TEMP VIEW v_contracts_deduped AS
SELECT * EXCLUDE (rn)
FROM (
  SELECT
    *,
    ROW_NUMBER() OVER (
      PARTITION BY contract_id
      ORDER BY record_changed_at DESC NULLS LAST, updated_at DESC NULLS LAST, created_at DESC NULLS LAST
    ) AS rn,
  FROM v_contracts_source
)
QUALIFY rn = 1;

INSERT INTO pg.pcms.contracts BY NAME (
  SELECT * FROM v_contracts_deduped
)
ON CONFLICT (contract_id) DO UPDATE SET
  player_id = EXCLUDED.player_id,
  signing_team_id = EXCLUDED.signing_team_id,
  team_code = EXCLUDED.team_code,
  signing_date = EXCLUDED.signing_date,
  contract_end_date = EXCLUDED.contract_end_date,
  record_status_lk = EXCLUDED.record_status_lk,
  signed_method_lk = EXCLUDED.signed_method_lk,
  team_exception_id = EXCLUDED.team_exception_id,
  is_sign_and_trade = EXCLUDED.is_sign_and_trade,
  sign_and_trade_date = EXCLUDED.sign_and_trade_date,
  sign_and_trade_to_team_id = EXCLUDED.sign_and_trade_to_team_id,
  sign_and_trade_to_team_code = EXCLUDED.sign_and_trade_to_team_code,
  sign_and_trade_id = EXCLUDED.sign_and_trade_id,
  start_year = EXCLUDED.start_year,
  contract_length_wnba = EXCLUDED.contract_length_wnba,
  convert_date = EXCLUDED.convert_date,
  two_way_service_limit = EXCLUDED.two_way_service_limit,
  updated_at = EXCLUDED.updated_at,
  record_changed_at = EXCLUDED.record_changed_at,
  ingested_at = EXCLUDED.ingested_at;

-- ─────────────────────────────────────────────────────────────────────────────
-- contract_versions
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TEMP VIEW v_contract_versions_source AS
WITH v_src AS (
  SELECT
    c_json,
    TRY_CAST(c_json->>'$.contract_id' AS INTEGER) AS contract_id,
    COALESCE(
      json_extract(c_json, '$.versions.version'),
      json_extract(c_json, '$.versions')
    ) AS versions_json,
  FROM v_contract_json
  WHERE c_json->>'$.contract_id' IS NOT NULL
), v_arr AS (
  SELECT
    *,
    CASE
      WHEN versions_json IS NULL THEN json('[]')
      WHEN json_type(versions_json) = 'ARRAY' THEN versions_json
      ELSE json('[' || CAST(versions_json AS VARCHAR) || ']')
    END AS versions_arr,
  FROM v_src
)
SELECT
  contract_id,

  -- Normalize version_number: 1.01 -> 101
  CASE
    WHEN TRY_CAST(v_json->>'$.version_number' AS DOUBLE) IS NULL THEN NULL
    WHEN floor(TRY_CAST(v_json->>'$.version_number' AS DOUBLE)) = TRY_CAST(v_json->>'$.version_number' AS DOUBLE)
      THEN TRY_CAST(TRY_CAST(v_json->>'$.version_number' AS DOUBLE) AS INTEGER)
    ELSE ROUND(TRY_CAST(v_json->>'$.version_number' AS DOUBLE) * 100)::INTEGER
  END AS version_number,

  TRY_CAST(v_json->>'$.transaction_id' AS INTEGER) AS transaction_id,
  TRY_CAST(v_json->>'$.version_date' AS DATE) AS version_date,
  TRY_CAST(COALESCE(v_json->>'$.start_year', v_json->>'$.start_salary_year') AS INTEGER) AS start_salary_year,
  TRY_CAST(v_json->>'$.contract_length' AS INTEGER) AS contract_length,
  NULLIF(trim(v_json->>'$.contract_type_lk'), '') AS contract_type_lk,
  NULLIF(trim(v_json->>'$.record_status_lk'), '') AS record_status_lk,
  TRY_CAST(v_json->>'$.agency_id' AS INTEGER) AS agency_id,
  TRY_CAST(v_json->>'$.agent_id' AS INTEGER) AS agent_id,

  TRY_CAST(v_json->>'$.full_protection_flg' AS BOOLEAN) AS is_full_protection,
  TRY_CAST(v_json->>'$.exhibit10' AS BOOLEAN) AS is_exhibit_10,
  TRY_CAST(v_json->>'$.exhibit10_bonus_amount' AS BIGINT) AS exhibit_10_bonus_amount,
  TRY_CAST(v_json->>'$.exhibit10_protection_amount' AS BIGINT) AS exhibit_10_protection_amount,
  TRY_CAST(v_json->>'$.exhibit10_end_date' AS DATE) AS exhibit_10_end_date,

  TRY_CAST(v_json->>'$.is_two_way' AS BOOLEAN) AS is_two_way,
  TRY_CAST(v_json->>'$.dp_rookie_scale_extension_flg' AS BOOLEAN) AS is_rookie_scale_extension,
  TRY_CAST(v_json->>'$.dp_veteran_extension_flg' AS BOOLEAN) AS is_veteran_extension,

  TRY_CAST(v_json->>'$.poison_pill_flg' AS BOOLEAN) AS is_poison_pill,
  TRY_CAST(v_json->>'$.poison_pill_amt' AS BIGINT) AS poison_pill_amount,

  TRY_CAST(v_json->>'$.trade_bonus_percent' AS DOUBLE) AS trade_bonus_percent,
  TRY_CAST(v_json->>'$.trade_bonus_amount' AS BIGINT) AS trade_bonus_amount,
  TRY_CAST(v_json->>'$.trade_bonus_flg' AS BOOLEAN) AS is_trade_bonus,
  TRY_CAST(v_json->>'$.no_trade_flg' AS BOOLEAN) AS is_no_trade,

  TRY_CAST(v_json->>'$.is_minimum_contract' AS BOOLEAN) AS is_minimum_contract,
  TRY_CAST(v_json->>'$.is_protected_contract' AS BOOLEAN) AS is_protected_contract,

  -- Keep NULL for now (avoids storing large nested blobs by default).
  NULL::JSON AS version_json,

  TRY_CAST(v_json->>'$.create_date' AS TIMESTAMPTZ) AS created_at,
  TRY_CAST(v_json->>'$.last_change_date' AS TIMESTAMPTZ) AS updated_at,
  TRY_CAST(v_json->>'$.record_change_date' AS TIMESTAMPTZ) AS record_changed_at,

  now() AS ingested_at,
FROM v_arr,
json_each(v_arr.versions_arr) AS ve(idx, v_json)
WHERE v_json IS NOT NULL;

CREATE OR REPLACE TEMP VIEW v_contract_versions_deduped AS
SELECT * EXCLUDE (rn)
FROM (
  SELECT
    *,
    ROW_NUMBER() OVER (
      PARTITION BY contract_id, version_number
      ORDER BY record_changed_at DESC NULLS LAST, updated_at DESC NULLS LAST, created_at DESC NULLS LAST
    ) AS rn,
  FROM v_contract_versions_source
)
QUALIFY rn = 1;

INSERT INTO pg.pcms.contract_versions BY NAME (
  SELECT
    contract_id,
    version_number,
    transaction_id,
    version_date,
    start_salary_year,
    contract_length,
    contract_type_lk,
    record_status_lk,
    agency_id,
    agent_id,
    is_full_protection,
    is_exhibit_10,
    exhibit_10_bonus_amount,
    exhibit_10_protection_amount,
    exhibit_10_end_date,
    is_two_way,
    is_rookie_scale_extension,
    is_veteran_extension,
    is_poison_pill,
    poison_pill_amount,
    trade_bonus_percent,
    trade_bonus_amount,
    is_trade_bonus,
    is_no_trade,
    is_minimum_contract,
    is_protected_contract,
    version_json,
    created_at,
    updated_at,
    record_changed_at,
    ingested_at,
  FROM v_contract_versions_deduped
  WHERE contract_id IS NOT NULL
    AND version_number IS NOT NULL
)
ON CONFLICT (contract_id, version_number) DO UPDATE SET
  transaction_id = EXCLUDED.transaction_id,
  version_date = EXCLUDED.version_date,
  start_salary_year = EXCLUDED.start_salary_year,
  contract_length = EXCLUDED.contract_length,
  contract_type_lk = EXCLUDED.contract_type_lk,
  record_status_lk = EXCLUDED.record_status_lk,
  agency_id = EXCLUDED.agency_id,
  agent_id = EXCLUDED.agent_id,
  is_full_protection = EXCLUDED.is_full_protection,
  is_exhibit_10 = EXCLUDED.is_exhibit_10,
  exhibit_10_bonus_amount = EXCLUDED.exhibit_10_bonus_amount,
  exhibit_10_protection_amount = EXCLUDED.exhibit_10_protection_amount,
  exhibit_10_end_date = EXCLUDED.exhibit_10_end_date,
  is_two_way = EXCLUDED.is_two_way,
  is_rookie_scale_extension = EXCLUDED.is_rookie_scale_extension,
  is_veteran_extension = EXCLUDED.is_veteran_extension,
  is_poison_pill = EXCLUDED.is_poison_pill,
  poison_pill_amount = EXCLUDED.poison_pill_amount,
  trade_bonus_percent = EXCLUDED.trade_bonus_percent,
  trade_bonus_amount = EXCLUDED.trade_bonus_amount,
  is_trade_bonus = EXCLUDED.is_trade_bonus,
  is_no_trade = EXCLUDED.is_no_trade,
  is_minimum_contract = EXCLUDED.is_minimum_contract,
  is_protected_contract = EXCLUDED.is_protected_contract,
  version_json = EXCLUDED.version_json,
  updated_at = EXCLUDED.updated_at,
  record_changed_at = EXCLUDED.record_changed_at,
  ingested_at = EXCLUDED.ingested_at;

-- ─────────────────────────────────────────────────────────────────────────────
-- salaries
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TEMP VIEW v_salaries_source AS
WITH v_src AS (
  SELECT
    contract_id,
    version_number,
    to_json(v) AS v_json,
  FROM v_contract_versions_deduped AS v
  WHERE contract_id IS NOT NULL AND version_number IS NOT NULL
), v_salaries AS (
  SELECT
    *,
    COALESCE(
      json_extract(v_json, '$.salaries.salary'),
      json_extract(v_json, '$.salaries')
    ) AS salaries_json,
  FROM v_src
), v_arr AS (
  SELECT
    *,
    CASE
      WHEN salaries_json IS NULL THEN json('[]')
      WHEN json_type(salaries_json) = 'ARRAY' THEN salaries_json
      ELSE json('[' || CAST(salaries_json AS VARCHAR) || ']')
    END AS salaries_arr,
  FROM v_salaries
)
SELECT
  contract_id,
  version_number,
  TRY_CAST(s_json->>'$.salary_year' AS INTEGER) AS salary_year,

  TRY_CAST(s_json->>'$.total_salary' AS BIGINT) AS total_salary,
  TRY_CAST(s_json->>'$.total_salary_adjustment' AS BIGINT) AS total_salary_adjustment,
  TRY_CAST(s_json->>'$.total_base_comp' AS BIGINT) AS total_base_comp,
  TRY_CAST(s_json->>'$.current_base_comp' AS BIGINT) AS current_base_comp,
  TRY_CAST(s_json->>'$.deferred_base_comp' AS BIGINT) AS deferred_base_comp,
  TRY_CAST(s_json->>'$.signing_bonus' AS BIGINT) AS signing_bonus,
  TRY_CAST(s_json->>'$.likely_bonus' AS BIGINT) AS likely_bonus,
  TRY_CAST(s_json->>'$.unlikely_bonus' AS BIGINT) AS unlikely_bonus,

  TRY_CAST(s_json->>'$.contract_cap_salary' AS BIGINT) AS contract_cap_salary,
  TRY_CAST(s_json->>'$.contract_cap_salary_adjustment' AS BIGINT) AS contract_cap_salary_adjustment,
  TRY_CAST(s_json->>'$.contract_tax_salary' AS BIGINT) AS contract_tax_salary,
  TRY_CAST(s_json->>'$.contract_tax_salary_adjustment' AS BIGINT) AS contract_tax_salary_adjustment,
  TRY_CAST(s_json->>'$.contract_tax_apron_salary' AS BIGINT) AS contract_tax_apron_salary,
  TRY_CAST(s_json->>'$.contract_tax_apron_salary_adjustment' AS BIGINT) AS contract_tax_apron_salary_adjustment,
  TRY_CAST(s_json->>'$.contract_mts_salary' AS BIGINT) AS contract_mts_salary,

  TRY_CAST(s_json->>'$.skill_protection_amount' AS BIGINT) AS skill_protection_amount,
  TRY_CAST(s_json->>'$.trade_bonus_amount' AS BIGINT) AS trade_bonus_amount,
  TRY_CAST(s_json->>'$.trade_bonus_amount_calc' AS BIGINT) AS trade_bonus_amount_calc,

  TRY_CAST(s_json->>'$.cap_raise_percent' AS DOUBLE) AS cap_raise_percent,

  TRY_CAST(s_json->>'$.two_way_nba_salary' AS BIGINT) AS two_way_nba_salary,
  TRY_CAST(s_json->>'$.two_way_dlg_salary' AS BIGINT) AS two_way_dlg_salary,

  TRY_CAST(s_json->>'$.wnba_salary' AS BIGINT) AS wnba_salary,
  TRY_CAST(s_json->>'$.wnba_time_off_bonus_amount' AS BIGINT) AS wnba_time_off_bonus_amount,
  TRY_CAST(s_json->>'$.wnba_merit_bonus_amount' AS BIGINT) AS wnba_merit_bonus_amount,
  TRY_CAST(s_json->>'$.wnba_time_off_bonus_days' AS INTEGER) AS wnba_time_off_bonus_days,

  NULLIF(trim(s_json->>'$.option_lk'), '') AS option_lk,
  NULLIF(trim(s_json->>'$.option_decision_lk'), '') AS option_decision_lk,
  TRY_CAST(s_json->>'$.applicable_min_salary_flg' AS BOOLEAN) AS is_applicable_min_salary,

  TRY_CAST(s_json->>'$.create_date' AS TIMESTAMPTZ) AS created_at,
  TRY_CAST(s_json->>'$.last_change_date' AS TIMESTAMPTZ) AS updated_at,
  TRY_CAST(s_json->>'$.record_change_date' AS TIMESTAMPTZ) AS record_changed_at,

  now() AS ingested_at,

  -- Keep salary JSON around for downstream nested extraction
  s_json AS salary_json,
FROM v_arr,
json_each(v_arr.salaries_arr) AS se(idx, s_json)
WHERE s_json IS NOT NULL;

CREATE OR REPLACE TEMP VIEW v_salaries_deduped AS
SELECT * EXCLUDE (rn)
FROM (
  SELECT
    *,
    ROW_NUMBER() OVER (
      PARTITION BY contract_id, version_number, salary_year
      ORDER BY record_changed_at DESC NULLS LAST, updated_at DESC NULLS LAST, created_at DESC NULLS LAST
    ) AS rn,
  FROM v_salaries_source
)
QUALIFY rn = 1;

INSERT INTO pg.pcms.salaries BY NAME (
  SELECT
    contract_id,
    version_number,
    salary_year,
    total_salary,
    total_salary_adjustment,
    total_base_comp,
    current_base_comp,
    deferred_base_comp,
    signing_bonus,
    likely_bonus,
    unlikely_bonus,
    contract_cap_salary,
    contract_cap_salary_adjustment,
    contract_tax_salary,
    contract_tax_salary_adjustment,
    contract_tax_apron_salary,
    contract_tax_apron_salary_adjustment,
    contract_mts_salary,
    skill_protection_amount,
    trade_bonus_amount,
    trade_bonus_amount_calc,
    cap_raise_percent,
    two_way_nba_salary,
    two_way_dlg_salary,
    wnba_salary,
    wnba_time_off_bonus_amount,
    wnba_merit_bonus_amount,
    wnba_time_off_bonus_days,
    option_lk,
    option_decision_lk,
    is_applicable_min_salary,
    created_at,
    updated_at,
    record_changed_at,
    ingested_at,
  FROM v_salaries_deduped
  WHERE contract_id IS NOT NULL
    AND version_number IS NOT NULL
    AND salary_year IS NOT NULL
)
ON CONFLICT (contract_id, version_number, salary_year) DO UPDATE SET
  total_salary = EXCLUDED.total_salary,
  total_salary_adjustment = EXCLUDED.total_salary_adjustment,
  total_base_comp = EXCLUDED.total_base_comp,
  current_base_comp = EXCLUDED.current_base_comp,
  deferred_base_comp = EXCLUDED.deferred_base_comp,
  signing_bonus = EXCLUDED.signing_bonus,
  likely_bonus = EXCLUDED.likely_bonus,
  unlikely_bonus = EXCLUDED.unlikely_bonus,
  contract_cap_salary = EXCLUDED.contract_cap_salary,
  contract_cap_salary_adjustment = EXCLUDED.contract_cap_salary_adjustment,
  contract_tax_salary = EXCLUDED.contract_tax_salary,
  contract_tax_salary_adjustment = EXCLUDED.contract_tax_salary_adjustment,
  contract_tax_apron_salary = EXCLUDED.contract_tax_apron_salary,
  contract_tax_apron_salary_adjustment = EXCLUDED.contract_tax_apron_salary_adjustment,
  contract_mts_salary = EXCLUDED.contract_mts_salary,
  skill_protection_amount = EXCLUDED.skill_protection_amount,
  trade_bonus_amount = EXCLUDED.trade_bonus_amount,
  trade_bonus_amount_calc = EXCLUDED.trade_bonus_amount_calc,
  cap_raise_percent = EXCLUDED.cap_raise_percent,
  two_way_nba_salary = EXCLUDED.two_way_nba_salary,
  two_way_dlg_salary = EXCLUDED.two_way_dlg_salary,
  wnba_salary = EXCLUDED.wnba_salary,
  wnba_time_off_bonus_amount = EXCLUDED.wnba_time_off_bonus_amount,
  wnba_merit_bonus_amount = EXCLUDED.wnba_merit_bonus_amount,
  wnba_time_off_bonus_days = EXCLUDED.wnba_time_off_bonus_days,
  option_lk = EXCLUDED.option_lk,
  option_decision_lk = EXCLUDED.option_decision_lk,
  is_applicable_min_salary = EXCLUDED.is_applicable_min_salary,
  updated_at = EXCLUDED.updated_at,
  record_changed_at = EXCLUDED.record_changed_at,
  ingested_at = EXCLUDED.ingested_at;

-- ─────────────────────────────────────────────────────────────────────────────
-- payment_schedules (nested under salaries)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TEMP VIEW v_payment_schedules_source AS
WITH v_src AS (
  SELECT
    contract_id,
    version_number,
    salary_year AS salary_year_from_salary,
    salary_json,
  FROM v_salaries_deduped
  WHERE salary_json IS NOT NULL
), v_ps AS (
  SELECT
    *,
    COALESCE(
      json_extract(salary_json, '$.payment_schedules.payment_schedule'),
      json_extract(salary_json, '$.payment_schedules')
    ) AS ps_json,
  FROM v_src
), v_arr AS (
  SELECT
    *,
    CASE
      WHEN ps_json IS NULL THEN json('[]')
      WHEN json_type(ps_json) = 'ARRAY' THEN ps_json
      ELSE json('[' || CAST(ps_json AS VARCHAR) || ']')
    END AS ps_arr,
  FROM v_ps
)
SELECT
  TRY_CAST(COALESCE(ps_item->>'$.contract_payment_schedule_id', ps_item->>'$.payment_schedule_id') AS INTEGER) AS payment_schedule_id,
  contract_id,
  version_number,
  COALESCE(
    TRY_CAST(ps_item->>'$.salary_year' AS INTEGER),
    salary_year_from_salary
  ) AS salary_year,

  TRY_CAST(ps_item->>'$.payment_amount' AS BIGINT) AS payment_amount,
  TRY_CAST(ps_item->>'$.payment_start_date' AS DATE) AS payment_start_date,
  NULLIF(trim(COALESCE(ps_item->>'$.payment_schedule_type_lk', ps_item->>'$.schedule_type_lk')), '') AS schedule_type_lk,
  NULLIF(trim(COALESCE(ps_item->>'$.contract_payment_type_lk', ps_item->>'$.payment_type_lk')), '') AS payment_type_lk,
  TRY_CAST(COALESCE(ps_item->>'$.default_payment_schedule_flg', ps_item->>'$.is_default_schedule') AS BOOLEAN) AS is_default_schedule,

  TRY_CAST(ps_item->>'$.create_date' AS TIMESTAMPTZ) AS created_at,
  TRY_CAST(ps_item->>'$.last_change_date' AS TIMESTAMPTZ) AS updated_at,
  TRY_CAST(ps_item->>'$.record_change_date' AS TIMESTAMPTZ) AS record_changed_at,

  now() AS ingested_at,

  ps_item AS payment_schedule_json,
FROM v_arr,
json_each(v_arr.ps_arr) AS pe(idx, ps_item)
WHERE ps_item IS NOT NULL;

CREATE OR REPLACE TEMP VIEW v_payment_schedules_deduped AS
SELECT * EXCLUDE(rn)
FROM (
  SELECT
    *,
    ROW_NUMBER() OVER (
      PARTITION BY payment_schedule_id
      ORDER BY record_changed_at DESC NULLS LAST, updated_at DESC NULLS LAST, created_at DESC NULLS LAST
    ) AS rn,
  FROM v_payment_schedules_source
)
QUALIFY rn = 1;

INSERT INTO pg.pcms.payment_schedules BY NAME (
  SELECT
    payment_schedule_id,
    contract_id,
    version_number,
    salary_year,
    payment_amount,
    payment_start_date,
    schedule_type_lk,
    payment_type_lk,
    is_default_schedule,
    created_at,
    updated_at,
    record_changed_at,
    ingested_at,
  FROM v_payment_schedules_deduped
  WHERE payment_schedule_id IS NOT NULL
)
ON CONFLICT (payment_schedule_id) DO UPDATE SET
  contract_id = EXCLUDED.contract_id,
  version_number = EXCLUDED.version_number,
  salary_year = EXCLUDED.salary_year,
  payment_amount = EXCLUDED.payment_amount,
  payment_start_date = EXCLUDED.payment_start_date,
  schedule_type_lk = EXCLUDED.schedule_type_lk,
  payment_type_lk = EXCLUDED.payment_type_lk,
  is_default_schedule = EXCLUDED.is_default_schedule,
  updated_at = EXCLUDED.updated_at,
  record_changed_at = EXCLUDED.record_changed_at,
  ingested_at = EXCLUDED.ingested_at;

-- ─────────────────────────────────────────────────────────────────────────────
-- payment_schedule_details (nested under payment_schedules)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TEMP VIEW v_payment_schedule_details_source AS
WITH v_src AS (
  SELECT
    payment_schedule_id,
    payment_schedule_json,
  FROM v_payment_schedules_deduped
  WHERE payment_schedule_json IS NOT NULL AND payment_schedule_id IS NOT NULL
), v_sd AS (
  SELECT
    *,
    COALESCE(
      json_extract(payment_schedule_json, '$.schedule_details.schedule_detail'),
      json_extract(payment_schedule_json, '$.schedule_details')
    ) AS sd_json,
  FROM v_src
), v_arr AS (
  SELECT
    *,
    CASE
      WHEN sd_json IS NULL THEN json('[]')
      WHEN json_type(sd_json) = 'ARRAY' THEN sd_json
      ELSE json('[' || CAST(sd_json AS VARCHAR) || ']')
    END AS sd_arr,
  FROM v_sd
)
SELECT
  TRY_CAST(COALESCE(sd_item->>'$.payment_detail_id', sd_item->>'$.contract_payment_detail_id') AS INTEGER) AS payment_detail_id,
  payment_schedule_id,
  TRY_CAST(sd_item->>'$.payment_date' AS DATE) AS payment_date,
  TRY_CAST(sd_item->>'$.payment_amount' AS BIGINT) AS payment_amount,
  TRY_CAST(sd_item->>'$.number_of_days' AS INTEGER) AS number_of_days,
  NULLIF(trim(sd_item->>'$.payment_type_lk'), '') AS payment_type_lk,
  NULLIF(trim(sd_item->>'$.within_days_lk'), '') AS within_days_lk,
  TRY_CAST(COALESCE(sd_item->>'$.scheduled_flg', sd_item->>'$.is_scheduled') AS BOOLEAN) AS is_scheduled,

  TRY_CAST(sd_item->>'$.create_date' AS TIMESTAMPTZ) AS created_at,
  TRY_CAST(sd_item->>'$.last_change_date' AS TIMESTAMPTZ) AS updated_at,
  TRY_CAST(sd_item->>'$.record_change_date' AS TIMESTAMPTZ) AS record_changed_at,

  now() AS ingested_at,
FROM v_arr,
json_each(v_arr.sd_arr) AS de(idx, sd_item)
WHERE sd_item IS NOT NULL;

CREATE OR REPLACE TEMP VIEW v_payment_schedule_details_deduped AS
SELECT * EXCLUDE(rn)
FROM (
  SELECT
    *,
    ROW_NUMBER() OVER (
      PARTITION BY payment_detail_id
      ORDER BY record_changed_at DESC NULLS LAST, updated_at DESC NULLS LAST, created_at DESC NULLS LAST
    ) AS rn,
  FROM v_payment_schedule_details_source
)
QUALIFY rn = 1;

INSERT INTO pg.pcms.payment_schedule_details BY NAME (
  SELECT
    payment_detail_id,
    payment_schedule_id,
    payment_date,
    payment_amount,
    number_of_days,
    payment_type_lk,
    within_days_lk,
    is_scheduled,
    created_at,
    updated_at,
    record_changed_at,
    ingested_at,
  FROM v_payment_schedule_details_deduped
  WHERE payment_detail_id IS NOT NULL
)
ON CONFLICT (payment_detail_id) DO UPDATE SET
  payment_schedule_id = EXCLUDED.payment_schedule_id,
  payment_date = EXCLUDED.payment_date,
  payment_amount = EXCLUDED.payment_amount,
  number_of_days = EXCLUDED.number_of_days,
  payment_type_lk = EXCLUDED.payment_type_lk,
  within_days_lk = EXCLUDED.within_days_lk,
  is_scheduled = EXCLUDED.is_scheduled,
  updated_at = EXCLUDED.updated_at,
  record_changed_at = EXCLUDED.record_changed_at,
  ingested_at = EXCLUDED.ingested_at;

-- ─────────────────────────────────────────────────────────────────────────────
-- contract_bonuses (nested under contract_versions)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TEMP VIEW v_contract_bonuses_source AS
WITH v_src AS (
  SELECT
    contract_id,
    version_number,
    to_json(v) AS v_json,
  FROM v_contract_versions_deduped AS v
  WHERE contract_id IS NOT NULL AND version_number IS NOT NULL
), v_b AS (
  SELECT
    *,
    COALESCE(
      json_extract(v_json, '$.bonuses.bonus'),
      json_extract(v_json, '$.bonuses')
    ) AS bonuses_json,
  FROM v_src
), v_arr AS (
  SELECT
    *,
    CASE
      WHEN bonuses_json IS NULL THEN json('[]')
      WHEN json_type(bonuses_json) = 'ARRAY' THEN bonuses_json
      ELSE json('[' || CAST(bonuses_json AS VARCHAR) || ']')
    END AS bonuses_arr,
  FROM v_b
)
SELECT
  TRY_CAST(b_json->>'$.bonus_id' AS INTEGER) AS bonus_id,
  contract_id,
  version_number,
  TRY_CAST(COALESCE(b_json->>'$.bonus_year', b_json->>'$.salary_year') AS INTEGER) AS salary_year,
  TRY_CAST(b_json->>'$.bonus_amount' AS BIGINT) AS bonus_amount,
  NULLIF(trim(COALESCE(b_json->>'$.contract_bonus_type_lk', b_json->>'$.bonus_type_lk')), '') AS bonus_type_lk,
  TRY_CAST(COALESCE(b_json->>'$.bonus_likely_flg', b_json->>'$.is_likely') AS BOOLEAN) AS is_likely,
  NULLIF(trim(b_json->>'$.earned_lk'), '') AS earned_lk,
  TRY_CAST(COALESCE(b_json->>'$.bonus_paid_by_date', b_json->>'$.paid_by_date') AS DATE) AS paid_by_date,
  NULLIF(trim(b_json->>'$.clause_name'), '') AS clause_name,
  NULLIF(trim(b_json->>'$.criteria_description'), '') AS criteria_description,
  COALESCE(json_extract(b_json, '$.bonus_criteria'), json_extract(b_json, '$.criteria_json')) AS criteria_json,
  now() AS ingested_at,

  -- keep for downstream criteria extraction
  b_json AS bonus_json,
FROM v_arr,
json_each(v_arr.bonuses_arr) AS be(idx, b_json)
WHERE b_json IS NOT NULL;

CREATE OR REPLACE TEMP VIEW v_contract_bonuses_deduped AS
SELECT * EXCLUDE(rn)
FROM (
  SELECT
    *,
    ROW_NUMBER() OVER (
      PARTITION BY bonus_id
      ORDER BY salary_year DESC NULLS LAST
    ) AS rn,
  FROM v_contract_bonuses_source
)
QUALIFY rn = 1;

INSERT INTO pg.pcms.contract_bonuses BY NAME (
  SELECT
    bonus_id,
    contract_id,
    version_number,
    salary_year,
    bonus_amount,
    bonus_type_lk,
    is_likely,
    earned_lk,
    paid_by_date,
    clause_name,
    criteria_description,
    criteria_json,
    ingested_at,
  FROM v_contract_bonuses_deduped
  WHERE bonus_id IS NOT NULL
)
ON CONFLICT (bonus_id) DO UPDATE SET
  contract_id = EXCLUDED.contract_id,
  version_number = EXCLUDED.version_number,
  salary_year = EXCLUDED.salary_year,
  bonus_amount = EXCLUDED.bonus_amount,
  bonus_type_lk = EXCLUDED.bonus_type_lk,
  is_likely = EXCLUDED.is_likely,
  earned_lk = EXCLUDED.earned_lk,
  paid_by_date = EXCLUDED.paid_by_date,
  clause_name = EXCLUDED.clause_name,
  criteria_description = EXCLUDED.criteria_description,
  criteria_json = EXCLUDED.criteria_json,
  ingested_at = EXCLUDED.ingested_at;

-- ─────────────────────────────────────────────────────────────────────────────
-- contract_bonus_criteria (nested under contract_bonuses)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TEMP VIEW v_contract_bonus_criteria_source AS
WITH v_src AS (
  SELECT
    bonus_id,
    bonus_json,
    COALESCE(
      json_extract(bonus_json, '$.bonus_criteria.bonus_criterion'),
      json_extract(bonus_json, '$.bonus_criteria')
    ) AS criteria_json,
  FROM v_contract_bonuses_deduped
  WHERE bonus_id IS NOT NULL AND bonus_json IS NOT NULL
), v_arr AS (
  SELECT
    *,
    CASE
      WHEN criteria_json IS NULL THEN json('[]')
      WHEN json_type(criteria_json) = 'ARRAY' THEN criteria_json
      ELSE json('[' || CAST(criteria_json AS VARCHAR) || ']')
    END AS criteria_arr,
  FROM v_src
)
SELECT
  TRY_CAST(COALESCE(c_json->>'$.bonus_criteria_id', c_json->>'$.bonus_criterion_id', c_json->>'$.criteria_id') AS INTEGER) AS bonus_criteria_id,
  bonus_id,
  NULLIF(trim(COALESCE(c_json->>'$.criteria_lk', c_json->>'$.criterion_lk')), '') AS criteria_lk,
  NULLIF(trim(COALESCE(c_json->>'$.criteria_operator_lk', c_json->>'$.operator_lk', c_json->>'$.criteria_operator')), '') AS criteria_operator_lk,
  NULLIF(trim(c_json->>'$.modifier_lk'), '') AS modifier_lk,
  NULLIF(trim(c_json->>'$.season_type_lk'), '') AS season_type_lk,
  TRY_CAST(COALESCE(c_json->>'$.player_criteria_flg', c_json->>'$.is_player_criteria') AS BOOLEAN) AS is_player_criteria,
  TRY_CAST(COALESCE(c_json->>'$.team_criteria_flg', c_json->>'$.is_team_criteria') AS BOOLEAN) AS is_team_criteria,
  TRY_CAST(c_json->>'$.value_1' AS DOUBLE) AS value_1,
  TRY_CAST(c_json->>'$.value_2' AS DOUBLE) AS value_2,
  TRY_CAST(c_json->>'$.date_1' AS DATE) AS date_1,
  TRY_CAST(c_json->>'$.date_2' AS DATE) AS date_2,
  now() AS ingested_at,
FROM v_arr,
json_each(v_arr.criteria_arr) AS ce(idx, c_json)
WHERE c_json IS NOT NULL;

CREATE OR REPLACE TEMP VIEW v_contract_bonus_criteria_deduped AS
SELECT * EXCLUDE(rn)
FROM (
  SELECT
    *,
    ROW_NUMBER() OVER (
      PARTITION BY bonus_criteria_id
      ORDER BY bonus_id DESC
    ) AS rn,
  FROM v_contract_bonus_criteria_source
)
QUALIFY rn = 1;

INSERT INTO pg.pcms.contract_bonus_criteria BY NAME (
  SELECT
    bonus_criteria_id,
    bonus_id,
    criteria_lk,
    criteria_operator_lk,
    modifier_lk,
    season_type_lk,
    is_player_criteria,
    is_team_criteria,
    value_1,
    value_2,
    date_1,
    date_2,
    ingested_at,
  FROM v_contract_bonus_criteria_deduped
  WHERE bonus_criteria_id IS NOT NULL
)
ON CONFLICT (bonus_criteria_id) DO UPDATE SET
  bonus_id = EXCLUDED.bonus_id,
  criteria_lk = EXCLUDED.criteria_lk,
  criteria_operator_lk = EXCLUDED.criteria_operator_lk,
  modifier_lk = EXCLUDED.modifier_lk,
  season_type_lk = EXCLUDED.season_type_lk,
  is_player_criteria = EXCLUDED.is_player_criteria,
  is_team_criteria = EXCLUDED.is_team_criteria,
  value_1 = EXCLUDED.value_1,
  value_2 = EXCLUDED.value_2,
  date_1 = EXCLUDED.date_1,
  date_2 = EXCLUDED.date_2,
  ingested_at = EXCLUDED.ingested_at;

-- ─────────────────────────────────────────────────────────────────────────────
-- contract_bonus_maximums (nested under salaries)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TEMP VIEW v_contract_bonus_maximums_source AS
WITH v_src AS (
  SELECT
    contract_id,
    version_number,
    salary_year,
    salary_json,
    COALESCE(
      json_extract(salary_json, '$.bonus_maximums.bonus_maximum'),
      json_extract(salary_json, '$.bonus_maximums')
    ) AS max_json,
  FROM v_salaries_deduped
  WHERE salary_json IS NOT NULL
), v_arr AS (
  SELECT
    *,
    CASE
      WHEN max_json IS NULL THEN json('[]')
      WHEN json_type(max_json) = 'ARRAY' THEN max_json
      ELSE json('[' || CAST(max_json AS VARCHAR) || ']')
    END AS max_arr,
  FROM v_src
)
SELECT
  TRY_CAST(COALESCE(m_json->>'$.bonus_max_id', m_json->>'$.bonus_maximum_id') AS INTEGER) AS bonus_max_id,
  contract_id,
  version_number,
  salary_year,
  TRY_CAST(COALESCE(m_json->>'$.max_amount', m_json->>'$.maximum_amount', m_json->>'$.bonus_max_amount') AS BIGINT) AS max_amount,
  NULLIF(trim(COALESCE(m_json->>'$.bonus_type_lk', m_json->>'$.contract_bonus_type_lk')), '') AS bonus_type_lk,
  TRY_CAST(COALESCE(m_json->>'$.bonus_likely_flg', m_json->>'$.is_likely') AS BOOLEAN) AS is_likely,
  now() AS ingested_at,
FROM v_arr,
json_each(v_arr.max_arr) AS me(idx, m_json)
WHERE m_json IS NOT NULL;

CREATE OR REPLACE TEMP VIEW v_contract_bonus_maximums_deduped AS
SELECT * EXCLUDE(rn)
FROM (
  SELECT
    *,
    ROW_NUMBER() OVER (
      PARTITION BY bonus_max_id
      ORDER BY salary_year DESC NULLS LAST
    ) AS rn,
  FROM v_contract_bonus_maximums_source
)
QUALIFY rn = 1;

INSERT INTO pg.pcms.contract_bonus_maximums BY NAME (
  SELECT
    bonus_max_id,
    contract_id,
    version_number,
    salary_year,
    max_amount,
    bonus_type_lk,
    is_likely,
    ingested_at,
  FROM v_contract_bonus_maximums_deduped
  WHERE bonus_max_id IS NOT NULL
)
ON CONFLICT (bonus_max_id) DO UPDATE SET
  contract_id = EXCLUDED.contract_id,
  version_number = EXCLUDED.version_number,
  salary_year = EXCLUDED.salary_year,
  max_amount = EXCLUDED.max_amount,
  bonus_type_lk = EXCLUDED.bonus_type_lk,
  is_likely = EXCLUDED.is_likely,
  ingested_at = EXCLUDED.ingested_at;

-- ─────────────────────────────────────────────────────────────────────────────
-- contract_protections (nested under contract_versions)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TEMP VIEW v_contract_protections_source AS
WITH v_src AS (
  SELECT
    contract_id,
    version_number,
    to_json(v) AS v_json,
    COALESCE(
      json_extract(to_json(v), '$.protections.protection'),
      json_extract(to_json(v), '$.protections')
    ) AS protections_json,
  FROM v_contract_versions_deduped AS v
  WHERE contract_id IS NOT NULL AND version_number IS NOT NULL
), v_arr AS (
  SELECT
    *,
    CASE
      WHEN protections_json IS NULL THEN json('[]')
      WHEN json_type(protections_json) = 'ARRAY' THEN protections_json
      ELSE json('[' || CAST(protections_json AS VARCHAR) || ']')
    END AS protections_arr,
  FROM v_src
)
SELECT
  TRY_CAST(COALESCE(p_json->>'$.protection_id', p_json->>'$.contract_protection_id') AS INTEGER) AS protection_id,
  contract_id,
  version_number,
  TRY_CAST(COALESCE(p_json->>'$.salary_year', p_json->>'$.protection_year') AS INTEGER) AS salary_year,
  TRY_CAST(COALESCE(p_json->>'$.protection_amount', p_json->>'$.amount') AS BIGINT) AS protection_amount,
  TRY_CAST(p_json->>'$.effective_protection_amount' AS BIGINT) AS effective_protection_amount,
  NULLIF(trim(p_json->>'$.protection_coverage_lk'), '') AS protection_coverage_lk,
  TRY_CAST(COALESCE(p_json->>'$.conditional_protection_flg', p_json->>'$.is_conditional_protection') AS BOOLEAN) AS is_conditional_protection,
  NULLIF(trim(COALESCE(p_json->>'$.conditional_protection_comments', p_json->>'$.conditional_comments')), '') AS conditional_protection_comments,
  COALESCE(
    json_extract(p_json, '$.protection_types'),
    json_extract(p_json, '$.protection_types_json')
  ) AS protection_types_json,
  now() AS ingested_at,

  p_json AS protection_json,
FROM v_arr,
json_each(v_arr.protections_arr) AS pe(idx, p_json)
WHERE p_json IS NOT NULL;

CREATE OR REPLACE TEMP VIEW v_contract_protections_deduped AS
SELECT * EXCLUDE(rn)
FROM (
  SELECT
    *,
    ROW_NUMBER() OVER (
      PARTITION BY protection_id
      ORDER BY salary_year DESC NULLS LAST
    ) AS rn,
  FROM v_contract_protections_source
)
QUALIFY rn = 1;

INSERT INTO pg.pcms.contract_protections BY NAME (
  SELECT
    protection_id,
    contract_id,
    version_number,
    salary_year,
    protection_amount,
    effective_protection_amount,
    protection_coverage_lk,
    is_conditional_protection,
    conditional_protection_comments,
    protection_types_json,
    ingested_at,
  FROM v_contract_protections_deduped
  WHERE protection_id IS NOT NULL
)
ON CONFLICT (protection_id) DO UPDATE SET
  contract_id = EXCLUDED.contract_id,
  version_number = EXCLUDED.version_number,
  salary_year = EXCLUDED.salary_year,
  protection_amount = EXCLUDED.protection_amount,
  effective_protection_amount = EXCLUDED.effective_protection_amount,
  protection_coverage_lk = EXCLUDED.protection_coverage_lk,
  is_conditional_protection = EXCLUDED.is_conditional_protection,
  conditional_protection_comments = EXCLUDED.conditional_protection_comments,
  protection_types_json = EXCLUDED.protection_types_json,
  ingested_at = EXCLUDED.ingested_at;

-- ─────────────────────────────────────────────────────────────────────────────
-- contract_protection_conditions (nested under contract_protections)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TEMP VIEW v_contract_protection_conditions_source AS
WITH v_src AS (
  SELECT
    protection_id,
    protection_json,
    COALESCE(
      json_extract(protection_json, '$.protection_conditions.protection_condition'),
      json_extract(protection_json, '$.protection_conditions')
    ) AS cond_json,
  FROM v_contract_protections_deduped
  WHERE protection_id IS NOT NULL AND protection_json IS NOT NULL
), v_arr AS (
  SELECT
    *,
    CASE
      WHEN cond_json IS NULL THEN json('[]')
      WHEN json_type(cond_json) = 'ARRAY' THEN cond_json
      ELSE json('[' || CAST(cond_json AS VARCHAR) || ']')
    END AS cond_arr,
  FROM v_src
)
SELECT
  TRY_CAST(COALESCE(c_json->>'$.condition_id', c_json->>'$.protection_condition_id') AS INTEGER) AS condition_id,
  protection_id,
  TRY_CAST(c_json->>'$.amount' AS BIGINT) AS amount,
  NULLIF(trim(c_json->>'$.clause_name'), '') AS clause_name,
  TRY_CAST(c_json->>'$.earned_date' AS DATE) AS earned_date,
  NULLIF(trim(c_json->>'$.earned_type_lk'), '') AS earned_type_lk,
  TRY_CAST(COALESCE(c_json->>'$.full_condition_flg', c_json->>'$.is_full_condition') AS BOOLEAN) AS is_full_condition,
  NULLIF(trim(c_json->>'$.criteria_description'), '') AS criteria_description,
  COALESCE(
    json_extract(c_json, '$.criteria_json'),
    json_extract(c_json, '$.criteria')
  ) AS criteria_json,
  now() AS ingested_at,
FROM v_arr,
json_each(v_arr.cond_arr) AS ce(idx, c_json)
WHERE c_json IS NOT NULL;

CREATE OR REPLACE TEMP VIEW v_contract_protection_conditions_deduped AS
SELECT * EXCLUDE(rn)
FROM (
  SELECT
    *,
    ROW_NUMBER() OVER (
      PARTITION BY condition_id
      ORDER BY protection_id DESC
    ) AS rn,
  FROM v_contract_protection_conditions_source
)
QUALIFY rn = 1;

INSERT INTO pg.pcms.contract_protection_conditions BY NAME (
  SELECT
    condition_id,
    protection_id,
    amount,
    clause_name,
    earned_date,
    earned_type_lk,
    is_full_condition,
    criteria_description,
    criteria_json,
    ingested_at,
  FROM v_contract_protection_conditions_deduped
  WHERE condition_id IS NOT NULL
)
ON CONFLICT (condition_id) DO UPDATE SET
  protection_id = EXCLUDED.protection_id,
  amount = EXCLUDED.amount,
  clause_name = EXCLUDED.clause_name,
  earned_date = EXCLUDED.earned_date,
  earned_type_lk = EXCLUDED.earned_type_lk,
  is_full_condition = EXCLUDED.is_full_condition,
  criteria_description = EXCLUDED.criteria_description,
  criteria_json = EXCLUDED.criteria_json,
  ingested_at = EXCLUDED.ingested_at;

-- 5) Summary
SELECT
  'contracts' AS step,
  (SELECT count(*) FROM v_contracts_deduped) AS contracts_rows_upserted,
  (SELECT count(*) FROM v_contract_versions_deduped) AS contract_versions_rows_upserted,
  (SELECT count(*) FROM v_salaries_deduped) AS salaries_rows_upserted,
  (SELECT count(*) FROM v_contract_bonuses_deduped) AS contract_bonuses_rows_upserted,
  (SELECT count(*) FROM v_contract_bonus_criteria_deduped) AS contract_bonus_criteria_rows_upserted,
  (SELECT count(*) FROM v_contract_bonus_maximums_deduped) AS contract_bonus_maximums_rows_upserted,
  (SELECT count(*) FROM v_contract_protections_deduped) AS contract_protections_rows_upserted,
  (SELECT count(*) FROM v_contract_protection_conditions_deduped) AS contract_protection_conditions_rows_upserted,
  (SELECT count(*) FROM v_payment_schedules_deduped) AS payment_schedules_rows_upserted,
  (SELECT count(*) FROM v_payment_schedule_details_deduped) AS payment_schedule_details_rows_upserted,
  now() AS finished_at,
; 
