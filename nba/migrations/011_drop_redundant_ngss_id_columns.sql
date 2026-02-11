-- Collapse redundant NGSS/NBA dual ID columns where values are expected to be identical.
-- Keeps only canonical NBA-domain identifiers in ngss_* tables.

DO $$
DECLARE
    mismatch_count bigint;
    duplicate_count bigint;
BEGIN
    -- nba.ngss_rosters: ngss_game_id duplicates game_id
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'nba'
          AND table_name = 'ngss_rosters'
          AND column_name = 'ngss_game_id'
    ) THEN
        SELECT COUNT(*) INTO mismatch_count
        FROM nba.ngss_rosters
        WHERE ngss_game_id IS DISTINCT FROM game_id;

        IF mismatch_count > 0 THEN
            RAISE EXCEPTION 'Cannot drop nba.ngss_rosters.ngss_game_id: % rows differ from game_id', mismatch_count;
        END IF;

        SELECT COUNT(*) INTO duplicate_count
        FROM (
            SELECT game_id, nba_id, COUNT(*) AS row_count
            FROM nba.ngss_rosters
            GROUP BY game_id, nba_id
            HAVING COUNT(*) > 1
        ) dupes;

        IF duplicate_count > 0 THEN
            RAISE EXCEPTION 'Cannot move nba.ngss_rosters PK to (game_id, nba_id): % duplicate keys', duplicate_count;
        END IF;

        ALTER TABLE nba.ngss_rosters DROP CONSTRAINT IF EXISTS ngss_rosters_ngss_game_id_fkey;
        ALTER TABLE nba.ngss_rosters DROP CONSTRAINT IF EXISTS ngss_rosters_pkey;
        ALTER TABLE nba.ngss_rosters ALTER COLUMN game_id SET NOT NULL;
        ALTER TABLE nba.ngss_rosters ALTER COLUMN nba_id SET NOT NULL;
        ALTER TABLE nba.ngss_rosters ADD CONSTRAINT ngss_rosters_pkey PRIMARY KEY (game_id, nba_id);
        ALTER TABLE nba.ngss_rosters DROP COLUMN ngss_game_id;
    END IF;

    -- nba.ngss_rosters: ngss_team_id duplicates team_id
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'nba'
          AND table_name = 'ngss_rosters'
          AND column_name = 'ngss_team_id'
    ) THEN
        SELECT COUNT(*) INTO mismatch_count
        FROM nba.ngss_rosters
        WHERE team_id IS NULL
           OR ngss_team_id IS NULL
           OR ngss_team_id <> team_id::text;

        IF mismatch_count > 0 THEN
            RAISE EXCEPTION 'Cannot drop nba.ngss_rosters.ngss_team_id: % rows are NULL/mismatched vs team_id', mismatch_count;
        END IF;

        ALTER TABLE nba.ngss_rosters DROP COLUMN ngss_team_id;
    END IF;

    -- nba.ngss_games: ngss_game_id duplicates game_id
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'nba'
          AND table_name = 'ngss_games'
          AND column_name = 'ngss_game_id'
    ) THEN
        SELECT COUNT(*) INTO mismatch_count
        FROM nba.ngss_games
        WHERE ngss_game_id IS DISTINCT FROM game_id;

        IF mismatch_count > 0 THEN
            RAISE EXCEPTION 'Cannot drop nba.ngss_games.ngss_game_id: % rows differ from game_id', mismatch_count;
        END IF;

        ALTER TABLE nba.ngss_games DROP CONSTRAINT IF EXISTS ngss_games_ngss_game_id_key;
        ALTER TABLE nba.ngss_games DROP COLUMN ngss_game_id;
    END IF;

    -- nba.ngss_boxscores: ngss_game_id duplicates game_id
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'nba'
          AND table_name = 'ngss_boxscores'
          AND column_name = 'ngss_game_id'
    ) THEN
        SELECT COUNT(*) INTO mismatch_count
        FROM nba.ngss_boxscores
        WHERE ngss_game_id IS DISTINCT FROM game_id;

        IF mismatch_count > 0 THEN
            RAISE EXCEPTION 'Cannot drop nba.ngss_boxscores.ngss_game_id: % rows differ from game_id', mismatch_count;
        END IF;

        ALTER TABLE nba.ngss_boxscores DROP COLUMN ngss_game_id;
    END IF;

    -- nba.ngss_pbp: ngss_game_id duplicates game_id
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'nba'
          AND table_name = 'ngss_pbp'
          AND column_name = 'ngss_game_id'
    ) THEN
        SELECT COUNT(*) INTO mismatch_count
        FROM nba.ngss_pbp
        WHERE ngss_game_id IS DISTINCT FROM game_id;

        IF mismatch_count > 0 THEN
            RAISE EXCEPTION 'Cannot drop nba.ngss_pbp.ngss_game_id: % rows differ from game_id', mismatch_count;
        END IF;

        ALTER TABLE nba.ngss_pbp DROP COLUMN ngss_game_id;
    END IF;
END
$$;
