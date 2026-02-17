-- 075_player_rights_trade_direction_assertions.sql
--
-- Draft-rights direction guardrails:
-- - trade-derived rights rows must come from DRLST receiver rows (is_sent=false)
-- - curated override rows must land on expected team ownership

DO $$
DECLARE c int;
BEGIN
  SELECT COUNT(*) INTO c
  FROM pcms.player_rights_warehouse prw
  JOIN pcms.trade_team_details ttd
    ON ttd.trade_team_detail_id = prw.source_trade_team_detail_id
  WHERE prw.rights_kind = 'NBA_DRAFT_RIGHTS'
    AND prw.rights_source = 'trade_team_details'
    AND ttd.trade_entry_lk = 'DRLST'
    AND COALESCE(ttd.is_sent, true) <> false;

  IF c > 0 THEN
    RAISE EXCEPTION
      'player_rights_warehouse uses DRLST sender rows as ownership source; rows=%',
      c;
  END IF;
END
$$;

DO $$
DECLARE r record;
BEGIN
  SELECT rights_team_code, source_trade_id
    INTO r
  FROM pcms.player_rights_warehouse
  WHERE player_id = 203532; -- Bojan Dubljevic

  IF FOUND
     AND r.source_trade_id = 2022107
     AND r.rights_team_code IS DISTINCT FROM 'NYK' THEN
    RAISE EXCEPTION
      'Bojan Dubljevic rights expected NYK for trade 2022107, got %',
      r.rights_team_code;
  END IF;
END
$$;

DO $$
DECLARE r record;
BEGIN
  SELECT rights_team_code, rights_source
    INTO r
  FROM pcms.player_rights_warehouse
  WHERE player_id = 1626229; -- Daniel Diez

  IF FOUND
     AND (
       r.rights_team_code IS DISTINCT FROM 'NYK'
       OR r.rights_source IS DISTINCT FROM 'manual_override'
     ) THEN
    RAISE EXCEPTION
      'Daniel Diez rights expected NYK/manual_override, got team=% source=%',
      r.rights_team_code,
      r.rights_source;
  END IF;
END
$$;
