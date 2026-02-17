-- 074_salary_book_team_assignment_assertions.sql
--
-- team_code in salary_book_warehouse must represent the player's current
-- people.team_code (not contract/signing team fallback).

DO $$
DECLARE c int;
BEGIN
  SELECT COUNT(*) INTO c
  FROM pcms.salary_book_warehouse
  WHERE team_code IS DISTINCT FROM person_team_code;

  IF c > 0 THEN
    RAISE EXCEPTION
      'salary_book_warehouse team_code differs from person_team_code; rows=%',
      c;
  END IF;
END
$$;

DO $$
DECLARE c int;
BEGIN
  SELECT COUNT(*) INTO c
  FROM pcms.salary_book_warehouse sbw
  JOIN pcms.people p
    ON p.person_id = sbw.player_id
  WHERE p.player_status_lk IN ('WAV', 'UFA', 'PRE', 'NOTM', 'VRET', 'RET')
    AND sbw.team_code IS NOT NULL;

  IF c > 0 THEN
    RAISE EXCEPTION
      'salary_book_warehouse has off-team statuses with non-null team_code; rows=%',
      c;
  END IF;
END
$$;
