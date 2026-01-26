-- 054_exceptions_warehouse_proration_assertions.sql
--
-- Invariants for the Daily Exception Reduction Rule fields added in
-- migrations/archive/042_exceptions_warehouse_expiration_and_proration.sql.

-- 1) Warehouse should not contain expired exceptions.
DO $$
DECLARE c int;
BEGIN
  SELECT COUNT(*) INTO c
  FROM pcms.exceptions_warehouse
  WHERE expiration_date IS NOT NULL
    AND expiration_date < CURRENT_DATE;

  IF c > 0 THEN
    RAISE EXCEPTION 'exceptions_warehouse has % expired rows (should be filtered out)', c;
  END IF;
END
$$;

-- 2) For proration-applicable exception types, proration_factor should be in [0,1].
DO $$
DECLARE c int;
BEGIN
  SELECT COUNT(*) INTO c
  FROM pcms.exceptions_warehouse
  WHERE proration_applies
    AND (proration_factor < 0 OR proration_factor > 1 OR proration_factor IS NULL);

  IF c > 0 THEN
    RAISE EXCEPTION 'exceptions_warehouse has % rows with invalid proration_factor', c;
  END IF;
END
$$;

-- 3) For proration-applicable exception types, prorated_remaining_amount should be <= remaining_amount.
DO $$
DECLARE c int;
BEGIN
  SELECT COUNT(*) INTO c
  FROM pcms.exceptions_warehouse
  WHERE proration_applies
    AND prorated_remaining_amount IS NOT NULL
    AND remaining_amount IS NOT NULL
    AND prorated_remaining_amount > remaining_amount;

  IF c > 0 THEN
    RAISE EXCEPTION 'exceptions_warehouse has % rows where prorated_remaining_amount > remaining_amount', c;
  END IF;
END
$$;
