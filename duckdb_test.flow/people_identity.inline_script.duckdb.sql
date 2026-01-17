-- result_collection=last_statement_all_rows

ATTACH '$res:f/env/postgres' AS pg (TYPE postgres);
SET TimeZone='UTC';

--
-- people_identity.inline_script.duckdb.sql
--
-- Imports:
--   - pg.pcms.agencies   (from lookups.json: lk_agencies.lk_agency[])
--   - pg.pcms.people     (from players.json)
--   - pg.pcms.agents     (from players.json filtered by person_type_lk = 'AGENT')
--
-- Source files (hard-coded):
--   ./shared/pcms/nba_pcms_full_extract/lookups.json
--   ./shared/pcms/nba_pcms_full_extract/players.json
--
-- Notes:
--   - players.json has a few non-snake-case keys (e.g. pronoun1, exhibit10)
--   - draft_pick is an array in JSON; we take element [0]
--   - dedupe is mandatory to avoid Postgres "ON CONFLICT cannot affect row a second time" errors
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
-- 2) Agencies
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TEMP VIEW v_agencies_source AS
SELECT
  TRY_CAST(a_json->>'$.agency_id' AS INTEGER) AS agency_id,
  NULLIF(trim(a_json->>'$.agency_name'), '') AS agency_name,
  TRY_CAST(a_json->>'$.active_flg' AS BOOLEAN) AS is_active,
  TRY_CAST(a_json->>'$.create_date' AS TIMESTAMPTZ) AS created_at,
  TRY_CAST(a_json->>'$.last_change_date' AS TIMESTAMPTZ) AS updated_at,
  TRY_CAST(a_json->>'$.record_change_date' AS TIMESTAMPTZ) AS record_changed_at,
  a_json AS agency_json,
  now() AS ingested_at,
FROM (
  SELECT
    to_json(a) AS a_json,
  FROM read_json_auto('./shared/pcms/nba_pcms_full_extract/lookups.json') AS lookups,
  UNNEST(lookups.lk_agencies.lk_agency) AS t(a)
)
WHERE a_json->>'$.agency_id' IS NOT NULL;

CREATE OR REPLACE TEMP VIEW v_agencies_deduped AS
SELECT * EXCLUDE (rn)
FROM (
  SELECT
    *,
    ROW_NUMBER() OVER (
      PARTITION BY agency_id
      ORDER BY record_changed_at DESC NULLS LAST, updated_at DESC NULLS LAST, created_at DESC NULLS LAST
    ) AS rn,
  FROM v_agencies_source
)
QUALIFY rn = 1;

