-- Drop legacy estimated advanced columns from nba.boxscores_advanced.
-- The current official /api/stats/boxscore (measureType=Advanced) payload does not
-- include these e_* fields, and they are always NULL in preprod.

DO $$
DECLARE
    col text;
    nonnull_count bigint;
    estimated_cols text[] := ARRAY[
        'e_off_rating',
        'e_def_rating',
        'e_net_rating',
        'e_ast_ratio',
        'e_oreb_pct',
        'e_dreb_pct',
        'e_reb_pct',
        'e_tm_tov_pct',
        'e_usg_pct',
        'e_pace'
    ];
BEGIN
    IF to_regclass('nba.boxscores_advanced') IS NULL THEN
        RETURN;
    END IF;

    FOREACH col IN ARRAY estimated_cols
    LOOP
        IF EXISTS (
            SELECT 1
            FROM information_schema.columns
            WHERE table_schema = 'nba'
              AND table_name = 'boxscores_advanced'
              AND column_name = col
        ) THEN
            EXECUTE format(
                'SELECT COUNT(*) FROM nba.boxscores_advanced WHERE %I IS NOT NULL',
                col
            )
            INTO nonnull_count;

            IF nonnull_count > 0 THEN
                RAISE EXCEPTION 'Cannot drop nba.boxscores_advanced.%: found % non-NULL values', col, nonnull_count;
            END IF;

            EXECUTE format(
                'ALTER TABLE nba.boxscores_advanced DROP COLUMN %I',
                col
            );
        END IF;
    END LOOP;
END
$$;
