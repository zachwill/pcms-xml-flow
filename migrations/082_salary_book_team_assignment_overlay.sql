-- 082_salary_book_team_assignment_overlay.sql
--
-- Ensure salary_book_warehouse.team_code mirrors current people.team_code.
--
-- Why:
-- - team_code in salary_book_warehouse drives team roster rendering and
--   contract-roster rollups (team_salary_warehouse.cap_rost).
-- - Falling back to contract_team_code when people.team_code is NULL causes
--   off-team contracts (WAV/UFA/term money) to surface on active team rosters.
--
-- Rule:
-- - team_code should always equal person_team_code (normalized NULL/blank).
-- - contract_team_code remains available for contract provenance metadata.

BEGIN;

CREATE OR REPLACE FUNCTION pcms.refresh_salary_book_team_assignment_overlay()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM set_config('statement_timeout', '0', true);
  PERFORM set_config('lock_timeout', '5s', true);

  UPDATE pcms.salary_book_warehouse sbw
  SET
    person_team_code = NULLIF(BTRIM(sbw.person_team_code), ''),
    team_code = NULLIF(BTRIM(sbw.person_team_code), '')
  WHERE sbw.person_team_code IS DISTINCT FROM NULLIF(BTRIM(sbw.person_team_code), '')
     OR sbw.team_code IS DISTINCT FROM NULLIF(BTRIM(sbw.person_team_code), '');
END;
$$;

CREATE OR REPLACE FUNCTION pcms.refresh_salary_book_warehouse()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM pcms.refresh_salary_book_warehouse_core();
  PERFORM pcms.refresh_salary_book_option_decisions_overlay();
  PERFORM pcms.refresh_salary_book_team_assignment_overlay();
  PERFORM pcms.refresh_salary_book_cap_holds_overlay();
  PERFORM pcms.refresh_salary_book_two_way_overlay();
END;
$$;

-- Backfill current rows in-place so stale contract-team fallbacks disappear now.
SELECT pcms.refresh_salary_book_team_assignment_overlay();

COMMIT;
