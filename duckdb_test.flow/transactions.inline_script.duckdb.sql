-- result_collection=last_statement_all_rows

ATTACH '$res:f/env/postgres' AS pg (TYPE postgres);
SET TimeZone='UTC';

--
-- transactions.inline_script.duckdb.sql
--
-- Imports (upserts):
--   - pg.pcms.trades
--   - pg.pcms.trade_teams
--   - pg.pcms.trade_team_details
--   - pg.pcms.trade_groups
--   - pg.pcms.transactions
--   - pg.pcms.ledger_entries
--   - pg.pcms.transaction_waiver_amounts
--
-- Source files (hard-coded):
--   ./shared/pcms/nba_pcms_full_extract/lookups.json
--   ./shared/pcms/nba_pcms_full_extract/trades.json
--   ./shared/pcms/nba_pcms_full_extract/transactions.json
--   ./shared/pcms/nba_pcms_full_extract/ledger.json
--   ./shared/pcms/nba_pcms_full_extract/transaction_waiver_amounts.json
--
-- Notes:
--   - Deduplication with QUALIFY is mandatory prior to each Postgres upsert.
--   - Trade-related tables use synthetic text primary keys (same as the TS importer):
--       trade_team_id        = trade_id || '_' || team_id
--       trade_team_detail_id = trade_id || '_' || team_id || '_' || seqno
--       trade_group_id       = trade_id || '_' || team_id || '_' || trade_group_number
--   - Version numbers can be decimals (e.g. 1.01) and must be normalized to integers (101).
--   - Ledger PKs are NUMERIC in Postgres; cast to DECIMAL(38,0) (not INTEGER).
--   - Ledger has a handful of rows with null team_id; filter them out.
--

-- 1) Team lookup (reused for team_code joins)
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

-- ─────────────────────────────────────────────────────────────────────────────
-- Trades (trades.json)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TEMP VIEW v_trade_json AS
SELECT
  to_json(t) AS trade_json,
FROM read_json_auto('./shared/pcms/nba_pcms_full_extract/trades.json') AS t;

-- trades
CREATE OR REPLACE TEMP VIEW v_trades_source AS
SELECT
  TRY_CAST(trade_json->>'$.trade_id' AS INTEGER) AS trade_id,
  TRY_CAST(trade_json->>'$.trade_date' AS DATE) AS trade_date,
  TRY_CAST(trade_json->>'$.trade_finalized_date' AS DATE) AS trade_finalized_date,
  NULLIF(trim(trade_json->>'$.league_lk'), '') AS league_lk,
  NULLIF(trim(trade_json->>'$.record_status_lk'), '') AS record_status_lk,
  NULLIF(trim(trade_json->>'$.trade_comments'), '') AS trade_comments,
  TRY_CAST(trade_json->>'$.create_date' AS TIMESTAMPTZ) AS created_at,
  TRY_CAST(trade_json->>'$.last_change_date' AS TIMESTAMPTZ) AS updated_at,
  TRY_CAST(trade_json->>'$.record_change_date' AS TIMESTAMPTZ) AS record_changed_at,
  now() AS ingested_at,
FROM v_trade_json
WHERE trade_json->>'$.trade_id' IS NOT NULL;

CREATE OR REPLACE TEMP VIEW v_trades_deduped AS
SELECT * EXCLUDE (rn)
FROM (
  SELECT
    *,
    ROW_NUMBER() OVER (
      PARTITION BY trade_id
      ORDER BY record_changed_at DESC NULLS LAST, updated_at DESC NULLS LAST, created_at DESC NULLS LAST
    ) AS rn,
  FROM v_trades_source
)
QUALIFY rn = 1;

INSERT INTO pg.pcms.trades BY NAME (
  SELECT * FROM v_trades_deduped
)
ON CONFLICT (trade_id) DO UPDATE SET
  trade_date = EXCLUDED.trade_date,
  trade_finalized_date = EXCLUDED.trade_finalized_date,
  league_lk = EXCLUDED.league_lk,
  record_status_lk = EXCLUDED.record_status_lk,
  trade_comments = EXCLUDED.trade_comments,
  updated_at = EXCLUDED.updated_at,
  record_changed_at = EXCLUDED.record_changed_at,
  ingested_at = EXCLUDED.ingested_at;

-- trade_teams
CREATE OR REPLACE TEMP VIEW v_trade_team_json AS
WITH v_src AS (
  SELECT
    TRY_CAST(trade_json->>'$.trade_id' AS INTEGER) AS trade_id,
    json_extract(trade_json, '$.trade_teams.trade_team') AS teams_json,
  FROM v_trade_json
  WHERE trade_json->>'$.trade_id' IS NOT NULL
), v_arr AS (
  SELECT
    trade_id,
    CASE
      WHEN teams_json IS NULL THEN json('[]')
      WHEN json_type(teams_json) = 'ARRAY' THEN teams_json
      ELSE json('[' || CAST(teams_json AS VARCHAR) || ']')
    END AS teams_arr,
  FROM v_src
)
SELECT
  trade_id,
  tt.value AS tt_json,
FROM v_arr,
json_each(teams_arr) AS tt;

CREATE OR REPLACE TEMP VIEW v_trade_teams_source AS
SELECT
  concat_ws('_', CAST(trade_id AS VARCHAR), CAST(TRY_CAST(tt_json->>'$.team_id' AS INTEGER) AS VARCHAR)) AS trade_team_id,
  trade_id,
  TRY_CAST(tt_json->>'$.team_id' AS INTEGER) AS team_id,
  teams.team_code AS team_code,
  TRY_CAST(tt_json->>'$.team_salary_change' AS BIGINT) AS team_salary_change,
  TRY_CAST(tt_json->>'$.total_cash_received' AS BIGINT) AS total_cash_received,
  TRY_CAST(tt_json->>'$.total_cash_sent' AS BIGINT) AS total_cash_sent,
  TRY_CAST(tt_json->>'$.seqno' AS INTEGER) AS seqno,
  now() AS ingested_at,
