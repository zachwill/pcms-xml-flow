-- Add missing P0/P1 NBA ingestion tables:
-- - Team rosters (players/coaches)
-- - Query Tool event-level stats (player/team/league)
-- - Game data status log history
-- - Injury history (alongside current nba.injuries snapshot)

CREATE TABLE IF NOT EXISTS nba.team_roster_players (
    league_id text NOT NULL,
    season_year integer,
    season_label text NOT NULL,
    team_id integer NOT NULL REFERENCES nba.teams(team_id),
    team_city text,
    team_name text,
    team_tricode text,
    nba_id integer NOT NULL,
    player_name text,
    player_slug text,
    jersey_num text,
    position text,
    height text,
    weight text,
    birthdate date,
    age integer,
    season_experience text,
    school text,
    is_two_way boolean,
    is_ten_day boolean,
    roster_json jsonb,
    created_at timestamptz,
    updated_at timestamptz,
    fetched_at timestamptz,
    PRIMARY KEY (league_id, season_label, team_id, nba_id)
);

CREATE INDEX IF NOT EXISTS team_roster_players_team_id_idx ON nba.team_roster_players (team_id);
CREATE INDEX IF NOT EXISTS team_roster_players_nba_id_idx ON nba.team_roster_players (nba_id);
CREATE INDEX IF NOT EXISTS team_roster_players_season_idx ON nba.team_roster_players (season_year, season_label);

CREATE TABLE IF NOT EXISTS nba.team_roster_coaches (
    league_id text NOT NULL,
    season_year integer,
    season_label text NOT NULL,
    team_id integer NOT NULL REFERENCES nba.teams(team_id),
    team_city text,
    team_name text,
    team_tricode text,
    coach_id integer NOT NULL,
    coach_name text,
    coach_type text,
    is_assistant integer,
    sort_sequence integer,
    coach_json jsonb,
    created_at timestamptz,
    updated_at timestamptz,
    fetched_at timestamptz,
    PRIMARY KEY (league_id, season_label, team_id, coach_id)
);

CREATE INDEX IF NOT EXISTS team_roster_coaches_team_id_idx ON nba.team_roster_coaches (team_id);
CREATE INDEX IF NOT EXISTS team_roster_coaches_season_idx ON nba.team_roster_coaches (season_year, season_label);

CREATE TABLE IF NOT EXISTS nba.querytool_event_player (
    query_hash text NOT NULL,
    row_hash text NOT NULL,
    league_id text,
    season_year integer,
    season_label text,
    season_type text,
    game_id text,
    game_date date,
    nba_id integer,
    team_id integer,
    team_name text,
    team_tricode text,
    opponent_name text,
    event_number integer,
    period integer,
    game_clock numeric(10,3),
    x integer,
    y integer,
    event_type text,
    per_mode text,
    sum_scope text,
    query_grouping text,
    team_grouping text,
    stats_json jsonb,
    row_json jsonb,
    query_params_json jsonb,
    first_seen_at timestamptz,
    last_seen_at timestamptz,
    created_at timestamptz,
    updated_at timestamptz,
    fetched_at timestamptz,
    PRIMARY KEY (query_hash, row_hash)
);

CREATE INDEX IF NOT EXISTS querytool_event_player_game_id_idx ON nba.querytool_event_player (game_id);
CREATE INDEX IF NOT EXISTS querytool_event_player_nba_id_idx ON nba.querytool_event_player (nba_id);
CREATE INDEX IF NOT EXISTS querytool_event_player_team_id_idx ON nba.querytool_event_player (team_id);
CREATE INDEX IF NOT EXISTS querytool_event_player_event_type_idx ON nba.querytool_event_player (event_type);
CREATE INDEX IF NOT EXISTS querytool_event_player_stats_json_gin ON nba.querytool_event_player USING gin (stats_json);

CREATE TABLE IF NOT EXISTS nba.querytool_event_team (
    query_hash text NOT NULL,
    row_hash text NOT NULL,
    league_id text,
    season_year integer,
    season_label text,
    season_type text,
    game_id text,
    game_date date,
    team_id integer,
    team_name text,
    team_tricode text,
    opponent_name text,
    event_number integer,
    period integer,
    game_clock numeric(10,3),
    x integer,
    y integer,
    event_type text,
    per_mode text,
    sum_scope text,
    query_grouping text,
    stats_json jsonb,
    row_json jsonb,
    query_params_json jsonb,
    first_seen_at timestamptz,
    last_seen_at timestamptz,
    created_at timestamptz,
    updated_at timestamptz,
    fetched_at timestamptz,
    PRIMARY KEY (query_hash, row_hash)
);

