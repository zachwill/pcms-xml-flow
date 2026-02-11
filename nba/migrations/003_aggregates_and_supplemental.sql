CREATE TABLE IF NOT EXISTS nba.player_stats_aggregated (
    nba_id integer REFERENCES nba.players(nba_id),
    team_id integer REFERENCES nba.teams(team_id),
    season_year integer,
    season_label text,
    season_type text,
    per_mode text,
    measure_type text,
    games_played integer,
    minutes numeric(8,2),
    fgm numeric(8,2),
    fga numeric(8,2),
    fg_pct numeric(5,4),
    fg3m numeric(8,2),
    fg3a numeric(8,2),
    fg3_pct numeric(5,4),
    fg2m numeric(8,2),
    fg2a numeric(8,2),
    fg2_pct numeric(5,4),
    ftm numeric(8,2),
    fta numeric(8,2),
    ft_pct numeric(5,4),
    oreb numeric(8,2),
    dreb numeric(8,2),
    reb numeric(8,2),
    ast numeric(8,2),
    stl numeric(8,2),
    blk numeric(8,2),
    tov numeric(8,2),
    pf numeric(8,2),
    pts numeric(8,2),
    plus_minus numeric(8,2),
    double_doubles integer,
    triple_doubles integer,
    off_rating numeric(6,2),
    def_rating numeric(6,2),
    net_rating numeric(6,2),
    ast_pct numeric(5,4),
    ast_tov numeric(6,2),
    ast_ratio numeric(6,2),
    oreb_pct numeric(5,4),
    dreb_pct numeric(5,4),
    reb_pct numeric(5,4),
    tm_tov_pct numeric(5,4),
    efg_pct numeric(5,4),
    ts_pct numeric(5,4),
    usg_pct numeric(5,4),
    pace numeric(6,2),
    pie numeric(5,4),
    poss numeric(10,2),
    fta_rate numeric(6,3),
    pts_off_tov numeric(8,2),
    pts_2nd_chance numeric(8,2),
    pts_fb numeric(8,2),
    pts_paint numeric(8,2),
    opp_pts_off_tov numeric(8,2),
    opp_pts_2nd_chance numeric(8,2),
    opp_pts_fb numeric(8,2),
    opp_pts_paint numeric(8,2),
    nba_fantasy_pts numeric(10,2),
    created_at timestamptz,
    updated_at timestamptz,
    fetched_at timestamptz,
    PRIMARY KEY (nba_id, team_id, season_year, season_type, per_mode, measure_type)
);

CREATE INDEX IF NOT EXISTS player_stats_aggregated_nba_id_idx ON nba.player_stats_aggregated (nba_id);
CREATE INDEX IF NOT EXISTS player_stats_aggregated_team_id_idx ON nba.player_stats_aggregated (team_id);
CREATE INDEX IF NOT EXISTS player_stats_aggregated_season_idx ON nba.player_stats_aggregated (season_year, season_type);
CREATE INDEX IF NOT EXISTS player_stats_aggregated_season_label_idx ON nba.player_stats_aggregated (season_label);