INSERT INTO pg.pcms.agencies BY NAME (
  SELECT
    agency_id,
    agency_name,
    is_active,
    created_at,
    updated_at,
    record_changed_at,
    agency_json,
    ingested_at,
  FROM v_agencies_deduped
)
ON CONFLICT (agency_id) DO UPDATE SET
  agency_name = EXCLUDED.agency_name,
  is_active = EXCLUDED.is_active,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  record_changed_at = EXCLUDED.record_changed_at,
  agency_json = EXCLUDED.agency_json,
  ingested_at = EXCLUDED.ingested_at;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3) People
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TEMP VIEW v_people_source AS
SELECT
  TRY_CAST(p_json->>'$.player_id' AS INTEGER) AS person_id,
  NULLIF(trim(p_json->>'$.first_name'), '') AS first_name,
  NULLIF(trim(p_json->>'$.last_name'), '') AS last_name,
  NULLIF(trim(p_json->>'$.middle_name'), '') AS middle_name,
  NULLIF(trim(p_json->>'$.display_first_name'), '') AS display_first_name,
  NULLIF(trim(p_json->>'$.display_last_name'), '') AS display_last_name,
  NULLIF(trim(p_json->>'$.roster_first_name'), '') AS roster_first_name,
  NULLIF(trim(p_json->>'$.roster_last_name'), '') AS roster_last_name,

  TRY_CAST(p_json->>'$.birth_date' AS DATE) AS birth_date,
  NULLIF(trim(p_json->>'$.birth_country_lk'), '') AS birth_country_lk,

  -- Source uses numeric gender codes (e.g. 1). Keep as text.
  NULLIF(trim(p_json->>'$.gender'), '') AS gender,

  NULLIF(trim(p_json->>'$.pronoun1'), '') AS pronoun_1,
  NULLIF(trim(p_json->>'$.pronoun2'), '') AS pronoun_2,
  NULLIF(trim(p_json->>'$.pronoun3'), '') AS pronoun_3,

  TRY_CAST(p_json->>'$.height' AS DOUBLE) AS height,
  TRY_CAST(p_json->>'$.weight' AS INTEGER) AS weight,

  NULLIF(trim(p_json->>'$.person_type_lk'), '') AS person_type_lk,
  NULLIF(trim(p_json->>'$.player_status_lk'), '') AS player_status_lk,
  NULLIF(trim(p_json->>'$.record_status_lk'), '') AS record_status_lk,
  NULLIF(trim(p_json->>'$.league_lk'), '') AS league_lk,

  TRY_CAST(p_json->>'$.team_id' AS INTEGER) AS team_id,
  team.team_code AS team_code,

  TRY_CAST(p_json->>'$.school_id' AS INTEGER) AS school_id,
  TRY_CAST(p_json->>'$.high_school_id' AS INTEGER) AS high_school_id,
  TRY_CAST(p_json->>'$.last_affiliation_id' AS INTEGER) AS last_affiliation_id,

  TRY_CAST(p_json->>'$.agency_id' AS INTEGER) AS agency_id,
  TRY_CAST(p_json->>'$.agent_id' AS INTEGER) AS agent_id,

  TRY_CAST(p_json->>'$.draft_year' AS INTEGER) AS draft_year,
  TRY_CAST(p_json->>'$.draft_round' AS INTEGER) AS draft_round,
  TRY_CAST(p_json->>'$.draft_pick[0]' AS INTEGER) AS draft_pick,

  TRY_CAST(p_json->>'$.draft_team_id' AS INTEGER) AS draft_team_id,
  draft_team.team_code AS draft_team_code,

  TRY_CAST(p_json->>'$.early_entry' AS BOOLEAN) AS early_entry,

  TRY_CAST(p_json->>'$.years_of_service' AS INTEGER) AS years_of_service,
  TRY_CAST(p_json->>'$.years_of_service_p' AS INTEGER) AS years_of_service_p,

  TRY_CAST(p_json->>'$.player_start_date' AS DATE) AS player_start_date,
  TRY_CAST(p_json->>'$.effective_date' AS DATE) AS effective_date,

  NULLIF(trim(p_json->>'$.uniform_number'), '') AS uniform_number,
  NULLIF(trim(p_json->>'$.uniform_number_dleague'), '') AS uniform_number_dleague,
  NULLIF(trim(p_json->>'$.uniform_number_wnba'), '') AS uniform_number_wnba,

  TRY_CAST(p_json->>'$.active_for_nba_game_days' AS INTEGER) AS active_for_nba_game_days,
  TRY_CAST(p_json->>'$.non_nba_days' AS INTEGER) AS non_nba_days,
  TRY_CAST(p_json->>'$.non_nba_glg_days' AS INTEGER) AS non_nba_glg_days,
  TRY_CAST(p_json->>'$.total_days' AS INTEGER) AS total_days,
  TRY_CAST(p_json->>'$.travel_with_nba_days' AS INTEGER) AS travel_with_nba_days,
  TRY_CAST(p_json->>'$.with_nba_days' AS INTEGER) AS with_nba_days,

  TRY_CAST(p_json->>'$.exhibit10' AS BOOLEAN) AS exhibit_10,
  TRY_CAST(p_json->>'$.exhibit10_end_date' AS DATE) AS exhibit_10_end_date,

  TRY_CAST(p_json->>'$.two_way_flg' AS BOOLEAN) AS is_two_way,
  TRY_CAST(p_json->>'$.flex_flg' AS BOOLEAN) AS is_flex,
  TRY_CAST(p_json->>'$.pc_replacement_player_flg' AS BOOLEAN) AS is_pc_replacement_player,
  TRY_CAST(p_json->>'$.i9_verification_flg' AS BOOLEAN) AS is_i9_verified,
  TRY_CAST(p_json->>'$.onboarding_forms_flg' AS BOOLEAN) AS is_onboarding_complete,
  TRY_CAST(p_json->>'$.waive_gt_non_tax_mle_flg' AS BOOLEAN) AS is_waive_gt_non_tax_mle,

  TRY_CAST(p_json->>'$.no_trade_flg' AS BOOLEAN) AS is_no_trade,
  NULLIF(trim(p_json->>'$.trade_restriction_lk'), '') AS trade_restriction_lk,
  TRY_CAST(p_json->>'$.trade_restriction_end_date' AS TIMESTAMPTZ) AS trade_restriction_end_date,

  TRY_CAST(p_json->>'$.player_consent_lk' AS VARCHAR) AS player_consent_lk,
  TRY_CAST(p_json->>'$.player_consent_end_date' AS TIMESTAMPTZ) AS player_consent_end_date,

  TRY_CAST(p_json->>'$.no_aggregate_flg' AS BOOLEAN) AS is_no_aggregate,
  TRY_CAST(p_json->>'$.no_aggregate_end_date' AS DATE) AS no_aggregate_end_date,

  TRY_CAST(p_json->>'$.poison_pill_flg' AS BOOLEAN) AS is_poison_pill,
  TRY_CAST(p_json->>'$.poison_pill_amt' AS BIGINT) AS poison_pill_amt,

  TRY_CAST(p_json->>'$.trade_bonus_flg' AS BOOLEAN) AS is_trade_bonus,
  TRY_CAST(p_json->>'$.trade_bonus_earned_flg' AS BOOLEAN) AS is_trade_bonus_earned,

  NULLIF(trim(p_json->>'$.free_agent_status_lk'), '') AS free_agent_status_lk,
  NULLIF(trim(p_json->>'$.free_agent_designation_lk'), '') AS free_agent_designation_lk,
  NULLIF(trim(p_json->>'$.min_contract_lk'), '') AS min_contract_lk,

  NULLIF(trim(p_json->>'$.dleague_player_status_lk'), '') AS dleague_player_status_lk,
  TRY_CAST(p_json->>'$.dlg_returning_rights_season' AS INTEGER) AS dlg_returning_rights_salary_year,
  TRY_CAST(p_json->>'$.dlg_returning_rights_team_id' AS INTEGER) AS dlg_returning_rights_team_id,
  dlg_rr_team.team_code AS dlg_returning_rights_team_code,

  TRY_CAST(p_json->>'$.dlg_team_id' AS INTEGER) AS dlg_team_id,
  dlg_team.team_code AS dlg_team_code,

  NULLIF(trim(p_json->>'$.version_notes'), '') AS version_notes,
  p_json->'$.player_service_years' AS service_years_json,

  TRY_CAST(p_json->>'$.create_date' AS TIMESTAMPTZ) AS created_at,
  TRY_CAST(p_json->>'$.last_change_date' AS TIMESTAMPTZ) AS updated_at,
  TRY_CAST(p_json->>'$.record_change_date' AS TIMESTAMPTZ) AS record_changed_at,

  now() AS ingested_at,
