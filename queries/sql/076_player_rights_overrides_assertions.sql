-- 076_player_rights_overrides_assertions.sql
--
-- Table-backed manual override guardrails for player rights.

SELECT 1 AS ok
FROM information_schema.tables
WHERE table_schema='pcms' AND table_name='player_rights_overrides';

DO $$
DECLARE c int;
BEGIN
  SELECT COUNT(*) INTO c
  FROM pcms.player_rights_overrides pro
  WHERE NULLIF(BTRIM(pro.reason), '') IS NULL;

  IF c > 0 THEN
    RAISE EXCEPTION
      'player_rights_overrides has blank reason rows: %',
      c;
  END IF;
END
$$;

DO $$
DECLARE c int;
BEGIN
  SELECT COUNT(*) INTO c
  FROM pcms.player_rights_overrides pro
  LEFT JOIN pcms.teams t
    ON t.team_code = pro.rights_team_code
  WHERE pro.is_active
    AND t.team_id IS NULL;

  IF c > 0 THEN
    RAISE EXCEPTION
      'player_rights_overrides has active rows with unknown rights_team_code: %',
      c;
  END IF;
END
$$;

DO $$
DECLARE c int;
BEGIN
  SELECT COUNT(*) INTO c
  FROM pcms.player_rights_warehouse prw
  LEFT JOIN pcms.player_rights_overrides pro
    ON pro.player_id = prw.player_id
   AND pro.is_active
  WHERE prw.rights_kind = 'NBA_DRAFT_RIGHTS'
    AND prw.rights_source = 'manual_override'
    AND (
      pro.player_id IS NULL
      OR prw.rights_team_code IS DISTINCT FROM pro.rights_team_code
    );

  IF c > 0 THEN
    RAISE EXCEPTION
      'manual_override rights rows do not match active player_rights_overrides rows: %',
      c;
  END IF;
END
$$;

DO $$
DECLARE c int;
BEGIN
  SELECT COUNT(*) INTO c
  FROM pcms.player_rights_overrides pro
  JOIN pcms.people p
    ON p.person_id = pro.player_id
  LEFT JOIN pcms.player_rights_warehouse prw
    ON prw.player_id = pro.player_id
  WHERE pro.is_active
    AND p.league_lk = 'NBA'
    AND p.record_status_lk = 'ACT'
    AND p.player_status_lk = 'CDL'
    AND (
      prw.player_id IS NULL
      OR prw.rights_source IS DISTINCT FROM 'manual_override'
      OR prw.rights_team_code IS DISTINCT FROM pro.rights_team_code
    );

  IF c > 0 THEN
    RAISE EXCEPTION
      'active NBA ACT/CDL overrides missing from player_rights_warehouse: %',
      c;
  END IF;
END
$$;

DO $$
DECLARE c int;
BEGIN
  SELECT COUNT(*) INTO c
  FROM pcms.player_rights_overrides pro
  WHERE pro.player_id = 1626229
    AND pro.is_active
    AND pro.rights_team_code = 'NYK';

  IF c <> 1 THEN
    RAISE EXCEPTION
      'Expected one active Daniel Diez override row (NYK), got %',
      c;
  END IF;
END
$$;
