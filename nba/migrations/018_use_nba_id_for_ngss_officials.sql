-- NGSS officials personId is the same NBA identifier domain as nba_id.
-- Replace ngss_official_id with nba_id in nba.ngss_officials.

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'nba'
          AND table_name = 'ngss_officials'
          AND column_name = 'ngss_official_id'
    ) THEN
        IF EXISTS (
            SELECT 1
            FROM nba.ngss_officials
            WHERE ngss_official_id IS NULL
               OR ngss_official_id !~ '^[0-9]+$'
        ) THEN
            RAISE EXCEPTION 'Cannot migrate nba.ngss_officials: found NULL/non-numeric ngss_official_id values';
        END IF;

        ALTER TABLE nba.ngss_officials ADD COLUMN IF NOT EXISTS nba_id integer;

        UPDATE nba.ngss_officials
        SET nba_id = ngss_official_id::integer
        WHERE nba_id IS DISTINCT FROM ngss_official_id::integer;

        IF EXISTS (
            SELECT 1
            FROM (
                SELECT game_id, nba_id, COUNT(*) AS row_count
                FROM nba.ngss_officials
                GROUP BY game_id, nba_id
                HAVING COUNT(*) > 1
            ) dupes
        ) THEN
            RAISE EXCEPTION 'Cannot migrate nba.ngss_officials: duplicate (game_id, nba_id) keys after backfill';
        END IF;

        ALTER TABLE nba.ngss_officials DROP CONSTRAINT IF EXISTS ngss_officials_pkey;
        ALTER TABLE nba.ngss_officials ALTER COLUMN nba_id SET NOT NULL;
        ALTER TABLE nba.ngss_officials ADD CONSTRAINT ngss_officials_pkey PRIMARY KEY (game_id, nba_id);
        ALTER TABLE nba.ngss_officials DROP COLUMN ngss_official_id;
    END IF;
END
$$;

CREATE INDEX IF NOT EXISTS ngss_officials_nba_id_idx ON nba.ngss_officials (nba_id);