FROM v_trade_team_json
LEFT JOIN v_teams AS teams
  ON teams.team_id = TRY_CAST(tt_json->>'$.team_id' AS BIGINT)
WHERE tt_json->>'$.team_id' IS NOT NULL;

CREATE OR REPLACE TEMP VIEW v_trade_teams_deduped AS
SELECT * EXCLUDE (rn)
FROM (
  SELECT
    *,
    ROW_NUMBER() OVER (
      PARTITION BY trade_team_id
      ORDER BY seqno DESC NULLS LAST
    ) AS rn,
  FROM v_trade_teams_source
)
QUALIFY rn = 1;

INSERT INTO pg.pcms.trade_teams BY NAME (
  SELECT * FROM v_trade_teams_deduped
)
ON CONFLICT (trade_team_id) DO UPDATE SET
  trade_id = EXCLUDED.trade_id,
  team_id = EXCLUDED.team_id,
  team_code = EXCLUDED.team_code,
  team_salary_change = EXCLUDED.team_salary_change,
  total_cash_received = EXCLUDED.total_cash_received,
  total_cash_sent = EXCLUDED.total_cash_sent,
  seqno = EXCLUDED.seqno,
  ingested_at = EXCLUDED.ingested_at;

-- trade_team_details
CREATE OR REPLACE TEMP VIEW v_trade_team_detail_json AS
WITH v_src AS (
  SELECT
    trade_id,
    TRY_CAST(tt_json->>'$.team_id' AS INTEGER) AS team_id,
    json_extract(tt_json, '$.trade_team_details.trade_team_detail') AS details_json,
  FROM v_trade_team_json
  WHERE tt_json->>'$.team_id' IS NOT NULL
), v_arr AS (
  SELECT
    trade_id,
    team_id,
    CASE
      WHEN details_json IS NULL THEN json('[]')
      WHEN json_type(details_json) = 'ARRAY' THEN details_json
      ELSE json('[' || CAST(details_json AS VARCHAR) || ']')
    END AS details_arr,
  FROM v_src
)
SELECT
  trade_id,
  team_id,
  d.value AS detail_json,
FROM v_arr,
json_each(details_arr) AS d;

CREATE OR REPLACE TEMP VIEW v_trade_team_details_source AS
WITH v_src AS (
  SELECT
    trade_id,
    team_id,
    detail_json,
    TRY_CAST(detail_json->>'$.seqno' AS INTEGER) AS seqno,
    TRY_CAST(detail_json->>'$.version_number' AS DOUBLE) AS version_number_raw,
    TRY_CAST(detail_json->>'$.post_version_number' AS DOUBLE) AS post_version_number_raw,
  FROM v_trade_team_detail_json
  WHERE detail_json->>'$.seqno' IS NOT NULL
)
SELECT
  concat_ws('_', CAST(trade_id AS VARCHAR), CAST(team_id AS VARCHAR), CAST(seqno AS VARCHAR)) AS trade_team_detail_id,
  trade_id,
  team_id,
  teams.team_code AS team_code,
  seqno,
  TRY_CAST(detail_json->>'$.group_number' AS INTEGER) AS group_number,
  TRY_CAST(detail_json->>'$.player_id' AS INTEGER) AS player_id,
  TRY_CAST(detail_json->>'$.contract_id' AS INTEGER) AS contract_id,

  CASE
    WHEN version_number_raw IS NULL THEN NULL
    WHEN floor(version_number_raw) = version_number_raw THEN version_number_raw::INTEGER
    ELSE round(version_number_raw * 100)::INTEGER
  END AS version_number,

  CASE
    WHEN post_version_number_raw IS NULL THEN NULL
    WHEN floor(post_version_number_raw) = post_version_number_raw THEN post_version_number_raw::INTEGER
    ELSE round(post_version_number_raw * 100)::INTEGER
  END AS post_version_number,

  TRY_CAST(detail_json->>'$.sent_flg' AS BOOLEAN) AS is_sent,
  TRY_CAST(detail_json->>'$.sign_and_trade_flg' AS BOOLEAN) AS is_sign_and_trade,
  TRY_CAST(detail_json->>'$.mts_value_override' AS BIGINT) AS mts_value_override,
  TRY_CAST(detail_json->>'$.trade_bonus_flg' AS BOOLEAN) AS is_trade_bonus,
  TRY_CAST(detail_json->>'$.no_trade_flg' AS BOOLEAN) AS is_no_trade,
  TRY_CAST(detail_json->>'$.player_consent_flg' AS BOOLEAN) AS is_player_consent,
  TRY_CAST(detail_json->>'$.poison_pill_flg' AS BOOLEAN) AS is_poison_pill,
  TRY_CAST(detail_json->>'$.incentive_bonus_flg' AS BOOLEAN) AS is_incentive_bonus,
  TRY_CAST(detail_json->>'$.cash_amount' AS BIGINT) AS cash_amount,
  NULLIF(trim(detail_json->>'$.trade_entry_lk'), '') AS trade_entry_lk,
  NULLIF(trim(detail_json->>'$.free_agent_designation_lk'), '') AS free_agent_designation_lk,
  TRY_CAST(detail_json->>'$.base_year_amount' AS BIGINT) AS base_year_amount,
  TRY_CAST(detail_json->>'$.base_year_flg' AS BOOLEAN) AS is_base_year,
  TRY_CAST(detail_json->>'$.draft_pick_year' AS INTEGER) AS draft_pick_year,
  TRY_CAST(detail_json->>'$.draft_pick_round' AS INTEGER) AS draft_pick_round,
  TRY_CAST(detail_json->>'$.draft_pick_future_flg' AS BOOLEAN) AS is_draft_pick_future,
  TRY_CAST(detail_json->>'$.draft_pick_swap_flg' AS BOOLEAN) AS is_draft_pick_swap,
  NULLIF(trim(detail_json->>'$.draft_pick_conditional_lk'), '') AS draft_pick_conditional_lk,
  TRY_CAST(detail_json->>'$.draft_year_plus_two_flg' AS BOOLEAN) AS is_draft_year_plus_two,
  now() AS ingested_at,