FROM (
  SELECT
    to_json(p) AS p_json,
  FROM read_json_auto('./shared/pcms/nba_pcms_full_extract/players.json') AS p
) AS src
LEFT JOIN v_teams AS team ON team.team_id = TRY_CAST(p_json->>'$.team_id' AS BIGINT)
LEFT JOIN v_teams AS draft_team ON draft_team.team_id = TRY_CAST(p_json->>'$.draft_team_id' AS BIGINT)
LEFT JOIN v_teams AS dlg_rr_team ON dlg_rr_team.team_id = TRY_CAST(p_json->>'$.dlg_returning_rights_team_id' AS BIGINT)
LEFT JOIN v_teams AS dlg_team ON dlg_team.team_id = TRY_CAST(p_json->>'$.dlg_team_id' AS BIGINT)
WHERE p_json->>'$.player_id' IS NOT NULL;

CREATE OR REPLACE TEMP VIEW v_people_deduped AS
SELECT * EXCLUDE (rn)
FROM (
  SELECT
    *,
    ROW_NUMBER() OVER (
      PARTITION BY person_id
      ORDER BY record_changed_at DESC NULLS LAST, updated_at DESC NULLS LAST, created_at DESC NULLS LAST
    ) AS rn,
  FROM v_people_source
)
QUALIFY rn = 1;

