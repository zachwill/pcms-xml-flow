-- 077_team_salary_two_way_count_assertions.sql
--
-- Ensure team_salary_warehouse two-way counts are valid and aligned with
-- salary_book_yearly for overlapping years.

DO $$
DECLARE
  invalid_count int;
BEGIN
  SELECT COUNT(*) INTO invalid_count
  FROM pcms.team_salary_warehouse tsw
  WHERE COALESCE(tsw.two_way_row_count, 0) > 3
     OR COALESCE(tsw.two_way_row_count, 0) < 0;

  IF invalid_count > 0 THEN
    RAISE EXCEPTION
      'team_salary_warehouse two_way_row_count outside [0,3], rows=%',
      invalid_count;
  END IF;
END;
$$;

DO $$
DECLARE
  mismatch_count int;
BEGIN
  WITH sby_counts AS (
    SELECT
      sby.team_code,
      sby.salary_year,
      COUNT(DISTINCT sby.player_id) FILTER (WHERE COALESCE(sby.is_two_way, false))::int AS sby_two_way_count
    FROM pcms.salary_book_yearly sby
    WHERE sby.team_code IS NOT NULL
      AND sby.salary_year IS NOT NULL
    GROUP BY 1,2
  )
  SELECT COUNT(*) INTO mismatch_count
  FROM pcms.team_salary_warehouse tsw
  JOIN sby_counts s
    ON s.team_code = tsw.team_code
   AND s.salary_year = tsw.salary_year
  WHERE COALESCE(tsw.two_way_row_count, 0) <> COALESCE(s.sby_two_way_count, 0);

  IF mismatch_count > 0 THEN
    RAISE EXCEPTION
      'team_salary_warehouse two_way_row_count mismatches salary_book_yearly in overlapping years, rows=%',
      mismatch_count;
  END IF;
END;
$$;
