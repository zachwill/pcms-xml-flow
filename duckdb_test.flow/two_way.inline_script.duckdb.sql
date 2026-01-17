-- result_collection=last_statement_all_rows

ATTACH '$res:f/env/postgres' AS pg (TYPE postgres);
SET TimeZone='UTC';

--
-- two_way.inline_script.duckdb.sql
--
-- Imports:
--   - pg.pcms.two_way_daily_statuses     (two_way.json)
--   - pg.pcms.two_way_contract_utility   (two_way.json; nested under two_way_seasons)
--   - pg.pcms.two_way_game_utility       (two_way_utility.json; nested under active_list_by_team)
--   - pg.pcms.team_two_way_capacity      (two_way_utility.json; nested under under15_games)
--
-- Source files (hard-coded):
--   ./shared/pcms/nba_pcms_full_extract/lookups.json
--   ./shared/pcms/nba_pcms_full_extract/two_way.json
--   ./shared/pcms/nba_pcms_full_extract/two_way_utility.json
--
-- Notes:
--   - two_way.json is a single JSON object (not an array) and may contain hyphenated keys.
--   - We use json_extract() + json_each() heavily to handle mixed nesting patterns:
--       daily_statuses["daily-status"] vs daily_statuses.daily_status
--       two_way_seasons["two-way-season"] vs two_way_seasons.two_way_season
--   - Deduplication is mandatory to avoid Postgres "ON CONFLICT cannot affect row a second time".
--

-- 1) Team lookup (shared)
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
-- 2) two_way_daily_statuses (two_way.json)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TEMP VIEW v_two_way_root AS
SELECT
  to_json(r) AS root_json,
FROM read_json_auto('./shared/pcms/nba_pcms_full_extract/two_way.json') AS r;

CREATE OR REPLACE TEMP VIEW v_two_way_daily_statuses_source AS
WITH statuses AS (
  SELECT
    COALESCE(
      json_extract(root_json, '$.daily_statuses."daily-status"'),
      json_extract(root_json, '$.daily_statuses.daily_status'),
      json_extract(root_json, '$.daily_statuses'),
      json('[]')
    ) AS statuses_json,
  FROM v_two_way_root
),
status_rows AS (
  SELECT
    value AS status_json,
  FROM statuses,
  json_each(statuses.statuses_json)
)
SELECT
  TRY_CAST(status_json->>'$.player_id' AS INTEGER) AS player_id,

  -- PCMS uses timestamp-like strings; schema expects DATE.
  TRY_CAST(substr(status_json->>'$.status_date', 1, 10) AS DATE) AS status_date,

  COALESCE(
    TRY_CAST(status_json->>'$.season_year' AS INTEGER),
    year(TRY_CAST(substr(status_json->>'$.status_date', 1, 10) AS DATE))
  ) AS salary_year,

  TRY_CAST(status_json->>'$.day_of_season' AS INTEGER) AS day_of_season,
  NULLIF(trim(status_json->>'$.two_way_daily_status_lk'), '') AS status_lk,

  COALESCE(
    TRY_CAST(status_json->>'$.team_id' AS INTEGER),
    TRY_CAST(status_json->>'$.status_team_id' AS INTEGER)
  ) AS status_team_id,
  status_team.team_code AS status_team_code,

  TRY_CAST(status_json->>'$.contract_id' AS INTEGER) AS contract_id,
  TRY_CAST(status_json->>'$.contract_team_id' AS INTEGER) AS contract_team_id,
  contract_team.team_code AS contract_team_code,

  TRY_CAST(status_json->>'$.signing_team_id' AS INTEGER) AS signing_team_id,
  signing_team.team_code AS signing_team_code,

  TRY_CAST(status_json->>'$.nba_service_days' AS INTEGER) AS nba_service_days,
  TRY_CAST(status_json->>'$.nba_service_limit' AS INTEGER) AS nba_service_limit,
  TRY_CAST(status_json->>'$.nba_days_remaining' AS INTEGER) AS nba_days_remaining,

  TRY_CAST(status_json->>'$.nba_earned_salary' AS NUMERIC) AS nba_earned_salary,
  TRY_CAST(status_json->>'$.glg_earned_salary' AS NUMERIC) AS glg_earned_salary,

  TRY_CAST(status_json->>'$.nba_salary_days' AS INTEGER) AS nba_salary_days,
  TRY_CAST(status_json->>'$.glg_salary_days' AS INTEGER) AS glg_salary_days,
  TRY_CAST(status_json->>'$.unreported_days' AS INTEGER) AS unreported_days,

  TRY_CAST(status_json->>'$.season_active_nba_game_days' AS INTEGER) AS season_active_nba_game_days,
  TRY_CAST(status_json->>'$.season_with_nba_days' AS INTEGER) AS season_with_nba_days,
  TRY_CAST(status_json->>'$.season_travel_with_nba_days' AS INTEGER) AS season_travel_with_nba_days,
  TRY_CAST(status_json->>'$.season_non_nba_days' AS INTEGER) AS season_non_nba_days,
  TRY_CAST(status_json->>'$.season_non_nba_glg_days' AS INTEGER) AS season_non_nba_glg_days,
  TRY_CAST(status_json->>'$.season_total_days' AS INTEGER) AS season_total_days,

  TRY_CAST(status_json->>'$.create_date' AS TIMESTAMPTZ) AS created_at,
  TRY_CAST(status_json->>'$.last_change_date' AS TIMESTAMPTZ) AS updated_at,
  TRY_CAST(status_json->>'$.record_change_date' AS TIMESTAMPTZ) AS record_changed_at,

  now() AS ingested_at,
