-- Add standings extras:
-- - /api/standings/playoff/bracket snapshots
-- - /api/standings/ist team standings snapshots

CREATE TABLE IF NOT EXISTS nba.standings_playoff_bracket (
    league_id text NOT NULL,
    season_year integer,
    season_label text NOT NULL,
    bracket_state text NOT NULL,
    bracket_type text,
    standing_date date NOT NULL,
    meta_time timestamptz,
    playoff_picture_series_count integer,
    play_in_bracket_series_count integer,
    playoff_bracket_series_count integer,
    ist_bracket_series_count integer,
    bracket_json jsonb,
    created_at timestamptz,
    updated_at timestamptz,
    fetched_at timestamptz,
    PRIMARY KEY (league_id, season_label, bracket_state, standing_date)
);

CREATE INDEX IF NOT EXISTS standings_playoff_bracket_season_idx
    ON nba.standings_playoff_bracket (season_year, season_label);
CREATE INDEX IF NOT EXISTS standings_playoff_bracket_state_idx
    ON nba.standings_playoff_bracket (bracket_state);
CREATE INDEX IF NOT EXISTS standings_playoff_bracket_date_idx
    ON nba.standings_playoff_bracket (standing_date);
CREATE INDEX IF NOT EXISTS standings_playoff_bracket_json_gin
    ON nba.standings_playoff_bracket USING gin (bracket_json);

CREATE TABLE IF NOT EXISTS nba.standings_ist (
    league_id text NOT NULL,
    season_year integer,
    season_label text NOT NULL,
    team_id integer NOT NULL REFERENCES nba.teams(team_id),
    standing_date date NOT NULL,
    team_city text,
    team_name text,
    team_tricode text,
    team_slug text,
    conference text,
    ist_group text,
    clinch_indicator text,
    is_clinched_ist_knockout boolean,
    is_clinched_ist_group boolean,
    is_clinched_ist_wildcard boolean,
    ist_wildcard_rank integer,
    ist_group_rank integer,
    ist_knockout_rank integer,
    wins integer,
    losses integer,
    win_pct numeric,
    ist_group_gb numeric,
    ist_wildcard_gb numeric,
    diff integer,
    pts integer,
    opp_pts integer,
    games_json jsonb,
    created_at timestamptz,
    updated_at timestamptz,
    fetched_at timestamptz,
    PRIMARY KEY (league_id, season_label, team_id, standing_date)
);

CREATE INDEX IF NOT EXISTS standings_ist_team_id_idx ON nba.standings_ist (team_id);
CREATE INDEX IF NOT EXISTS standings_ist_season_idx ON nba.standings_ist (season_year, season_label);
CREATE INDEX IF NOT EXISTS standings_ist_date_idx ON nba.standings_ist (standing_date);
CREATE INDEX IF NOT EXISTS standings_ist_group_idx ON nba.standings_ist (ist_group);
CREATE INDEX IF NOT EXISTS standings_ist_games_json_gin ON nba.standings_ist USING gin (games_json);