FROM v_src
LEFT JOIN v_teams AS teams
  ON teams.team_id = team_id::BIGINT;

CREATE OR REPLACE TEMP VIEW v_trade_team_details_deduped AS
SELECT * EXCLUDE (rn)
FROM (
  SELECT
    *,
    ROW_NUMBER() OVER (
      PARTITION BY trade_team_detail_id
      ORDER BY seqno DESC NULLS LAST
    ) AS rn,
  FROM v_trade_team_details_source
)
QUALIFY rn = 1;

INSERT INTO pg.pcms.trade_team_details BY NAME (
  SELECT * FROM v_trade_team_details_deduped
)
ON CONFLICT (trade_team_detail_id) DO UPDATE SET
  trade_id = EXCLUDED.trade_id,
  team_id = EXCLUDED.team_id,
  team_code = EXCLUDED.team_code,
  seqno = EXCLUDED.seqno,
  group_number = EXCLUDED.group_number,
  player_id = EXCLUDED.player_id,
  contract_id = EXCLUDED.contract_id,
  version_number = EXCLUDED.version_number,
  post_version_number = EXCLUDED.post_version_number,
  is_sent = EXCLUDED.is_sent,
  is_sign_and_trade = EXCLUDED.is_sign_and_trade,
  mts_value_override = EXCLUDED.mts_value_override,
  is_trade_bonus = EXCLUDED.is_trade_bonus,
  is_no_trade = EXCLUDED.is_no_trade,
  is_player_consent = EXCLUDED.is_player_consent,
  is_poison_pill = EXCLUDED.is_poison_pill,
  is_incentive_bonus = EXCLUDED.is_incentive_bonus,
  cash_amount = EXCLUDED.cash_amount,
  trade_entry_lk = EXCLUDED.trade_entry_lk,
  free_agent_designation_lk = EXCLUDED.free_agent_designation_lk,
  base_year_amount = EXCLUDED.base_year_amount,
  is_base_year = EXCLUDED.is_base_year,
  draft_pick_year = EXCLUDED.draft_pick_year,
  draft_pick_round = EXCLUDED.draft_pick_round,
  is_draft_pick_future = EXCLUDED.is_draft_pick_future,
  is_draft_pick_swap = EXCLUDED.is_draft_pick_swap,
  draft_pick_conditional_lk = EXCLUDED.draft_pick_conditional_lk,
  is_draft_year_plus_two = EXCLUDED.is_draft_year_plus_two,
  ingested_at = EXCLUDED.ingested_at;

-- trade_groups
-- Groups may be nested per-team (tt_json.trade_groups.trade_group). If absent, fall back to
-- trade-level groups (trade_json.trade_groups.trade_group), repeated for each trade_team.
CREATE OR REPLACE TEMP VIEW v_trade_group_json AS
WITH v_src AS (
  SELECT
    tt.trade_id,
    TRY_CAST(tt.tt_json->>'$.team_id' AS INTEGER) AS team_id,
    tr.trade_json,
    json_extract(tt.tt_json, '$.trade_groups.trade_group') AS team_groups_json,
    json_extract(tr.trade_json, '$.trade_groups.trade_group') AS trade_groups_json,
  FROM v_trade_team_json AS tt
  JOIN v_trade_json AS tr
    ON TRY_CAST(tr.trade_json->>'$.trade_id' AS INTEGER) = tt.trade_id
  WHERE tt.tt_json->>'$.team_id' IS NOT NULL
), v_arr AS (
  SELECT
    trade_id,
    team_id,
    CASE
      WHEN team_groups_json IS NULL THEN json('[]')
      WHEN json_type(team_groups_json) = 'ARRAY' THEN team_groups_json
      ELSE json('[' || CAST(team_groups_json AS VARCHAR) || ']')
    END AS team_groups_arr,
    CASE
      WHEN trade_groups_json IS NULL THEN json('[]')
      WHEN json_type(trade_groups_json) = 'ARRAY' THEN trade_groups_json
      ELSE json('[' || CAST(trade_groups_json AS VARCHAR) || ']')
    END AS trade_groups_arr,
  FROM v_src
), v_chosen AS (
  SELECT
    trade_id,
    team_id,
    CASE
      WHEN json_array_length(team_groups_arr) > 0 THEN team_groups_arr
      ELSE trade_groups_arr
    END AS groups_arr,
  FROM v_arr
)
SELECT
  trade_id,
  team_id,
  g.value AS group_json,
FROM v_chosen,
json_each(groups_arr) AS g;

