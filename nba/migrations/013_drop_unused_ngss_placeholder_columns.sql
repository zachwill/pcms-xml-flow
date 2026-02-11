-- Drop legacy NGSS placeholder columns from core nba.* tables.
-- These are either always NULL today or duplicate the canonical NBA IDs.

DO $$
DECLARE
    mismatch_count bigint;
BEGIN
    -- nba.players.ngss_person_id duplicates nba_id when present
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'nba'
          AND table_name = 'players'
          AND column_name = 'ngss_person_id'
    ) THEN
        SELECT COUNT(*) INTO mismatch_count
        FROM nba.players
        WHERE ngss_person_id IS NOT NULL
          AND ngss_person_id <> nba_id::text;

        IF mismatch_count > 0 THEN
            RAISE EXCEPTION 'Cannot drop nba.players.ngss_person_id: % mismatched rows vs nba_id', mismatch_count;
        END IF;

        DROP INDEX IF EXISTS nba.players_ngss_person_id_idx;
        ALTER TABLE nba.players DROP COLUMN ngss_person_id;
    END IF;

    -- nba.teams.ngss_team_id duplicates team_id when present
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'nba'
          AND table_name = 'teams'
          AND column_name = 'ngss_team_id'
    ) THEN
        SELECT COUNT(*) INTO mismatch_count
        FROM nba.teams
        WHERE ngss_team_id IS NOT NULL
          AND ngss_team_id <> team_id::text;

        IF mismatch_count > 0 THEN
            RAISE EXCEPTION 'Cannot drop nba.teams.ngss_team_id: % mismatched rows vs team_id', mismatch_count;
        END IF;

        DROP INDEX IF EXISTS nba.teams_ngss_team_id_idx;
        ALTER TABLE nba.teams DROP COLUMN ngss_team_id;
    END IF;

    -- nba.games.ngss_game_id duplicates game_id when present
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'nba'
          AND table_name = 'games'
          AND column_name = 'ngss_game_id'
    ) THEN
        SELECT COUNT(*) INTO mismatch_count
        FROM nba.games
        WHERE ngss_game_id IS NOT NULL
          AND ngss_game_id <> game_id;

        IF mismatch_count > 0 THEN
            RAISE EXCEPTION 'Cannot drop nba.games.ngss_game_id: % mismatched rows vs game_id', mismatch_count;
        END IF;

        DROP INDEX IF EXISTS nba.games_ngss_game_id_idx;
        ALTER TABLE nba.games DROP COLUMN ngss_game_id;
    END IF;

    -- nba.schedules.ngss_season_id is a never-used placeholder
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'nba'
          AND table_name = 'schedules'
          AND column_name = 'ngss_season_id'
    ) THEN
        IF EXISTS (
            SELECT 1
            FROM nba.schedules
            WHERE ngss_season_id IS NOT NULL
        ) THEN
            RAISE EXCEPTION 'Cannot drop nba.schedules.ngss_season_id: found non-NULL values';
        END IF;

        DROP INDEX IF EXISTS nba.schedules_ngss_season_id_idx;
        ALTER TABLE nba.schedules DROP COLUMN ngss_season_id;
    END IF;
END
$$;
