-- Migration: Remove lineage tracking columns
-- 
-- Simplification: Just use ingested_at timestamp for tracking.
-- No need for source_drop_file, source_hash, parser_version on every row.
--
-- Generated: 2026-01-16

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- Drop columns from all tables
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE pcms.agencies 
  DROP COLUMN IF EXISTS source_drop_file,
  DROP COLUMN IF EXISTS source_hash,
  DROP COLUMN IF EXISTS parser_version;

ALTER TABLE pcms.agents 
  DROP COLUMN IF EXISTS source_drop_file,
  DROP COLUMN IF EXISTS source_hash,
  DROP COLUMN IF EXISTS parser_version;

ALTER TABLE pcms.apron_constraints 
  DROP COLUMN IF EXISTS source_drop_file,
  DROP COLUMN IF EXISTS source_hash,
  DROP COLUMN IF EXISTS parser_version;

ALTER TABLE pcms.audit_logs 
  DROP COLUMN IF EXISTS source_drop_file,
  DROP COLUMN IF EXISTS source_hash,
  DROP COLUMN IF EXISTS parser_version;

ALTER TABLE pcms.contract_bonus_criteria 
  DROP COLUMN IF EXISTS source_drop_file,
  DROP COLUMN IF EXISTS source_hash,
  DROP COLUMN IF EXISTS parser_version;

ALTER TABLE pcms.contract_bonus_maximums 
  DROP COLUMN IF EXISTS source_drop_file,
  DROP COLUMN IF EXISTS source_hash,
  DROP COLUMN IF EXISTS parser_version;

ALTER TABLE pcms.contract_bonuses 
  DROP COLUMN IF EXISTS source_drop_file,
  DROP COLUMN IF EXISTS source_hash,
  DROP COLUMN IF EXISTS parser_version;

ALTER TABLE pcms.contract_protection_conditions 
  DROP COLUMN IF EXISTS source_drop_file,
  DROP COLUMN IF EXISTS source_hash,
  DROP COLUMN IF EXISTS parser_version;

ALTER TABLE pcms.contract_protections 
  DROP COLUMN IF EXISTS source_drop_file,
  DROP COLUMN IF EXISTS source_hash,
  DROP COLUMN IF EXISTS parser_version;

ALTER TABLE pcms.contract_versions 
  DROP COLUMN IF EXISTS source_drop_file,
  DROP COLUMN IF EXISTS source_hash,
  DROP COLUMN IF EXISTS parser_version;

ALTER TABLE pcms.contracts 
  DROP COLUMN IF EXISTS source_drop_file,
  DROP COLUMN IF EXISTS source_hash,
  DROP COLUMN IF EXISTS parser_version;

ALTER TABLE pcms.depth_charts 
  DROP COLUMN IF EXISTS source_drop_file,
  DROP COLUMN IF EXISTS source_hash,
  DROP COLUMN IF EXISTS parser_version;

ALTER TABLE pcms.draft_picks 
  DROP COLUMN IF EXISTS source_drop_file,
  DROP COLUMN IF EXISTS source_hash,
  DROP COLUMN IF EXISTS parser_version;

ALTER TABLE pcms.draft_rankings 
  DROP COLUMN IF EXISTS source_drop_file,
  DROP COLUMN IF EXISTS source_hash,
  DROP COLUMN IF EXISTS parser_version;

ALTER TABLE pcms.injury_reports 
  DROP COLUMN IF EXISTS source_drop_file,
  DROP COLUMN IF EXISTS source_hash,
  DROP COLUMN IF EXISTS parser_version;

ALTER TABLE pcms.league_salary_cap_projections 
  DROP COLUMN IF EXISTS source_drop_file,
  DROP COLUMN IF EXISTS source_hash,
  DROP COLUMN IF EXISTS parser_version;

ALTER TABLE pcms.league_salary_scales 
  DROP COLUMN IF EXISTS source_drop_file,
  DROP COLUMN IF EXISTS source_hash,
  DROP COLUMN IF EXISTS parser_version;