FROM status_rows
LEFT JOIN v_teams AS status_team
  ON status_team.team_id = COALESCE(
    TRY_CAST(status_json->>'$.team_id' AS BIGINT),
    TRY_CAST(status_json->>'$.status_team_id' AS BIGINT)
  )
LEFT JOIN v_teams AS contract_team
  ON contract_team.team_id = TRY_CAST(status_json->>'$.contract_team_id' AS BIGINT)
LEFT JOIN v_teams AS signing_team
  ON signing_team.team_id = TRY_CAST(status_json->>'$.signing_team_id' AS BIGINT)
WHERE
  TRY_CAST(status_json->>'$.player_id' AS INTEGER) IS NOT NULL
  AND TRY_CAST(substr(status_json->>'$.status_date', 1, 10) AS DATE) IS NOT NULL
  AND NULLIF(trim(status_json->>'$.two_way_daily_status_lk'), '') IS NOT NULL;

CREATE OR REPLACE TEMP VIEW v_two_way_daily_statuses_deduped AS
SELECT * EXCLUDE (rn)
FROM (
  SELECT
    *,
    ROW_NUMBER() OVER (
      PARTITION BY player_id, status_date
      ORDER BY record_changed_at DESC NULLS LAST, updated_at DESC NULLS LAST, created_at DESC NULLS LAST
    ) AS rn,
  FROM v_two_way_daily_statuses_source
)
QUALIFY rn = 1;

INSERT INTO pg.pcms.two_way_daily_statuses BY NAME (
  SELECT
    player_id,
    status_date,
    salary_year,
    day_of_season,
    status_lk,
    status_team_id,
    status_team_code,
    contract_id,
    contract_team_id,
    contract_team_code,
    signing_team_id,
    signing_team_code,
    nba_service_days,
    nba_service_limit,
    nba_days_remaining,
    nba_earned_salary,
    glg_earned_salary,
    nba_salary_days,
    glg_salary_days,
    unreported_days,
    season_active_nba_game_days,
    season_with_nba_days,
    season_travel_with_nba_days,
    season_non_nba_days,
    season_non_nba_glg_days,
    season_total_days,
    created_at,
    updated_at,
    record_changed_at,
    ingested_at,
  FROM v_two_way_daily_statuses_deduped
)
ON CONFLICT (player_id, status_date) DO UPDATE SET
  salary_year = EXCLUDED.salary_year,
  day_of_season = EXCLUDED.day_of_season,
  status_lk = EXCLUDED.status_lk,
  status_team_id = EXCLUDED.status_team_id,
  status_team_code = EXCLUDED.status_team_code,
  contract_id = EXCLUDED.contract_id,
  contract_team_id = EXCLUDED.contract_team_id,
  contract_team_code = EXCLUDED.contract_team_code,
  signing_team_id = EXCLUDED.signing_team_id,
  signing_team_code = EXCLUDED.signing_team_code,
  nba_service_days = EXCLUDED.nba_service_days,
  nba_service_limit = EXCLUDED.nba_service_limit,
  nba_days_remaining = EXCLUDED.nba_days_remaining,
  nba_earned_salary = EXCLUDED.nba_earned_salary,
  glg_earned_salary = EXCLUDED.glg_earned_salary,
  nba_salary_days = EXCLUDED.nba_salary_days,
  glg_salary_days = EXCLUDED.glg_salary_days,
  unreported_days = EXCLUDED.unreported_days,
  season_active_nba_game_days = EXCLUDED.season_active_nba_game_days,
  season_with_nba_days = EXCLUDED.season_with_nba_days,
  season_travel_with_nba_days = EXCLUDED.season_travel_with_nba_days,
  season_non_nba_days = EXCLUDED.season_non_nba_days,
  season_non_nba_glg_days = EXCLUDED.season_non_nba_glg_days,
  season_total_days = EXCLUDED.season_total_days,
  updated_at = EXCLUDED.updated_at,
  record_changed_at = EXCLUDED.record_changed_at,
  ingested_at = EXCLUDED.ingested_at;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3) two_way_utility.json → two_way_game_utility + team_two_way_capacity
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TEMP VIEW v_two_way_utility_root AS
SELECT
  to_json(r) AS root_json,
