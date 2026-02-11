CREATE TABLE IF NOT EXISTS nba.boxscores_traditional (
    game_id text REFERENCES nba.games(game_id),
    nba_id integer REFERENCES nba.players(nba_id),
    team_id integer REFERENCES nba.teams(team_id),
    status text,
    not_playing_reason text,
    not_playing_description text,
    order_sequence integer,
    jersey_num text,
    position text,
    is_starter boolean,
    is_on_court boolean,
    played boolean,
    minutes numeric(8,2),
    pts integer,
    fgm integer,
    fga integer,
    fg_pct numeric(6,5),
    fg3m integer,
    fg3a integer,
    fg3_pct numeric(6,5),
    fg2m integer,
    fg2a integer,
    fg2_pct numeric(6,5),
    ftm integer,
    fta integer,
    ft_pct numeric(6,5),
    oreb integer,
    dreb integer,
    reb integer,
    ast integer,
    stl integer,
    blk integer,
    tov integer,
    pf integer,
    fouls_drawn integer,
    plus_minus numeric(5,1),
    created_at timestamptz,
    updated_at timestamptz,
    fetched_at timestamptz,
    PRIMARY KEY (game_id, nba_id)
);

CREATE INDEX IF NOT EXISTS boxscores_traditional_team_id_idx ON nba.boxscores_traditional (team_id);
CREATE INDEX IF NOT EXISTS boxscores_traditional_nba_id_idx ON nba.boxscores_traditional (nba_id);
CREATE INDEX IF NOT EXISTS boxscores_traditional_game_id_idx ON nba.boxscores_traditional (game_id);

CREATE TABLE IF NOT EXISTS nba.boxscores_traditional_team (
    game_id text REFERENCES nba.games(game_id),
    team_id integer REFERENCES nba.teams(team_id),
    minutes numeric(8,2),
    points integer,
    fgm integer,
    fga integer,
    fg_pct numeric(5,4),
    fg3m integer,
    fg3a integer,
    fg3_pct numeric(5,4),
    fg2m integer,
    fg2a integer,
    fg2_pct numeric(5,4),
    ftm integer,
    fta integer,
    ft_pct numeric(5,4),
    oreb integer,
    dreb integer,
    reb integer,
    ast integer,
    stl integer,
    blk integer,
    tov integer,
    pf integer,
    fouls_technical integer,
    fouls_team integer,
    fouls_team_technical integer,
    fouls_drawn integer,
    plus_minus numeric(5,1),
    pts_fast_break integer,
    pts_paint integer,
    pts_2nd_chance integer,
    bench_pts integer,
    biggest_lead integer,
    biggest_scoring_run integer,
    lead_changes integer,
    times_tied integer,
    ast_tov_ratio numeric(4,2),
    tov_team integer,
    tov_total integer,
    reb_team integer,
    reb_personal integer,
    created_at timestamptz,
    updated_at timestamptz,
    fetched_at timestamptz,
    PRIMARY KEY (game_id, team_id)
);

CREATE INDEX IF NOT EXISTS boxscores_traditional_team_team_id_idx ON nba.boxscores_traditional_team (team_id);
CREATE INDEX IF NOT EXISTS boxscores_traditional_team_game_id_idx ON nba.boxscores_traditional_team (game_id);

CREATE TABLE IF NOT EXISTS nba.boxscores_advanced (
    game_id text REFERENCES nba.games(game_id),
    nba_id integer REFERENCES nba.players(nba_id),
    team_id integer REFERENCES nba.teams(team_id),
    minutes numeric(8,2),
    off_rating numeric(6,2),
    def_rating numeric(6,2),
    net_rating numeric(6,2),
    ast_pct numeric(5,4),
    ast_to_ratio numeric(6,2),
    ast_ratio numeric(6,2),
    oreb_pct numeric(5,4),
    dreb_pct numeric(5,4),
    reb_pct numeric(5,4),
    tm_tov_pct numeric(5,4),
    efg_pct numeric(5,4),
    ts_pct numeric(5,4),
    usg_pct numeric(5,4),
    e_off_rating numeric(6,2),
    e_def_rating numeric(6,2),
    e_net_rating numeric(6,2),
    e_ast_ratio numeric(6,2),
    e_oreb_pct numeric(5,4),
    e_dreb_pct numeric(5,4),
    e_reb_pct numeric(5,4),
    e_tm_tov_pct numeric(5,4),
    e_usg_pct numeric(5,4),
    e_pace numeric(6,2),
    pace numeric(6,2),
    pace_per40 numeric(6,2),
    poss integer,
    pie numeric(5,4),
    created_at timestamptz,
    updated_at timestamptz,
    fetched_at timestamptz,
    PRIMARY KEY (game_id, nba_id)
);

