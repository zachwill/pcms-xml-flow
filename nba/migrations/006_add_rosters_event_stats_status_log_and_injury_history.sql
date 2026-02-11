-- Add missing P0/P1 NBA ingestion tables:
-- - Team rosters (players/coaches)
-- - Game data status log history
-- - Injury history (alongside current nba.injuries snapshot)
--
-- NOTE: querytool_event_* tables that were originally here have been removed.
-- Shot chart data is now in nba.shot_chart (see migration 012).

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
