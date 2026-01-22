-- 032_trade_planner_tpe_summary.sql
--
-- Add a top-level `summary` object to pcms.fn_trade_plan_tpe(...) output.
--
-- Goal:
-- - Make UI/tooling consumption trivial: a single object with the key counts/totals.
--
-- Summary includes:
-- - counts (found incoming/outgoing, absorbed, remaining main-leg incoming)
-- - totals (cap amounts)
-- - key outputs (max incoming, created TPE)
-- - padding gate (is_padding_removed)

BEGIN;

CREATE OR REPLACE FUNCTION pcms.fn_trade_plan_tpe(
  p_team_code text,
  p_salary_year int,
  p_outgoing_player_ids int[] DEFAULT '{}'::int[],
  p_incoming_player_ids int[] DEFAULT '{}'::int[],
  p_exception_ids int[] DEFAULT NULL,
  p_tpe_type text DEFAULT 'standard',
  p_league_lk text DEFAULT 'NBA'
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_incoming_found_ids int[] := '{}'::int[];
  v_missing_incoming_ids int[] := '{}'::int[];

  v_outgoing_found_ids int[] := '{}'::int[];
  v_missing_outgoing_ids int[] := '{}'::int[];

  v_remaining_incoming_ids int[] := '{}'::int[];

  v_absorption_legs jsonb := '[]'::jsonb;

  exc record;
  cand record;

  v_exc_absorbed jsonb;
  v_exc_absorbed_players jsonb;
  v_exc_absorbed_player_ids int[];
  v_remaining_amount bigint;
  v_remaining_before bigint;
  v_exc_absorbed_total bigint;
  v_exc_absorbed_count int;
  v_exc_remaining_pct numeric;

  v_tpe_math jsonb;
  v_max_incoming_cap bigint;
  v_created_tpe_cap bigint;
  v_is_padding_removed boolean;

  v_result jsonb;

  -- Totals for tooling
  v_outgoing_total_cap bigint := 0;
  v_incoming_found_total_cap bigint := 0;
  v_absorbed_total_cap bigint := 0;
  v_main_leg_incoming_total_cap bigint := 0;

  -- Counts for tooling
  v_absorbed_players_count int := 0;

BEGIN
  -- ---------------------------------------------------------------------------
  -- Resolve incoming/outgoing rows (diagnostics)
  -- ---------------------------------------------------------------------------

  SELECT COALESCE(array_agg(sby.player_id ORDER BY sby.incoming_cap_amount DESC), '{}'::int[])
    INTO v_incoming_found_ids
  FROM pcms.salary_book_yearly sby
  WHERE sby.league_lk = p_league_lk
    AND sby.salary_year = p_salary_year
    AND sby.player_id = ANY(COALESCE(p_incoming_player_ids, '{}'::int[]));

  SELECT COALESCE(array_agg(missing_id), '{}'::int[])
    INTO v_missing_incoming_ids
  FROM (
    SELECT unnest(COALESCE(p_incoming_player_ids, '{}'::int[])) AS missing_id
    EXCEPT
    SELECT unnest(v_incoming_found_ids) AS missing_id
  ) x;

  SELECT COALESCE(array_agg(sby.player_id), '{}'::int[])
    INTO v_outgoing_found_ids
  FROM pcms.salary_book_yearly sby
  WHERE sby.league_lk = p_league_lk
    AND sby.salary_year = p_salary_year
    AND sby.team_code = p_team_code
    AND sby.player_id = ANY(COALESCE(p_outgoing_player_ids, '{}'::int[]));

  SELECT COALESCE(array_agg(missing_id), '{}'::int[])
    INTO v_missing_outgoing_ids
  FROM (
    SELECT unnest(COALESCE(p_outgoing_player_ids, '{}'::int[])) AS missing_id
    EXCEPT
    SELECT unnest(v_outgoing_found_ids) AS missing_id
  ) x;

  v_remaining_incoming_ids := v_incoming_found_ids;

  -- Totals for the found sets
  SELECT COALESCE(SUM(sby.incoming_cap_amount), 0)::bigint
    INTO v_incoming_found_total_cap
  FROM pcms.salary_book_yearly sby
  WHERE sby.league_lk = p_league_lk
    AND sby.salary_year = p_salary_year
    AND sby.player_id = ANY(v_incoming_found_ids);

  SELECT COALESCE(SUM(sby.cap_amount), 0)::bigint
    INTO v_outgoing_total_cap
  FROM pcms.salary_book_yearly sby
  WHERE sby.league_lk = p_league_lk
    AND sby.salary_year = p_salary_year
    AND sby.team_code = p_team_code
    AND sby.player_id = ANY(v_outgoing_found_ids);

  -- ---------------------------------------------------------------------------
  -- Absorption legs: allocate incoming players into existing TPEs (TREXC)
  -- ---------------------------------------------------------------------------

  FOR exc IN
    SELECT
      ew.team_exception_id,
      ew.team_code,
      ew.salary_year,
      ew.exception_type_lk,
      ew.exception_type_name,
      ew.expiration_date,
      ew.effective_date,
      ew.remaining_amount
    FROM pcms.exceptions_warehouse ew
    WHERE ew.team_code = p_team_code
      AND ew.salary_year = p_salary_year
      AND ew.exception_type_lk = 'TREXC'
      AND COALESCE(ew.remaining_amount, 0) > 0
      AND (
        p_exception_ids IS NULL
        OR array_length(p_exception_ids, 1) IS NULL
        OR ew.team_exception_id = ANY(p_exception_ids)
      )
    ORDER BY ew.expiration_date ASC NULLS LAST, ew.remaining_amount ASC
  LOOP
    v_remaining_amount := COALESCE(exc.remaining_amount, 0);
    v_remaining_before := v_remaining_amount;

    v_exc_absorbed_players := '[]'::jsonb;
    v_exc_absorbed_player_ids := '{}'::int[];
    v_exc_absorbed_total := 0;
    v_exc_absorbed_count := 0;

    LOOP
      -- Pick the largest incoming player that fits.
      SELECT
        sby.player_id,
        sby.player_name,
        sby.incoming_cap_amount AS cap_amount
      INTO cand
      FROM pcms.salary_book_yearly sby
      WHERE sby.league_lk = p_league_lk
        AND sby.salary_year = p_salary_year
        AND sby.player_id = ANY(v_remaining_incoming_ids)
        AND sby.incoming_cap_amount IS NOT NULL
        AND sby.incoming_cap_amount <= v_remaining_amount
      ORDER BY sby.incoming_cap_amount DESC
      LIMIT 1;

      EXIT WHEN cand.player_id IS NULL;

      v_exc_absorbed_players := v_exc_absorbed_players || jsonb_build_array(
        jsonb_build_object(
          'player_id', cand.player_id,
          'player_name', cand.player_name,
          'incoming_cap_amount', cand.cap_amount
        )
      );

      v_exc_absorbed_player_ids := v_exc_absorbed_player_ids || ARRAY[cand.player_id]::int[];

      v_remaining_amount := v_remaining_amount - cand.cap_amount;
      v_exc_absorbed_total := v_exc_absorbed_total + cand.cap_amount;
      v_absorbed_total_cap := v_absorbed_total_cap + cand.cap_amount;
      v_exc_absorbed_count := v_exc_absorbed_count + 1;
      v_absorbed_players_count := v_absorbed_players_count + 1;

      v_remaining_incoming_ids := array_remove(v_remaining_incoming_ids, cand.player_id);
    END LOOP;

    IF jsonb_array_length(v_exc_absorbed_players) > 0 THEN
      v_exc_remaining_pct := NULL;
      IF v_remaining_before > 0 THEN
        v_exc_remaining_pct := (v_remaining_amount::numeric / v_remaining_before::numeric);
      END IF;

      v_exc_absorbed := jsonb_build_object(
        'team_exception_id', exc.team_exception_id,
        'exception_type_lk', exc.exception_type_lk,
        'exception_type_name', exc.exception_type_name,
        'effective_date', exc.effective_date,
        'expiration_date', exc.expiration_date,
        'remaining_amount_before', v_remaining_before,
        'absorbed_players', v_exc_absorbed_players,
        'absorbed_player_ids', v_exc_absorbed_player_ids,
        'absorbed_cap_total', v_exc_absorbed_total,
        'absorbed_count', v_exc_absorbed_count,
        'remaining_amount_after', v_remaining_amount,
        'remaining_pct', v_exc_remaining_pct
      );

      v_absorption_legs := v_absorption_legs || jsonb_build_array(v_exc_absorbed);
    END IF;
  END LOOP;

  -- ---------------------------------------------------------------------------
  -- Main-leg totals + math (remaining incoming after absorption)
  -- ---------------------------------------------------------------------------

  SELECT COALESCE(SUM(sby.incoming_cap_amount), 0)::bigint
    INTO v_main_leg_incoming_total_cap
  FROM pcms.salary_book_yearly sby
  WHERE sby.league_lk = p_league_lk
    AND sby.salary_year = p_salary_year
    AND sby.player_id = ANY(v_remaining_incoming_ids);

  SELECT to_jsonb(r)
    INTO v_tpe_math
  FROM pcms.fn_tpe_trade_math(
    p_team_code,
    p_salary_year,
    v_outgoing_found_ids,
    v_remaining_incoming_ids,
    p_tpe_type,
    p_league_lk
  ) AS r;

  v_max_incoming_cap := NULL;
  v_created_tpe_cap := NULL;
  v_is_padding_removed := NULL;

  IF v_tpe_math ? 'max_replacement_salary' THEN
    v_max_incoming_cap := (v_tpe_math->>'max_replacement_salary')::bigint;
  END IF;

  IF v_tpe_math ? 'created_exception_amount' THEN
    v_created_tpe_cap := (v_tpe_math->>'created_exception_amount')::bigint;
  END IF;

  IF v_tpe_math ? 'is_padding_removed' THEN
    v_is_padding_removed := (v_tpe_math->>'is_padding_removed')::boolean;
  END IF;

  -- ---------------------------------------------------------------------------
  -- Final response
  -- ---------------------------------------------------------------------------

  v_result := jsonb_build_object(
    'team_code', p_team_code,
    'salary_year', p_salary_year,
    'league_lk', p_league_lk,
    'tpe_type', lower(p_tpe_type),

    'input', jsonb_build_object(
      'outgoing_player_ids', COALESCE(p_outgoing_player_ids, '{}'::int[]),
      'incoming_player_ids', COALESCE(p_incoming_player_ids, '{}'::int[]),
      'exception_ids', COALESCE(p_exception_ids, '{}'::int[])
    ),

    'diagnostics', jsonb_build_object(
      'outgoing_rows_found', COALESCE(array_length(v_outgoing_found_ids, 1), 0),
      'missing_outgoing_player_ids', v_missing_outgoing_ids,
      'incoming_rows_found', COALESCE(array_length(v_incoming_found_ids, 1), 0),
      'missing_incoming_player_ids', v_missing_incoming_ids
    ),

    'totals', jsonb_build_object(
      'outgoing_found_total_cap', v_outgoing_total_cap,
      'incoming_found_total_cap', v_incoming_found_total_cap,
      'absorbed_total_cap', v_absorbed_total_cap,
      'main_leg_outgoing_total_cap', v_outgoing_total_cap,
      'main_leg_incoming_total_cap', v_main_leg_incoming_total_cap
    ),

    'summary', jsonb_build_object(
      'outgoing_players_found', COALESCE(array_length(v_outgoing_found_ids, 1), 0),
      'incoming_players_found', COALESCE(array_length(v_incoming_found_ids, 1), 0),
      'absorbed_players_count', v_absorbed_players_count,
      'absorption_legs_count', COALESCE(jsonb_array_length(v_absorption_legs), 0),
      'main_leg_incoming_players_count', COALESCE(array_length(v_remaining_incoming_ids, 1), 0),

      'outgoing_found_total_cap', v_outgoing_total_cap,
      'incoming_found_total_cap', v_incoming_found_total_cap,
      'absorbed_total_cap', v_absorbed_total_cap,
      'main_leg_incoming_total_cap', v_main_leg_incoming_total_cap,

      'max_incoming_cap', v_max_incoming_cap,
      'created_tpe_cap', v_created_tpe_cap,
      'is_padding_removed', v_is_padding_removed
    ),

    'absorption_legs', v_absorption_legs,

    'main_leg', jsonb_build_object(
      'outgoing_player_ids', v_outgoing_found_ids,
      'incoming_player_ids', v_remaining_incoming_ids,
      'outgoing_total_cap', v_outgoing_total_cap,
      'incoming_total_cap', v_main_leg_incoming_total_cap,
      'tpe_math', v_tpe_math,
      'max_incoming_cap', v_max_incoming_cap,
      'created_tpe_cap', v_created_tpe_cap
    )
  );

  RETURN v_result;
END;
$$;

COMMIT;