CREATE OR REPLACE TEMP VIEW v_trade_groups_source AS
SELECT
  concat_ws(
    '_',
    CAST(trade_id AS VARCHAR),
    CAST(COALESCE(TRY_CAST(group_json->>'$.team_id' AS INTEGER), team_id) AS VARCHAR),
    CAST(TRY_CAST(group_json->>'$.trade_group_number' AS INTEGER) AS VARCHAR)
  ) AS trade_group_id,
  trade_id,
  COALESCE(TRY_CAST(group_json->>'$.team_id' AS INTEGER), team_id) AS team_id,
  teams.team_code AS team_code,
  TRY_CAST(group_json->>'$.trade_group_number' AS INTEGER) AS trade_group_number,
  NULLIF(trim(group_json->>'$.trade_group_comments'), '') AS trade_group_comments,
  TRY_CAST(group_json->>'$.acquired_team_exception_id' AS INTEGER) AS acquired_team_exception_id,
  TRY_CAST(group_json->>'$.generated_team_exception_id' AS INTEGER) AS generated_team_exception_id,
  NULLIF(trim(group_json->>'$.signed_method_lk'), '') AS signed_method_lk,
  now() AS ingested_at,
FROM v_trade_group_json
LEFT JOIN v_teams AS teams
  ON teams.team_id = COALESCE(TRY_CAST(group_json->>'$.team_id' AS BIGINT), team_id::BIGINT)
WHERE group_json->>'$.trade_group_number' IS NOT NULL;

CREATE OR REPLACE TEMP VIEW v_trade_groups_deduped AS
SELECT * EXCLUDE (rn)
FROM (
  SELECT
    *,
    ROW_NUMBER() OVER (
      PARTITION BY trade_group_id
      ORDER BY trade_group_number DESC NULLS LAST
    ) AS rn,
  FROM v_trade_groups_source
)
QUALIFY rn = 1;

INSERT INTO pg.pcms.trade_groups BY NAME (
  SELECT * FROM v_trade_groups_deduped
)
ON CONFLICT (trade_group_id) DO UPDATE SET
  trade_id = EXCLUDED.trade_id,
  team_id = EXCLUDED.team_id,
  team_code = EXCLUDED.team_code,
  trade_group_number = EXCLUDED.trade_group_number,
  trade_group_comments = EXCLUDED.trade_group_comments,
  acquired_team_exception_id = EXCLUDED.acquired_team_exception_id,
  generated_team_exception_id = EXCLUDED.generated_team_exception_id,
  signed_method_lk = EXCLUDED.signed_method_lk,
  ingested_at = EXCLUDED.ingested_at;

-- ─────────────────────────────────────────────────────────────────────────────
-- Transactions (transactions.json)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TEMP VIEW v_transaction_json AS
SELECT
  to_json(t) AS tx_json,
FROM read_json_auto('./shared/pcms/nba_pcms_full_extract/transactions.json') AS t;