CREATE INDEX IF NOT EXISTS boxscores_advanced_team_id_idx ON nba.boxscores_advanced (team_id);
CREATE INDEX IF NOT EXISTS boxscores_advanced_nba_id_idx ON nba.boxscores_advanced (nba_id);
CREATE INDEX IF NOT EXISTS boxscores_advanced_game_id_idx ON nba.boxscores_advanced (game_id);

CREATE TABLE IF NOT EXISTS nba.boxscores_advanced_team (
    game_id text REFERENCES nba.games(game_id),
    team_id integer REFERENCES nba.teams(team_id),
    minutes numeric(8,2),
    off_rating numeric(6,2),
    def_rating numeric(6,2),
    net_rating numeric(6,2),
    ast_pct numeric(5,4),
    ast_to_ratio numeric(6,2),
    ast_ratio numeric(6,2),
    oreb_pct numeric(5,4),
    dreb_pct numeric(5,4),
    reb_pct numeric(5,4),
    tm_tov_pct numeric(5,4),
    efg_pct numeric(5,4),
    ts_pct numeric(5,4),
    pace numeric(6,2),
    pace_per40 numeric(6,2),
    poss integer,
    pie numeric(5,4),
    created_at timestamptz,
    updated_at timestamptz,
    fetched_at timestamptz,
    PRIMARY KEY (game_id, team_id)
);

CREATE INDEX IF NOT EXISTS boxscores_advanced_team_team_id_idx ON nba.boxscores_advanced_team (team_id);
CREATE INDEX IF NOT EXISTS boxscores_advanced_team_game_id_idx ON nba.boxscores_advanced_team (game_id);

CREATE TABLE IF NOT EXISTS nba.play_by_play (
    game_id text REFERENCES nba.games(game_id),
    pbp_json jsonb,
    created_at timestamptz,
    updated_at timestamptz,
    fetched_at timestamptz,
    PRIMARY KEY (game_id)
);

CREATE INDEX IF NOT EXISTS play_by_play_game_id_idx ON nba.play_by_play (game_id);
CREATE INDEX IF NOT EXISTS play_by_play_pbp_json_gin ON nba.play_by_play USING gin (pbp_json);

CREATE TABLE IF NOT EXISTS nba.players_on_court (
    game_id text REFERENCES nba.games(game_id),
    poc_json jsonb,
    created_at timestamptz,
    updated_at timestamptz,
    fetched_at timestamptz,
    PRIMARY KEY (game_id)
);

CREATE INDEX IF NOT EXISTS players_on_court_game_id_idx ON nba.players_on_court (game_id);
CREATE INDEX IF NOT EXISTS players_on_court_poc_json_gin ON nba.players_on_court USING gin (poc_json);

CREATE TABLE IF NOT EXISTS nba.hustle_stats (
    game_id text REFERENCES nba.games(game_id),
    nba_id integer REFERENCES nba.players(nba_id),
    team_id integer REFERENCES nba.teams(team_id),
    minutes numeric(8,2),
    contested_field_goals integer,
    contested_2pt_field_goals integer,
    contested_3pt_field_goals integer,
    deflections integer,
    loose_balls_recovered integer,
    loose_balls_recovered_offensive integer,
    loose_balls_recovered_defensive integer,
    charges_drawn integer,
    screen_assists integer,
    screen_assists_pts integer,
    boxouts integer,
    boxouts_offensive integer,
    boxouts_defensive integer,
    boxout_player_rebound_pct numeric(5,2),
    boxout_team_rebound_pct numeric(5,2),
    forced_turnovers integer,
    created_at timestamptz,
    updated_at timestamptz,
    fetched_at timestamptz,
    PRIMARY KEY (game_id, nba_id)
);

