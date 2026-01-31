-- 057_minimum_salary_assertions.sql
-- Assertion tests for pcms.fn_minimum_salary().

-- 1) Contract year 1 should match the base table for a known tier.
DO $$
DECLARE
  v_base bigint;
  v_fn bigint;
BEGIN
  SELECT minimum_salary_amount INTO v_base
  FROM pcms.league_salary_scales
  WHERE league_lk='NBA' AND salary_year=2025 AND years_of_service=4;

  SELECT pcms.fn_minimum_salary(2025, 4, 1, 'NBA') INTO v_fn;

  IF v_fn IS DISTINCT FROM v_base THEN
    RAISE EXCEPTION 'fn_minimum_salary year1 mismatch (YOS=4): expected %, got %', v_base, v_fn;
  END IF;
END
$$;

-- 2) Contract year 2 should be Year1 * 1.05 (rounded) for an eligible tier.
DO $$
DECLARE
  v_base bigint;
  v_expected bigint;
  v_fn bigint;
BEGIN
  SELECT minimum_salary_amount INTO v_base
  FROM pcms.league_salary_scales
  WHERE league_lk='NBA' AND salary_year=2025 AND years_of_service=4;

  v_expected := ROUND(v_base::numeric * 1.05, 0)::bigint;
  SELECT pcms.fn_minimum_salary(2025, 4, 2, 'NBA') INTO v_fn;

  IF v_fn IS DISTINCT FROM v_expected THEN
    RAISE EXCEPTION 'fn_minimum_salary year2 mismatch (YOS=4): expected %, got %', v_expected, v_fn;
  END IF;
END
$$;

-- 3) Year-4 special-case: YOS=3 uses 1.045 multiplier in Year 4.
DO $$
DECLARE
  v_base bigint;
  v_y2 bigint;
  v_y3 bigint;
  v_y4_expected bigint;
  v_fn bigint;
BEGIN
  SELECT minimum_salary_amount INTO v_base
  FROM pcms.league_salary_scales
  WHERE league_lk='NBA' AND salary_year=2025 AND years_of_service=3;

  v_y2 := ROUND(v_base::numeric * 1.05, 0)::bigint;
  v_y3 := ROUND(v_y2::numeric * 1.047, 0)::bigint;
  v_y4_expected := ROUND(v_y3::numeric * 1.045, 0)::bigint;

  SELECT pcms.fn_minimum_salary(2025, 3, 4, 'NBA') INTO v_fn;

  IF v_fn IS DISTINCT FROM v_y4_expected THEN
    RAISE EXCEPTION 'fn_minimum_salary year4 mismatch (YOS=3): expected %, got %', v_y4_expected, v_fn;
  END IF;
END
$$;

-- 4) Eligibility rules: YOS=0 cannot have contract year 2+.
DO $$
DECLARE v_fn bigint;
BEGIN
  SELECT pcms.fn_minimum_salary(2025, 0, 2, 'NBA') INTO v_fn;

  IF v_fn IS NOT NULL THEN
    RAISE EXCEPTION 'fn_minimum_salary eligibility failed: expected NULL for YOS=0, year=2; got %', v_fn;
  END IF;
END
$$;

-- 5) Eligibility rules: YOS=2 cannot have contract year 4+.
DO $$
DECLARE v_fn bigint;
BEGIN
  SELECT pcms.fn_minimum_salary(2025, 2, 4, 'NBA') INTO v_fn;

  IF v_fn IS NOT NULL THEN
    RAISE EXCEPTION 'fn_minimum_salary eligibility failed: expected NULL for YOS=2, year=4; got %', v_fn;
  END IF;
END
$$;
