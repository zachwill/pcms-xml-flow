-- Standardize minutes columns to numeric(8,2) and add team-level advanced boxscores.

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

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'nba'
          AND table_name = 'boxscores_traditional'
          AND column_name = 'minutes'
          AND data_type = 'interval'
    ) THEN
        ALTER TABLE nba.boxscores_traditional
            ALTER COLUMN minutes TYPE numeric(8,2)
            USING ROUND(EXTRACT(EPOCH FROM minutes)::numeric / 60, 2);
    END IF;

    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'nba'
          AND table_name = 'boxscores_traditional_team'
          AND column_name = 'minutes'
          AND data_type = 'interval'
    ) THEN
        ALTER TABLE nba.boxscores_traditional_team
            ALTER COLUMN minutes TYPE numeric(8,2)
            USING ROUND(EXTRACT(EPOCH FROM minutes)::numeric / 60, 2);
    END IF;

    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'nba'
          AND table_name = 'boxscores_advanced'
          AND column_name = 'minutes'
          AND data_type = 'interval'
    ) THEN
        ALTER TABLE nba.boxscores_advanced
            ALTER COLUMN minutes TYPE numeric(8,2)
            USING ROUND(EXTRACT(EPOCH FROM minutes)::numeric / 60, 2);
    END IF;

    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'nba'
          AND table_name = 'hustle_stats'
          AND column_name = 'minutes'
          AND data_type = 'interval'
    ) THEN
        ALTER TABLE nba.hustle_stats
            ALTER COLUMN minutes TYPE numeric(8,2)
            USING ROUND(EXTRACT(EPOCH FROM minutes)::numeric / 60, 2);
    END IF;

    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'nba'
          AND table_name = 'tracking_stats'
          AND column_name = 'minutes'
          AND data_type = 'interval'
    ) THEN
        ALTER TABLE nba.tracking_stats
            ALTER COLUMN minutes TYPE numeric(8,2)
            USING ROUND(EXTRACT(EPOCH FROM minutes)::numeric / 60, 2);
    END IF;

    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'nba'
          AND table_name = 'lineup_stats_season'
          AND column_name = 'min'
    ) THEN
        ALTER TABLE nba.lineup_stats_season RENAME COLUMN min TO minutes;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'nba'
          AND table_name = 'lineup_stats_season'
          AND column_name = 'minutes'
          AND data_type = 'interval'
    ) THEN
        ALTER TABLE nba.lineup_stats_season
            ALTER COLUMN minutes TYPE numeric(8,2)
            USING ROUND(EXTRACT(EPOCH FROM minutes)::numeric / 60, 2);
    END IF;

    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'nba'
          AND table_name = 'lineup_stats_game'
          AND column_name = 'min'
    ) THEN
        ALTER TABLE nba.lineup_stats_game RENAME COLUMN min TO minutes;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'nba'
          AND table_name = 'lineup_stats_game'
          AND column_name = 'minutes'
          AND data_type = 'interval'
    ) THEN
        ALTER TABLE nba.lineup_stats_game
            ALTER COLUMN minutes TYPE numeric(8,2)
            USING ROUND(EXTRACT(EPOCH FROM minutes)::numeric / 60, 2);
    END IF;

    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'nba'
          AND table_name = 'lineups'
          AND column_name = 'min'
    ) THEN
        ALTER TABLE nba.lineups RENAME COLUMN min TO minutes;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'nba'
          AND table_name = 'lineups'
          AND column_name = 'minutes'
          AND data_type = 'interval'
    ) THEN
        ALTER TABLE nba.lineups
            ALTER COLUMN minutes TYPE numeric(8,2)
            USING ROUND(EXTRACT(EPOCH FROM minutes)::numeric / 60, 2);
    END IF;
END $$;