ALTER TABLE pcms.league_system_values 
  DROP COLUMN IF EXISTS source_drop_file,
  DROP COLUMN IF EXISTS source_hash,
  DROP COLUMN IF EXISTS parser_version;

ALTER TABLE pcms.league_tax_rates 
  DROP COLUMN IF EXISTS source_drop_file,
  DROP COLUMN IF EXISTS source_hash,
  DROP COLUMN IF EXISTS parser_version;

ALTER TABLE pcms.ledger_entries 
  DROP COLUMN IF EXISTS source_drop_file,
  DROP COLUMN IF EXISTS source_hash,
  DROP COLUMN IF EXISTS parser_version;

ALTER TABLE pcms.lk_subject_to_apron_reasons 
  DROP COLUMN IF EXISTS source_drop_file,
  DROP COLUMN IF EXISTS source_hash,
  DROP COLUMN IF EXISTS parser_version;

ALTER TABLE pcms.lookups 
  DROP COLUMN IF EXISTS source_drop_file,
  DROP COLUMN IF EXISTS source_hash,
  DROP COLUMN IF EXISTS parser_version;

ALTER TABLE pcms.medical_intel 
  DROP COLUMN IF EXISTS source_drop_file,
  DROP COLUMN IF EXISTS source_hash,
  DROP COLUMN IF EXISTS parser_version;

ALTER TABLE pcms.non_contract_amounts 
  DROP COLUMN IF EXISTS source_drop_file,
  DROP COLUMN IF EXISTS source_hash,
  DROP COLUMN IF EXISTS parser_version;

ALTER TABLE pcms.payment_schedule_details 
  DROP COLUMN IF EXISTS source_drop_file,
  DROP COLUMN IF EXISTS source_hash,
  DROP COLUMN IF EXISTS parser_version;

ALTER TABLE pcms.payment_schedules 
  DROP COLUMN IF EXISTS source_drop_file,
  DROP COLUMN IF EXISTS source_hash,
  DROP COLUMN IF EXISTS parser_version;

ALTER TABLE pcms.people 
  DROP COLUMN IF EXISTS source_drop_file,
  DROP COLUMN IF EXISTS source_hash,
  DROP COLUMN IF EXISTS parser_version;

ALTER TABLE pcms.rookie_scale_amounts 
  DROP COLUMN IF EXISTS source_drop_file,
  DROP COLUMN IF EXISTS source_hash,
  DROP COLUMN IF EXISTS parser_version;

ALTER TABLE pcms.salaries 
  DROP COLUMN IF EXISTS source_drop_file,
  DROP COLUMN IF EXISTS source_hash,
  DROP COLUMN IF EXISTS parser_version;

ALTER TABLE pcms.scouting_reports 
  DROP COLUMN IF EXISTS source_drop_file,
  DROP COLUMN IF EXISTS source_hash,
  DROP COLUMN IF EXISTS parser_version;

ALTER TABLE pcms.synergy_instat_links 
  DROP COLUMN IF EXISTS source_drop_file,
  DROP COLUMN IF EXISTS source_hash,
  DROP COLUMN IF EXISTS parser_version;

ALTER TABLE pcms.tax_team_status 
  DROP COLUMN IF EXISTS source_drop_file,
  DROP COLUMN IF EXISTS source_hash,
  DROP COLUMN IF EXISTS parser_version;

ALTER TABLE pcms.team_budget_snapshots 
  DROP COLUMN IF EXISTS source_drop_file,
  DROP COLUMN IF EXISTS source_hash,
  DROP COLUMN IF EXISTS parser_version;

ALTER TABLE pcms.team_exception_usage 
  DROP COLUMN IF EXISTS source_drop_file,
  DROP COLUMN IF EXISTS source_hash,
  DROP COLUMN IF EXISTS parser_version;

ALTER TABLE pcms.team_exceptions 
  DROP COLUMN IF EXISTS source_drop_file,
  DROP COLUMN IF EXISTS source_hash,
  DROP COLUMN IF EXISTS parser_version;

