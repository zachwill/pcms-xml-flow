-- 065_cap_holds_and_salary_book_hold_columns_assertions.sql
--
-- Validate:
-- 1) cap_holds_warehouse includes all eligible non_contract_amounts rows,
--    including tbs.is_fa_amount=true cases.
-- 2) salary_book_warehouse cap_hold_20xx columns match non_contract_amounts.

DO $$
DECLARE
  missing_count int;
  extra_count int;
BEGIN
  WITH eligible AS (
    SELECT nca.non_contract_amount_id
    FROM pcms.non_contract_amounts nca
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
      )
  )
  SELECT COUNT(*) INTO missing_count
  FROM eligible e
  LEFT JOIN pcms.cap_holds_warehouse chw
    ON chw.non_contract_amount_id = e.non_contract_amount_id
  WHERE chw.non_contract_amount_id IS NULL;

  IF missing_count > 0 THEN
    RAISE EXCEPTION
      'cap_holds_warehouse missing eligible non_contract rows; count=%',
      missing_count;
  END IF;

  WITH eligible AS (
    SELECT nca.non_contract_amount_id
    FROM pcms.non_contract_amounts nca
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
      )
  )
  SELECT COUNT(*) INTO extra_count
  FROM pcms.cap_holds_warehouse chw
  LEFT JOIN eligible e
    ON e.non_contract_amount_id = chw.non_contract_amount_id
  WHERE e.non_contract_amount_id IS NULL;

  IF extra_count > 0 THEN
    RAISE EXCEPTION
      'cap_holds_warehouse contains non-eligible rows; count=%',
      extra_count;
  END IF;
END;
$$;

DO $$
DECLARE mismatch_count int;
BEGIN
  WITH expected AS (
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
  SELECT COUNT(*) INTO mismatch_count
  FROM pcms.salary_book_warehouse sbw
  LEFT JOIN expected e
    ON e.player_id = sbw.player_id
   AND e.team_code = sbw.team_code
  WHERE sbw.cap_hold_2025 IS DISTINCT FROM e.cap_hold_2025
     OR sbw.cap_hold_2026 IS DISTINCT FROM e.cap_hold_2026
     OR sbw.cap_hold_2027 IS DISTINCT FROM e.cap_hold_2027
     OR sbw.cap_hold_2028 IS DISTINCT FROM e.cap_hold_2028
     OR sbw.cap_hold_2029 IS DISTINCT FROM e.cap_hold_2029
     OR sbw.cap_hold_2030 IS DISTINCT FROM e.cap_hold_2030;

  IF mismatch_count > 0 THEN
    RAISE EXCEPTION
      'salary_book_warehouse cap_hold_20xx mismatch vs non_contract_amounts; rows=%',
      mismatch_count;
  END IF;
END;
$$;
