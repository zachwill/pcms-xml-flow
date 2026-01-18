-- Migration: 007_add_missing_unique_indexes.sql
-- Description: Adds missing unique indexes for ON CONFLICT upserts in import scripts.
-- Date: 2026-01-18

BEGIN;

-- ----------------------------------------------------------------------------
-- tax_team_status
--
-- The import script upserts by (team_id, salary_year). Need unique constraint.
-- Clean up duplicates first, keeping most recently ingested row.
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
  FROM pcms.tax_team_status
)
DELETE FROM pcms.tax_team_status t
USING ranked r
WHERE t.ctid = r.ctid
  AND r.rn > 1;

CREATE UNIQUE INDEX IF NOT EXISTS ux_tax_team_status_team_year
  ON pcms.tax_team_status(team_id, salary_year);

-- ----------------------------------------------------------------------------
-- salaries
--
-- The import script upserts by (contract_id, version_number, salary_year).
-- Clean up duplicates first.
-- ----------------------------------------------------------------------------

WITH ranked AS (
  SELECT
    ctid,
    row_number() OVER (
      PARTITION BY contract_id, version_number, salary_year
      ORDER BY ingested_at DESC NULLS LAST,
               updated_at DESC NULLS LAST,
               created_at DESC NULLS LAST,
               ctid DESC
    ) AS rn
  FROM pcms.salaries
)
DELETE FROM pcms.salaries t
USING ranked r
WHERE t.ctid = r.ctid
  AND r.rn > 1;

CREATE UNIQUE INDEX IF NOT EXISTS ux_salaries_contract_version_year
  ON pcms.salaries(contract_id, version_number, salary_year);

-- ----------------------------------------------------------------------------
-- contract_versions
--
-- The import script upserts by (contract_id, version_number).
-- Clean up duplicates first.
-- ----------------------------------------------------------------------------

WITH ranked AS (
  SELECT
    ctid,
    row_number() OVER (
      PARTITION BY contract_id, version_number
      ORDER BY ingested_at DESC NULLS LAST,
               updated_at DESC NULLS LAST,
               created_at DESC NULLS LAST,
               ctid DESC
    ) AS rn
  FROM pcms.contract_versions
)
DELETE FROM pcms.contract_versions t
USING ranked r
WHERE t.ctid = r.ctid
  AND r.rn > 1;

CREATE UNIQUE INDEX IF NOT EXISTS ux_contract_versions_contract_version
  ON pcms.contract_versions(contract_id, version_number);

-- ----------------------------------------------------------------------------
-- team_budget_snapshots
--
-- The import script upserts by a 7-column composite key. This is complex.
-- Instead of adding a 7-column unique index (which may have NULL issues),
-- we'll not add a constraint and rely on the script's deduplication.
-- The serial PK allows plain INSERT without upsert.
-- ----------------------------------------------------------------------------

-- No constraint added for team_budget_snapshots; script handles deduplication.

COMMIT;
