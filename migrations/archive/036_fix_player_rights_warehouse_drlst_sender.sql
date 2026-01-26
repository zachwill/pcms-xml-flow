-- 036_fix_player_rights_warehouse_drlst_sender.sql
-- Update refresh function to use DRLST sender rows (is_sent=true) as rights holder.

BEGIN;

CREATE OR REPLACE FUNCTION pcms.refresh_player_rights_warehouse()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  TRUNCATE TABLE pcms.player_rights_warehouse;

  WITH drlst_sender AS (
    SELECT
      ttd.player_id,
      ttd.team_id AS rights_team_id,
      t.team_code AS rights_team_code,
      ttd.trade_id AS source_trade_id,
      tr.trade_date AS source_trade_date,
      ttd.trade_team_detail_id AS source_trade_team_detail_id,
      ROW_NUMBER() OVER (
        PARTITION BY ttd.player_id
        ORDER BY tr.trade_date DESC NULLS LAST, ttd.trade_id DESC, ttd.seqno DESC
      ) AS rn
    FROM pcms.trade_team_details ttd
    JOIN pcms.trades tr ON tr.trade_id = ttd.trade_id
    LEFT JOIN pcms.teams t ON t.team_id = ttd.team_id
    WHERE ttd.trade_entry_lk = 'DRLST'
      AND ttd.player_id IS NOT NULL
      AND ttd.is_sent = true
  ),
  nba_contracts AS (
    SELECT DISTINCT player_id
    FROM pcms.salary_book_warehouse
  )
  INSERT INTO pcms.player_rights_warehouse (
    player_id,
    player_name,
    league_lk,
    rights_team_id,
    rights_team_code,
    rights_kind,
    rights_source,
    source_trade_id,
    source_trade_date,
    source_trade_team_detail_id,
    draft_year,
    draft_round,
    draft_pick,
    draft_team_id,
    draft_team_code,
    has_active_nba_contract,
    needs_review,
    refreshed_at
  )
  SELECT
    p.person_id AS player_id,
    NULLIF(trim(concat_ws(' ', p.display_first_name, p.display_last_name)), '') AS player_name,
    p.league_lk,

    COALESCE(ds.rights_team_id, p.draft_team_id) AS rights_team_id,
    COALESCE(ds.rights_team_code, dt.team_code) AS rights_team_code,

    'NBA_DRAFT_RIGHTS' AS rights_kind,
    CASE WHEN ds.player_id IS NOT NULL THEN 'trade_team_details' ELSE 'people' END AS rights_source,

    ds.source_trade_id,
    ds.source_trade_date,
    ds.source_trade_team_detail_id,

    p.draft_year,
    p.draft_round,
    p.draft_pick,
    p.draft_team_id,
    dt.team_code AS draft_team_code,

    (nc.player_id IS NOT NULL) AS has_active_nba_contract,

    (COALESCE(ds.rights_team_code, dt.team_code) IS NULL OR COALESCE(ds.rights_team_code, dt.team_code) = '') AS needs_review,

    now() AS refreshed_at
  FROM pcms.people p
  LEFT JOIN drlst_sender ds
    ON ds.player_id = p.person_id
   AND ds.rn = 1
  LEFT JOIN pcms.teams dt
    ON dt.team_id = p.draft_team_id
  LEFT JOIN nba_contracts nc
    ON nc.player_id = p.person_id
  WHERE p.league_lk = 'NBA'
    AND p.draft_year IS NOT NULL
    AND nc.player_id IS NULL;

  INSERT INTO pcms.player_rights_warehouse (
    player_id,
    player_name,
    league_lk,
    rights_team_id,
    rights_team_code,
    rights_kind,
    rights_source,
    draft_year,
    draft_round,
    draft_pick,
    draft_team_id,
    draft_team_code,
    has_active_nba_contract,
    needs_review,
    refreshed_at
  )
  SELECT
    p.person_id,
    NULLIF(trim(concat_ws(' ', p.display_first_name, p.display_last_name)), '') AS player_name,
    p.league_lk,
    p.dlg_returning_rights_team_id,
    p.dlg_returning_rights_team_code,
    'DLG_RETURNING_RIGHTS',
    'people',
    p.draft_year,
    p.draft_round,
    p.draft_pick,
    p.draft_team_id,
    dt.team_code,
    false,
    (p.dlg_returning_rights_team_code IS NULL OR p.dlg_returning_rights_team_code=''),
    now()
  FROM pcms.people p
  LEFT JOIN pcms.teams dt ON dt.team_id = p.draft_team_id
  WHERE p.league_lk = 'DLG'
    AND p.dlg_returning_rights_team_id IS NOT NULL
  ON CONFLICT (player_id) DO NOTHING;

END;
$$;

COMMIT;