CREATE OR REPLACE TEMP VIEW v_transactions_source AS
WITH v_src AS (
  SELECT
    tx_json,
    TRY_CAST(tx_json->>'$.version_number' AS DOUBLE) AS version_number_raw,
  FROM v_transaction_json
  WHERE tx_json->>'$.transaction_id' IS NOT NULL
)
SELECT
  TRY_CAST(tx_json->>'$.transaction_id' AS INTEGER) AS transaction_id,
  TRY_CAST(tx_json->>'$.player_id' AS INTEGER) AS player_id,

  TRY_CAST(tx_json->>'$.from_team_id' AS INTEGER) AS from_team_id,
  from_team.team_code AS from_team_code,

  TRY_CAST(tx_json->>'$.to_team_id' AS INTEGER) AS to_team_id,
  to_team.team_code AS to_team_code,

  TRY_CAST(tx_json->>'$.transaction_date' AS DATE) AS transaction_date,
  TRY_CAST(tx_json->>'$.trade_finalized_date' AS DATE) AS trade_finalized_date,
  TRY_CAST(tx_json->>'$.trade_id' AS INTEGER) AS trade_id,

  NULLIF(trim(tx_json->>'$.transaction_type_lk'), '') AS transaction_type_lk,
  NULLIF(trim(tx_json->>'$.transaction_description_lk'), '') AS transaction_description_lk,
  NULLIF(trim(tx_json->>'$.record_status_lk'), '') AS record_status_lk,
  NULLIF(trim(tx_json->>'$.league_lk'), '') AS league_lk,

  TRY_CAST(tx_json->>'$.seqno' AS INTEGER) AS seqno,
  TRY_CAST(tx_json->>'$.in_season_flg' AS BOOLEAN) AS is_in_season,

  TRY_CAST(tx_json->>'$.contract_id' AS INTEGER) AS contract_id,
  TRY_CAST(tx_json->>'$.original_contract_id' AS INTEGER) AS original_contract_id,

  CASE
    WHEN version_number_raw IS NULL THEN NULL
    WHEN floor(version_number_raw) = version_number_raw THEN version_number_raw::INTEGER
    ELSE round(version_number_raw * 100)::INTEGER
  END AS version_number,

  NULLIF(trim(tx_json->>'$.contract_type_lk'), '') AS contract_type_lk,
  NULLIF(trim(tx_json->>'$.min_contract_lk'), '') AS min_contract_lk,
  NULLIF(trim(tx_json->>'$.signed_method_lk'), '') AS signed_method_lk,
  TRY_CAST(tx_json->>'$.team_exception_id' AS INTEGER) AS team_exception_id,

  TRY_CAST(tx_json->>'$.rights_team_id' AS INTEGER) AS rights_team_id,
  rights_team.team_code AS rights_team_code,

  TRY_CAST(tx_json->>'$.waiver_clear_date' AS DATE) AS waiver_clear_date,
  TRY_CAST(tx_json->>'$.clear_player_rights_flg' AS BOOLEAN) AS is_clear_player_rights,

  NULLIF(trim(tx_json->>'$.free_agent_status_lk'), '') AS free_agent_status_lk,
  NULLIF(trim(tx_json->>'$.free_agent_designation_lk'), '') AS free_agent_designation_lk,
  NULLIF(trim(tx_json->>'$.from_player_status_lk'), '') AS from_player_status_lk,
  NULLIF(trim(tx_json->>'$.to_player_status_lk'), '') AS to_player_status_lk,

  TRY_CAST(tx_json->>'$.option_year' AS INTEGER) AS option_year,
  TRY_CAST(tx_json->>'$.adjustment_amount' AS BIGINT) AS adjustment_amount,
  TRY_CAST(tx_json->>'$.bonus_true_up_amount' AS BIGINT) AS bonus_true_up_amount,
  TRY_CAST(tx_json->>'$.draft_amount' AS BIGINT) AS draft_amount,

  TRY_CAST(tx_json->>'$.draft_pick[0]' AS INTEGER) AS draft_pick,
  TRY_CAST(tx_json->>'$.draft_round' AS INTEGER) AS draft_round,
  TRY_CAST(tx_json->>'$.draft_year' AS INTEGER) AS draft_year,

  TRY_CAST(tx_json->>'$.free_agent_amount' AS BIGINT) AS free_agent_amount,
  TRY_CAST(tx_json->>'$.qoe_amount' AS BIGINT) AS qoe_amount,
  TRY_CAST(tx_json->>'$.tender_amount' AS BIGINT) AS tender_amount,
  TRY_CAST(tx_json->>'$.divorce_flg' AS BOOLEAN) AS is_divorce,

  TRY_CAST(tx_json->>'$.effective_salary_year' AS INTEGER) AS effective_salary_year,
  TRY_CAST(tx_json->>'$.initially_convertible_exception_flg' AS BOOLEAN) AS is_initially_convertible_exception,

  TRY_CAST(tx_json->>'$.sign_and_trade_flg' AS BOOLEAN) AS is_sign_and_trade,
  TRY_CAST(tx_json->>'$.sign_and_trade_team_id' AS INTEGER) AS sign_and_trade_team_id,
  sat_team.team_code AS sign_and_trade_team_code,

  TRY_CAST(tx_json->>'$.sign_and_trade_link_transaction_id' AS INTEGER) AS sign_and_trade_link_transaction_id,

  TRY_CAST(tx_json->>'$.dlg_contract_id' AS INTEGER) AS dlg_contract_id,
  NULLIF(trim(tx_json->>'$.dlg_experience_level_lk'), '') AS dlg_experience_level_lk,
  NULLIF(trim(tx_json->>'$.dlg_salary_level_lk'), '') AS dlg_salary_level_lk,

  NULLIF(trim(tx_json->>'$.comments'), '') AS comments,

  TRY_CAST(tx_json->>'$.create_date' AS TIMESTAMPTZ) AS created_at,
  TRY_CAST(tx_json->>'$.last_change_date' AS TIMESTAMPTZ) AS updated_at,
  TRY_CAST(tx_json->>'$.record_change_date' AS TIMESTAMPTZ) AS record_changed_at,
  now() AS ingested_at,
FROM v_src
LEFT JOIN v_teams AS from_team
  ON from_team.team_id = TRY_CAST(tx_json->>'$.from_team_id' AS BIGINT)
LEFT JOIN v_teams AS to_team
  ON to_team.team_id = TRY_CAST(tx_json->>'$.to_team_id' AS BIGINT)
LEFT JOIN v_teams AS rights_team
  ON rights_team.team_id = TRY_CAST(tx_json->>'$.rights_team_id' AS BIGINT)
LEFT JOIN v_teams AS sat_team
  ON sat_team.team_id = TRY_CAST(tx_json->>'$.sign_and_trade_team_id' AS BIGINT);

CREATE OR REPLACE TEMP VIEW v_transactions_deduped AS
SELECT * EXCLUDE (rn)
FROM (
  SELECT
    *,
    ROW_NUMBER() OVER (
      PARTITION BY transaction_id
      ORDER BY record_changed_at DESC NULLS LAST, updated_at DESC NULLS LAST, created_at DESC NULLS LAST
    ) AS rn,
  FROM v_transactions_source
)
QUALIFY rn = 1;

