-- 085_player_rights_overrides_table.sql
--
-- Replace hardcoded player-rights override CTE with a durable curated table.
--
-- Why:
-- - Manual overrides need to be auditable and editable without changing SQL function code.
-- - Keep provenance (reason + source note/endnote + timestamps).

BEGIN;

CREATE TABLE IF NOT EXISTS pcms.player_rights_overrides (
  player_id integer PRIMARY KEY,
  rights_team_code text NOT NULL,
  reason text NOT NULL,
  source_note text,
  source_endnote_id integer,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT player_rights_overrides_player_fk
    FOREIGN KEY (player_id) REFERENCES pcms.people(person_id) ON DELETE CASCADE,
  CONSTRAINT player_rights_overrides_endnote_fk
    FOREIGN KEY (source_endnote_id) REFERENCES pcms.endnotes(endnote_id),
  CONSTRAINT player_rights_overrides_team_code_chk
    CHECK (rights_team_code ~ '^[A-Z]{3}$'),
  CONSTRAINT player_rights_overrides_reason_chk
    CHECK (NULLIF(BTRIM(reason), '') IS NOT NULL)
);

COMMENT ON TABLE pcms.player_rights_overrides IS
  'Curated overrides for pcms.player_rights_warehouse ownership when transaction-derived direction conflicts with business output.';

COMMENT ON COLUMN pcms.player_rights_overrides.reason IS
  'Human-readable reason for override.';

COMMENT ON COLUMN pcms.player_rights_overrides.source_note IS
  'Optional provenance note/doc link for the override decision.';

COMMENT ON COLUMN pcms.player_rights_overrides.source_endnote_id IS
  'Optional link to pcms.endnotes evidence.';

CREATE INDEX IF NOT EXISTS idx_player_rights_overrides_is_active
  ON pcms.player_rights_overrides (is_active);

CREATE INDEX IF NOT EXISTS idx_player_rights_overrides_rights_team_code
  ON pcms.player_rights_overrides (rights_team_code);

CREATE OR REPLACE FUNCTION pcms.player_rights_overrides_set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_player_rights_overrides_set_updated_at ON pcms.player_rights_overrides;

CREATE TRIGGER trg_player_rights_overrides_set_updated_at
BEFORE UPDATE ON pcms.player_rights_overrides
FOR EACH ROW
EXECUTE FUNCTION pcms.player_rights_overrides_set_updated_at();

-- Seed existing curated override.
INSERT INTO pcms.player_rights_overrides (
  player_id,
  rights_team_code,
  reason,
  source_note,
  source_endnote_id,
  is_active
)
VALUES (
  1626229,
  'NYK',
  'Curated override: rights ownership expected NYK despite latest transaction direction.',
  'reference/warehouse/specs/2026-02-17-player-rights-handoff.md',
  NULL,
  true
)
ON CONFLICT (player_id) DO UPDATE
SET rights_team_code = EXCLUDED.rights_team_code,
    reason = EXCLUDED.reason,
    source_note = EXCLUDED.source_note,
    source_endnote_id = EXCLUDED.source_endnote_id,
    is_active = EXCLUDED.is_active,
    updated_at = now();

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
  rights_overrides_enriched AS (
    SELECT
      pro.player_id,
      pro.rights_team_code,
      t.team_id AS rights_team_id
    FROM pcms.player_rights_overrides pro
    LEFT JOIN pcms.teams t
      ON t.team_code = pro.rights_team_code
    WHERE pro.is_active = true
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

    (
      COALESCE(roe.rights_team_code, dr.rights_team_code, pt.team_code, dt.team_code) IS NULL
      OR COALESCE(roe.rights_team_code, dr.rights_team_code, pt.team_code, dt.team_code) = ''
      OR (roe.player_id IS NOT NULL AND roe.rights_team_id IS NULL)
    ) AS needs_review,

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