CREATE TABLE IF NOT EXISTS nba.team_stats_aggregated (
    team_id integer REFERENCES nba.teams(team_id),
    season_year integer,
    season_label text,
    season_type text,
    per_mode text,
    measure_type text,
    games_played integer,
    wins integer,
    losses integer,
    win_pct numeric(5,4),
    minutes numeric(8,2),
    fgm numeric(8,2),
    fga numeric(8,2),
    fg_pct numeric(5,4),
    fg3m numeric(8,2),
    fg3a numeric(8,2),
    fg3_pct numeric(5,4),
    fg2m numeric(8,2),
    fg2a numeric(8,2),
    fg2_pct numeric(5,4),
    ftm numeric(8,2),
    fta numeric(8,2),
    ft_pct numeric(5,4),
    oreb numeric(8,2),
    dreb numeric(8,2),
    reb numeric(8,2),
    ast numeric(8,2),
    stl numeric(8,2),
    blk numeric(8,2),
    tov numeric(8,2),
    pf numeric(8,2),
    pts numeric(8,2),
    plus_minus numeric(8,2),
    off_rating numeric(6,2),
    def_rating numeric(6,2),
    net_rating numeric(6,2),
    ast_pct numeric(5,4),
    ast_tov numeric(6,2),
    ast_ratio numeric(6,2),
    oreb_pct numeric(5,4),
    dreb_pct numeric(5,4),
    reb_pct numeric(5,4),
    tm_tov_pct numeric(5,4),
    efg_pct numeric(5,4),
    ts_pct numeric(5,4),
    pace numeric(6,2),
    pie numeric(5,4),
    poss numeric(10,2),
    fta_rate numeric(6,3),
    pts_off_tov numeric(8,2),
    pts_2nd_chance numeric(8,2),
    pts_fb numeric(8,2),
    pts_paint numeric(8,2),
    opp_pts_off_tov numeric(8,2),
    opp_pts_2nd_chance numeric(8,2),
    opp_pts_fb numeric(8,2),
    opp_pts_paint numeric(8,2),
    created_at timestamptz,
    updated_at timestamptz,
    fetched_at timestamptz,
    PRIMARY KEY (team_id, season_year, season_type, per_mode, measure_type)
);

CREATE INDEX IF NOT EXISTS team_stats_aggregated_team_id_idx ON nba.team_stats_aggregated (team_id);
CREATE INDEX IF NOT EXISTS team_stats_aggregated_season_idx ON nba.team_stats_aggregated (season_year, season_type);
CREATE INDEX IF NOT EXISTS team_stats_aggregated_season_label_idx ON nba.team_stats_aggregated (season_label);

CREATE TABLE IF NOT EXISTS nba.lineup_stats_season (
    league_id text,
    season_year integer,
    season_label text,
    season_type text,
    team_id integer REFERENCES nba.teams(team_id),
    player_ids integer[],
    per_mode text,
    measure_type text,
    gp integer,
    minutes numeric(8,2),
    off_rating numeric(5,2),
    def_rating numeric(5,2),
    net_rating numeric(5,2),
    ast_pct numeric(5,4),
    ast_tov numeric(5,2),
    ast_ratio numeric(5,2),
    oreb_pct numeric(5,4),
    dreb_pct numeric(5,4),
    reb_pct numeric(5,4),
    tm_tov_pct numeric(5,4),
    efg_pct numeric(5,4),
    ts_pct numeric(5,4),
    usg_pct numeric(5,4),
    pace numeric(6,2),
    pie numeric(5,4),
    created_at timestamptz,
    updated_at timestamptz,
    fetched_at timestamptz,
    PRIMARY KEY (league_id, season_year, season_type, team_id, player_ids, per_mode, measure_type)
);

CREATE INDEX IF NOT EXISTS lineup_stats_season_season_idx ON nba.lineup_stats_season (season_year, season_type);
CREATE INDEX IF NOT EXISTS lineup_stats_season_team_id_idx ON nba.lineup_stats_season (team_id);
CREATE INDEX IF NOT EXISTS lineup_stats_season_player_ids_idx ON nba.lineup_stats_season (player_ids);
CREATE INDEX IF NOT EXISTS lineup_stats_season_league_id_idx ON nba.lineup_stats_season (league_id);

CREATE TABLE IF NOT EXISTS nba.lineup_stats_game (
    game_id text REFERENCES nba.games(game_id),
    league_id text,
    season_year integer,
    season_label text,
    season_type text,
    team_id integer REFERENCES nba.teams(team_id),
    player_ids integer[],
    per_mode text,
    measure_type text,
    gp integer,
    minutes numeric(8,2),
    off_rating numeric(5,2),
    def_rating numeric(5,2),
    net_rating numeric(5,2),
    ast_pct numeric(5,4),
    ast_tov numeric(5,2),
    ast_ratio numeric(5,2),
    oreb_pct numeric(5,4),
    dreb_pct numeric(5,4),
    reb_pct numeric(5,4),
    tm_tov_pct numeric(5,4),
    efg_pct numeric(5,4),
    ts_pct numeric(5,4),
    usg_pct numeric(5,4),
    pace numeric(6,2),
    pie numeric(5,4),
    created_at timestamptz,
    updated_at timestamptz,
    fetched_at timestamptz,
    PRIMARY KEY (game_id, team_id, player_ids, per_mode, measure_type)
);