CREATE INDEX IF NOT EXISTS hustle_stats_team_id_idx ON nba.hustle_stats (team_id);
CREATE INDEX IF NOT EXISTS hustle_stats_nba_id_idx ON nba.hustle_stats (nba_id);
CREATE INDEX IF NOT EXISTS hustle_stats_game_id_idx ON nba.hustle_stats (game_id);

CREATE TABLE IF NOT EXISTS nba.hustle_stats_team (
    game_id text REFERENCES nba.games(game_id),
    team_id integer REFERENCES nba.teams(team_id),
    contested_field_goals integer,
    contested_2pt_field_goals integer,
    contested_3pt_field_goals integer,
    deflections integer,
    loose_balls_recovered integer,
    loose_balls_recovered_offensive integer,
    loose_balls_recovered_defensive integer,
    charges_drawn integer,
    screen_assists integer,
    screen_assists_pts integer,
    boxouts integer,
    boxouts_offensive integer,
    boxouts_defensive integer,
    boxout_team_rebound_pct numeric(5,2),
    forced_turnovers integer,
    created_at timestamptz,
    updated_at timestamptz,
    fetched_at timestamptz,
    PRIMARY KEY (game_id, team_id)
);

CREATE INDEX IF NOT EXISTS hustle_stats_team_team_id_idx ON nba.hustle_stats_team (team_id);
CREATE INDEX IF NOT EXISTS hustle_stats_team_game_id_idx ON nba.hustle_stats_team (game_id);

CREATE TABLE IF NOT EXISTS nba.hustle_events (
    game_id text REFERENCES nba.games(game_id),
    hustle_events_json jsonb,
    created_at timestamptz,
    updated_at timestamptz,
    fetched_at timestamptz,
    PRIMARY KEY (game_id)
);

CREATE INDEX IF NOT EXISTS hustle_events_game_id_idx ON nba.hustle_events (game_id);
CREATE INDEX IF NOT EXISTS hustle_events_json_gin ON nba.hustle_events USING gin (hustle_events_json);

CREATE TABLE IF NOT EXISTS nba.tracking_stats (
    game_id text REFERENCES nba.games(game_id),
    team_id integer REFERENCES nba.teams(team_id),
    nba_id integer REFERENCES nba.players(nba_id),
    minutes numeric(8,2),
    dist_miles numeric(6,2),
    dist_miles_off numeric(6,2),
    dist_miles_def numeric(6,2),
    avg_speed numeric(5,2),
    avg_speed_off numeric(5,2),
    avg_speed_def numeric(5,2),
    touches integer,
    secondary_ast integer,
    ft_ast integer,
    passes integer,
    ast integer,
    cfgm integer,
    cfga integer,
    cfg_pct numeric(5,4),
    uf_fgm integer,
    uf_fga integer,
    uf_fg_pct numeric(5,4),
    fg_pct numeric(5,4),
    fg2m integer,
    fg2a integer,
    fg2_pct numeric(5,4),
    dfgm integer,
    dfga integer,
    dfg_pct numeric(5,4),
    created_at timestamptz,
    updated_at timestamptz,
    fetched_at timestamptz,
    PRIMARY KEY (game_id, nba_id)
);

CREATE INDEX IF NOT EXISTS tracking_stats_team_id_idx ON nba.tracking_stats (team_id);
CREATE INDEX IF NOT EXISTS tracking_stats_nba_id_idx ON nba.tracking_stats (nba_id);
CREATE INDEX IF NOT EXISTS tracking_stats_game_id_idx ON nba.tracking_stats (game_id);

CREATE TABLE IF NOT EXISTS nba.tracking_streams (
    stream_id text PRIMARY KEY,
    game_id text REFERENCES nba.games(game_id),
    stream_name text,
    processor_name text,
    status text,
    stream_created_at timestamptz,
    expires_at timestamptz,
    created_at timestamptz,
    updated_at timestamptz,
    fetched_at timestamptz
);

CREATE INDEX IF NOT EXISTS tracking_streams_game_id_idx ON nba.tracking_streams (game_id);
CREATE INDEX IF NOT EXISTS tracking_streams_status_idx ON nba.tracking_streams (status);
