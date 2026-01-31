-- 059_fn_minimum_salary.sql
--
-- Helper to derive multi-year minimum salaries (Years 2–5) from PCMS Year-1
-- minimums using the escalator constants observed in Sean's workbook.

BEGIN;

CREATE OR REPLACE FUNCTION pcms.fn_minimum_salary(
  p_salary_year int,
  p_years_of_service int,
  p_contract_year int,
  p_league_lk text DEFAULT 'NBA'
)
RETURNS bigint
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_base bigint;
  v_result bigint;
  v_max_contract_year int;
BEGIN
  IF p_salary_year IS NULL
     OR p_years_of_service IS NULL
     OR p_contract_year IS NULL THEN
    RETURN NULL;
  END IF;

  IF p_contract_year < 1 OR p_contract_year > 5 THEN
    RETURN NULL;
  END IF;

  IF p_years_of_service < 0 THEN
    RETURN NULL;
  END IF;

  -- Eligibility by YOS (as implied by Sean's minimum salary table layout):
  -- 0 YOS -> 1 year, 1 YOS -> 2 years, 2 YOS -> 3 years, 3 YOS -> 4 years, 4+ -> 5 years
  v_max_contract_year := LEAST(5, p_years_of_service + 1);
  IF p_contract_year > v_max_contract_year THEN
    RETURN NULL;
  END IF;

  SELECT lss.minimum_salary_amount
  INTO v_base
  FROM pcms.league_salary_scales lss
  WHERE lss.salary_year = p_salary_year
    AND lss.league_lk = p_league_lk
    AND lss.years_of_service = p_years_of_service;

  IF v_base IS NULL THEN
    RETURN NULL;
  END IF;

  IF p_contract_year = 1 THEN
    RETURN v_base;
  END IF;

  -- Year 2: +5.0%
  v_result := ROUND(v_base::numeric * 1.05, 0)::bigint;
  IF p_contract_year = 2 THEN
    RETURN v_result;
  END IF;

  -- Year 3: +4.7%
  v_result := ROUND(v_result::numeric * 1.047, 0)::bigint;
  IF p_contract_year = 3 THEN
    RETURN v_result;
  END IF;

  -- Year 4: +4.5% for YOS=3, +4.7% for YOS>=4
  v_result := ROUND(
    v_result::numeric * (CASE WHEN p_years_of_service = 3 THEN 1.045 ELSE 1.047 END),
    0
  )::bigint;
  IF p_contract_year = 4 THEN
    RETURN v_result;
  END IF;

  -- Year 5: +4.3%
  v_result := ROUND(v_result::numeric * 1.043, 0)::bigint;
  RETURN v_result;
END;
$$;

COMMIT;