FROM read_json_auto('./shared/pcms/nba_pcms_full_extract/two_way_utility.json') AS r;

-- 3a) team_two_way_capacity (under15_games.under15_team_budget[])
CREATE OR REPLACE TEMP VIEW v_team_two_way_capacity_source AS
WITH budgets AS (
  SELECT
    COALESCE(
      json_extract(root_json, '$.under15_games.under15_team_budget'),
      json('[]')
    ) AS budgets_json,
  FROM v_two_way_utility_root
),
budget_rows AS (
  SELECT
    value AS budget_json,
  FROM budgets,
  json_each(budgets.budgets_json)
)
SELECT
  TRY_CAST(budget_json->>'$.team_id' AS INTEGER) AS team_id,
  teams.team_code AS team_code,
  TRY_CAST(budget_json->>'$.current_contract_count' AS INTEGER) AS current_contract_count,
  TRY_CAST(budget_json->>'$.games_remaining' AS INTEGER) AS games_remaining,
  TRY_CAST(budget_json->>'$.under15_games_count' AS INTEGER) AS under_15_games_count,
  TRY_CAST(budget_json->>'$.under15_games_remaining' AS INTEGER) AS under_15_games_remaining,
  now() AS ingested_at,
FROM budget_rows
LEFT JOIN v_teams AS teams
  ON teams.team_id = TRY_CAST(budget_json->>'$.team_id' AS BIGINT)
WHERE TRY_CAST(budget_json->>'$.team_id' AS INTEGER) IS NOT NULL;

CREATE OR REPLACE TEMP VIEW v_team_two_way_capacity_deduped AS
SELECT * EXCLUDE (rn)
FROM (
  SELECT
    *,
    ROW_NUMBER() OVER (PARTITION BY team_id ORDER BY team_id) AS rn,
  FROM v_team_two_way_capacity_source
)
QUALIFY rn = 1;

INSERT INTO pg.pcms.team_two_way_capacity BY NAME (
  SELECT
    team_id,
    current_contract_count,
    games_remaining,
    under_15_games_count,
    under_15_games_remaining,
    ingested_at,
    team_code,
  FROM v_team_two_way_capacity_deduped
)
ON CONFLICT (team_id) DO UPDATE SET
  current_contract_count = EXCLUDED.current_contract_count,
  games_remaining = EXCLUDED.games_remaining,
  under_15_games_count = EXCLUDED.under_15_games_count,
  under_15_games_remaining = EXCLUDED.under_15_games_remaining,
  team_code = EXCLUDED.team_code,
  ingested_at = EXCLUDED.ingested_at;

