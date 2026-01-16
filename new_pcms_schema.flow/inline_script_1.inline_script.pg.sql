-- result_collection=last_statement_all_rows
-- database f/env/postgres

SET search_path TO pcms;

-- ==========================================
-- Table: lookups
-- Source: lookups.txt
-- ==========================================
CREATE TABLE IF NOT EXISTS lookups (
    lookup_id serial PRIMARY KEY,
    lookup_type text NOT NULL, -- e.g., 'lkContractType', 'lkPosition'
    lookup_code text NOT NULL, -- the "Lk" value from source
    description text,
    short_description text,
    is_active boolean DEFAULT true,
    seqno integer,
    properties_json jsonb,     -- flags like nbaFlg, dleagueFlg, etc.
    created_at timestamptz,
    updated_at timestamptz,
    record_changed_at timestamptz,
    source_drop_file text,
    source_hash text,
    parser_version text,
    ingested_at timestamptz DEFAULT now(),

    UNIQUE (lookup_type, lookup_code)
);

CREATE INDEX IF NOT EXISTS idx_lookups_type_code ON lookups (lookup_type, lookup_code);

-- ==========================================
-- Table: teams
-- Source: teams.txt
-- ==========================================
CREATE TABLE IF NOT EXISTS teams (
    team_id integer PRIMARY KEY, -- from teamId
    team_name text,
    team_name_short text,
    team_nickname text,
    city text,
    state_lk text,
    country_lk text,
    division_name text,
    conference_name text,
    league_lk text,
    is_active boolean,
    record_status_lk text,
    first_game_date date,
    created_at timestamptz,
    updated_at timestamptz,
    record_changed_at timestamptz,
    metadata_json jsonb,
    source_drop_file text,
    source_hash text,
    parser_version text,
    ingested_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_teams_league_lk ON teams (league_lk);
CREATE INDEX IF NOT EXISTS idx_teams_record_status_lk ON teams (record_status_lk);

-- ==========================================
-- Table: people
-- Source: people.txt
-- ==========================================
CREATE TABLE IF NOT EXISTS people (
    person_id integer PRIMARY KEY, -- from playerId
    first_name text,
    last_name text,
    middle_name text,
    display_first_name text,
    display_last_name text,
    roster_first_name text,
    roster_last_name text,
    birth_date date,
    birth_country_lk text,
    gender text,
    pronoun_1 text,
    pronoun_2 text,
    pronoun_3 text,
    height float,
    weight integer,
    person_type_lk text,
    player_status_lk text,
    record_status_lk text,
    league_lk text,
    team_id integer, -- FK: references teams(team_id)
    school_id integer,
    high_school_id integer,
    last_affiliation_id integer,
    agency_id integer,
    agent_id integer,
    draft_year integer,
    draft_round integer,
    draft_pick integer,
    draft_team_id integer, -- FK: references teams(team_id)
    early_entry boolean,
    years_of_service integer,
    years_of_service_p integer,
    player_start_date date,
    effective_date date,
    uniform_number text,
    uniform_number_dleague text,
    uniform_number_wnba text,
    active_for_nba_game_days integer,
    non_nba_days integer,
    non_nba_glg_days integer,
    total_days integer,
    travel_with_nba_days integer,
    with_nba_days integer,
    exhibit_10 boolean,
    exhibit_10_end_date date,
    is_two_way boolean,
    is_flex boolean,
    is_pc_replacement_player boolean,
    is_i9_verified boolean,
    is_onboarding_complete boolean,
    is_waive_gt_non_tax_mle boolean,
    is_no_trade boolean,
    is_no_aggregate boolean,
    no_aggregate_end_date date,
    is_poison_pill boolean,
    poison_pill_amt bigint, -- money in DOLLARS
    is_trade_bonus boolean,
    is_trade_bonus_earned boolean,
    trade_restriction_lk text,
    trade_restriction_end_date timestamptz,
    player_consent_lk text,
    player_consent_end_date timestamptz,
    free_agent_status_lk text,
    free_agent_designation_lk text,
    min_contract_lk text,
    dleague_player_status_lk text,
    dlg_returning_rights_salary_year integer,
    dlg_returning_rights_team_id integer,
    dlg_team_id integer,
    version_notes text,
    service_years_json jsonb,
    created_at timestamptz,
    updated_at timestamptz,
    record_changed_at timestamptz,
    source_drop_file text,
    source_hash text,
    parser_version text,
    ingested_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_people_team_id ON people (team_id);
CREATE INDEX IF NOT EXISTS idx_people_league_lk ON people (league_lk);
CREATE INDEX IF NOT EXISTS idx_people_player_status_lk ON people (player_status_lk);
CREATE INDEX IF NOT EXISTS idx_people_last_name_first_name ON people (last_name, first_name);

-- ==========================================
-- Table: synergy_instat_links
-- Source: synergy_instat_links.txt
-- ==========================================
CREATE TABLE IF NOT EXISTS synergy_instat_links (
    link_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    pcms_id integer, -- references people(person_id) or teams(team_id)
    entity_type_lk text NOT NULL, -- 'PLAYER', 'TEAM'
    sportradar_id text,
    synergy_id text,
    instat_id text,
    league_id text,
    other_ids_json jsonb,
    match_confidence numeric(3,2) DEFAULT 1.00,
    is_verified boolean DEFAULT true,
    notes text,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    source_drop_file text,
    source_hash text,
    parser_version text,
    ingested_at timestamptz DEFAULT now(),

    UNIQUE (pcms_id, entity_type_lk),
    UNIQUE (sportradar_id),
    UNIQUE (synergy_id),
    UNIQUE (instat_id)
);

CREATE INDEX IF NOT EXISTS idx_synergy_instat_links_pcms_id ON synergy_instat_links (pcms_id, entity_type_lk);