INSERT INTO pg.pcms.transactions BY NAME (
  SELECT * FROM v_transactions_deduped
)
ON CONFLICT (transaction_id) DO UPDATE SET
  player_id = EXCLUDED.player_id,
  from_team_id = EXCLUDED.from_team_id,
  from_team_code = EXCLUDED.from_team_code,
  to_team_id = EXCLUDED.to_team_id,
  to_team_code = EXCLUDED.to_team_code,
  transaction_date = EXCLUDED.transaction_date,
  trade_finalized_date = EXCLUDED.trade_finalized_date,
  trade_id = EXCLUDED.trade_id,
  transaction_type_lk = EXCLUDED.transaction_type_lk,
  transaction_description_lk = EXCLUDED.transaction_description_lk,
  record_status_lk = EXCLUDED.record_status_lk,
  league_lk = EXCLUDED.league_lk,
  seqno = EXCLUDED.seqno,
  is_in_season = EXCLUDED.is_in_season,
  contract_id = EXCLUDED.contract_id,
  original_contract_id = EXCLUDED.original_contract_id,
  version_number = EXCLUDED.version_number,
  contract_type_lk = EXCLUDED.contract_type_lk,
  min_contract_lk = EXCLUDED.min_contract_lk,
  signed_method_lk = EXCLUDED.signed_method_lk,
  team_exception_id = EXCLUDED.team_exception_id,
  rights_team_id = EXCLUDED.rights_team_id,
  rights_team_code = EXCLUDED.rights_team_code,
  waiver_clear_date = EXCLUDED.waiver_clear_date,
  is_clear_player_rights = EXCLUDED.is_clear_player_rights,
  free_agent_status_lk = EXCLUDED.free_agent_status_lk,
  free_agent_designation_lk = EXCLUDED.free_agent_designation_lk,
  from_player_status_lk = EXCLUDED.from_player_status_lk,
  to_player_status_lk = EXCLUDED.to_player_status_lk,
  option_year = EXCLUDED.option_year,
  adjustment_amount = EXCLUDED.adjustment_amount,
  bonus_true_up_amount = EXCLUDED.bonus_true_up_amount,
  draft_amount = EXCLUDED.draft_amount,
  draft_pick = EXCLUDED.draft_pick,
  draft_round = EXCLUDED.draft_round,
  draft_year = EXCLUDED.draft_year,
  free_agent_amount = EXCLUDED.free_agent_amount,
  qoe_amount = EXCLUDED.qoe_amount,
  tender_amount = EXCLUDED.tender_amount,
  is_divorce = EXCLUDED.is_divorce,
  effective_salary_year = EXCLUDED.effective_salary_year,
  is_initially_convertible_exception = EXCLUDED.is_initially_convertible_exception,
  is_sign_and_trade = EXCLUDED.is_sign_and_trade,
  sign_and_trade_team_id = EXCLUDED.sign_and_trade_team_id,
  sign_and_trade_team_code = EXCLUDED.sign_and_trade_team_code,
  sign_and_trade_link_transaction_id = EXCLUDED.sign_and_trade_link_transaction_id,
  dlg_contract_id = EXCLUDED.dlg_contract_id,
  dlg_experience_level_lk = EXCLUDED.dlg_experience_level_lk,
  dlg_salary_level_lk = EXCLUDED.dlg_salary_level_lk,
  comments = EXCLUDED.comments,
  updated_at = EXCLUDED.updated_at,
  record_changed_at = EXCLUDED.record_changed_at,
  ingested_at = EXCLUDED.ingested_at;

-- ─────────────────────────────────────────────────────────────────────────────
-- Ledger (ledger.json)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TEMP VIEW v_ledger_json AS
SELECT
  to_json(le) AS le_json,
FROM read_json_auto('./shared/pcms/nba_pcms_full_extract/ledger.json') AS le;

CREATE OR REPLACE TEMP VIEW v_ledger_source AS
WITH v_src AS (
  SELECT
    le_json,
    TRY_CAST(le_json->>'$.version_number' AS DOUBLE) AS version_number_raw,
  FROM v_ledger_json
  WHERE le_json->>'$.transaction_ledger_entry_id' IS NOT NULL
    AND le_json->>'$.team_id' IS NOT NULL
)
SELECT
  TRY_CAST(le_json->>'$.transaction_ledger_entry_id' AS DECIMAL(38,0)) AS transaction_ledger_entry_id,
  TRY_CAST(le_json->>'$.transaction_id' AS DECIMAL(38,0)) AS transaction_id,

  TRY_CAST(le_json->>'$.team_id' AS DECIMAL(38,0)) AS team_id,
  teams.team_code AS team_code,

  TRY_CAST(le_json->>'$.player_id' AS DECIMAL(38,0)) AS player_id,
  TRY_CAST(le_json->>'$.contract_id' AS DECIMAL(38,0)) AS contract_id,
  TRY_CAST(le_json->>'$.dlg_contract_id' AS DECIMAL(38,0)) AS dlg_contract_id,

  TRY_CAST(le_json->>'$.salary_year' AS INTEGER) AS salary_year,
  TRY_CAST(le_json->>'$.ledger_date' AS DATE) AS ledger_date,

  NULLIF(trim(le_json->>'$.league_lk'), '') AS league_lk,
  NULLIF(trim(le_json->>'$.transaction_type_lk'), '') AS transaction_type_lk,
  NULLIF(trim(le_json->>'$.transaction_description_lk'), '') AS transaction_description_lk,

  CASE
    WHEN version_number_raw IS NULL THEN NULL
    WHEN floor(version_number_raw) = version_number_raw THEN version_number_raw::INTEGER
    ELSE round(version_number_raw * 100)::INTEGER
  END AS version_number,

  TRY_CAST(le_json->>'$.seqno' AS INTEGER) AS seqno,
  TRY_CAST(le_json->>'$.sub_seqno' AS INTEGER) AS sub_seqno,
  TRY_CAST(le_json->>'$.team_ledger_seqno' AS INTEGER) AS team_ledger_seqno,

  TRY_CAST(le_json->>'$.leaving_team_flg' AS BOOLEAN) AS is_leaving_team,
  TRY_CAST(le_json->>'$.no_budget_impact_flg' AS BOOLEAN) AS has_no_budget_impact,

  TRY_CAST(le_json->>'$.mts_amount' AS BIGINT) AS mts_amount,
  TRY_CAST(le_json->>'$.mts_change' AS BIGINT) AS mts_change,
  TRY_CAST(le_json->>'$.mts_value' AS BIGINT) AS mts_value,

  TRY_CAST(le_json->>'$.cap_amount' AS BIGINT) AS cap_amount,
  TRY_CAST(le_json->>'$.cap_change' AS BIGINT) AS cap_change,
  TRY_CAST(le_json->>'$.cap_value' AS BIGINT) AS cap_value,

  TRY_CAST(le_json->>'$.tax_amount' AS BIGINT) AS tax_amount,
  TRY_CAST(le_json->>'$.tax_change' AS BIGINT) AS tax_change,
  TRY_CAST(le_json->>'$.tax_value' AS BIGINT) AS tax_value,

  TRY_CAST(le_json->>'$.apron_amount' AS BIGINT) AS apron_amount,
  TRY_CAST(le_json->>'$.apron_change' AS BIGINT) AS apron_change,
  TRY_CAST(le_json->>'$.apron_value' AS BIGINT) AS apron_value,

  TRY_CAST(le_json->>'$.trade_bonus_amount' AS BIGINT) AS trade_bonus_amount,

  now() AS ingested_at,
