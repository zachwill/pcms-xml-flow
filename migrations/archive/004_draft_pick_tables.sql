-- Migration: 004_draft_pick_tables.sql
-- Description: Create draft_pick_summaries (raw PCMS data) and draft_pick_ownership (enriched/parsed) tables
-- Date: 2026-01-16
--
-- See DRAFT_PICKS.md for full documentation on the data format and endnote reference system.

BEGIN;

-- =============================================================================
-- Table 1: draft_pick_summaries (Raw PCMS Data)
-- =============================================================================
-- Stores the raw PCMS draft pick summary extract as-is.
-- The first_round and second_round fields contain human-readable descriptions
-- with embedded endnote references like "To SAS(58)" or "Has HOU(81) (via LAC(78))".
--
-- These endnote numbers are internal PCMS references - the lookup table is NOT
-- included in the extract, so they serve as opaque correlation markers.

CREATE TABLE IF NOT EXISTS pcms.draft_pick_summaries (
  draft_year integer NOT NULL,
  team_id integer NOT NULL,
  team_code text,                        -- Denormalized from pcms.teams for convenience
  first_round text,                      -- Raw description with endnote refs (e.g., "Own | Has DAL(70)")
  second_round text,                     -- Raw description with endnote refs
  is_active boolean,
  created_at timestamptz,
  updated_at timestamptz,
  record_changed_at timestamptz,
  ingested_at timestamptz DEFAULT now(),
  PRIMARY KEY (draft_year, team_id)
);

COMMENT ON TABLE pcms.draft_pick_summaries IS 'Per-team-per-year NBA draft pick ownership summaries from PCMS (raw data)';
COMMENT ON COLUMN pcms.draft_pick_summaries.first_round IS 'Description of 1st round pick status. Patterns: "Own", "To TEAM(N)", "Has TEAM(N)", "May have TEAM(N)", "(via TEAM(N))"';
COMMENT ON COLUMN pcms.draft_pick_summaries.second_round IS 'Description of 2nd round pick status. Same patterns as first_round.';
COMMENT ON COLUMN pcms.draft_pick_summaries.team_code IS 'Denormalized team code (e.g., ATL, BOS) for easier querying';

CREATE INDEX IF NOT EXISTS idx_draft_pick_summaries_team_code ON pcms.draft_pick_summaries(team_code);
CREATE INDEX IF NOT EXISTS idx_draft_pick_summaries_draft_year ON pcms.draft_pick_summaries(draft_year);

-- =============================================================================
-- Table 2: draft_pick_ownership (Enriched/Parsed Data)
-- =============================================================================
-- Normalized table for structured queries on pick ownership.
-- Can be populated by:
--   1. Parsing the summary text programmatically
--   2. Manual curation/verification
--   3. External data sources (RealGM, Spotrac, etc.)
--
-- This table represents ONE pick per row (original_team + year + round),
-- with current ownership status and provenance chain.

CREATE TABLE IF NOT EXISTS pcms.draft_pick_ownership (
  id serial PRIMARY KEY,
  draft_year integer NOT NULL,
  round integer NOT NULL,                -- 1 or 2
  
  -- Original pick ownership
  original_team_id integer NOT NULL,     -- Team whose pick this originally was
  original_team_code text,
  
  -- Current ownership
  current_team_id integer,               -- Team that currently owns/controls it
  current_team_code text,
  ownership_status text NOT NULL,        -- 'owns', 'traded', 'conditional', 'swap_rights'
  
  -- Trade destination (if traded away)
  destination_team_id integer,           -- If traded, who owns it now
  destination_team_code text,
  
  -- Conditions and protections
  is_conditional boolean DEFAULT false,
  condition_description text,            -- Human-readable condition (e.g., "if pick falls outside top 10")
  protection_description text,           -- e.g., "top-10 protected", "top-3 protected in 2027"
  
  -- Swap rights
  swap_rights_team_id integer,           -- Team with swap rights on this pick (if any)
  swap_rights_team_code text,
  
  -- Provenance tracking
  provenance_chain jsonb,                -- Array of {team_code, endnote_ref} showing trade path
  endnote_refs integer[],                -- All PCMS endnote references involved
  
  -- Metadata
  source text DEFAULT 'parsed',          -- 'parsed', 'manual', 'external'
  confidence text DEFAULT 'high',        -- 'high', 'medium', 'low' for parsed data
  notes text,
  
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  
  UNIQUE (draft_year, round, original_team_id)
);

COMMENT ON TABLE pcms.draft_pick_ownership IS 'Normalized draft pick ownership data - parsed from summaries or manually curated';
COMMENT ON COLUMN pcms.draft_pick_ownership.ownership_status IS 'Current status: owns (team has their pick), traded (pick sent away), conditional (depends on outcome), swap_rights (another team can swap)';
COMMENT ON COLUMN pcms.draft_pick_ownership.provenance_chain IS 'JSON array showing how pick moved, e.g., [{"team":"DET","ref":10},{"team":"OKC","ref":19},{"team":"UTA","ref":30}]';
COMMENT ON COLUMN pcms.draft_pick_ownership.endnote_refs IS 'PCMS internal reference IDs from the summary text - opaque but useful for correlation';
COMMENT ON COLUMN pcms.draft_pick_ownership.source IS 'How this row was created: parsed (from summaries), manual (human entered), external (other data source)';
COMMENT ON COLUMN pcms.draft_pick_ownership.confidence IS 'For parsed data: high (simple case), medium (some ambiguity), low (complex/needs review)';

CREATE INDEX IF NOT EXISTS idx_draft_pick_ownership_year ON pcms.draft_pick_ownership(draft_year);
CREATE INDEX IF NOT EXISTS idx_draft_pick_ownership_round ON pcms.draft_pick_ownership(round);
CREATE INDEX IF NOT EXISTS idx_draft_pick_ownership_original_team ON pcms.draft_pick_ownership(original_team_id);
CREATE INDEX IF NOT EXISTS idx_draft_pick_ownership_current_team ON pcms.draft_pick_ownership(current_team_id);
CREATE INDEX IF NOT EXISTS idx_draft_pick_ownership_destination_team ON pcms.draft_pick_ownership(destination_team_id);
CREATE INDEX IF NOT EXISTS idx_draft_pick_ownership_status ON pcms.draft_pick_ownership(ownership_status);
CREATE INDEX IF NOT EXISTS idx_draft_pick_ownership_conditional ON pcms.draft_pick_ownership(is_conditional) WHERE is_conditional = true;
CREATE INDEX IF NOT EXISTS idx_draft_pick_ownership_endnote_refs ON pcms.draft_pick_ownership USING gin(endnote_refs);

-- =============================================================================
-- Backfill team_code for any existing data
-- =============================================================================

UPDATE pcms.draft_pick_summaries dps 
SET team_code = t.team_code
FROM pcms.teams t 
WHERE dps.team_id = t.team_id 
  AND dps.team_code IS NULL;

COMMIT;
