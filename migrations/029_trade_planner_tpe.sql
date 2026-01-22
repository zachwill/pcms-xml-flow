-- 029_trade_planner_tpe.sql
--
-- Trade planner MVP (TPE-only).
--
-- Purpose:
-- - Model the common front-office workflow:
--   (1) Use existing Traded Player Exceptions (TPEs) to absorb some incoming players
--   (2) Run the remaining players through main-leg salary matching (6(j) primitive)
--
-- Heuristic (documented + deterministic):
-- - Consider only exception_type_lk='TREXC' (Traded Player Exception)
-- - Prefer exceptions that expire sooner (expiration_date ASC NULLS LAST)
-- - For each exception, repeatedly absorb the *largest* incoming player that fits
--   (incoming_cap_amount <= remaining_amount)
--
-- Output:
-- - Returns a single JSONB blob describing absorption legs + main-leg math.

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
  v_remaining_amount bigint;
  v_remaining_before bigint;

  v_main_leg jsonb;
  v_result jsonb;

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

      -- Record absorption
      v_exc_absorbed_players := v_exc_absorbed_players || jsonb_build_array(
        jsonb_build_object(
          'player_id', cand.player_id,
          'player_name', cand.player_name,
          'incoming_cap_amount', cand.cap_amount
        )
      );

      -- Update exception remaining + remaining incoming ids
      v_remaining_amount := v_remaining_amount - cand.cap_amount;
      v_remaining_incoming_ids := array_remove(v_remaining_incoming_ids, cand.player_id);

      -- Continue until nothing fits.
    END LOOP;

    IF jsonb_array_length(v_exc_absorbed_players) > 0 THEN
      v_exc_absorbed := jsonb_build_object(
        'team_exception_id', exc.team_exception_id,
        'exception_type_lk', exc.exception_type_lk,
        'exception_type_name', exc.exception_type_name,
        'effective_date', exc.effective_date,
        'expiration_date', exc.expiration_date,
        'remaining_amount_before', v_remaining_before,
        'absorbed_players', v_exc_absorbed_players,
        'remaining_amount_after', v_remaining_amount
      );

      v_absorption_legs := v_absorption_legs || jsonb_build_array(v_exc_absorbed);
    END IF;
  END LOOP;

  -- ---------------------------------------------------------------------------
  -- Main-leg math (remaining incoming after absorption)
  -- ---------------------------------------------------------------------------

  SELECT to_jsonb(r)
    INTO v_main_leg
  FROM pcms.fn_tpe_trade_math(
    p_team_code,
    p_salary_year,
    v_outgoing_found_ids,
    v_remaining_incoming_ids,
    p_tpe_type,
    p_league_lk
  ) AS r;

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

    'absorption_legs', v_absorption_legs,

    'main_leg', jsonb_build_object(
      'outgoing_player_ids', v_outgoing_found_ids,
      'incoming_player_ids', v_remaining_incoming_ids,
      'tpe_math', v_main_leg
    )
  );

  RETURN v_result;
END;
$$;

COMMIT;