CREATE INDEX IF NOT EXISTS lineup_stats_game_game_id_idx ON nba.lineup_stats_game (game_id);
CREATE INDEX IF NOT EXISTS lineup_stats_game_team_id_idx ON nba.lineup_stats_game (team_id);
CREATE INDEX IF NOT EXISTS lineup_stats_game_player_ids_idx ON nba.lineup_stats_game (player_ids);

CREATE TABLE IF NOT EXISTS nba.lineups (
    team_id integer REFERENCES nba.teams(team_id),
    player_ids integer[],
    gp integer,
    minutes numeric(8,2),
    off_rating numeric(5,2),
    def_rating numeric(5,2),
    net_rating numeric(5,2),
    ast_pct numeric(5,4),
    ast_tov numeric(5,2),
    ast_ratio numeric(5,2),
    oreb_pct numeric(5,4),
    dreb_pct numeric(5,4),
    reb_pct numeric(5,4),
    tm_tov_pct numeric(5,4),
    efg_pct numeric(5,4),
    ts_pct numeric(5,4),
    usg_pct numeric(5,4),
    pace numeric(6,2),
    pie numeric(5,4),
    created_at timestamptz,
    updated_at timestamptz,
    fetched_at timestamptz,
    PRIMARY KEY (team_id, player_ids)
);

CREATE INDEX IF NOT EXISTS lineups_team_id_idx ON nba.lineups (team_id);
CREATE INDEX IF NOT EXISTS lineups_player_ids_idx ON nba.lineups (player_ids);

CREATE TABLE IF NOT EXISTS nba.injuries (
    nba_id integer REFERENCES nba.players(nba_id),
    team_id integer REFERENCES nba.teams(team_id),
    injury_status text,
    injury_type text,
    injury_location text,
    injury_details text,
    injury_side text,
    return_date text,
    created_at timestamptz,
    updated_at timestamptz,
    fetched_at timestamptz,
    PRIMARY KEY (nba_id, team_id)
);

CREATE INDEX IF NOT EXISTS injuries_team_id_idx ON nba.injuries (team_id);
CREATE INDEX IF NOT EXISTS injuries_nba_id_idx ON nba.injuries (nba_id);

CREATE TABLE IF NOT EXISTS nba.alerts (
    alert_id text PRIMARY KEY,
    game_id text REFERENCES nba.games(game_id),
    team_id integer REFERENCES nba.teams(team_id),
    alert_type text,
    alert_text text,
    alert_priority integer,
    alert_json jsonb,
    created_at timestamptz,
    updated_at timestamptz,
    fetched_at timestamptz
);

CREATE INDEX IF NOT EXISTS alerts_game_id_idx ON nba.alerts (game_id);
CREATE INDEX IF NOT EXISTS alerts_team_id_idx ON nba.alerts (team_id);
CREATE INDEX IF NOT EXISTS alerts_alert_type_idx ON nba.alerts (alert_type);

CREATE TABLE IF NOT EXISTS nba.pregame_storylines (
    game_id text REFERENCES nba.games(game_id),
    team_id integer REFERENCES nba.teams(team_id),
    storyline_text text,
    storyline_order integer,
    storyline_json jsonb,
    created_at timestamptz,
    updated_at timestamptz,
    fetched_at timestamptz,
    PRIMARY KEY (game_id, team_id, storyline_order)
);

CREATE INDEX IF NOT EXISTS pregame_storylines_game_id_idx ON nba.pregame_storylines (game_id);
