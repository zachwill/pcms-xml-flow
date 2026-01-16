-- result_collection=last_statement_all_rows
-- database f/env/postgres

SET search_path TO pcms;

-- ==========================================
-- SYSTEM VALUES & UI PROJECTIONS
-- ==========================================

-- ### league_system_values
-- Source: system_values.txt
CREATE TABLE IF NOT EXISTS league_system_values (
    league_lk text NOT NULL, -- v1: 'NBA' only
    salary_year integer NOT NULL,
    rsa_from_year integer,
    rsa_to_year integer,
    yss_from_year integer,
    yss_to_year integer,
    ysv_from_year integer,
    ysv_to_year integer,
    rsa_league_lk text,
    yss_league_lk text,
    ysv_league_lk text,

    -- Financial Constants (in DOLLARS)
    salary_cap_amount bigint,
    tax_level_amount bigint,
    tax_apron_amount bigint,
    tax_apron2_amount bigint,
    tax_bracket_amount bigint,
    minimum_team_salary_amount bigint,
    maximum_salary_25_pct bigint,
    maximum_salary_30_pct bigint,
    maximum_salary_35_pct bigint,
    average_salary_amount bigint,
    estimated_average_salary_amount bigint,
    non_taxpayer_mid_level_amount bigint,
    taxpayer_mid_level_amount bigint,
    room_mid_level_amount bigint,
    bi_annual_amount bigint,
    two_way_salary_amount bigint,
    two_way_dlg_salary_amount bigint,
    wnba_offseason_end_at timestamptz,
    tpe_dollar_allowance bigint,
    max_trade_cash_amount bigint,
    international_player_payment_limit bigint,
    scale_raise_rate numeric,

    -- League Dates & Milestones
    days_in_season integer,
    season_start_at timestamptz,
    season_end_at timestamptz,
    playing_start_at timestamptz,
    playing_end_at timestamptz,
    finals_end_at timestamptz,
    training_camp_start_at timestamptz,
    training_camp_end_at timestamptz,
    rookie_camp_start_at timestamptz,
    rookie_camp_end_at timestamptz,
    draft_at timestamptz,
    moratorium_start_at timestamptz,
    moratorium_end_at timestamptz,
    trade_deadline_at timestamptz,
    cut_down_at timestamptz,
    two_way_cut_down_at timestamptz,
    notification_start_at timestamptz,
    notification_end_at timestamptz,
    exception_start_at timestamptz,
    exception_prorate_at timestamptz,
    exceptions_added_at timestamptz,
    rnd2_pick_exc_zero_cap_end_at timestamptz,

    -- Derived Milestones
    jan_5_ten_day_start_at timestamptz,
    jan_10_guarantee_at timestamptz,
    dec_15_trade_lift_at timestamptz,
    jan_15_trade_lift_at timestamptz,
    march_1_playoff_waiver_at timestamptz,

    -- State Flags
    bonuses_finalized_at timestamptz,
    is_bonuses_finalized boolean,
    is_cap_projection_generated boolean,
    is_exceptions_added boolean,
    free_agent_status_finalized_at timestamptz,
    is_free_agent_amounts_finalized boolean,
    wnba_season_finalized_at timestamptz,
    is_wnba_season_finalized boolean,

    -- D-League
    dlg_countable_roster_moves integer,
    dlg_max_level_a_salary_players integer,
    dlg_salary_level_a integer,
    dlg_salary_level_b integer,
    dlg_salary_level_c integer,
    dlg_team_salary_budget bigint,

    -- Provenance
    created_at timestamptz,
    updated_at timestamptz,
    record_changed_at timestamptz,
    source_drop_file text,
    source_hash text,
    parser_version text,
    ingested_at timestamptz DEFAULT now(),

    PRIMARY KEY (league_lk, salary_year)
);

-- ### league_salary_cap_projections
-- Source: system_values.txt
CREATE TABLE IF NOT EXISTS league_salary_cap_projections (
    projection_id integer PRIMARY KEY,
    salary_year integer NOT NULL,
    cap_amount bigint,
    tax_level_amount bigint,
    estimated_average_player_salary bigint,
    growth_rate numeric,
    effective_date timestamptz,
    is_generated boolean,
    created_at timestamptz,
    updated_at timestamptz,
    record_changed_at timestamptz,
    source_drop_file text,
    source_hash text,
    parser_version text,
    ingested_at timestamptz DEFAULT now()
);

-- ### league_salary_scales
-- Source: system_values.txt
CREATE TABLE IF NOT EXISTS league_salary_scales (
    salary_scale_id serial PRIMARY KEY,
    salary_year integer NOT NULL,
    league_lk text NOT NULL,
    years_of_service integer NOT NULL,
    minimum_salary_amount bigint,
    created_at timestamptz,
    updated_at timestamptz,
    record_changed_at timestamptz,
    source_drop_file text,
    source_hash text,
    parser_version text,
    ingested_at timestamptz DEFAULT now(),

    UNIQUE (salary_year, league_lk, years_of_service)
);

-- ### ui_projections
-- Source: ui_projections.txt
CREATE TABLE IF NOT EXISTS ui_projections (
    projection_id uuid PRIMARY KEY,
    team_id integer NOT NULL, -- FK: references teams(team_id)
    salary_year integer NOT NULL,
    name text NOT NULL,
    description text,
    created_by text,
    is_public boolean DEFAULT false,
    base_salary_cap bigint,
    base_tax_level bigint,
    base_apron1_level bigint,
    base_apron2_level bigint,
    base_source_hash text,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ui_projections_team_year ON ui_projections(team_id, salary_year);

-- ### ui_projection_overrides
-- Source: ui_projections.txt
CREATE TABLE IF NOT EXISTS ui_projection_overrides (
    override_id uuid PRIMARY KEY,
    projection_id uuid NOT NULL, -- FK: references ui_projections(projection_id)
    entity_type text NOT NULL,
    entity_id text NOT NULL,
    action_type text NOT NULL,
    override_params_json jsonb,
    created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ui_projection_overrides_projection ON ui_projection_overrides(projection_id);

-- ### ui_projected_salaries
-- Source: ui_projections.txt
CREATE TABLE IF NOT EXISTS ui_projected_salaries (
    projection_salary_id serial PRIMARY KEY,
    projection_id uuid NOT NULL, -- FK: references ui_projections(projection_id)
    team_id integer NOT NULL,
    salary_year integer NOT NULL,
    item_id text NOT NULL,
    item_type_lk text NOT NULL,
    player_id integer, -- FK: references people(person_id)
    player_name text,
    cap_hit bigint NOT NULL,
    tax_hit bigint NOT NULL,
    cash_amount bigint,
    is_guaranteed boolean,
    is_waived boolean DEFAULT false,
    is_stretched boolean DEFAULT false,
    stretch_years_remaining integer,
    option_status_lk text,
    option_decision_lk text,
    incentive_treatment_lk text,
    is_renounced boolean DEFAULT false,
    trade_status_lk text DEFAULT 'RETAINED',
    projection_notes text,
    ingested_at timestamptz DEFAULT now(),

    UNIQUE (projection_id, item_id, salary_year)
);

CREATE INDEX IF NOT EXISTS idx_ui_projected_salaries_projection ON ui_projected_salaries(projection_id);
