-- 070_nba_shot_chart_assertions.sql
-- Validate nba.shot_chart data integrity.

-- 1. Table exists
DO $$
BEGIN
  IF to_regclass('nba.shot_chart') IS NULL THEN
    RAISE EXCEPTION 'missing relation: nba.shot_chart';
  END IF;
END
$$;

-- 2. Not empty (at least some shots exist)
DO $$
DECLARE c int;
BEGIN
  SELECT count(*) INTO c FROM nba.shot_chart;
  IF c = 0 THEN
    RAISE EXCEPTION 'nba.shot_chart is empty';
  END IF;
  RAISE NOTICE 'nba.shot_chart: % rows', c;
END
$$;

-- 3. Every game_id exists in nba.games
DO $$
DECLARE c int;
BEGIN
  SELECT count(DISTINCT sc.game_id) INTO c
  FROM nba.shot_chart sc
  LEFT JOIN nba.games g ON g.game_id = sc.game_id
  WHERE g.game_id IS NULL;
  IF c > 0 THEN
    RAISE EXCEPTION 'nba.shot_chart has % game_ids not in nba.games', c;
  END IF;
END
$$;

-- 4. Every nba_id exists in nba.players
DO $$
DECLARE c int;
BEGIN
  SELECT count(DISTINCT sc.nba_id) INTO c
  FROM nba.shot_chart sc
  LEFT JOIN nba.players p ON p.nba_id = sc.nba_id
  WHERE p.nba_id IS NULL;
  IF c > 0 THEN
    RAISE EXCEPTION 'nba.shot_chart has % nba_ids not in nba.players', c;
  END IF;
END
$$;

-- 5. shot_made and is_three are never null
DO $$
DECLARE c int;
BEGIN
  SELECT count(*) INTO c FROM nba.shot_chart WHERE shot_made IS NULL;
  IF c > 0 THEN
    RAISE EXCEPTION 'nba.shot_chart has % rows with null shot_made', c;
  END IF;
  SELECT count(*) INTO c FROM nba.shot_chart WHERE is_three IS NULL;
  IF c > 0 THEN
    RAISE EXCEPTION 'nba.shot_chart has % rows with null is_three', c;
  END IF;
END
$$;

-- 6. shot_type is one of the 7 known values (never null)
DO $$
DECLARE c int;
BEGIN
  SELECT count(*) INTO c FROM nba.shot_chart
  WHERE shot_type IS NULL
     OR shot_type NOT IN ('jumper', 'layup', 'dunk', 'hook', 'tip', 'alley_oop', 'finger_roll');
  IF c > 0 THEN
    RAISE EXCEPTION 'nba.shot_chart has % rows with invalid/null shot_type', c;
  END IF;
END
$$;

-- 7. Reasonable shots per game (at least 50, at most 400)
DO $$
DECLARE min_shots int;
DECLARE max_shots int;
BEGIN
  SELECT min(cnt), max(cnt) INTO min_shots, max_shots
  FROM (SELECT count(*) AS cnt FROM nba.shot_chart GROUP BY game_id) sub;
  IF min_shots < 50 THEN
    RAISE EXCEPTION 'nba.shot_chart has a game with only % shots (expect >=50)', min_shots;
  END IF;
  IF max_shots > 400 THEN
    RAISE EXCEPTION 'nba.shot_chart has a game with % shots (expect <=400)', max_shots;
  END IF;
  RAISE NOTICE 'shots per game: min=%, max=%', min_shots, max_shots;
END
$$;

-- 8. x/y coordinates are present and in valid range
DO $$
DECLARE c int;
BEGIN
  SELECT count(*) INTO c FROM nba.shot_chart WHERE x IS NULL OR y IS NULL;
  IF c > 0 THEN
    RAISE EXCEPTION 'nba.shot_chart has % rows with null x or y', c;
  END IF;
END
$$;

-- 9. period is reasonable (1-7, covering regulation + OT)
DO $$
DECLARE c int;
BEGIN
  SELECT count(*) INTO c FROM nba.shot_chart WHERE period IS NULL OR period < 1 OR period > 7;
  IF c > 0 THEN
    RAISE EXCEPTION 'nba.shot_chart has % rows with invalid period', c;
  END IF;
END
$$;

-- 10. FG% sanity: season-wide should be between 40-55%
DO $$
DECLARE pct numeric;
BEGIN
  SELECT round(100.0 * count(*) FILTER (WHERE shot_made) / count(*), 1) INTO pct
  FROM nba.shot_chart;
  IF pct < 40 OR pct > 55 THEN
    RAISE EXCEPTION 'nba.shot_chart season FG%% is % (expect 40-55)', pct;
  END IF;
  RAISE NOTICE 'season FG%%: %', pct;
END
$$;
