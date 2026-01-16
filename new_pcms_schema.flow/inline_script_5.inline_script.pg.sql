-- result_collection=last_statement_all_rows
-- database f/env/postgres

SET search_path TO pcms;

-- ==========================================
-- OPERATIONS & SCOUTING
-- ==========================================

-- ### agencies
-- Source: agencies_and_agents.txt
CREATE TABLE IF NOT EXISTS agencies (
    agency_id integer PRIMARY KEY,
    agency_name text,
    is_active boolean DEFAULT true,
    created_at timestamptz,
    updated_at timestamptz,
    record_changed_at timestamptz,
    agency_json jsonb,
    source_drop_file text,
    source_hash text,
    parser_version text,
    ingested_at timestamptz DEFAULT now()
);

-- ### agents
-- Source: agencies_and_agents.txt
CREATE TABLE IF NOT EXISTS agents (
    agent_id integer PRIMARY KEY,
    agency_id integer, -- FK: references agencies(agency_id)
    agency_name text,
    first_name text,
    last_name text,
    full_name text,
    is_active boolean DEFAULT true,
    is_certified boolean DEFAULT true,
    person_type_lk text,
    created_at timestamptz,
    updated_at timestamptz,
    record_changed_at timestamptz,
    agent_json jsonb,
    source_drop_file text,
    source_hash text,
    parser_version text,
    ingested_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_agents_agency_id ON agents(agency_id);

-- ### depth_charts
-- Source: depth_charts.txt
CREATE TABLE IF NOT EXISTS depth_charts (
    team_id integer NOT NULL, -- FK: references teams(team_id)
    person_id integer NOT NULL, -- FK: references people(person_id)
    salary_year integer NOT NULL,
    chart_type_lk text NOT NULL DEFAULT 'PRIMARY',
    position_lk text NOT NULL,
    depth_rank integer NOT NULL,
    position_2_lk text,
    role_lk text,
    roster_status_lk text,
    is_starter boolean DEFAULT false,
    notes text,
    availability_status_lk text,
    injury_description text,
    estimated_return_date date,
    updated_at timestamptz DEFAULT now(),
    updated_by_user_id text,
    source_drop_file text,
    source_record_id text,
    source_hash text,
    parser_version text,
    ingested_at timestamptz DEFAULT now(),

    PRIMARY KEY (team_id, salary_year, chart_type_lk, person_id, position_lk),
    UNIQUE (team_id, salary_year, chart_type_lk, position_lk, depth_rank)
);

CREATE INDEX IF NOT EXISTS idx_depth_charts_lookup ON depth_charts(team_id, salary_year, chart_type_lk);

-- ### injury_reports
-- Source: injury_reports.txt
CREATE TABLE IF NOT EXISTS injury_reports (
    injury_report_id serial PRIMARY KEY,
    person_id integer NOT NULL, -- FK: references people(person_id)
    team_id integer NOT NULL, -- FK: references teams(team_id)
    report_date date NOT NULL,
    salary_year integer NOT NULL,
    availability_status_lk text,
    participation_lk text,
    is_active_roster boolean,
    injury_description text,
    reason text,
    body_region_lk text,
    body_part_lk text,
    laterality_lk text,
    injury_type_lk text,
    is_covid_cardiac_clearance boolean,
    is_health_safety_protocol boolean,
    ps_games_missed_count integer DEFAULT 0,
    rs_games_missed_count integer DEFAULT 0,
    po_games_missed_count integer DEFAULT 0,
    notes text,
    estimated_return_date date,
    author_id text,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    source_drop_file text,
    source_hash text,
    parser_version text,
    ingested_at timestamptz DEFAULT now(),

    UNIQUE (person_id, team_id, report_date, salary_year)
);

CREATE INDEX IF NOT EXISTS idx_injury_reports_person_date ON injury_reports(person_id, report_date);
CREATE INDEX IF NOT EXISTS idx_injury_reports_team_year ON injury_reports(team_id, salary_year);

-- ### medical_intel
-- Source: medical_intel.txt
CREATE TABLE IF NOT EXISTS medical_intel (
    medical_intel_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    person_id integer NOT NULL, -- FK: references people(person_id)
    draft_year integer NOT NULL,
    is_medical_flag boolean DEFAULT false,
    is_intel_flag boolean DEFAULT false,
    red_flag_notes text,
    medical_history text,
    medical_history_finalized_at timestamptz,
    medical_history_finalized_by_id text,
    internal_assessment text,
    internal_assessment_risk_lk text,
    internal_assessment_finalized_at timestamptz,
    internal_assessment_finalized_by_id text,
    orthopedic_exam text,
    orthopedic_exam_risk_lk text,
    orthopedic_exam_finalized_at timestamptz,
    orthopedic_exam_finalized_by_id text,
    movement_performance text,
    movement_performance_finalized_at timestamptz,
    movement_performance_finalized_by_id text,
    scouting_review text,
    vaccination_status text,
    covid_history_json jsonb,
    intel_concerns_count integer DEFAULT 0,
    medical_concerns_count integer DEFAULT 0,
    imaging_requests_json jsonb,
    intel_reports_json jsonb,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    source_drop_file text,
    source_hash text,
    parser_version text,
    ingested_at timestamptz DEFAULT now(),

    UNIQUE (person_id, draft_year)
);

CREATE INDEX IF NOT EXISTS idx_medical_intel_person ON medical_intel(person_id);

-- ### scouting_reports
-- Source: scouting_reports.txt
CREATE TABLE IF NOT EXISTS scouting_reports (
    scouting_report_id serial PRIMARY KEY,
    scout_id text NOT NULL,
    scout_name text,
    player_id integer, -- FK: references people(person_id)
    team_id integer, -- FK: references teams(team_id)
    game_id text,
    event_id text,
    league_lk text,
    report_type text NOT NULL,
    vertical text,
    rubric_type text,
    evaluation_date date,
    overall_grade float,
    scout_rank integer,
    scouting_notes text,
    strengths text,
    weaknesses text,
    projected_role text,
    comparison_player_id integer,
    comparison_notes text,
    is_draft boolean DEFAULT false,
    is_final boolean DEFAULT true,
    grades_json jsonb,
    criteria_json jsonb,
    fields_json jsonb,
    source_system text,
    source_record_id text,
    created_at timestamptz,
    updated_at timestamptz,
    submitted_at timestamptz,
    source_drop_file text,
    source_hash text,
    parser_version text,
    ingested_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_scouting_reports_player ON scouting_reports(player_id);
CREATE INDEX IF NOT EXISTS idx_scouting_reports_scout ON scouting_reports(scout_id);

-- ### scouting_report_rubrics
-- Source: scouting_reports.txt
CREATE TABLE IF NOT EXISTS scouting_report_rubrics (
    rubric_id serial PRIMARY KEY,
    rubric_name text UNIQUE NOT NULL,
    description text,
    report_type text,
    definition_json jsonb,
    is_active boolean DEFAULT true,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now()
);
