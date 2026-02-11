CREATE SCHEMA IF NOT EXISTS nba;

CREATE TABLE IF NOT EXISTS nba.teams (
    team_id integer PRIMARY KEY,
    team_name text,
    team_city text,
    team_full_name text,
    team_tricode text,
    team_slug text,
    league_id text,
    conference text,
    division text,
    state text,
    arena_name text,
    arena_city text,
    arena_state text,
    arena_timezone text,
    is_active boolean DEFAULT true,
    ngss_team_id text,
    created_at timestamptz,
    updated_at timestamptz,
    fetched_at timestamptz
);

CREATE INDEX IF NOT EXISTS teams_team_tricode_idx ON nba.teams (team_tricode);
CREATE INDEX IF NOT EXISTS teams_league_id_idx ON nba.teams (league_id);
CREATE INDEX IF NOT EXISTS teams_ngss_team_id_idx ON nba.teams (ngss_team_id);

CREATE TABLE IF NOT EXISTS nba.players (
    nba_id integer PRIMARY KEY,
    first_name text,
    last_name text,
    full_name text,
    player_slug text,
    is_active boolean,
    status text,
    position text,
    jersey text,
    height text,
    weight text,
    birthdate date,
    country text,
    last_affiliation text,
    draft_year integer,
    draft_round integer,
    draft_number integer,
    season_exp integer,
    from_year integer,
    to_year integer,
    current_team_id integer,
    current_team_tricode text,
    league_id text,
    dleague_flag boolean,
    nba_flag boolean,
    games_played_flag boolean,
    draft_flag boolean,
    greatest_75_flag boolean,
    roster_status text,
    ngss_person_id text,
    created_at timestamptz,
    updated_at timestamptz,
    fetched_at timestamptz
);

CREATE INDEX IF NOT EXISTS players_current_team_id_idx ON nba.players (current_team_id);
CREATE INDEX IF NOT EXISTS players_full_name_idx ON nba.players (full_name);
CREATE INDEX IF NOT EXISTS players_player_slug_idx ON nba.players (player_slug);

CREATE TABLE IF NOT EXISTS nba.schedules (
    season_year integer,
    season_label text,
    league_id text,
    stats_season_id text,
    roster_season_id text,
    schedule_season_id text,
    standings_season_id text,
    ngss_season_id text,
    weeks_json jsonb,
    full_schedule_json jsonb,
    broadcasters_json jsonb,
    season_calendar_json jsonb,
    created_at timestamptz,
    updated_at timestamptz,
    fetched_at timestamptz,
    PRIMARY KEY (season_year, league_id)
);

CREATE INDEX IF NOT EXISTS schedules_stats_season_id_idx ON nba.schedules (stats_season_id);
CREATE INDEX IF NOT EXISTS schedules_ngss_season_id_idx ON nba.schedules (ngss_season_id);
CREATE INDEX IF NOT EXISTS schedules_league_id_idx ON nba.schedules (league_id);
CREATE INDEX IF NOT EXISTS schedules_season_label_idx ON nba.schedules (season_label);

CREATE TABLE IF NOT EXISTS nba.games (
    game_id text PRIMARY KEY,
    league_id text,
    season_year integer,
    season_label text,
    season_type text,
    game_date date,
    game_sequence integer,
    postponed_status text,
    game_date_est timestamptz,
    game_date_utc timestamptz,
    game_time_utc timestamptz,
    game_datetime_utc timestamptz,
    game_code text,
    game_status integer,
    game_status_text text,
    period integer,
    game_clock text,
    home_team_id integer REFERENCES nba.teams(team_id),
    away_team_id integer REFERENCES nba.teams(team_id),
    home_score integer,
    away_score integer,
    home_wins integer,
    home_losses integer,
    away_wins integer,
    away_losses integer,
    arena_name text,
    arena_city text,
    arena_state text,
    arena_timezone text,
    attendance integer,
    game_duration_minutes integer,
    week_number integer,
    week_name text,
    game_label text,
    game_sublabel text,
    game_subtype text,
    series_game_number text,
    series_text text,
    series_conference text,
    po_round integer,
    if_necessary boolean,
    is_neutral boolean,
    is_target_score_ending boolean,
    target_score_period integer,
    target_score integer,
    national_broadcasters text[],
    home_tv_broadcasters text[],
    home_radio_broadcasters text[],
    away_tv_broadcasters text[],
    away_radio_broadcasters text[],
    game_json jsonb,
    ngss_game_id text,
    created_at timestamptz,
    updated_at timestamptz,
    fetched_at timestamptz
);

