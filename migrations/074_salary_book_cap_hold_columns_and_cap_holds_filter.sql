-- 074_salary_book_cap_hold_columns_and_cap_holds_filter.sql
--
-- Goals:
-- 1) Include upcoming FA holds (including rows flagged via is_fa_amount) in cap_holds_warehouse.
-- 2) Expose player-level cap hold amounts on salary_book_warehouse in year-suffixed columns.
--
-- Notes:
-- - salary_book_warehouse remains contract-centric (one row per active contract).
-- - cap hold columns are parallel metadata (not additive to cap_20xx salary columns).

BEGIN;

-- -----------------------------------------------------------------------------
-- 1) Add salary_book cap-hold columns (year-suffixed to match existing schema)
-- -----------------------------------------------------------------------------

ALTER TABLE pcms.salary_book_warehouse
  ADD COLUMN IF NOT EXISTS cap_hold_2025 bigint,
  ADD COLUMN IF NOT EXISTS cap_hold_2026 bigint,
  ADD COLUMN IF NOT EXISTS cap_hold_2027 bigint,
  ADD COLUMN IF NOT EXISTS cap_hold_2028 bigint,
  ADD COLUMN IF NOT EXISTS cap_hold_2029 bigint,
  ADD COLUMN IF NOT EXISTS cap_hold_2030 bigint;


-- -----------------------------------------------------------------------------
-- 2) Refresh cap_holds_warehouse using a de-duplicating EXISTS predicate
--    and include rows marked is_fa_amount in team_budget_snapshots.
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION pcms.refresh_cap_holds_warehouse()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM set_config('statement_timeout', '0', true);
  PERFORM set_config('lock_timeout', '5s', true);

  TRUNCATE TABLE pcms.cap_holds_warehouse;

  INSERT INTO pcms.cap_holds_warehouse (
    non_contract_amount_id,

    team_id,
    team_code,
    salary_year,

    player_id,
    player_name,

    amount_type_lk,

    cap_amount,
    tax_amount,
    apron_amount,

    fa_amount,
    fa_amount_calc,
    salary_fa_amount,

    qo_amount,
    rofr_amount,
    rookie_scale_amount,

    carry_over_fa_flg,

    fa_amount_type_lk,
    fa_amount_type_lk_calc,
    free_agent_designation_lk,
    free_agent_status_lk,
    min_contract_lk,

    contract_id,
    contract_type_lk,
    transaction_id,
    version_number,
    years_of_service,

    refreshed_at
  )
  SELECT
    nca.non_contract_amount_id,

    nca.team_id,
    nca.team_code,
    nca.salary_year,

    nca.player_id,
    (p.last_name || ', ' || p.first_name) AS player_name,

    nca.amount_type_lk,

    nca.cap_amount,
    nca.tax_amount,
    nca.apron_amount,

    nca.fa_amount,
    nca.fa_amount_calc,
    nca.salary_fa_amount,

    nca.qo_amount,
    nca.rofr_amount,
    nca.rookie_scale_amount,

    nca.carry_over_fa_flg,

    nca.fa_amount_type_lk,
    nca.fa_amount_type_lk_calc,
    nca.free_agent_designation_lk,
    nca.free_agent_status_lk,
    nca.min_contract_lk,

    nca.contract_id,
    nca.contract_type_lk,
    nca.transaction_id,
    nca.version_number,
    nca.years_of_service,

    now() AS refreshed_at

  FROM pcms.non_contract_amounts nca
  LEFT JOIN pcms.people p
    ON p.person_id = nca.player_id
  WHERE nca.salary_year >= 2025
    AND nca.team_code IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM pcms.team_budget_snapshots tbs
      WHERE tbs.team_code = nca.team_code
        AND tbs.salary_year = nca.salary_year
        AND tbs.player_id = nca.player_id
        AND (
          tbs.budget_group_lk IN ('FA', 'QO', 'DRFPK', 'PR10D')
          OR COALESCE(tbs.is_fa_amount, false) = true
        )
    );
