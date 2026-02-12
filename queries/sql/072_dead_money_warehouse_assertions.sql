-- 072_dead_money_warehouse_assertions.sql
-- Invariants for pcms.dead_money_warehouse under "current TERM-only" semantics.

-- 1) team_code must always be present.
DO $$
DECLARE c int;
BEGIN
  SELECT COUNT(*) INTO c
  FROM pcms.dead_money_warehouse
  WHERE team_code IS NULL OR BTRIM(team_code) = '';

  IF c > 0 THEN
    RAISE EXCEPTION 'dead_money_warehouse has % rows with blank team_code', c;
  END IF;
END
$$;

-- 2) For each team/player/contract we should only have one active transaction stream.
DO $$
DECLARE c int;
BEGIN
  SELECT COUNT(*) INTO c
  FROM (
    SELECT team_code, player_id, contract_id
    FROM pcms.dead_money_warehouse
    WHERE salary_year BETWEEN 2025 AND 2030
    GROUP BY team_code, player_id, contract_id
    HAVING COUNT(DISTINCT transaction_id) > 1
  ) dup;

  IF c > 0 THEN
    RAISE EXCEPTION 'dead_money_warehouse has % team/player/contract groups with >1 transaction_id', c;
  END IF;
END
$$;

-- 3) Every warehouse row must correspond to a counting TERM row in team_budget_snapshots.
DO $$
DECLARE c int;
BEGIN
  SELECT COUNT(*) INTO c
  FROM pcms.dead_money_warehouse dm
  WHERE dm.salary_year BETWEEN 2025 AND 2030
    AND NOT EXISTS (
      SELECT 1
      FROM pcms.team_budget_snapshots tbs
      WHERE tbs.team_code = dm.team_code
        AND tbs.salary_year = dm.salary_year
        AND tbs.player_id = dm.player_id
        AND tbs.contract_id = dm.contract_id
        AND tbs.budget_group_lk = 'TERM'
        AND COALESCE(tbs.cap_amount, 0) = COALESCE(dm.cap_value, 0)
    );

  IF c > 0 THEN
    RAISE EXCEPTION 'dead_money_warehouse has % rows not backed by TERM rows in team_budget_snapshots', c;
  END IF;
END
$$;

-- 4) Team-year TERM totals should reconcile to team_salary_warehouse.cap_term.
DO $$
DECLARE c int;
BEGIN
  WITH dm_rollup AS (
    SELECT team_code, salary_year, SUM(cap_value)::bigint AS dead_cap
    FROM pcms.dead_money_warehouse
    WHERE salary_year BETWEEN 2025 AND 2030
    GROUP BY team_code, salary_year
  )
  SELECT COUNT(*) INTO c
  FROM pcms.team_salary_warehouse tsw
  LEFT JOIN dm_rollup dm
    ON dm.team_code = tsw.team_code
   AND dm.salary_year = tsw.salary_year
  WHERE tsw.salary_year BETWEEN 2025 AND 2030
    AND COALESCE(tsw.cap_term, 0) <> COALESCE(dm.dead_cap, 0);

  IF c > 0 THEN
    RAISE EXCEPTION 'dead_money_warehouse rollup does not reconcile to team_salary_warehouse.cap_term for % team/year rows', c;
  END IF;
END
$$;