CREATE INDEX IF NOT EXISTS games_game_date_idx ON nba.games (game_date);
CREATE INDEX IF NOT EXISTS games_home_team_id_idx ON nba.games (home_team_id);
CREATE INDEX IF NOT EXISTS games_away_team_id_idx ON nba.games (away_team_id);
CREATE INDEX IF NOT EXISTS games_season_year_season_type_idx ON nba.games (season_year, season_type);
CREATE INDEX IF NOT EXISTS games_season_label_idx ON nba.games (season_label);
CREATE INDEX IF NOT EXISTS games_league_id_idx ON nba.games (league_id);
CREATE INDEX IF NOT EXISTS games_ngss_game_id_idx ON nba.games (ngss_game_id);

CREATE TABLE IF NOT EXISTS nba.playoff_series (
    series_id text PRIMARY KEY,
    league_id text,
    season_year integer,
    season_label text,
    season_type text,
    round_number integer,
    series_number integer,
    series_conference text,
    series_text text,
    series_status text,
    high_seed_id integer REFERENCES nba.teams(team_id),
    low_seed_id integer REFERENCES nba.teams(team_id),
    high_seed_rank integer,
    low_seed_rank integer,
    high_seed_series_wins integer,
    low_seed_series_wins integer,
    series_winner_team_id integer REFERENCES nba.teams(team_id),
    next_series_id text,
    next_game_id text,
    series_game_id_prefix text,
    series_json jsonb,
    created_at timestamptz,
    updated_at timestamptz,
    fetched_at timestamptz
);

CREATE INDEX IF NOT EXISTS playoff_series_league_year_idx ON nba.playoff_series (league_id, season_year);
CREATE INDEX IF NOT EXISTS playoff_series_season_year_type_idx ON nba.playoff_series (season_year, season_type);
CREATE INDEX IF NOT EXISTS playoff_series_high_seed_id_idx ON nba.playoff_series (high_seed_id);
CREATE INDEX IF NOT EXISTS playoff_series_low_seed_id_idx ON nba.playoff_series (low_seed_id);
CREATE INDEX IF NOT EXISTS playoff_series_winner_team_id_idx ON nba.playoff_series (series_winner_team_id);
CREATE INDEX IF NOT EXISTS playoff_series_series_json_gin ON nba.playoff_series USING gin (series_json);

CREATE TABLE IF NOT EXISTS nba.standings (
    league_id text,
    season_year integer,
    season_label text,
    season_type text,
    team_id integer REFERENCES nba.teams(team_id),
    standing_date date,
    team_city text,
    team_name text,
    team_slug text,
    team_tricode text,
    conference text,
    division text,
    playoff_rank integer,
    playoff_seeding integer,
    clinch_indicator text,
    wins integer,
    losses integer,
    win_pct numeric,
    league_rank integer,
    division_rank integer,
    record text,
    home text,
    road text,
    neutral text,
    l10 text,
    l10_home text,
    l10_road text,
    ot text,
    three_pts_or_less text,
    ten_pts_or_more text,
    current_streak integer,
    current_streak_text text,
    current_home_streak integer,
    current_home_streak_text text,
    current_road_streak integer,
    current_road_streak_text text,
    long_win_streak integer,
    long_loss_streak integer,
    long_home_streak integer,
    long_home_streak_text text,
    long_road_streak integer,
    long_road_streak_text text,
    conference_games_back numeric,
    division_games_back numeric,
    league_games_back numeric,
    is_clinched_conference boolean,
    is_clinched_division boolean,
    is_clinched_playoffs boolean,
    is_clinched_postseason boolean,
    is_clinched_play_in boolean,
    is_eliminated_conference boolean,
    is_eliminated_division boolean,
    ahead_at_half text,
    behind_at_half text,
    tied_at_half text,
    ahead_at_third text,
    behind_at_third text,
    tied_at_third text,
    score_100_plus text,
    opp_score_100_plus text,
    opp_over_500 text,
    lead_in_fg_pct text,
    lead_in_reb text,
    fewer_tov text,
    pts_per_game numeric,
    opp_pts_per_game numeric,
    diff_pts_per_game numeric,
    vs_east text,
    vs_west text,
    vs_atlantic text,
    vs_central text,
    vs_southeast text,
    vs_northwest text,
    vs_pacific text,
    vs_southwest text,
    jan text,
    feb text,
    mar text,
    apr text,
    may text,
    jun text,
    jul text,
    aug text,
    sep text,
    oct text,
    nov text,
    dec text,
    sort_order integer,
    created_at timestamptz,
    updated_at timestamptz,
    fetched_at timestamptz,
    PRIMARY KEY (league_id, season_year, season_type, team_id, standing_date)
);

CREATE INDEX IF NOT EXISTS standings_team_id_idx ON nba.standings (team_id);
CREATE INDEX IF NOT EXISTS standings_standing_date_idx ON nba.standings (standing_date);
CREATE INDEX IF NOT EXISTS standings_league_year_type_date_idx ON nba.standings (league_id, season_year, season_type, standing_date);
CREATE INDEX IF NOT EXISTS standings_season_label_idx ON nba.standings (season_label);
