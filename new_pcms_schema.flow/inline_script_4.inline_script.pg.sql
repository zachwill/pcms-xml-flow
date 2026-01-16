-- result_collection=last_statement_all_rows
-- database f/env/postgres

SET search_path TO pcms;

-- =============================================================================
-- FINANCIAL & BUDGET SNAPSHOTS
-- =============================================================================

-- team_budget_snapshots
-- Derived from 'team-budget-extract'. Provides a wide, analyst-friendly view of 
-- a team's financial position (Cap, Tax, MTS, Aprons).
CREATE TABLE IF NOT EXISTS team_budget_snapshots (
    team_budget_snapshot_id serial PRIMARY KEY,
    team_id integer NOT NULL, -- FK: references teams(team_id)
    salary_year integer NOT NULL, -- The starting year of the Salary Cap Year (e.g., 2024)
    player_id integer, -- FK: references people(person_id)
    contract_id integer, -- FK: references contract_terms(contract_id)
    transaction_id integer, -- FK: references transactions(transaction_id)
    transaction_type_lk text,
    transaction_description_lk text,
    budget_group_lk text, -- (e.g., 'ACTIVE_ROSTER', 'WAIVED_PLAYERS', 'EXCEPTIONS')
    contract_type_lk text,
    free_agent_designation_lk text,
    free_agent_status_lk text,
    signing_method_lk text,
    overall_contract_bonus_type_lk text,
    overall_protection_coverage_lk text,
    max_contract_lk text,
    years_of_service integer,
    ledger_date date,
    signing_date date,
    version_number integer,

    -- Calculated Amounts (in Dollars)
    cap_amount bigint,
    tax_amount bigint,
    mts_amount bigint,
    apron_amount bigint,
    is_fa_amount boolean,
    option_lk text,
    option_decision_lk text,

    -- Provenance
    source_drop_file text,
    source_hash text,
    parser_version text,
    ingested_at timestamptz DEFAULT now(),

    UNIQUE (team_id, salary_year, transaction_id, budget_group_lk, player_id, contract_id, version_number)
);

CREATE INDEX idx_team_budget_snaps_team_year ON team_budget_snapshots (team_id, salary_year);
CREATE INDEX idx_team_budget_snaps_player ON team_budget_snapshots (player_id);

-- team_tax_summary_snapshots
-- Snapshot of a team's tax and apron status specifically reflecting the values 
-- at the time of the budget extract.
CREATE TABLE IF NOT EXISTS team_tax_summary_snapshots (
    team_tax_summary_id serial PRIMARY KEY,
    team_id integer NOT NULL, -- FK: references teams(team_id)
    salary_year integer NOT NULL,
    is_taxpayer boolean DEFAULT false,
    is_repeater_taxpayer boolean DEFAULT false,
    is_subject_to_apron boolean DEFAULT false,
    subject_to_apron_reason_lk text,
    apron_level_lk text,
    apron1_transaction_id integer, -- FK: references transactions(transaction_id)
    apron2_transaction_id integer, -- FK: references transactions(transaction_id)
    record_changed_at timestamptz,
    created_at timestamptz,
    updated_at timestamptz,

    -- Provenance
    source_drop_file text,
    source_hash text,
    parser_version text,
    ingested_at timestamptz DEFAULT now(),

    UNIQUE (team_id, salary_year, source_hash)
);

-- =============================================================================
-- TAX & APRON CONFIGURATION
-- =============================================================================

-- league_tax_rates
-- Defines the tax brackets and their corresponding rates.
CREATE TABLE IF NOT EXISTS league_tax_rates (
    tax_rate_id serial PRIMARY KEY,
    league_lk text NOT NULL, -- v1: 'NBA' only
    salary_year integer NOT NULL,
    lower_limit bigint NOT NULL, -- Amount above the Tax Level where bracket starts
    upper_limit bigint, -- Amount above the Tax Level where bracket ends (NULL for top)
    tax_rate_non_repeater numeric(5,2) NOT NULL,
    tax_rate_repeater numeric(5,2) NOT NULL,
    base_charge_non_repeater bigint,
    base_charge_repeater bigint,
    created_at timestamptz,
    updated_at timestamptz,
    record_changed_at timestamptz,

    -- Provenance
    source_drop_file text,
    source_hash text,
    parser_version text,
    ingested_at timestamptz DEFAULT now(),

    UNIQUE (league_lk, salary_year, lower_limit)
);