CREATE INDEX IF NOT EXISTS querytool_event_team_game_id_idx ON nba.querytool_event_team (game_id);
CREATE INDEX IF NOT EXISTS querytool_event_team_team_id_idx ON nba.querytool_event_team (team_id);
CREATE INDEX IF NOT EXISTS querytool_event_team_event_type_idx ON nba.querytool_event_team (event_type);
CREATE INDEX IF NOT EXISTS querytool_event_team_stats_json_gin ON nba.querytool_event_team USING gin (stats_json);

CREATE TABLE IF NOT EXISTS nba.querytool_event_league (
    query_hash text NOT NULL,
    row_hash text NOT NULL,
    league_id text,
    season_year integer,
    season_label text,
    season_type text,
    game_id text,
    game_date date,
    visitor_team_name text,
    home_team_name text,
    game_score text,
    event_number integer,
    period integer,
    game_clock numeric(10,3),
    x integer,
    y integer,
    event_type text,
    per_mode text,
    sum_scope text,
    query_grouping text,
    stats_json jsonb,
    row_json jsonb,
    query_params_json jsonb,
    first_seen_at timestamptz,
    last_seen_at timestamptz,
    created_at timestamptz,
    updated_at timestamptz,
    fetched_at timestamptz,
    PRIMARY KEY (query_hash, row_hash)
);

CREATE INDEX IF NOT EXISTS querytool_event_league_game_id_idx ON nba.querytool_event_league (game_id);
CREATE INDEX IF NOT EXISTS querytool_event_league_event_type_idx ON nba.querytool_event_league (event_type);
CREATE INDEX IF NOT EXISTS querytool_event_league_stats_json_gin ON nba.querytool_event_league USING gin (stats_json);

CREATE TABLE IF NOT EXISTS nba.game_data_status_log (
    league_id text NOT NULL,
    season_year text NOT NULL,
    game_id text NOT NULL,
    status_hash text NOT NULL,
    generated_time text,
    generated_time_utc timestamptz,
    last_update_season_stats timestamptz,
    last_update_season_stats_utc timestamptz,
    home_team_id integer,
    visitor_team_id integer,
    game_date_est date,
    game_time_est text,
    last_update_game_schedule timestamptz,
    last_update_game_stats timestamptz,
    last_update_game_tracking timestamptz,
    first_seen_at timestamptz,
    last_seen_at timestamptz,
    created_at timestamptz,
    updated_at timestamptz,
    fetched_at timestamptz,
    PRIMARY KEY (league_id, season_year, game_id, status_hash)
);

CREATE INDEX IF NOT EXISTS game_data_status_log_game_id_idx ON nba.game_data_status_log (game_id);
CREATE INDEX IF NOT EXISTS game_data_status_log_last_update_stats_idx ON nba.game_data_status_log (last_update_game_stats);
CREATE INDEX IF NOT EXISTS game_data_status_log_last_update_tracking_idx ON nba.game_data_status_log (last_update_game_tracking);
CREATE INDEX IF NOT EXISTS game_data_status_log_last_seen_idx ON nba.game_data_status_log (last_seen_at);

CREATE TABLE IF NOT EXISTS nba.injuries_history (
    nba_id integer NOT NULL REFERENCES nba.players(nba_id),
    team_id integer NOT NULL REFERENCES nba.teams(team_id),
    status_hash text NOT NULL,
    injury_status text,
    injury_type text,
    injury_location text,
    injury_details text,
    injury_side text,
    return_date text,
    first_seen_at timestamptz,
    last_seen_at timestamptz,
    created_at timestamptz,
    updated_at timestamptz,
    fetched_at timestamptz,
    PRIMARY KEY (nba_id, team_id, status_hash)
);

CREATE INDEX IF NOT EXISTS injuries_history_team_id_idx ON nba.injuries_history (team_id);
CREATE INDEX IF NOT EXISTS injuries_history_nba_id_idx ON nba.injuries_history (nba_id);
CREATE INDEX IF NOT EXISTS injuries_history_last_seen_idx ON nba.injuries_history (last_seen_at);
