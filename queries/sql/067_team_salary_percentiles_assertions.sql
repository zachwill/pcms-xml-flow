-- 067_team_salary_percentiles_assertions.sql
--
-- Validate cap_total_percentile on team_salary_warehouse:
-- 1) values are in [0, 1]
-- 2) for seasons with 2+ teams, percentile is populated for every row

DO $$
DECLARE
  out_of_range_count int;
BEGIN
  SELECT COUNT(*) INTO out_of_range_count
  FROM pcms.team_salary_warehouse t
  WHERE t.cap_total_percentile IS NOT NULL
    AND (t.cap_total_percentile < 0 OR t.cap_total_percentile > 1);

  IF out_of_range_count > 0 THEN
    RAISE EXCEPTION
      'team_salary_warehouse cap_total_percentile out-of-range rows=%',
      out_of_range_count;
  END IF;
END;
$$;

DO $$
DECLARE
  missing_count int;
BEGIN
  WITH eligible_years AS (
    SELECT salary_year
    FROM pcms.team_salary_warehouse
    GROUP BY salary_year
    HAVING COUNT(*) >= 2
  )
  SELECT COUNT(*) INTO missing_count
  FROM pcms.team_salary_warehouse t
  JOIN eligible_years y
    ON y.salary_year = t.salary_year
  WHERE t.cap_total_percentile IS NULL;

  IF missing_count > 0 THEN
    RAISE EXCEPTION
      'team_salary_warehouse cap_total_percentile missing rows=%',
      missing_count;
  END IF;
END;
$$;