-- tax_team_status
-- Tracks each team's status relative to the luxury tax and aprons.
CREATE TABLE IF NOT EXISTS tax_team_status (
    tax_team_status_id serial PRIMARY KEY,
    team_id integer NOT NULL, -- FK: references teams(team_id)
    salary_year integer NOT NULL,
    is_taxpayer boolean NOT NULL DEFAULT false,
    is_repeater_taxpayer boolean NOT NULL DEFAULT false,
    is_subject_to_apron boolean NOT NULL DEFAULT false,
    apron_level_lk text,
    subject_to_apron_reason_lk text,
    apron1_transaction_id integer, -- FK: references transactions(transaction_id)
    apron2_transaction_id integer, -- FK: references transactions(transaction_id)
    created_at timestamptz,
    updated_at timestamptz,
    record_changed_at timestamptz,

    -- Provenance
    source_drop_file text,
    source_hash text,
    parser_version text,
    ingested_at timestamptz DEFAULT now(),

    UNIQUE (team_id, salary_year)
);

-- lk_subject_to_apron_reasons
-- Lookup for why a team became subject to apron constraints.
CREATE TABLE IF NOT EXISTS lk_subject_to_apron_reasons (
    reason_lk text PRIMARY KEY,
    description text,
    apron_level_lk text,
    created_at timestamptz,
    updated_at timestamptz,
    record_changed_at timestamptz,

    -- Provenance
    source_drop_file text,
    source_hash text,
    parser_version text,
    ingested_at timestamptz DEFAULT now()
);

-- apron_constraints
-- Maps apron levels to specific transaction constraints.
CREATE TABLE IF NOT EXISTS apron_constraints (
    apron_level_lk text NOT NULL,
    constraint_code text NOT NULL,
    effective_salary_year integer NOT NULL,
    description text,
    created_at timestamptz,
    updated_at timestamptz,
    record_changed_at timestamptz,

    -- Provenance
    source_drop_file text,
    source_hash text,
    parser_version text,
    ingested_at timestamptz DEFAULT now(),

    PRIMARY KEY (apron_level_lk, constraint_code, effective_salary_year)
);

-- =============================================================================
-- ROOKIE SCALE & NON-CONTRACT AMOUNTS
-- =============================================================================

-- rookie_scale_amounts
-- Standard salary obligations and option percentages for first-round draft picks.
CREATE TABLE IF NOT EXISTS rookie_scale_amounts (
    rookie_scale_id serial PRIMARY KEY,
    salary_year integer NOT NULL,
    pick_number integer NOT NULL,
    league_lk text NOT NULL,
    salary_year_1 bigint,
    salary_year_2 bigint,
    salary_year_3 bigint,
    salary_year_4 bigint,
    option_amount_year_3 bigint,
    option_amount_year_4 bigint,
    option_pct_year_3 numeric,
    option_pct_year_4 numeric,
    is_baseline_scale boolean,
    is_active boolean,
    created_at timestamptz,
    updated_at timestamptz,
    record_changed_at timestamptz,

    -- Provenance
    source_drop_file text,
    source_hash text,
    parser_version text,
    ingested_at timestamptz DEFAULT now(),

    UNIQUE (salary_year, pick_number, league_lk)
);

-- non_contract_amounts
-- Cap hits not tied to active player contracts (dead money, cap holds, etc.)
CREATE TABLE IF NOT EXISTS non_contract_amounts (
    non_contract_amount_id bigint PRIMARY KEY,
    player_id integer NOT NULL, -- FK: references people(person_id)
    team_id integer NOT NULL, -- FK: references teams(team_id)
    salary_year integer NOT NULL,
    amount_type_lk text NOT NULL,
    cap_amount bigint DEFAULT 0,
    tax_amount bigint DEFAULT 0,
    apron_amount bigint DEFAULT 0,
    fa_amount bigint DEFAULT 0,
    fa_amount_calc bigint DEFAULT 0,
    salary_fa_amount bigint DEFAULT 0,
    qo_amount bigint,
    rofr_amount bigint,
    rookie_scale_amount bigint,
    carry_over_fa_flg boolean DEFAULT false,
    fa_amount_type_lk text,
    fa_amount_type_lk_calc text,
    free_agent_designation_lk text,
    free_agent_status_lk text,
    min_contract_lk text,
    contract_id integer, -- FK: references contract_terms(contract_id)
    contract_type_lk text,
    transaction_id integer, -- FK: references transactions(transaction_id)
    version_number text,
    years_of_service integer,
    created_at timestamptz,
    updated_at timestamptz,
    record_changed_at timestamptz,

    -- Provenance
    source_drop_file text NOT NULL,
    source_hash text NOT NULL,
    parser_version text,
    ingested_at timestamptz DEFAULT now()
);

