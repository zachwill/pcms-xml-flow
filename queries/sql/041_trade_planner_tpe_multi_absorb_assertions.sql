-- 041_trade_planner_tpe_multi_absorb_assertions.sql
-- Integration test: planner should be able to absorb multiple incoming players
-- into a single TREXC when they fit within remaining_amount.

DO $$
DECLARE
  v_team_code text;
  v_salary_year int := 2025;
  v_team_exception_id int;
  v_remaining_amount bigint;

  v_player1_id int;
  v_player2_id int;
  v_player1_amt bigint;
  v_player2_amt bigint;
  v_two_sum bigint;

  v_plan jsonb;
  v_absorbed_count int;
  v_main_incoming_len int;
  v_remaining_after bigint;
BEGIN
  -- Find two *small* incoming contracts for the year; these should exist in any realistic dataset.
  SELECT sby.player_id, sby.incoming_cap_amount
  INTO v_player1_id, v_player1_amt
  FROM pcms.salary_book_yearly sby
  WHERE sby.league_lk='NBA'
    AND sby.salary_year=v_salary_year
    AND sby.incoming_cap_amount IS NOT NULL
    AND sby.incoming_cap_amount > 0
  ORDER BY sby.incoming_cap_amount ASC
  LIMIT 1;

  SELECT sby.player_id, sby.incoming_cap_amount
  INTO v_player2_id, v_player2_amt
  FROM pcms.salary_book_yearly sby
  WHERE sby.league_lk='NBA'
    AND sby.salary_year=v_salary_year
    AND sby.incoming_cap_amount IS NOT NULL
    AND sby.incoming_cap_amount > 0
    AND sby.player_id <> v_player1_id
  ORDER BY sby.incoming_cap_amount ASC
  LIMIT 1;

  IF v_player1_id IS NULL OR v_player2_id IS NULL THEN
    RAISE EXCEPTION 'need at least two incoming salary_book_yearly rows for NBA/%', v_salary_year;
  END IF;

  v_two_sum := v_player1_amt + v_player2_amt;

  -- Pick a TREXC that can absorb both.
  SELECT
    ew.team_code,
    ew.salary_year,
    ew.team_exception_id,
    ew.remaining_amount
  INTO v_team_code, v_salary_year, v_team_exception_id, v_remaining_amount
  FROM pcms.exceptions_warehouse ew
  WHERE ew.salary_year = v_salary_year
    AND ew.exception_type_lk = 'TREXC'
    AND COALESCE(ew.remaining_amount, 0) >= v_two_sum
  ORDER BY ew.expiration_date ASC NULLS LAST, ew.remaining_amount ASC
  LIMIT 1;

  IF v_team_exception_id IS NULL THEN
    RAISE EXCEPTION 'no TREXC found that can absorb two smallest contracts (sum=%)', v_two_sum;
  END IF;

  v_plan := pcms.fn_trade_plan_tpe(
    v_team_code,
    v_salary_year,
    '{}'::int[],
    ARRAY[v_player1_id, v_player2_id]::int[],
    ARRAY[v_team_exception_id]::int[],
    'standard',
    'NBA'
  );

  -- Both players should be absorbed.
  SELECT COUNT(*) INTO v_absorbed_count
  FROM jsonb_array_elements(v_plan->'absorption_legs') leg
  CROSS JOIN jsonb_array_elements(leg->'absorbed_players') p
  WHERE (p->>'player_id')::int IN (v_player1_id, v_player2_id);

  IF v_absorbed_count <> 2 THEN
    RAISE EXCEPTION 'expected both players to be absorbed (count=2), got %', v_absorbed_count;
  END IF;

  -- Main-leg should have no incoming players.
  v_main_incoming_len := COALESCE(jsonb_array_length(v_plan#>'{main_leg,incoming_player_ids}'), 0);
  IF v_main_incoming_len <> 0 THEN
    RAISE EXCEPTION 'expected main_leg.incoming_player_ids empty after absorption; got len=%', v_main_incoming_len;
  END IF;

  -- Remaining amount should be reduced by the sum.
  SELECT (leg->>'remaining_amount_after')::bigint
  INTO v_remaining_after
  FROM jsonb_array_elements(v_plan->'absorption_legs') leg
  WHERE (leg->>'team_exception_id')::int = v_team_exception_id
  LIMIT 1;

  -- Totals should match.
  IF (v_plan#>>'{totals,incoming_found_total_cap}')::bigint IS DISTINCT FROM v_two_sum THEN
    RAISE EXCEPTION 'expected totals.incoming_found_total_cap=% but got %', v_two_sum, (v_plan#>>'{totals,incoming_found_total_cap}')::bigint;
  END IF;

  IF (v_plan#>>'{totals,absorbed_total_cap}')::bigint IS DISTINCT FROM v_two_sum THEN
    RAISE EXCEPTION 'expected totals.absorbed_total_cap=% but got %', v_two_sum, (v_plan#>>'{totals,absorbed_total_cap}')::bigint;
  END IF;

  IF (v_plan#>>'{main_leg,incoming_total_cap}')::bigint <> 0 THEN
    RAISE EXCEPTION 'expected main_leg.incoming_total_cap=0 after absorption';
  END IF;

  IF v_remaining_after IS NULL THEN
    RAISE EXCEPTION 'could not read remaining_amount_after for exc_id=%', v_team_exception_id;
  END IF;

  IF v_remaining_after <> (v_remaining_amount - v_two_sum) THEN
    RAISE EXCEPTION 'expected remaining_amount_after=% but got % (before %, absorbed %)', (v_remaining_amount - v_two_sum), v_remaining_after, v_remaining_amount, v_two_sum;
  END IF;

  -- absorbed_count should match.
  IF COALESCE((v_plan#>>'{absorption_legs,0,absorbed_count}')::int, 0) <> 2 THEN
    RAISE EXCEPTION 'expected absorption_legs[0].absorbed_count=2';
  END IF;

  -- Summary should exist and match.
  IF (v_plan ? 'summary') IS DISTINCT FROM TRUE THEN
    RAISE EXCEPTION 'expected planner output to include summary object';
  END IF;

  IF (v_plan#>>'{summary,absorbed_players_count}')::int <> 2 THEN
    RAISE EXCEPTION 'expected summary.absorbed_players_count=2';
  END IF;

  IF (v_plan#>>'{summary,incoming_found_total_cap}')::bigint IS DISTINCT FROM v_two_sum THEN
    RAISE EXCEPTION 'expected summary.incoming_found_total_cap=%', v_two_sum;
  END IF;

  IF (v_plan#>>'{summary,absorbed_total_cap}')::bigint IS DISTINCT FROM v_two_sum THEN
    RAISE EXCEPTION 'expected summary.absorbed_total_cap=%', v_two_sum;
  END IF;

  IF (v_plan#>>'{summary,main_leg_incoming_total_cap}')::bigint <> 0 THEN
    RAISE EXCEPTION 'expected summary.main_leg_incoming_total_cap=0 after absorption';
  END IF;

  IF (v_plan#>>'{summary,main_leg_max_incoming_cap_delta}') IS NULL THEN
    RAISE EXCEPTION 'expected summary.main_leg_max_incoming_cap_delta to be present';
  END IF;

  IF (v_plan#>>'{summary,main_leg_max_incoming_cap_delta}')::bigint <> (v_plan#>>'{summary,max_incoming_cap}')::bigint THEN
    RAISE EXCEPTION 'expected delta == max_incoming_cap when main_leg_incoming_total_cap=0';
  END IF;
END
$$;