INSERT INTO pg.pcms.people BY NAME (
  SELECT
    person_id,
    first_name,
    last_name,
    middle_name,
    display_first_name,
    display_last_name,
    roster_first_name,
    roster_last_name,
    birth_date,
    birth_country_lk,
    gender,
    pronoun_1,
    pronoun_2,
    pronoun_3,
    height,
    weight,
    person_type_lk,
    player_status_lk,
    record_status_lk,
    league_lk,
    team_id,
    team_code,
    school_id,
    high_school_id,
    last_affiliation_id,
    agency_id,
    agent_id,
    draft_year,
    draft_round,
    draft_pick,
    draft_team_id,
    draft_team_code,
    early_entry,
    years_of_service,
    years_of_service_p,
    player_start_date,
    effective_date,
    uniform_number,
    uniform_number_dleague,
    uniform_number_wnba,
    active_for_nba_game_days,
    non_nba_days,
    non_nba_glg_days,
    total_days,
    travel_with_nba_days,
    with_nba_days,
    exhibit_10,
    exhibit_10_end_date,
    is_two_way,
    is_flex,
    is_pc_replacement_player,
    is_i9_verified,
    is_onboarding_complete,
    is_waive_gt_non_tax_mle,
    is_no_trade,
    trade_restriction_lk,
    trade_restriction_end_date,
    player_consent_lk,
    player_consent_end_date,
    is_no_aggregate,
    no_aggregate_end_date,
    is_poison_pill,
    poison_pill_amt,
    is_trade_bonus,
    is_trade_bonus_earned,
    free_agent_status_lk,
    free_agent_designation_lk,
    min_contract_lk,
    dleague_player_status_lk,
    dlg_returning_rights_salary_year,
    dlg_returning_rights_team_id,
    dlg_returning_rights_team_code,
    dlg_team_id,
    dlg_team_code,
    version_notes,
    service_years_json,
    created_at,
    updated_at,
    record_changed_at,
    ingested_at,
  FROM v_people_deduped
)
ON CONFLICT (person_id) DO UPDATE SET
  first_name = EXCLUDED.first_name,
  last_name = EXCLUDED.last_name,
  middle_name = EXCLUDED.middle_name,
  display_first_name = EXCLUDED.display_first_name,
  display_last_name = EXCLUDED.display_last_name,
  roster_first_name = EXCLUDED.roster_first_name,
  roster_last_name = EXCLUDED.roster_last_name,
  birth_date = EXCLUDED.birth_date,
  birth_country_lk = EXCLUDED.birth_country_lk,
  gender = EXCLUDED.gender,
  pronoun_1 = EXCLUDED.pronoun_1,
  pronoun_2 = EXCLUDED.pronoun_2,
  pronoun_3 = EXCLUDED.pronoun_3,
  height = EXCLUDED.height,
  weight = EXCLUDED.weight,
  person_type_lk = EXCLUDED.person_type_lk,
  player_status_lk = EXCLUDED.player_status_lk,
  record_status_lk = EXCLUDED.record_status_lk,
  league_lk = EXCLUDED.league_lk,
  team_id = EXCLUDED.team_id,
  team_code = EXCLUDED.team_code,
  school_id = EXCLUDED.school_id,
  high_school_id = EXCLUDED.high_school_id,
  last_affiliation_id = EXCLUDED.last_affiliation_id,
  agency_id = EXCLUDED.agency_id,
  agent_id = EXCLUDED.agent_id,
  draft_year = EXCLUDED.draft_year,
  draft_round = EXCLUDED.draft_round,
  draft_pick = EXCLUDED.draft_pick,
  draft_team_id = EXCLUDED.draft_team_id,
  draft_team_code = EXCLUDED.draft_team_code,
  early_entry = EXCLUDED.early_entry,
  years_of_service = EXCLUDED.years_of_service,
  years_of_service_p = EXCLUDED.years_of_service_p,
  player_start_date = EXCLUDED.player_start_date,
  effective_date = EXCLUDED.effective_date,
  uniform_number = EXCLUDED.uniform_number,
  uniform_number_dleague = EXCLUDED.uniform_number_dleague,
  uniform_number_wnba = EXCLUDED.uniform_number_wnba,
  active_for_nba_game_days = EXCLUDED.active_for_nba_game_days,
  non_nba_days = EXCLUDED.non_nba_days,
  non_nba_glg_days = EXCLUDED.non_nba_glg_days,
  total_days = EXCLUDED.total_days,
  travel_with_nba_days = EXCLUDED.travel_with_nba_days,
  with_nba_days = EXCLUDED.with_nba_days,
  exhibit_10 = EXCLUDED.exhibit_10,
  exhibit_10_end_date = EXCLUDED.exhibit_10_end_date,
  is_two_way = EXCLUDED.is_two_way,
  is_flex = EXCLUDED.is_flex,
  is_pc_replacement_player = EXCLUDED.is_pc_replacement_player,
  is_i9_verified = EXCLUDED.is_i9_verified,
  is_onboarding_complete = EXCLUDED.is_onboarding_complete,
  is_waive_gt_non_tax_mle = EXCLUDED.is_waive_gt_non_tax_mle,
  is_no_trade = EXCLUDED.is_no_trade,
  trade_restriction_lk = EXCLUDED.trade_restriction_lk,
  trade_restriction_end_date = EXCLUDED.trade_restriction_end_date,
  player_consent_lk = EXCLUDED.player_consent_lk,
  player_consent_end_date = EXCLUDED.player_consent_end_date,
  is_no_aggregate = EXCLUDED.is_no_aggregate,
  no_aggregate_end_date = EXCLUDED.no_aggregate_end_date,
  is_poison_pill = EXCLUDED.is_poison_pill,
  poison_pill_amt = EXCLUDED.poison_pill_amt,
  is_trade_bonus = EXCLUDED.is_trade_bonus,
  is_trade_bonus_earned = EXCLUDED.is_trade_bonus_earned,
  free_agent_status_lk = EXCLUDED.free_agent_status_lk,
  free_agent_designation_lk = EXCLUDED.free_agent_designation_lk,
  min_contract_lk = EXCLUDED.min_contract_lk,
  dleague_player_status_lk = EXCLUDED.dleague_player_status_lk,
  dlg_returning_rights_salary_year = EXCLUDED.dlg_returning_rights_salary_year,
  dlg_returning_rights_team_id = EXCLUDED.dlg_returning_rights_team_id,
  dlg_returning_rights_team_code = EXCLUDED.dlg_returning_rights_team_code,
  dlg_team_id = EXCLUDED.dlg_team_id,
  dlg_team_code = EXCLUDED.dlg_team_code,
  version_notes = EXCLUDED.version_notes,
  service_years_json = EXCLUDED.service_years_json,
  updated_at = EXCLUDED.updated_at,
  record_changed_at = EXCLUDED.record_changed_at,
  ingested_at = EXCLUDED.ingested_at;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4) Agents (subset of players where person_type_lk = 'AGENT')
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TEMP VIEW v_agents_source AS
SELECT
  TRY_CAST(p_json->>'$.player_id' AS INTEGER) AS agent_id,
  TRY_CAST(p_json->>'$.agency_id' AS INTEGER) AS agency_id,
  a.agency_name AS agency_name,
  NULLIF(trim(p_json->>'$.first_name'), '') AS first_name,
  NULLIF(trim(p_json->>'$.last_name'), '') AS last_name,
  NULLIF(trim(concat_ws(' ', NULLIF(trim(p_json->>'$.first_name'), ''), NULLIF(trim(p_json->>'$.last_name'), ''))), '') AS full_name,
  CASE
    WHEN p_json->>'$.record_status_lk' IS NULL THEN NULL
    WHEN p_json->>'$.record_status_lk' = 'ACT' THEN TRUE
    ELSE FALSE
  END AS is_active,
  TRUE AS is_certified,
  NULLIF(trim(p_json->>'$.person_type_lk'), '') AS person_type_lk,
  TRY_CAST(p_json->>'$.create_date' AS TIMESTAMPTZ) AS created_at,
  TRY_CAST(p_json->>'$.last_change_date' AS TIMESTAMPTZ) AS updated_at,
  TRY_CAST(p_json->>'$.record_change_date' AS TIMESTAMPTZ) AS record_changed_at,
  p_json AS agent_json,
  now() AS ingested_at,
