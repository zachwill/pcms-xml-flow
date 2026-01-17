-- result_collection=last_statement_all_rows

ATTACH '$res:f/env/postgres' AS pg (TYPE postgres);
SET TimeZone='UTC';

--
-- team_exceptions.inline_script.duckdb.sql
--
-- Imports (upserts) from team_exceptions.json (nested + some hyphenated keys):
--   - pg.pcms.team_exceptions
--   - pg.pcms.team_exception_usage
--
-- Source files (hard-coded):
--   ./shared/pcms/nba_pcms_full_extract/team_exceptions.json
--   ./shared/pcms/nba_pcms_full_extract/lookups.json
--
-- Notes:
--   - This extract is not a simple array; it's a JSON object with exception_team[]
--   - Nested nodes are sometimes arrays or single objects; we defensively
--     "force" them into arrays before json_each().
--   - Hyphenated keys are handled via JSONPath (e.g. $."team-exceptions")
--   - Deduplication with QUALIFY is mandatory prior to each Postgres upsert.
--

-- 1) Team lookup (reused)
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

-- 2) Read team_exceptions.json root as a single JSON object
CREATE OR REPLACE TEMP VIEW v_team_exceptions_root AS
SELECT
  to_json(r) AS root_json,
FROM read_json_auto('./shared/pcms/nba_pcms_full_extract/team_exceptions.json') AS r;

-- 3) exception_team[] (one row per team)
CREATE OR REPLACE TEMP VIEW v_exception_team_json AS
WITH v_src AS (
  SELECT
    json_extract(root_json, '$.exception_team') AS exception_team_json,
  FROM v_team_exceptions_root
), v_arr AS (
  SELECT
    CASE
      WHEN exception_team_json IS NULL THEN json('[]')
      WHEN json_type(exception_team_json) = 'ARRAY' THEN exception_team_json
      ELSE json('[' || CAST(exception_team_json AS VARCHAR) || ']')
    END AS exception_team_arr,
  FROM v_src
)
SELECT
  et.value AS et_json,
FROM v_arr,
json_each(exception_team_arr) AS et;

-- 4) team-exceptions.team-exception[] (one row per team exception)
CREATE OR REPLACE TEMP VIEW v_team_exception_json AS
WITH v_src AS (
  SELECT
    TRY_CAST(et_json->>'$.team_id' AS INTEGER) AS team_id,
    et_json,
    COALESCE(
      json_extract(et_json, '$."team-exceptions"."team-exception"'),
      json_extract(et_json, '$."team-exceptions"'),
      json_extract(et_json, '$.team_exceptions'),
      json_extract(et_json, '$.team_exception')
    ) AS team_exceptions_json,
  FROM v_exception_team_json
), v_arr AS (
  SELECT
    *,
    CASE
      WHEN team_exceptions_json IS NULL THEN json('[]')
      WHEN json_type(team_exceptions_json) = 'ARRAY' THEN team_exceptions_json
      ELSE json('[' || CAST(team_exceptions_json AS VARCHAR) || ']')
    END AS team_exceptions_arr,
  FROM v_src
)
SELECT
  team_id,
  te.value AS te_json,
FROM v_arr,
json_each(team_exceptions_arr) AS te;

