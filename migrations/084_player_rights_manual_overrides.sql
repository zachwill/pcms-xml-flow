-- 084_player_rights_manual_overrides.sql
--
-- Apply curated player-rights overrides after DRLST resolution for known
-- source-direction anomalies.
--
-- Current override:
-- - Daniel Diez (1626229): force NYK draft rights.
--   Context: latest DRLST trade rows vs curated rights intent are inconsistent.

BEGIN;

CREATE OR REPLACE FUNCTION pcms.refresh_player_rights_warehouse()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  TRUNCATE TABLE pcms.player_rights_warehouse;

  WITH drlst_receiver AS (
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
      AND ttd.is_sent = false
  ),
  rights_overrides AS (
    SELECT 1626229::integer AS player_id, 'NYK'::text AS rights_team_code
  ),
  rights_overrides_enriched AS (
    SELECT
      ro.player_id,
      ro.rights_team_code,
      t.team_id AS rights_team_id
    FROM rights_overrides ro
    LEFT JOIN pcms.teams t
      ON t.team_code = ro.rights_team_code
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

    COALESCE(roe.rights_team_id, dr.rights_team_id, p.team_id, p.draft_team_id) AS rights_team_id,
    COALESCE(roe.rights_team_code, dr.rights_team_code, pt.team_code, dt.team_code) AS rights_team_code,

    'NBA_DRAFT_RIGHTS' AS rights_kind,
    CASE
      WHEN roe.player_id IS NOT NULL THEN 'manual_override'
      WHEN dr.player_id IS NOT NULL THEN 'trade_team_details'
      WHEN p.team_id IS NOT NULL THEN 'people'
      ELSE 'people'
    END AS rights_source,

    dr.source_trade_id,
    dr.source_trade_date,
    dr.source_trade_team_detail_id,

    p.draft_year,
    p.draft_round,
    p.draft_pick,
    p.draft_team_id,
    dt.team_code AS draft_team_code,

    false AS has_active_nba_contract,

    (COALESCE(roe.rights_team_code, dr.rights_team_code, pt.team_code, dt.team_code) IS NULL OR COALESCE(roe.rights_team_code, dr.rights_team_code, pt.team_code, dt.team_code) = '') AS needs_review,

    now() AS refreshed_at
  FROM pcms.people p
  LEFT JOIN drlst_receiver dr
    ON dr.player_id = p.person_id
   AND dr.rn = 1
  LEFT JOIN rights_overrides_enriched roe
    ON roe.player_id = p.person_id
  LEFT JOIN pcms.teams pt
    ON pt.team_id = p.team_id
  LEFT JOIN pcms.teams dt
    ON dt.team_id = p.draft_team_id
  WHERE p.league_lk = 'NBA'
    AND p.record_status_lk = 'ACT'
    AND p.player_status_lk = 'CDL';

  -- DLG returning rights (separate kind). Only insert if not already present.
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

SELECT pcms.refresh_player_rights_warehouse();

COMMIT;
