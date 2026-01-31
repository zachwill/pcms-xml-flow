-- 058_buyout_primitives_assertions.sql
-- Assertion tests for buyout / waiver primitives.

-- 1) fn_days_remaining should match the workbook example dates.
DO $$
DECLARE v int;
BEGIN
  SELECT pcms.fn_days_remaining('2026-01-15'::date, '2025-10-20'::date) INTO v;

  -- waive 2026-01-15 -> clears 2026-01-17
  -- day_of_season = 2026-01-17 - 2025-10-20 = 89
  -- days_remaining = 174 - 89 = 85
  IF v IS DISTINCT FROM 85 THEN
    RAISE EXCEPTION 'fn_days_remaining mismatch: expected %, got %', 85, v;
  END IF;
END
$$;

-- 2) fn_stretch_waiver sanity
DO $$
DECLARE r record;
BEGIN
  SELECT * INTO r FROM pcms.fn_stretch_waiver(30000000, 1);

  IF r.stretch_years IS DISTINCT FROM 3 OR r.annual_amount IS DISTINCT FROM 10000000 THEN
    RAISE EXCEPTION 'fn_stretch_waiver mismatch: expected (3, 10000000), got (%, %)', r.stretch_years, r.annual_amount;
  END IF;
END
$$;

-- 3) fn_setoff_amount matches Sean's example shape: (new_salary - 1YOS min) / 2
DO $$
DECLARE v bigint;
BEGIN
  SELECT pcms.fn_setoff_amount(14104000, 1, 2025, 'NBA') INTO v;

  -- 2025 1-YOS minimum = 2,048,494
  -- (14,104,000 - 2,048,494) / 2 = 6,027,753
  IF v IS DISTINCT FROM 6027753 THEN
    RAISE EXCEPTION 'fn_setoff_amount mismatch: expected %, got %', 6027753, v;
  END IF;
END
$$;

-- 4) fn_buyout_scenario reproduces the Trae Young example structure (2-year remaining).
DO $$
DECLARE
  v_player_id int;
  v_diff int;
BEGIN
  SELECT sby.player_id
  INTO v_player_id
  FROM pcms.salary_book_yearly sby
  WHERE sby.league_lk='NBA'
    AND sby.salary_year=2025
    AND sby.player_name='Young, Trae'
  LIMIT 1;

  IF v_player_id IS NULL THEN
    RAISE EXCEPTION 'fixture missing: expected to find Young, Trae in pcms.salary_book_yearly for 2025';
  END IF;

  WITH season AS (
    SELECT pcms.fn_days_remaining('2026-01-15'::date, '2025-10-20'::date) AS days_remaining
  ),
  caps AS (
    SELECT
      MAX(CASE WHEN sby.salary_year=2025 THEN sby.cap_amount END)::bigint AS cap25,
      MAX(CASE WHEN sby.salary_year=2026 THEN sby.cap_amount END)::bigint AS cap26
    FROM pcms.salary_book_yearly sby
    WHERE sby.league_lk='NBA'
      AND sby.player_id=v_player_id
      AND sby.salary_year IN (2025, 2026)
  ),
  calc AS (
    SELECT
      c.cap25,
      c.cap26,
      s.days_remaining,
      ROUND(c.cap25::numeric * s.days_remaining::numeric / 174, 0)::bigint AS guar25,
      c.cap26::bigint AS guar26
    FROM caps c
    CROSS JOIN season s
  ),
  expected AS (
    SELECT
      2025::int AS salary_year,
      calc.cap25 AS cap_salary,
      calc.days_remaining AS days_remaining,
      calc.guar25 AS guaranteed_remaining,
      ROUND((calc.guar25::numeric / NULLIF((calc.guar25 + calc.guar26), 0)) * 9000000, 0)::bigint AS give_back_amount,
      (calc.cap25 - ROUND((calc.guar25::numeric / NULLIF((calc.guar25 + calc.guar26), 0)) * 9000000, 0)::bigint)::bigint AS dead_money
    FROM calc

    UNION ALL

    SELECT
      2026::int AS salary_year,
      calc.cap26 AS cap_salary,
      NULL::int AS days_remaining,
      calc.guar26 AS guaranteed_remaining,
      (
        9000000
        - ROUND((calc.guar25::numeric / NULLIF((calc.guar25 + calc.guar26), 0)) * 9000000, 0)::bigint
      )::bigint AS give_back_amount,
      (
        calc.cap26
        - (
          9000000
          - ROUND((calc.guar25::numeric / NULLIF((calc.guar25 + calc.guar26), 0)) * 9000000, 0)::bigint
        )
      )::bigint AS dead_money
    FROM calc
  ),
  actual AS (
    SELECT
      salary_year,
      cap_salary,
      days_remaining,
      guaranteed_remaining,
      give_back_amount,
      dead_money
    FROM pcms.fn_buyout_scenario(
      v_player_id,
      '2026-01-15'::date,
      9000000,
      '2025-10-20'::date,
      'NBA'
    )
  ),
  diff AS (
    (
      SELECT * FROM expected
      EXCEPT
      SELECT * FROM actual
    )
    UNION ALL
    (
      SELECT * FROM actual
      EXCEPT
      SELECT * FROM expected
    )
  )
  SELECT COUNT(*) INTO v_diff FROM diff;

  IF v_diff <> 0 THEN
    RAISE EXCEPTION 'fn_buyout_scenario mismatch for Trae Young: % differing rows', v_diff;
  END IF;
END
$$;