END;
$$;


-- -----------------------------------------------------------------------------
-- 3) Overlay cap-hold columns onto salary_book_warehouse rows
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION pcms.refresh_salary_book_cap_holds_overlay()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM set_config('statement_timeout', '0', true);
  PERFORM set_config('lock_timeout', '5s', true);

  -- Clear first so removed holds do not leave stale values.
  UPDATE pcms.salary_book_warehouse
  SET
    cap_hold_2025 = NULL,
    cap_hold_2026 = NULL,
    cap_hold_2027 = NULL,
    cap_hold_2028 = NULL,
    cap_hold_2029 = NULL,
    cap_hold_2030 = NULL;

  WITH hold_pivot AS (
    SELECT
      nca.player_id,
      nca.team_code,
      MAX(CASE WHEN nca.salary_year = 2025 THEN nca.cap_amount END) AS cap_hold_2025,
      MAX(CASE WHEN nca.salary_year = 2026 THEN nca.cap_amount END) AS cap_hold_2026,
      MAX(CASE WHEN nca.salary_year = 2027 THEN nca.cap_amount END) AS cap_hold_2027,
      MAX(CASE WHEN nca.salary_year = 2028 THEN nca.cap_amount END) AS cap_hold_2028,
      MAX(CASE WHEN nca.salary_year = 2029 THEN nca.cap_amount END) AS cap_hold_2029,
      MAX(CASE WHEN nca.salary_year = 2030 THEN nca.cap_amount END) AS cap_hold_2030
    FROM pcms.non_contract_amounts nca
    WHERE nca.team_code IS NOT NULL
      AND nca.salary_year BETWEEN 2025 AND 2030
      AND EXISTS (
        SELECT 1
        FROM pcms.team_budget_snapshots tbs
        WHERE tbs.team_code = nca.team_code
          AND tbs.salary_year = nca.salary_year
          AND tbs.player_id = nca.player_id
          AND (
            tbs.budget_group_lk IN ('FA', 'QO', 'DRFPK', 'PR10D')
            OR COALESCE(tbs.is_fa_amount, false) = true
          )
      )
    GROUP BY 1, 2
  )
  UPDATE pcms.salary_book_warehouse sbw
  SET
    cap_hold_2025 = hp.cap_hold_2025,
    cap_hold_2026 = hp.cap_hold_2026,
    cap_hold_2027 = hp.cap_hold_2027,
    cap_hold_2028 = hp.cap_hold_2028,
    cap_hold_2029 = hp.cap_hold_2029,
    cap_hold_2030 = hp.cap_hold_2030
  FROM hold_pivot hp
  WHERE sbw.player_id = hp.player_id
    AND sbw.team_code = hp.team_code;
END;
$$;


-- -----------------------------------------------------------------------------
-- 4) Wrap refresh_salary_book_warehouse() so hold overlay is always applied
-- -----------------------------------------------------------------------------

DO $$
BEGIN
  -- First run after this migration: rename existing implementation.
  IF EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'pcms'
      AND p.proname = 'refresh_salary_book_warehouse'
      AND pg_get_function_identity_arguments(p.oid) = ''
  )
  AND NOT EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'pcms'
      AND p.proname = 'refresh_salary_book_warehouse_core'
      AND pg_get_function_identity_arguments(p.oid) = ''
  ) THEN
    EXECUTE 'ALTER FUNCTION pcms.refresh_salary_book_warehouse() RENAME TO refresh_salary_book_warehouse_core';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION pcms.refresh_salary_book_warehouse()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM pcms.refresh_salary_book_warehouse_core();
  PERFORM pcms.refresh_salary_book_cap_holds_overlay();
END;
$$;


-- -----------------------------------------------------------------------------
-- 5) Backfill current cache data in-place
-- -----------------------------------------------------------------------------

SELECT pcms.refresh_cap_holds_warehouse();
SELECT pcms.refresh_salary_book_cap_holds_overlay();

COMMIT;