ALTER TABLE pcms.team_tax_summary_snapshots 
  DROP COLUMN IF EXISTS source_drop_file,
  DROP COLUMN IF EXISTS source_hash,
  DROP COLUMN IF EXISTS parser_version;

ALTER TABLE pcms.team_two_way_capacity 
  DROP COLUMN IF EXISTS source_drop_file,
  DROP COLUMN IF EXISTS source_hash,
  DROP COLUMN IF EXISTS parser_version;

ALTER TABLE pcms.teams 
  DROP COLUMN IF EXISTS source_drop_file,
  DROP COLUMN IF EXISTS source_hash,
  DROP COLUMN IF EXISTS parser_version;

ALTER TABLE pcms.trades 
  DROP COLUMN IF EXISTS source_drop_file,
  DROP COLUMN IF EXISTS source_hash,
  DROP COLUMN IF EXISTS parser_version;

ALTER TABLE pcms.transaction_waiver_amounts 
  DROP COLUMN IF EXISTS source_drop_file,
  DROP COLUMN IF EXISTS source_hash,
  DROP COLUMN IF EXISTS parser_version;

ALTER TABLE pcms.transactions 
  DROP COLUMN IF EXISTS source_drop_file,
  DROP COLUMN IF EXISTS source_hash,
  DROP COLUMN IF EXISTS parser_version;

ALTER TABLE pcms.two_way_contract_utility 
  DROP COLUMN IF EXISTS source_drop_file,
  DROP COLUMN IF EXISTS source_hash,
  DROP COLUMN IF EXISTS parser_version;

ALTER TABLE pcms.two_way_daily_statuses 
  DROP COLUMN IF EXISTS source_drop_file,
  DROP COLUMN IF EXISTS source_hash,
  DROP COLUMN IF EXISTS parser_version;

ALTER TABLE pcms.two_way_game_utility 
  DROP COLUMN IF EXISTS source_drop_file,
  DROP COLUMN IF EXISTS source_hash,
  DROP COLUMN IF EXISTS parser_version;

ALTER TABLE pcms.waiver_priority 
  DROP COLUMN IF EXISTS source_drop_file,
  DROP COLUMN IF EXISTS source_hash,
  DROP COLUMN IF EXISTS parser_version;

ALTER TABLE pcms.waiver_priority_ranks 
  DROP COLUMN IF EXISTS source_drop_file,
  DROP COLUMN IF EXISTS source_hash,
  DROP COLUMN IF EXISTS parser_version;

-- ─────────────────────────────────────────────────────────────────────────────
-- Simplify pcms_lineage table (keep it but simpler)
-- ─────────────────────────────────────────────────────────────────────────────

-- Keep: lineage_id, s3_key, record_count, ingested_at, ingestion_status, error_log
-- Drop: source_hash, parser_version (redundant tracking)

ALTER TABLE pcms.pcms_lineage
  DROP COLUMN IF EXISTS source_hash,
  DROP COLUMN IF EXISTS parser_version,
  DROP COLUMN IF EXISTS source_extract_type,
  DROP COLUMN IF EXISTS source_extract_version,
  DROP COLUMN IF EXISTS as_of_date,
  DROP COLUMN IF EXISTS run_date;

-- ─────────────────────────────────────────────────────────────────────────────
-- Drop pcms_lineage_audit (not needed with simplified approach)
-- ─────────────────────────────────────────────────────────────────────────────

DROP TABLE IF EXISTS pcms.pcms_lineage_audit;

COMMIT;

-- ─────────────────────────────────────────────────────────────────────────────
-- Summary
-- ─────────────────────────────────────────────────────────────────────────────
-- 
-- Removed from 47 tables:
--   - source_drop_file
--   - source_hash  
--   - parser_version
--
-- Simplified pcms_lineage to just track:
--   - lineage_id (PK)
--   - drop_filename
--   - s3_bucket
--   - s3_key
--   - record_count
--   - ingested_at
--   - ingestion_status
--   - error_log
--
-- Dropped pcms_lineage_audit table entirely.
--
-- Tracking is now simple: use ingested_at timestamp on each row.
