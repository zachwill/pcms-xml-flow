-- Add additional Query Tool-derived datasets:
-- - Shot chart enrichment via /event/player EventType=TrackingShots
-- - Defensive attribution stats via /game/player MeasureType=Defensive
-- - Violations breakdowns via /game/player + /game/team MeasureType=Violations
-- - Volatile event-level tracking streams (passes/drives/isos/postups/defensive events)
--
-- These are intentionally UPSERT-friendly, keyed on natural game/player keys where
-- possible. For event streams where Query Tool does not provide a stable unique
-- row identifier (e.g. eventNumber repeats), we store one JSONB blob per
-- (game_id, event_type).

-- ─────────────────────────────────────────────────────────────────────────────
-- Shot chart enrichment columns
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE IF EXISTS nba.shot_chart
    ADD COLUMN IF NOT EXISTS tracking_shot_after_screens boolean,
    ADD COLUMN IF NOT EXISTS tracking_shot_catch_and_shoot boolean,
    ADD COLUMN IF NOT EXISTS tracking_shot_lob boolean,
    ADD COLUMN IF NOT EXISTS tracking_shot_long_heave boolean,
    ADD COLUMN IF NOT EXISTS tracking_shot_pull_up boolean,
    ADD COLUMN IF NOT EXISTS tracking_shot_tip_in boolean,
    ADD COLUMN IF NOT EXISTS tracking_shot_trailing_three boolean,
    ADD COLUMN IF NOT EXISTS tracking_shot_transition boolean;

COMMENT ON COLUMN nba.shot_chart.tracking_shot_after_screens IS
    'Query Tool TrackingShots event flag: SHOT_AFTER_SCREENS.';
COMMENT ON COLUMN nba.shot_chart.tracking_shot_catch_and_shoot IS
    'Query Tool TrackingShots event flag: SHOT_CATCH_AND_SHOOT.';
COMMENT ON COLUMN nba.shot_chart.tracking_shot_lob IS
    'Query Tool TrackingShots event flag: SHOT_LOB.';
COMMENT ON COLUMN nba.shot_chart.tracking_shot_long_heave IS
    'Query Tool TrackingShots event flag: SHOT_LONG_HEAVE.';
COMMENT ON COLUMN nba.shot_chart.tracking_shot_pull_up IS
    'Query Tool TrackingShots event flag: SHOT_PULL_UP.';
COMMENT ON COLUMN nba.shot_chart.tracking_shot_tip_in IS
    'Query Tool TrackingShots event flag: SHOT_TIP_IN.';
COMMENT ON COLUMN nba.shot_chart.tracking_shot_trailing_three IS
    'Query Tool TrackingShots event flag: SHOT_TRAILING_THREE.';
COMMENT ON COLUMN nba.shot_chart.tracking_shot_transition IS
    'Query Tool TrackingShots event flag: SHOT_TRANSITION.';

-- ─────────────────────────────────────────────────────────────────────────────
-- Defensive attribution stats (player-game)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS nba.defensive_stats (
    game_id text REFERENCES nba.games(game_id),
    team_id integer REFERENCES nba.teams(team_id),
    nba_id integer REFERENCES nba.players(nba_id),
    minutes numeric(8,2),
    def_fgm integer,
    def_fga integer,
    def_fg_pct numeric(6,4),
    def_fg3m integer,
    def_fg3a integer,
    def_fg3_pct numeric(6,4),
    def_ftm integer,
    def_fta integer,
    def_ft_pct numeric(6,4),
    def_ast integer,
    def_tov integer,
    def_foul integer,
    def_shooting_foul integer,
    def_blk integer,
    def_stl integer,
    def_pts integer,
    defensive_stats_json jsonb,
    created_at timestamptz,
    updated_at timestamptz,
    fetched_at timestamptz,
    PRIMARY KEY (game_id, nba_id)
);

CREATE INDEX IF NOT EXISTS defensive_stats_team_id_idx ON nba.defensive_stats (team_id);
CREATE INDEX IF NOT EXISTS defensive_stats_nba_id_idx ON nba.defensive_stats (nba_id);
CREATE INDEX IF NOT EXISTS defensive_stats_game_id_idx ON nba.defensive_stats (game_id);
CREATE INDEX IF NOT EXISTS defensive_stats_json_gin ON nba.defensive_stats USING gin (defensive_stats_json);

