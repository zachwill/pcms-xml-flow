-- 035_player_rights_warehouse.sql
-- Draft rights / returning rights tool-facing warehouse

BEGIN;

CREATE TABLE IF NOT EXISTS pcms.player_rights_warehouse (
  player_id integer PRIMARY KEY,
  player_name text,
  league_lk text,

  rights_team_id integer,
  rights_team_code text,
  rights_kind text NOT NULL, -- NBA_DRAFT_RIGHTS | DLG_RETURNING_RIGHTS
  rights_source text NOT NULL, -- trade_team_details | people

  -- provenance
  source_trade_id integer,
  source_trade_date date,
  source_trade_team_detail_id text,

  draft_year integer,
  draft_round integer,
  draft_pick integer,
  draft_team_id integer,
  draft_team_code text,

  has_active_nba_contract boolean,
  needs_review boolean DEFAULT false,

  refreshed_at timestamp with time zone NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_player_rights_warehouse_rights_team_code
  ON pcms.player_rights_warehouse(rights_team_code);

CREATE INDEX IF NOT EXISTS idx_player_rights_warehouse_rights_kind
  ON pcms.player_rights_warehouse(rights_kind);

CREATE OR REPLACE FUNCTION pcms.refresh_player_rights_warehouse()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  TRUNCATE TABLE pcms.player_rights_warehouse;

  -- Latest DRLST sending team per player. DRLST rows appear twice per trade (sent/received).
  -- Empirically (and per your Díez example), the controlling NBA rights holder corresponds
  -- to the *sending* team row (is_sent=true) in PCMS trade details.
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

    COALESCE(da.rights_team_id, p.draft_team_id) AS rights_team_id,
    COALESCE(da.rights_team_code, dt.team_code) AS rights_team_code,

    'NBA_DRAFT_RIGHTS' AS rights_kind,
    CASE WHEN da.player_id IS NOT NULL THEN 'trade_team_details' ELSE 'people' END AS rights_source,

    da.source_trade_id,
    da.source_trade_date,
    da.source_trade_team_detail_id,

    p.draft_year,
    p.draft_round,
    p.draft_pick,
    p.draft_team_id,
    dt.team_code AS draft_team_code,

    (nc.player_id IS NOT NULL) AS has_active_nba_contract,

    -- Needs review if we can't resolve a rights team code.
    (COALESCE(da.rights_team_code, dt.team_code) IS NULL OR COALESCE(da.rights_team_code, dt.team_code) = '') AS needs_review,

    now() AS refreshed_at
  FROM pcms.people p
  LEFT JOIN drlst_sender da
    ON da.player_id = p.person_id
   AND da.rn = 1
  LEFT JOIN pcms.teams dt
    ON dt.team_id = p.draft_team_id
  LEFT JOIN nba_contracts nc
    ON nc.player_id = p.person_id
  WHERE p.league_lk = 'NBA'
    AND p.draft_year IS NOT NULL
    -- rights-only-ish heuristic: exclude anyone with an NBA contract row
    AND nc.player_id IS NULL;

  -- Add DLG returning rights (separate kind). Keep NBA and DLG rows distinct by picking
  -- NBA draft rights as primary grain (player_id) and only inserting DLG if no NBA row exists.
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