-- ─────────────────────────────────────────────────────────────────────────────
-- team_exceptions
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TEMP VIEW v_team_exceptions_source AS
SELECT
  TRY_CAST(te_json->>'$.team_exception_id' AS INTEGER) AS team_exception_id,
  team_id,
  teams.team_code AS team_code,

  TRY_CAST(COALESCE(te_json->>'$.team_exception_year', te_json->>'$.salary_year') AS INTEGER) AS salary_year,
  NULLIF(trim(te_json->>'$.exception_type_lk'), '') AS exception_type_lk,
  TRY_CAST(te_json->>'$.effective_date' AS DATE) AS effective_date,
  TRY_CAST(te_json->>'$.expiration_date' AS DATE) AS expiration_date,

  TRY_CAST(te_json->>'$.original_amount' AS BIGINT) AS original_amount,
  TRY_CAST(te_json->>'$.remaining_amount' AS BIGINT) AS remaining_amount,
  TRY_CAST(te_json->>'$.proration_rate' AS DECIMAL(18,6)) AS proration_rate,

  TRY_CAST(te_json->>'$.initially_convertible_flg' AS BOOLEAN) AS is_initially_convertible,
  TRY_CAST(te_json->>'$.trade_exception_player_id' AS INTEGER) AS trade_exception_player_id,
  TRY_CAST(te_json->>'$.trade_id' AS INTEGER) AS trade_id,

  NULLIF(trim(te_json->>'$.record_status_lk'), '') AS record_status_lk,

  TRY_CAST(te_json->>'$.create_date' AS TIMESTAMPTZ) AS created_at,
  TRY_CAST(te_json->>'$.last_change_date' AS TIMESTAMPTZ) AS updated_at,
  TRY_CAST(te_json->>'$.record_change_date' AS TIMESTAMPTZ) AS record_changed_at,

  now() AS ingested_at,
FROM v_team_exception_json
LEFT JOIN v_teams AS teams
  ON teams.team_id = team_id::BIGINT
WHERE te_json->>'$.team_exception_id' IS NOT NULL;

CREATE OR REPLACE TEMP VIEW v_team_exceptions_deduped AS
SELECT * EXCLUDE (rn)
FROM (
  SELECT
    *,
    ROW_NUMBER() OVER (
      PARTITION BY team_exception_id
      ORDER BY record_changed_at DESC NULLS LAST, updated_at DESC NULLS LAST, created_at DESC NULLS LAST
    ) AS rn,
  FROM v_team_exceptions_source
)
QUALIFY rn = 1;

INSERT INTO pg.pcms.team_exceptions BY NAME (
  SELECT * FROM v_team_exceptions_deduped
)
ON CONFLICT (team_exception_id) DO UPDATE SET
  team_id = EXCLUDED.team_id,
  team_code = EXCLUDED.team_code,
  salary_year = EXCLUDED.salary_year,
  exception_type_lk = EXCLUDED.exception_type_lk,
  effective_date = EXCLUDED.effective_date,
  expiration_date = EXCLUDED.expiration_date,
  original_amount = EXCLUDED.original_amount,
  remaining_amount = EXCLUDED.remaining_amount,
  proration_rate = EXCLUDED.proration_rate,
  is_initially_convertible = EXCLUDED.is_initially_convertible,
  trade_exception_player_id = EXCLUDED.trade_exception_player_id,
  trade_id = EXCLUDED.trade_id,
  record_status_lk = EXCLUDED.record_status_lk,
  updated_at = EXCLUDED.updated_at,
  record_changed_at = EXCLUDED.record_changed_at,
  ingested_at = EXCLUDED.ingested_at;

-- ─────────────────────────────────────────────────────────────────────────────
-- team_exception_usage
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TEMP VIEW v_team_exception_detail_json AS
WITH v_src AS (
  SELECT
    TRY_CAST(te_json->>'$.team_exception_id' AS INTEGER) AS team_exception_id,
    COALESCE(
      json_extract(te_json, '$.exception_details.exception_detail'),
      json_extract(te_json, '$.exception_details'),
      json_extract(te_json, '$.exception_detail')
    ) AS details_json,
  FROM v_team_exception_json
  WHERE te_json->>'$.team_exception_id' IS NOT NULL
), v_arr AS (
  SELECT
    *,
    CASE
      WHEN details_json IS NULL THEN json('[]')
      WHEN json_type(details_json) = 'ARRAY' THEN details_json
      ELSE json('[' || CAST(details_json AS VARCHAR) || ']')
    END AS details_arr,
  FROM v_src
)
SELECT
  team_exception_id,
  d.value AS detail_json,
FROM v_arr,
json_each(details_arr) AS d;

