-- Replace the querytool_event_* JSONB dumping grounds with a proper shot chart table.
--
-- The old tables used (query_hash, row_hash) PKs with all real data buried in
-- stats_json / row_json blobs.  The new nba.shot_chart table has first-class
-- columns for every FieldGoals field, keyed on (game_id, event_number).

DROP TABLE IF EXISTS nba.querytool_event_player CASCADE;
DROP TABLE IF EXISTS nba.querytool_event_team CASCADE;
DROP TABLE IF EXISTS nba.querytool_event_league CASCADE;

CREATE TABLE IF NOT EXISTS nba.shot_chart (
    game_id          text NOT NULL,
    event_number     integer NOT NULL,
    nba_id           integer NOT NULL,
    team_id          integer,
    period           integer,
    game_clock       numeric(10,3),
    x                integer,
    y                integer,
    shot_made        boolean,
    is_three         boolean,
    shot_type        text,             -- jumper, layup, dunk, hook, tip, alley_oop, finger_roll
    shot_zone_area   text,
    shot_zone_range  text,
    assisted_by_id   integer,
    assisted_by_name text,
    player_name      text,
    position         text,
    opponent_name    text,
    game_date        date,
    season_year      integer,
    season_label     text,
    season_type      text,
    created_at       timestamptz,
    updated_at       timestamptz,
    fetched_at       timestamptz,
    PRIMARY KEY (game_id, event_number)
);

CREATE INDEX IF NOT EXISTS shot_chart_nba_id_idx ON nba.shot_chart (nba_id);
CREATE INDEX IF NOT EXISTS shot_chart_team_id_idx ON nba.shot_chart (team_id);
CREATE INDEX IF NOT EXISTS shot_chart_game_date_idx ON nba.shot_chart (game_date);
CREATE INDEX IF NOT EXISTS shot_chart_season_idx ON nba.shot_chart (season_year, season_type);
CREATE INDEX IF NOT EXISTS shot_chart_shot_type_idx ON nba.shot_chart (shot_type);
CREATE INDEX IF NOT EXISTS shot_chart_shot_made_idx ON nba.shot_chart (shot_made) WHERE shot_made;
