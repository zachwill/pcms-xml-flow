-- Migration: 005_add_unique_indexes_for_upserts.sql
-- Description: Adds missing unique indexes needed by ON CONFLICT upserts in import scripts.
-- Date: 2026-01-17

BEGIN;

-- ----------------------------------------------------------------------------
-- team_tax_summary_snapshots
--
-- The import script upserts by (team_id, salary_year). Earlier schemas used a
-- different uniqueness strategy (e.g. source_hash-based). After removing lineage
-- columns, that uniqueness can disappear, causing:
--   "there is no unique or exclusion constraint matching the ON CONFLICT specification"
--
-- We enforce one row per team+year. If duplicates exist already, keep the most
-- recently ingested/updated row.
-- ----------------------------------------------------------------------------

WITH ranked AS (
  SELECT
    ctid,
    row_number() OVER (
      PARTITION BY team_id, salary_year
      ORDER BY ingested_at DESC NULLS LAST,
               updated_at DESC NULLS LAST,
               created_at DESC NULLS LAST,
               ctid DESC
    ) AS rn
  FROM pcms.team_tax_summary_snapshots
)
DELETE FROM pcms.team_tax_summary_snapshots t
USING ranked r
WHERE t.ctid = r.ctid
  AND r.rn > 1;

CREATE UNIQUE INDEX IF NOT EXISTS ux_team_tax_summary_snapshots_team_year
  ON pcms.team_tax_summary_snapshots(team_id, salary_year);

COMMIT;