FROM v_src
LEFT JOIN v_teams AS teams
  ON teams.team_id = TRY_CAST(le_json->>'$.team_id' AS BIGINT);

CREATE OR REPLACE TEMP VIEW v_ledger_deduped AS
SELECT * EXCLUDE (rn)
FROM (
  SELECT
    *,
    ROW_NUMBER() OVER (
      PARTITION BY transaction_ledger_entry_id
      ORDER BY transaction_id DESC NULLS LAST, seqno DESC NULLS LAST, sub_seqno DESC NULLS LAST
    ) AS rn,
  FROM v_ledger_source
)
QUALIFY rn = 1;

INSERT INTO pg.pcms.ledger_entries BY NAME (
  SELECT * FROM v_ledger_deduped
)
ON CONFLICT (transaction_ledger_entry_id) DO UPDATE SET
  transaction_id = EXCLUDED.transaction_id,
  team_id = EXCLUDED.team_id,
  team_code = EXCLUDED.team_code,
  player_id = EXCLUDED.player_id,
  contract_id = EXCLUDED.contract_id,
  dlg_contract_id = EXCLUDED.dlg_contract_id,
  salary_year = EXCLUDED.salary_year,
  ledger_date = EXCLUDED.ledger_date,
  league_lk = EXCLUDED.league_lk,
  transaction_type_lk = EXCLUDED.transaction_type_lk,
  transaction_description_lk = EXCLUDED.transaction_description_lk,
  version_number = EXCLUDED.version_number,
  seqno = EXCLUDED.seqno,
  sub_seqno = EXCLUDED.sub_seqno,
  team_ledger_seqno = EXCLUDED.team_ledger_seqno,
  is_leaving_team = EXCLUDED.is_leaving_team,
  has_no_budget_impact = EXCLUDED.has_no_budget_impact,
  mts_amount = EXCLUDED.mts_amount,
  mts_change = EXCLUDED.mts_change,
  mts_value = EXCLUDED.mts_value,
  cap_amount = EXCLUDED.cap_amount,
  cap_change = EXCLUDED.cap_change,
  cap_value = EXCLUDED.cap_value,
  tax_amount = EXCLUDED.tax_amount,
  tax_change = EXCLUDED.tax_change,
  tax_value = EXCLUDED.tax_value,
  apron_amount = EXCLUDED.apron_amount,
  apron_change = EXCLUDED.apron_change,
  apron_value = EXCLUDED.apron_value,
  trade_bonus_amount = EXCLUDED.trade_bonus_amount,
  ingested_at = EXCLUDED.ingested_at;

-- ─────────────────────────────────────────────────────────────────────────────
-- Transaction waiver amounts (transaction_waiver_amounts.json)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TEMP VIEW v_waiver_json AS
SELECT
  to_json(wa) AS wa_json,
FROM read_json_auto('./shared/pcms/nba_pcms_full_extract/transaction_waiver_amounts.json') AS wa;