CREATE OR REPLACE TEMP VIEW v_team_exception_usage_source AS
SELECT
  TRY_CAST(detail_json->>'$.team_exception_detail_id' AS INTEGER) AS team_exception_detail_id,
  team_exception_id,

  TRY_CAST(detail_json->>'$.seqno' AS INTEGER) AS seqno,
  TRY_CAST(detail_json->>'$.effective_date' AS DATE) AS effective_date,
  NULLIF(trim(detail_json->>'$.exception_action_lk'), '') AS exception_action_lk,
  NULLIF(trim(detail_json->>'$.transaction_type_lk'), '') AS transaction_type_lk,

  TRY_CAST(detail_json->>'$.transaction_id' AS INTEGER) AS transaction_id,
  TRY_CAST(detail_json->>'$.player_id' AS INTEGER) AS player_id,
  TRY_CAST(detail_json->>'$.contract_id' AS INTEGER) AS contract_id,

  TRY_CAST(detail_json->>'$.change_amount' AS BIGINT) AS change_amount,
  TRY_CAST(detail_json->>'$.remaining_exception_amount' AS BIGINT) AS remaining_exception_amount,
  TRY_CAST(detail_json->>'$.proration_rate' AS DECIMAL(18,6)) AS proration_rate,
  TRY_CAST(detail_json->>'$.prorate_days' AS DECIMAL(18,6)) AS prorate_days,

  TRY_CAST(detail_json->>'$.convert_exception_flg' AS BOOLEAN) AS is_convert_exception,
  NULLIF(trim(detail_json->>'$.manual_action_text'), '') AS manual_action_text,

  TRY_CAST(detail_json->>'$.create_date' AS TIMESTAMPTZ) AS created_at,
  TRY_CAST(detail_json->>'$.last_change_date' AS TIMESTAMPTZ) AS updated_at,
  TRY_CAST(detail_json->>'$.record_change_date' AS TIMESTAMPTZ) AS record_changed_at,

  now() AS ingested_at,
FROM v_team_exception_detail_json
WHERE detail_json->>'$.team_exception_detail_id' IS NOT NULL;

CREATE OR REPLACE TEMP VIEW v_team_exception_usage_deduped AS
SELECT * EXCLUDE (rn)
FROM (
  SELECT
    *,
    ROW_NUMBER() OVER (
      PARTITION BY team_exception_detail_id
      ORDER BY record_changed_at DESC NULLS LAST, updated_at DESC NULLS LAST, created_at DESC NULLS LAST
    ) AS rn,
  FROM v_team_exception_usage_source
)
QUALIFY rn = 1;

INSERT INTO pg.pcms.team_exception_usage BY NAME (
  SELECT * FROM v_team_exception_usage_deduped
)
ON CONFLICT (team_exception_detail_id) DO UPDATE SET
  team_exception_id = EXCLUDED.team_exception_id,
  seqno = EXCLUDED.seqno,
  effective_date = EXCLUDED.effective_date,
  exception_action_lk = EXCLUDED.exception_action_lk,
  transaction_type_lk = EXCLUDED.transaction_type_lk,
  transaction_id = EXCLUDED.transaction_id,
  player_id = EXCLUDED.player_id,
  contract_id = EXCLUDED.contract_id,
  change_amount = EXCLUDED.change_amount,
  remaining_exception_amount = EXCLUDED.remaining_exception_amount,
  proration_rate = EXCLUDED.proration_rate,
  prorate_days = EXCLUDED.prorate_days,
  is_convert_exception = EXCLUDED.is_convert_exception,
  manual_action_text = EXCLUDED.manual_action_text,
  updated_at = EXCLUDED.updated_at,
  record_changed_at = EXCLUDED.record_changed_at,
  ingested_at = EXCLUDED.ingested_at;

-- 5) Return summary
SELECT
  'team_exceptions' AS step,
  (SELECT count(*) FROM v_team_exceptions_deduped) AS team_exceptions_upserted,
  (SELECT count(*) FROM v_team_exception_usage_deduped) AS team_exception_usage_upserted,
  now() AS finished_at;