CREATE INDEX idx_nca_player ON non_contract_amounts (player_id);
CREATE INDEX idx_nca_team_year ON non_contract_amounts (team_id, salary_year);

-- =============================================================================
-- TWO-WAY CONTRACTS
-- =============================================================================

-- two_way_daily_statuses
-- Tracks daily status and service day counts for Two-Way players.
CREATE TABLE IF NOT EXISTS two_way_daily_statuses (
    player_id integer NOT NULL, -- FK: references people(person_id)
    status_date date NOT NULL,
    salary_year integer NOT NULL,
    day_of_season integer,
    status_lk text NOT NULL,
    status_team_id integer, -- FK: references teams(team_id)
    contract_id integer, -- FK: references contract_terms(contract_id)
    contract_team_id integer, -- FK: references teams(team_id)
    signing_team_id integer, -- FK: references teams(team_id)

    -- Contract-specific Service & Salary Counts
    nba_service_days integer,
    nba_service_limit integer,
    nba_days_remaining integer,
    nba_earned_salary numeric,
    glg_earned_salary numeric,
    nba_salary_days integer,
    glg_salary_days integer,
    unreported_days integer,

    -- Player-Season Aggregate Totals
    season_active_nba_game_days integer,
    season_with_nba_days integer,
    season_travel_with_nba_days integer,
    season_non_nba_days integer,
    season_non_nba_glg_days integer,
    season_total_days integer,

    -- Provenance
    created_at timestamptz,
    updated_at timestamptz,
    record_changed_at timestamptz,
    source_drop_file text,
    source_hash text,
    parser_version text,
    ingested_at timestamptz DEFAULT now(),

    PRIMARY KEY (player_id, status_date)
);

CREATE INDEX idx_two_way_status_date ON two_way_daily_statuses (status_date);
CREATE INDEX idx_two_way_status_year ON two_way_daily_statuses (salary_year);

-- two_way_game_utility
-- Tracks active list utility for Two-Way players on a per-game basis.
CREATE TABLE IF NOT EXISTS two_way_game_utility (
    game_id integer NOT NULL, -- FK: references games(game_id)
    team_id integer NOT NULL, -- FK: references teams(team_id)
    player_id integer NOT NULL, -- FK: references people(person_id)
    game_date_est date,
    opposition_team_id integer, -- FK: references teams(team_id)
    roster_first_name text,
    roster_last_name text,
    display_first_name text,
    display_last_name text,

    -- Utility Counts
    games_on_active_list integer,
    active_list_games_limit integer,
    standard_nba_contracts_on_team integer,

    -- Provenance
    source_drop_file text,
    source_hash text,
    parser_version text,
    ingested_at timestamptz DEFAULT now(),

    PRIMARY KEY (game_id, player_id)
);

-- two_way_contract_utility
-- Tracks aggregate utility limits and remaining capacity for Two-Way contracts.
CREATE TABLE IF NOT EXISTS two_way_contract_utility (
    contract_id integer PRIMARY KEY, -- FK: references contract_terms(contract_id)
    player_id integer NOT NULL, -- FK: references people(person_id)
    contract_team_id integer, -- FK: references teams(team_id)
    signing_team_id integer, -- FK: references teams(team_id)
    is_active_two_way_contract boolean,
    games_on_active_list integer,
    active_list_games_limit integer,
    remaining_active_list_games integer,

    -- Provenance
    source_drop_file text,
    source_hash text,
    parser_version text,
    ingested_at timestamptz DEFAULT now()
);

-- team_two_way_capacity
-- Tracks team-level Two-Way roster capacity and limits.
CREATE TABLE IF NOT EXISTS team_two_way_capacity (
    team_id integer PRIMARY KEY, -- FK: references teams(team_id)
    current_contract_count integer,
    games_remaining integer,
    under_15_games_count integer,
    under_15_games_remaining integer,

    -- Provenance
    source_drop_file text,
    source_hash text,
    parser_version text,
    ingested_at timestamptz DEFAULT now()
);
