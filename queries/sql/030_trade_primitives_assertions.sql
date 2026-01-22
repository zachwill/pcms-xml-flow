-- 030_trade_primitives_assertions.sql
-- Invariants for the trade tooling primitives.

-- We avoid player-id-specific tests here; we just validate that:
-- - league constants exist
-- - fn_post_trade_apron behaves correctly for the empty-trade case
-- - fn_tpe_trade_math returns a row and respects the padding gate nullability

-- 1) league_system_values must exist for NBA 2025 (cap year used in tooling)
DO $$
DECLARE c int;
BEGIN
  SELECT COUNT(*) INTO c
  FROM pcms.league_system_values
  WHERE league_lk='NBA' AND salary_year=2025;

  IF c = 0 THEN
    RAISE EXCEPTION 'missing pcms.league_system_values for NBA salary_year=2025';
  END IF;
END
$$;

-- 2) fn_post_trade_apron(empty outgoing/incoming) should equal baseline apron_total
DO $$
DECLARE
  r record;
BEGIN
  SELECT * INTO r
  FROM pcms.fn_post_trade_apron('BOS', 2025, '{}'::int[], '{}'::int[], 'NBA');

  IF r.has_team_salary IS DISTINCT FROM TRUE THEN
    RAISE EXCEPTION 'fn_post_trade_apron: expected has_team_salary=TRUE for BOS/2025';
  END IF;

  IF r.outgoing_apron_total <> 0 OR r.incoming_apron_total <> 0 THEN
    RAISE EXCEPTION 'fn_post_trade_apron: expected outgoing/incoming totals 0 for empty arrays';
  END IF;

  IF r.post_trade_apron_total IS DISTINCT FROM r.baseline_apron_total THEN
    RAISE EXCEPTION 'fn_post_trade_apron: expected post_trade_apron_total == baseline_apron_total';
  END IF;
END
$$;

-- 3) fn_tpe_trade_math should return a row for BOS/2025 even with empty player arrays
--    (values will be 0, but constants should be present)
DO $$
DECLARE r record;
BEGIN
  SELECT * INTO r
  FROM pcms.fn_tpe_trade_math('BOS', 2025, '{}'::int[], '{}'::int[], 'standard', 'NBA');

  IF r.team_code IS DISTINCT FROM 'BOS' OR r.salary_year IS DISTINCT FROM 2025 THEN
    RAISE EXCEPTION 'fn_tpe_trade_math: unexpected identity row (% / %)', r.team_code, r.salary_year;
  END IF;

  IF r.has_league_system_values IS DISTINCT FROM TRUE THEN
    RAISE EXCEPTION 'fn_tpe_trade_math: expected has_league_system_values=TRUE for NBA/2025';
  END IF;

  -- Padding gate fields should either both be null (if apron totals missing) or both be non-null.
  IF (r.is_padding_removed IS NULL) <> (r.tpe_padding_amount IS NULL) THEN
    RAISE EXCEPTION 'fn_tpe_trade_math: padding gate nullability mismatch';
  END IF;
END
$$;
