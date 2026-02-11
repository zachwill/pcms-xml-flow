-- NGSS roster personId is the same NBA person identifier domain as nba_id.
-- Collapse redundant ngss_person_id storage into nba_id.

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'nba'
          AND table_name = 'ngss_rosters'
          AND column_name = 'ngss_person_id'
    ) THEN
        IF EXISTS (
            SELECT 1
            FROM nba.ngss_rosters
            WHERE ngss_person_id IS NULL
               OR ngss_person_id !~ '^[0-9]+$'
        ) THEN
            RAISE EXCEPTION 'Cannot migrate nba.ngss_rosters: found NULL/non-numeric ngss_person_id values';
        END IF;

        ALTER TABLE nba.ngss_rosters DROP CONSTRAINT IF EXISTS ngss_rosters_nba_id_fkey;

        UPDATE nba.ngss_rosters
        SET nba_id = ngss_person_id::integer
        WHERE nba_id IS DISTINCT FROM ngss_person_id::integer;

        IF EXISTS (
            SELECT 1
            FROM (
                SELECT ngss_game_id, nba_id, COUNT(*) AS row_count
                FROM nba.ngss_rosters
                GROUP BY ngss_game_id, nba_id
                HAVING COUNT(*) > 1
            ) dupes
        ) THEN
            RAISE EXCEPTION 'Cannot migrate nba.ngss_rosters: duplicate (ngss_game_id, nba_id) keys after backfill';
        END IF;

        ALTER TABLE nba.ngss_rosters DROP CONSTRAINT IF EXISTS ngss_rosters_pkey;
        ALTER TABLE nba.ngss_rosters ALTER COLUMN nba_id SET NOT NULL;
        ALTER TABLE nba.ngss_rosters ADD CONSTRAINT ngss_rosters_pkey PRIMARY KEY (ngss_game_id, nba_id);
        ALTER TABLE nba.ngss_rosters DROP COLUMN ngss_person_id;
    END IF;
END
$$;

CREATE INDEX IF NOT EXISTS ngss_rosters_nba_id_idx ON nba.ngss_rosters (nba_id);