FROM (
  SELECT
    to_json(p) AS p_json,
  FROM read_json_auto('./shared/pcms/nba_pcms_full_extract/players.json') AS p
) AS src
LEFT JOIN v_agencies_deduped AS a ON a.agency_id = TRY_CAST(p_json->>'$.agency_id' AS INTEGER)
WHERE p_json->>'$.person_type_lk' = 'AGENT'
  AND p_json->>'$.player_id' IS NOT NULL;

CREATE OR REPLACE TEMP VIEW v_agents_deduped AS
SELECT * EXCLUDE (rn)
FROM (
  SELECT
    *,
    ROW_NUMBER() OVER (
      PARTITION BY agent_id
      ORDER BY record_changed_at DESC NULLS LAST, updated_at DESC NULLS LAST, created_at DESC NULLS LAST
    ) AS rn,
  FROM v_agents_source
)
QUALIFY rn = 1;

INSERT INTO pg.pcms.agents BY NAME (
  SELECT
    agent_id,
    agency_id,
    agency_name,
    first_name,
    last_name,
    full_name,
    is_active,
    is_certified,
    person_type_lk,
    created_at,
    updated_at,
    record_changed_at,
    agent_json,
    ingested_at,
  FROM v_agents_deduped
)
ON CONFLICT (agent_id) DO UPDATE SET
  agency_id = EXCLUDED.agency_id,
  agency_name = EXCLUDED.agency_name,
  first_name = EXCLUDED.first_name,
  last_name = EXCLUDED.last_name,
  full_name = EXCLUDED.full_name,
  is_active = EXCLUDED.is_active,
  is_certified = EXCLUDED.is_certified,
  person_type_lk = EXCLUDED.person_type_lk,
  updated_at = EXCLUDED.updated_at,
  record_changed_at = EXCLUDED.record_changed_at,
  agent_json = EXCLUDED.agent_json,
  ingested_at = EXCLUDED.ingested_at;

-- 5) Summary
SELECT
  'people_identity' AS step,
  (SELECT count(*) FROM v_agencies_deduped) AS agencies_rows_upserted,
  (SELECT count(*) FROM v_people_deduped) AS people_rows_upserted,
  (SELECT count(*) FROM v_agents_deduped) AS agents_rows_upserted,
  now() AS finished_at,
;