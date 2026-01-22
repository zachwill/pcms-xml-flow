-- 040_trade_planner_tpe_assertions.sql
-- Invariants + minimal integration test for pcms.fn_trade_plan_tpe.

-- 0) Function exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname='pcms' AND p.proname='fn_trade_plan_tpe'
  ) THEN
    RAISE EXCEPTION 'missing function: pcms.fn_trade_plan_tpe';
  END IF;
END
$$;

-- 1) Integration test:
-- Pick a real TREXC for 2025 and an incoming player that fits within remaining_amount.
-- Expect: absorbed into the TPE, removed from the main-leg incoming list.
DO $$
DECLARE
  v_team_code text;
  v_salary_year int;
  v_team_exception_id int;
  v_remaining_amount bigint;
  v_player_id int;
  v_player_amt bigint;

  v_plan jsonb;
  v_absorbed_count int;
  v_main_incoming_len int;
  v_absorbed_total bigint;
BEGIN
  SELECT
    ew.team_code,
    ew.salary_year,
    ew.team_exception_id,
    ew.remaining_amount
  INTO v_team_code, v_salary_year, v_team_exception_id, v_remaining_amount
  FROM pcms.exceptions_warehouse ew
  WHERE ew.salary_year = 2025
    AND ew.exception_type_lk = 'TREXC'
    AND COALESCE(ew.remaining_amount, 0) > 0
  ORDER BY ew.expiration_date ASC NULLS LAST, ew.remaining_amount DESC
  LIMIT 1;

  IF v_team_exception_id IS NULL THEN
    RAISE EXCEPTION 'no TREXC rows found in exceptions_warehouse for salary_year=2025';
  END IF;

  SELECT sby.player_id, sby.incoming_cap_amount
  INTO v_player_id, v_player_amt
  FROM pcms.salary_book_yearly sby
  WHERE sby.league_lk = 'NBA'
    AND sby.salary_year = v_salary_year
    AND sby.incoming_cap_amount IS NOT NULL
    AND sby.incoming_cap_amount <= v_remaining_amount
  ORDER BY sby.incoming_cap_amount DESC
  LIMIT 1;

  IF v_player_id IS NULL THEN
    RAISE EXCEPTION 'could not find an incoming player that fits within TREXC remaining_amount (team %, remaining %)', v_team_code, v_remaining_amount;
  END IF;

  v_plan := pcms.fn_trade_plan_tpe(
    v_team_code,
    v_salary_year,
    '{}'::int[],
    ARRAY[v_player_id]::int[],
    ARRAY[v_team_exception_id]::int[],
    'standard',
    'NBA'
  );

  -- Ensure the absorbed player shows up in absorption_legs
  SELECT COUNT(*) INTO v_absorbed_count
  FROM jsonb_array_elements(v_plan->'absorption_legs') leg
  CROSS JOIN jsonb_array_elements(leg->'absorbed_players') p
  WHERE (p->>'player_id')::int = v_player_id;

  IF v_absorbed_count = 0 THEN
    RAISE EXCEPTION 'planner did not absorb player_id=% into the selected TREXC (team %, exc_id %)', v_player_id, v_team_code, v_team_exception_id;
  END IF;

  -- Ensure main-leg incoming ids is empty (player was absorbed)
  v_main_incoming_len := COALESCE(jsonb_array_length(v_plan#>'{main_leg,incoming_player_ids}'), 0);
  IF v_main_incoming_len <> 0 THEN
    RAISE EXCEPTION 'expected main_leg.incoming_player_ids to be empty after absorption; got len=%', v_main_incoming_len;
  END IF;

  -- Totals should exist and match.
  IF (v_plan ? 'totals') IS DISTINCT FROM TRUE THEN
    RAISE EXCEPTION 'expected planner output to include totals object';
  END IF;

  v_absorbed_total := (v_plan#>>'{totals,absorbed_total_cap}')::bigint;
  IF v_absorbed_total IS DISTINCT FROM v_player_amt THEN
    RAISE EXCEPTION 'expected totals.absorbed_total_cap=% but got %', v_player_amt, v_absorbed_total;
  END IF;

  IF (v_plan#>>'{totals,incoming_found_total_cap}')::bigint IS DISTINCT FROM v_player_amt THEN
    RAISE EXCEPTION 'expected totals.incoming_found_total_cap=%', v_player_amt;
  END IF;

  IF (v_plan#>>'{main_leg,incoming_total_cap}')::bigint <> 0 THEN
    RAISE EXCEPTION 'expected main_leg.incoming_total_cap=0 after absorption';
  END IF;

  -- UI convenience fields should exist.
  IF (v_plan#>>'{main_leg,max_incoming_cap}') IS NULL THEN
    RAISE EXCEPTION 'expected main_leg.max_incoming_cap to be present';
  END IF;

  IF (v_plan#>>'{main_leg,created_tpe_cap}') IS NULL THEN
    RAISE EXCEPTION 'expected main_leg.created_tpe_cap to be present';
  END IF;

  IF COALESCE((v_plan#>>'{absorption_legs,0,absorbed_count}')::int, 0) <> 1 THEN
    RAISE EXCEPTION 'expected absorption_legs[0].absorbed_count=1';
  END IF;

  -- Summary should exist and match totals.
  IF (v_plan ? 'summary') IS DISTINCT FROM TRUE THEN
    RAISE EXCEPTION 'expected planner output to include summary object';
  END IF;

  IF (v_plan#>>'{summary,absorbed_players_count}')::int <> 1 THEN
    RAISE EXCEPTION 'expected summary.absorbed_players_count=1';
  END IF;

  IF (v_plan#>>'{summary,incoming_found_total_cap}')::bigint IS DISTINCT FROM v_player_amt THEN
    RAISE EXCEPTION 'expected summary.incoming_found_total_cap=%', v_player_amt;
  END IF;

  IF (v_plan#>>'{summary,absorbed_total_cap}')::bigint IS DISTINCT FROM v_player_amt THEN
    RAISE EXCEPTION 'expected summary.absorbed_total_cap=%', v_player_amt;
  END IF;

  IF (v_plan#>>'{summary,main_leg_incoming_total_cap}')::bigint <> 0 THEN
    RAISE EXCEPTION 'expected summary.main_leg_incoming_total_cap=0 after absorption';
  END IF;

  -- Delta should match max_incoming_cap - main_leg_incoming_total_cap
  IF (v_plan#>>'{summary,main_leg_max_incoming_cap_delta}') IS NULL THEN
    RAISE EXCEPTION 'expected summary.main_leg_max_incoming_cap_delta to be present';
  END IF;

  IF (v_plan#>>'{summary,main_leg_max_incoming_cap_delta}')::bigint <> (v_plan#>>'{summary,max_incoming_cap}')::bigint THEN
    RAISE EXCEPTION 'expected delta == max_incoming_cap when main_leg_incoming_total_cap=0';
  END IF;
END
$$;
