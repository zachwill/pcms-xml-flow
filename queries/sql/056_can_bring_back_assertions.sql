-- 056_can_bring_back_assertions.sql
-- Assertion tests for the inverse trade-matching primitives.

-- NOTE: These are pure-formula tests (no player-id fixtures).

-- 1) Expanded mode — low tier (invert 200% + $250K)
DO $$
DECLARE v bigint;
BEGIN
  SELECT pcms.fn_min_outgoing_for_incoming(10000000, 2025, 'expanded', 'NBA') INTO v;

  -- (10,000,000 - 250,000) / 2 = 4,875,000
  IF v IS DISTINCT FROM 4875000 THEN
    RAISE EXCEPTION 'fn_min_outgoing_for_incoming low-tier failed: expected %, got %', 4875000, v;
  END IF;
END
$$;

-- 2) Expanded mode — mid tier (invert 100% + TPE allowance)
DO $$
DECLARE v bigint;
BEGIN
  SELECT pcms.fn_min_outgoing_for_incoming(20000000, 2025, 'expanded', 'NBA') INTO v;

  -- 20,000,000 - 8,527,000 = 11,473,000
  IF v IS DISTINCT FROM 11473000 THEN
    RAISE EXCEPTION 'fn_min_outgoing_for_incoming mid-tier failed: expected %, got %', 11473000, v;
  END IF;
END
$$;

-- 3) Expanded mode — high tier (invert 125% + $250K)
DO $$
DECLARE v bigint;
BEGIN
  SELECT pcms.fn_min_outgoing_for_incoming(50000000, 2025, 'expanded', 'NBA') INTO v;

  -- (50,000,000 - 250,000) / 1.25 = 39,800,000
  IF v IS DISTINCT FROM 39800000 THEN
    RAISE EXCEPTION 'fn_min_outgoing_for_incoming high-tier failed: expected %, got %', 39800000, v;
  END IF;
END
$$;

-- 4) Wrapper alias should match the core function
DO $$
DECLARE v bigint;
BEGIN
  SELECT pcms.fn_can_bring_back(2025, 20000000, 'expanded', 'NBA') INTO v;

  IF v IS DISTINCT FROM 11473000 THEN
    RAISE EXCEPTION 'fn_can_bring_back wrapper mismatch: expected %, got %', 11473000, v;
  END IF;
END
$$;

-- 5) fn_trade_salary_range returns a coherent window
DO $$
DECLARE r record;
BEGIN
  SELECT * INTO r
  FROM pcms.fn_trade_salary_range(20000000, 2025, 'expanded', 'NBA');

  IF r.min_incoming IS DISTINCT FROM 11473000 THEN
    RAISE EXCEPTION 'fn_trade_salary_range min_incoming mismatch: expected %, got %', 11473000, r.min_incoming;
  END IF;

  -- Forward expanded max for 20M outgoing:
  --   min(2x+250k=40.25M, x+TPE=28.527M) then max with 1.25x+250k=25.25M
  IF r.max_incoming IS DISTINCT FROM 28527000 THEN
    RAISE EXCEPTION 'fn_trade_salary_range max_incoming mismatch: expected %, got %', 28527000, r.max_incoming;
  END IF;
END
$$;