-- 3b) two_way_game_utility (active_list_by_team.two_way_util_game[] → players)
CREATE OR REPLACE TEMP VIEW v_two_way_game_utility_source AS
WITH games AS (
  SELECT
    COALESCE(
      json_extract(root_json, '$.active_list_by_team.two_way_util_game'),
      json('[]')
    ) AS games_json,
  FROM v_two_way_utility_root
),
game_rows AS (
  SELECT
    value AS game_json,
  FROM games,
  json_each(games.games_json)
),
player_arrays AS (
  SELECT
    game_json,
    COALESCE(
      json_extract(game_json, '$.two_way_util_players.two_way_util_player'),
      json('[]')
    ) AS players_json,
  FROM game_rows
),
player_rows AS (
  SELECT
    game_json,
    value AS player_json,
  FROM player_arrays,
  json_each(player_arrays.players_json)
)
SELECT
  TRY_CAST(game_json->>'$.game_id' AS INTEGER) AS game_id,
  TRY_CAST(game_json->>'$.team_id' AS INTEGER) AS team_id,
  team.team_code AS team_code,

  TRY_CAST(player_json->>'$.player_id' AS INTEGER) AS player_id,

  TRY_CAST(substr(game_json->>'$.date_est', 1, 10) AS DATE) AS game_date_est,

  TRY_CAST(game_json->>'$.opposition_team_id' AS INTEGER) AS opposition_team_id,
  opposition.team_code AS opposition_team_code,

  NULLIF(trim(player_json->>'$.roster_first_name'), '') AS roster_first_name,
  NULLIF(trim(player_json->>'$.roster_last_name'), '') AS roster_last_name,
  NULLIF(trim(player_json->>'$.display_first_name'), '') AS display_first_name,
  NULLIF(trim(player_json->>'$.display_last_name'), '') AS display_last_name,

  TRY_CAST(player_json->>'$.number_of_games_on_active_list' AS INTEGER) AS games_on_active_list,
  TRY_CAST(player_json->>'$.active_list_games_limit' AS INTEGER) AS active_list_games_limit,
  TRY_CAST(game_json->>'$.number_of_standard_nba_contracts' AS INTEGER) AS standard_nba_contracts_on_team,

  now() AS ingested_at,
FROM player_rows
LEFT JOIN v_teams AS team
  ON team.team_id = TRY_CAST(game_json->>'$.team_id' AS BIGINT)
LEFT JOIN v_teams AS opposition
  ON opposition.team_id = TRY_CAST(game_json->>'$.opposition_team_id' AS BIGINT)
WHERE
  TRY_CAST(game_json->>'$.game_id' AS INTEGER) IS NOT NULL
  AND TRY_CAST(game_json->>'$.team_id' AS INTEGER) IS NOT NULL
  AND TRY_CAST(player_json->>'$.player_id' AS INTEGER) IS NOT NULL;

CREATE OR REPLACE TEMP VIEW v_two_way_game_utility_deduped AS
SELECT * EXCLUDE (rn)
FROM (
  SELECT
    *,
    ROW_NUMBER() OVER (
      PARTITION BY game_id, player_id
      ORDER BY game_date_est DESC NULLS LAST, team_id ASC
    ) AS rn,
  FROM v_two_way_game_utility_source
)
QUALIFY rn = 1;

INSERT INTO pg.pcms.two_way_game_utility BY NAME (
  SELECT
    game_id,
    team_id,
    player_id,
    game_date_est,
    opposition_team_id,
    roster_first_name,
    roster_last_name,
    display_first_name,
    display_last_name,
    games_on_active_list,
    active_list_games_limit,
    standard_nba_contracts_on_team,
    ingested_at,
    team_code,
    opposition_team_code,
  FROM v_two_way_game_utility_deduped
)
ON CONFLICT (game_id, player_id) DO UPDATE SET
  team_id = EXCLUDED.team_id,
  team_code = EXCLUDED.team_code,
  game_date_est = EXCLUDED.game_date_est,
  opposition_team_id = EXCLUDED.opposition_team_id,
  opposition_team_code = EXCLUDED.opposition_team_code,
  roster_first_name = EXCLUDED.roster_first_name,
  roster_last_name = EXCLUDED.roster_last_name,
  display_first_name = EXCLUDED.display_first_name,
  display_last_name = EXCLUDED.display_last_name,
  games_on_active_list = EXCLUDED.games_on_active_list,
  active_list_games_limit = EXCLUDED.active_list_games_limit,
  standard_nba_contracts_on_team = EXCLUDED.standard_nba_contracts_on_team,
  ingested_at = EXCLUDED.ingested_at;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4) two_way.json → two_way_contract_utility (two_way_seasons nesting)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TEMP VIEW v_two_way_contract_utility_source AS