COMMENT ON TABLE nba.defensive_stats IS
    'Query Tool /game/player MeasureType=Defensive. Defensive attribution stats (defended FG, etc.) at player-game scope.';

-- ─────────────────────────────────────────────────────────────────────────────
-- Violations breakdowns
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS nba.violations_player (
    game_id text REFERENCES nba.games(game_id),
    team_id integer REFERENCES nba.teams(team_id),
    nba_id integer REFERENCES nba.players(nba_id),
    started boolean,
    minutes numeric(8,2),
    travel integer,
    double_dribble integer,
    discontinued_dribble integer,
    off_three_sec integer,
    def_three_sec integer,
    inbound integer,
    backcourt integer,
    off_goaltending integer,
    def_goaltending integer,
    palming integer,
    kicked_ball integer,
    jump_ball integer,
    lane integer,
    charge integer,
    off_foul integer,
    violations_stats_json jsonb,
    created_at timestamptz,
    updated_at timestamptz,
    fetched_at timestamptz,
    PRIMARY KEY (game_id, nba_id)
);

CREATE INDEX IF NOT EXISTS violations_player_team_id_idx ON nba.violations_player (team_id);
CREATE INDEX IF NOT EXISTS violations_player_nba_id_idx ON nba.violations_player (nba_id);
CREATE INDEX IF NOT EXISTS violations_player_game_id_idx ON nba.violations_player (game_id);
CREATE INDEX IF NOT EXISTS violations_player_json_gin ON nba.violations_player USING gin (violations_stats_json);

COMMENT ON TABLE nba.violations_player IS
    'Query Tool /game/player MeasureType=Violations. Player-level violation counts by type.';

CREATE TABLE IF NOT EXISTS nba.violations_team (
    game_id text REFERENCES nba.games(game_id),
    team_id integer REFERENCES nba.teams(team_id),
    minutes numeric(8,2),
    travel integer,
    double_dribble integer,
    discontinued_dribble integer,
    off_three_sec integer,
    def_three_sec integer,
    inbound integer,
    backcourt integer,
    off_goaltending integer,
    def_goaltending integer,
    palming integer,
    kicked_ball integer,
    jump_ball integer,
    lane integer,
    charge integer,
    off_foul integer,
    tm_delay_of_game integer,
    tm_eight_sec integer,
    tm_five_sec integer,
    tm_shot_clock integer,
    violations_stats_json jsonb,
    created_at timestamptz,
    updated_at timestamptz,
    fetched_at timestamptz,
    PRIMARY KEY (game_id, team_id)
);

CREATE INDEX IF NOT EXISTS violations_team_team_id_idx ON nba.violations_team (team_id);
CREATE INDEX IF NOT EXISTS violations_team_game_id_idx ON nba.violations_team (game_id);
CREATE INDEX IF NOT EXISTS violations_team_json_gin ON nba.violations_team USING gin (violations_stats_json);

COMMENT ON TABLE nba.violations_team IS
    'Query Tool /game/team MeasureType=Violations. Team-level violation counts by type (incl. team-only shot clock, delay of game, etc.).';

-- ─────────────────────────────────────────────────────────────────────────────
-- Query Tool event streams (volatile; store per-game JSON)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS nba.querytool_event_streams (
    game_id text REFERENCES nba.games(game_id),
    event_type text NOT NULL,
    events_json jsonb,
    created_at timestamptz,
    updated_at timestamptz,
    fetched_at timestamptz,
    PRIMARY KEY (game_id, event_type)
);

CREATE INDEX IF NOT EXISTS querytool_event_streams_game_id_idx ON nba.querytool_event_streams (game_id);
CREATE INDEX IF NOT EXISTS querytool_event_streams_event_type_idx ON nba.querytool_event_streams (event_type);
CREATE INDEX IF NOT EXISTS querytool_event_streams_events_json_gin ON nba.querytool_event_streams USING gin (events_json);

COMMENT ON TABLE nba.querytool_event_streams IS
    'Query Tool /event/player event streams stored as JSONB per (game_id, event_type). Used for tracking passes/drives/isos/postups and defensive events where eventNumber is not a stable unique key.';
