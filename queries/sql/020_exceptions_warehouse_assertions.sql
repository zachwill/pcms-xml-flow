-- 020_exceptions_warehouse_assertions.sql
-- Invariants for pcms.exceptions_warehouse.

-- 1) Warehouse should not have blank team codes (we derive them from team_id).
DO $$
DECLARE c int;
BEGIN
  SELECT COUNT(*) INTO c
  FROM pcms.exceptions_warehouse
  WHERE team_code IS NULL OR BTRIM(team_code) = '';

  IF c > 0 THEN
    RAISE EXCEPTION 'exceptions_warehouse has % rows with blank team_code', c;
  END IF;
END
$$;

-- 2) Exception type names should be filled (lookup_type=lk_exception_types).
DO $$
DECLARE c int;
BEGIN
  SELECT COUNT(*) INTO c
  FROM pcms.exceptions_warehouse
  WHERE exception_type_name IS NULL OR BTRIM(exception_type_name) = '';

  IF c > 0 THEN
    RAISE EXCEPTION 'exceptions_warehouse has % rows with blank exception_type_name', c;
  END IF;
END
$$;

-- 3) For recent years we expect at least some exceptions.
DO $$
DECLARE c int;
BEGIN
  SELECT COUNT(*) INTO c
  FROM pcms.exceptions_warehouse
  WHERE salary_year = 2025;

  IF c = 0 THEN
    RAISE EXCEPTION 'exceptions_warehouse has 0 rows for salary_year=2025 (unexpected)';
  END IF;
END
$$;