WITH seasons AS (
  SELECT
    COALESCE(
      json_extract(root_json, '$.two_way_seasons."two-way-season"'),
      json_extract(root_json, '$.two_way_seasons.two_way_season'),
      json_extract(root_json, '$.two_way_seasons'),
      json('[]')
    ) AS seasons_json,
  FROM v_two_way_root
),
season_rows AS (
  SELECT
    value AS season_json,
  FROM seasons,
  json_each(seasons.seasons_json)
),
player_arrays AS (
  SELECT
    season_json,
    COALESCE(
      json_extract(season_json, '$."two-way-players"."two-way-player"'),
      json_extract(season_json, '$.two_way_players.two_way_player'),
      json('[]')
    ) AS players_json,
  FROM season_rows
),
player_rows AS (
  SELECT
    season_json,
    value AS player_json,
  FROM player_arrays,
  json_each(player_arrays.players_json)
),
contract_arrays AS (
  SELECT
    season_json,
    player_json,
    COALESCE(
      json_extract(player_json, '$."two-way-contracts"."two-way-contract"'),
      json_extract(player_json, '$.two_way_contracts.two_way_contract'),
      json('[]')
    ) AS contracts_json,
  FROM player_rows
),
contract_rows AS (
  SELECT
    season_json,
    player_json,
    value AS contract_json,
  FROM contract_arrays,
  json_each(contract_arrays.contracts_json)
)
SELECT
  TRY_CAST(contract_json->>'$.contract_id' AS INTEGER) AS contract_id,
  COALESCE(
    TRY_CAST(contract_json->>'$.player_id' AS INTEGER),
    TRY_CAST(player_json->>'$.player_id' AS INTEGER)
  ) AS player_id,

  TRY_CAST(contract_json->>'$.contract_team_id' AS INTEGER) AS contract_team_id,
  contract_team.team_code AS contract_team_code,

  TRY_CAST(contract_json->>'$.signing_team_id' AS INTEGER) AS signing_team_id,
  signing_team.team_code AS signing_team_code,

  TRY_CAST(contract_json->>'$.is_active_two_way_contract' AS BOOLEAN) AS is_active_two_way_contract,
  TRY_CAST(contract_json->>'$.number_of_games_on_active_list' AS INTEGER) AS games_on_active_list,
  TRY_CAST(contract_json->>'$.active_list_games_limit' AS INTEGER) AS active_list_games_limit,
  TRY_CAST(contract_json->>'$.remaining_active_list_games' AS INTEGER) AS remaining_active_list_games,

  now() AS ingested_at,
FROM contract_rows
LEFT JOIN v_teams AS contract_team
  ON contract_team.team_id = TRY_CAST(contract_json->>'$.contract_team_id' AS BIGINT)
LEFT JOIN v_teams AS signing_team
  ON signing_team.team_id = TRY_CAST(contract_json->>'$.signing_team_id' AS BIGINT)
WHERE
  TRY_CAST(contract_json->>'$.contract_id' AS INTEGER) IS NOT NULL
  AND COALESCE(
    TRY_CAST(contract_json->>'$.player_id' AS INTEGER),
    TRY_CAST(player_json->>'$.player_id' AS INTEGER)
  ) IS NOT NULL;

CREATE OR REPLACE TEMP VIEW v_two_way_contract_utility_deduped AS
SELECT * EXCLUDE (rn)
FROM (
  SELECT
    *,
    ROW_NUMBER() OVER (
      PARTITION BY contract_id
      ORDER BY is_active_two_way_contract DESC NULLS LAST, player_id DESC
    ) AS rn,
  FROM v_two_way_contract_utility_source
)
QUALIFY rn = 1;

INSERT INTO pg.pcms.two_way_contract_utility BY NAME (
  SELECT
    contract_id,
    player_id,
    contract_team_id,
    signing_team_id,
    is_active_two_way_contract,
    games_on_active_list,
    active_list_games_limit,
    remaining_active_list_games,
    ingested_at,
    contract_team_code,
    signing_team_code,
  FROM v_two_way_contract_utility_deduped
)
ON CONFLICT (contract_id) DO UPDATE SET
  player_id = EXCLUDED.player_id,
  contract_team_id = EXCLUDED.contract_team_id,
  contract_team_code = EXCLUDED.contract_team_code,
  signing_team_id = EXCLUDED.signing_team_id,
  signing_team_code = EXCLUDED.signing_team_code,
  is_active_two_way_contract = EXCLUDED.is_active_two_way_contract,
  games_on_active_list = EXCLUDED.games_on_active_list,
  active_list_games_limit = EXCLUDED.active_list_games_limit,
  remaining_active_list_games = EXCLUDED.remaining_active_list_games,
  ingested_at = EXCLUDED.ingested_at;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5) Return summary
-- ─────────────────────────────────────────────────────────────────────────────

SELECT
  'two_way' AS step,
  (SELECT count(*) FROM v_two_way_daily_statuses_deduped) AS two_way_daily_statuses_rows,
  (SELECT count(*) FROM v_two_way_contract_utility_deduped) AS two_way_contract_utility_rows,
  (SELECT count(*) FROM v_two_way_game_utility_deduped) AS two_way_game_utility_rows,
  (SELECT count(*) FROM v_team_two_way_capacity_deduped) AS team_two_way_capacity_rows,
  now() AS finished_at;
