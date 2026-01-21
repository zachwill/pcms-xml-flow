-- Migration: 008_team_tax_summary_unique.sql
-- Description: Adds unique index on team_tax_summary_snapshots(team_id, salary_year) for upserts.
-- Date: 2026-01-18

BEGIN;

-- Remove duplicates first, keeping most recently ingested row
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