CREATE OR REPLACE TEMP VIEW v_waiver_source AS
WITH v_src AS (
  SELECT
    wa_json,
    TRY_CAST(wa_json->>'$.version_number' AS DOUBLE) AS version_number_raw,
  FROM v_waiver_json
  WHERE wa_json->>'$.transaction_waiver_amount_id' IS NOT NULL
)
SELECT
  TRY_CAST(wa_json->>'$.transaction_waiver_amount_id' AS INTEGER) AS transaction_waiver_amount_id,
  TRY_CAST(wa_json->>'$.transaction_id' AS INTEGER) AS transaction_id,
  TRY_CAST(wa_json->>'$.player_id' AS INTEGER) AS player_id,

  TRY_CAST(wa_json->>'$.team_id' AS INTEGER) AS team_id,
  teams.team_code AS team_code,

  TRY_CAST(wa_json->>'$.contract_id' AS INTEGER) AS contract_id,
  TRY_CAST(wa_json->>'$.salary_year' AS INTEGER) AS salary_year,

  CASE
    WHEN version_number_raw IS NULL THEN NULL
    WHEN floor(version_number_raw) = version_number_raw THEN version_number_raw::INTEGER
    ELSE round(version_number_raw * 100)::INTEGER
  END AS version_number,

  TRY_CAST(wa_json->>'$.waive_date' AS TIMESTAMPTZ) AS waive_date,

  TRY_CAST(wa_json->>'$.cap_value' AS BIGINT) AS cap_value,
  TRY_CAST(wa_json->>'$.cap_change_value' AS BIGINT) AS cap_change_value,
  CASE
    WHEN lower(COALESCE(wa_json->>'$.cap_calculated', '')) IN ('1', 'true') THEN TRUE
    WHEN lower(COALESCE(wa_json->>'$.cap_calculated', '')) IN ('0', 'false') THEN FALSE
    ELSE TRY_CAST(wa_json->>'$.cap_calculated' AS BOOLEAN)
  END AS is_cap_calculated,

  TRY_CAST(wa_json->>'$.tax_value' AS BIGINT) AS tax_value,
  TRY_CAST(wa_json->>'$.tax_change_value' AS BIGINT) AS tax_change_value,
  CASE
    WHEN lower(COALESCE(wa_json->>'$.tax_calculated', '')) IN ('1', 'true') THEN TRUE
    WHEN lower(COALESCE(wa_json->>'$.tax_calculated', '')) IN ('0', 'false') THEN FALSE
    ELSE TRY_CAST(wa_json->>'$.tax_calculated' AS BOOLEAN)
  END AS is_tax_calculated,

  TRY_CAST(wa_json->>'$.apron_value' AS BIGINT) AS apron_value,
  TRY_CAST(wa_json->>'$.apron_change_value' AS BIGINT) AS apron_change_value,
  CASE
    WHEN lower(COALESCE(wa_json->>'$.apron_calculated', '')) IN ('1', 'true') THEN TRUE
    WHEN lower(COALESCE(wa_json->>'$.apron_calculated', '')) IN ('0', 'false') THEN FALSE
    ELSE TRY_CAST(wa_json->>'$.apron_calculated' AS BOOLEAN)
  END AS is_apron_calculated,

  TRY_CAST(wa_json->>'$.mts_value' AS BIGINT) AS mts_value,
  TRY_CAST(wa_json->>'$.mts_change_value' AS BIGINT) AS mts_change_value,

  TRY_CAST(wa_json->>'$.two_way_salary' AS BIGINT) AS two_way_salary,
  TRY_CAST(wa_json->>'$.two_way_nba_salary' AS BIGINT) AS two_way_nba_salary,
  TRY_CAST(wa_json->>'$.two_way_dlg_salary' AS BIGINT) AS two_way_dlg_salary,

  NULLIF(trim(wa_json->>'$.option_decision_lk'), '') AS option_decision_lk,
  TRY_CAST(wa_json->>'$.wnba_contract_id' AS INTEGER) AS wnba_contract_id,
  NULLIF(trim(wa_json->>'$.wnba_version_number'), '') AS wnba_version_number,

  now() AS ingested_at,
FROM v_src
LEFT JOIN v_teams AS teams
  ON teams.team_id = TRY_CAST(wa_json->>'$.team_id' AS BIGINT);

CREATE OR REPLACE TEMP VIEW v_waiver_deduped AS
SELECT * EXCLUDE (rn)
FROM (
  SELECT
    *,
    ROW_NUMBER() OVER (
      PARTITION BY transaction_waiver_amount_id
      ORDER BY transaction_id DESC NULLS LAST, salary_year DESC NULLS LAST
    ) AS rn,
  FROM v_waiver_source
)
QUALIFY rn = 1;

INSERT INTO pg.pcms.transaction_waiver_amounts BY NAME (
  SELECT * FROM v_waiver_deduped
)
ON CONFLICT (transaction_waiver_amount_id) DO UPDATE SET
  transaction_id = EXCLUDED.transaction_id,
  player_id = EXCLUDED.player_id,
  team_id = EXCLUDED.team_id,
  team_code = EXCLUDED.team_code,
  contract_id = EXCLUDED.contract_id,
  salary_year = EXCLUDED.salary_year,
  version_number = EXCLUDED.version_number,
  waive_date = EXCLUDED.waive_date,
  cap_value = EXCLUDED.cap_value,
  cap_change_value = EXCLUDED.cap_change_value,
  is_cap_calculated = EXCLUDED.is_cap_calculated,
  tax_value = EXCLUDED.tax_value,
  tax_change_value = EXCLUDED.tax_change_value,
  is_tax_calculated = EXCLUDED.is_tax_calculated,
  apron_value = EXCLUDED.apron_value,
  apron_change_value = EXCLUDED.apron_change_value,
  is_apron_calculated = EXCLUDED.is_apron_calculated,
  mts_value = EXCLUDED.mts_value,
  mts_change_value = EXCLUDED.mts_change_value,
  two_way_salary = EXCLUDED.two_way_salary,
  two_way_nba_salary = EXCLUDED.two_way_nba_salary,
  two_way_dlg_salary = EXCLUDED.two_way_dlg_salary,
  option_decision_lk = EXCLUDED.option_decision_lk,
  wnba_contract_id = EXCLUDED.wnba_contract_id,
  wnba_version_number = EXCLUDED.wnba_version_number,
  ingested_at = EXCLUDED.ingested_at;

-- ─────────────────────────────────────────────────────────────────────────────
-- Summary
-- ─────────────────────────────────────────────────────────────────────────────

SELECT
  'transactions' AS step,
  (SELECT count(*) FROM v_trades_deduped) AS trades_rows_upserted,
  (SELECT count(*) FROM v_trade_teams_deduped) AS trade_teams_rows_upserted,
  (SELECT count(*) FROM v_trade_team_details_deduped) AS trade_team_details_rows_upserted,
  (SELECT count(*) FROM v_trade_groups_deduped) AS trade_groups_rows_upserted,
  (SELECT count(*) FROM v_transactions_deduped) AS transactions_rows_upserted,
  (SELECT count(*) FROM v_ledger_deduped) AS ledger_entries_rows_upserted,
  (SELECT count(*) FROM v_waiver_deduped) AS transaction_waiver_amounts_rows_upserted,
  now() AS finished_at,
;