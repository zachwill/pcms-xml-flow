-- 000_smoke.sql
-- Sanity: required relations/functions exist.

DO $$
BEGIN
  IF to_regclass('pcms.salary_book_warehouse') IS NULL THEN
    RAISE EXCEPTION 'missing relation: pcms.salary_book_warehouse';
  END IF;

  IF to_regclass('pcms.team_salary_warehouse') IS NULL THEN
    RAISE EXCEPTION 'missing relation: pcms.team_salary_warehouse';
  END IF;

  IF to_regclass('pcms.exceptions_warehouse') IS NULL THEN
    RAISE EXCEPTION 'missing relation: pcms.exceptions_warehouse';
  END IF;

  IF to_regclass('pcms.salary_book_yearly') IS NULL THEN
    RAISE EXCEPTION 'missing relation: pcms.salary_book_yearly';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname='pcms' AND p.proname='fn_post_trade_apron'
  ) THEN
    RAISE EXCEPTION 'missing function: pcms.fn_post_trade_apron';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname='pcms' AND p.proname='fn_tpe_trade_math'
  ) THEN
    RAISE EXCEPTION 'missing function: pcms.fn_tpe_trade_math';
  END IF;
END
$$;

-- Small rowcount sanity (not strict, but should not be empty)
DO $$
DECLARE c int;
BEGIN
  SELECT COUNT(*) INTO c FROM pcms.team_salary_warehouse;
  IF c = 0 THEN
    RAISE EXCEPTION 'pcms.team_salary_warehouse is empty';
  END IF;

  SELECT COUNT(*) INTO c FROM pcms.salary_book_warehouse;
  IF c = 0 THEN
    RAISE EXCEPTION 'pcms.salary_book_warehouse is empty';
  END IF;
END
$$;
