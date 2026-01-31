-- Migration: 010_composite_keys_for_nested_entities.sql
-- Description: Changes primary keys from single-column to composite keys for tables
--              where source IDs are only unique within their parent context.
--
-- Problem: The PCMS XML data has IDs like bonus_id, protection_id, etc. that are
--          sequential within each contract/version, not globally unique. This causes
--          data loss when using them as single-column primary keys.
--
-- Affected tables:
--   - contract_bonuses: bonus_id is unique per (contract_id, version_number)
--   - contract_bonus_criteria: bonus_criteria_id is unique per bonus
--   - contract_bonus_maximums: bonus_max_id is unique per (contract_id, version_number)
--   - contract_protections: protection_id is unique per (contract_id, version_number)
--   - contract_protection_conditions: condition_id is unique per protection
--
-- Date: 2026-01-21

BEGIN;

-- ============================================================================
-- 1. contract_bonuses
--    Old PK: bonus_id
--    New PK: (contract_id, version_number, bonus_id)
-- ============================================================================

-- Drop existing primary key constraint
ALTER TABLE pcms.contract_bonuses
  DROP CONSTRAINT IF EXISTS contract_bonuses_pkey;

-- Add composite primary key
ALTER TABLE pcms.contract_bonuses
  ADD PRIMARY KEY (contract_id, version_number, bonus_id);

-- ============================================================================
-- 2. contract_bonus_criteria
--    Old PK: bonus_criteria_id
--    New PK: (contract_id, version_number, bonus_id, bonus_criteria_id)
--    Need to add contract_id, version_number columns
-- ============================================================================

-- Add missing columns for the composite key
ALTER TABLE pcms.contract_bonus_criteria
  ADD COLUMN IF NOT EXISTS contract_id integer,
  ADD COLUMN IF NOT EXISTS version_number integer;

-- Drop existing primary key constraint
ALTER TABLE pcms.contract_bonus_criteria
  DROP CONSTRAINT IF EXISTS contract_bonus_criteria_pkey;

-- Add composite primary key
ALTER TABLE pcms.contract_bonus_criteria
  ADD PRIMARY KEY (contract_id, version_number, bonus_id, bonus_criteria_id);

-- Add foreign key to contract_bonuses
ALTER TABLE pcms.contract_bonus_criteria
  DROP CONSTRAINT IF EXISTS fk_bonus_criteria_bonus;

ALTER TABLE pcms.contract_bonus_criteria
  ADD CONSTRAINT fk_bonus_criteria_bonus
  FOREIGN KEY (contract_id, version_number, bonus_id)
  REFERENCES pcms.contract_bonuses(contract_id, version_number, bonus_id)
  ON DELETE CASCADE;

-- ============================================================================
-- 3. contract_bonus_maximums
--    Old PK: bonus_max_id
--    New PK: (contract_id, version_number, bonus_max_id)
--    Already has contract_id, version_number columns
-- ============================================================================

-- Drop existing primary key constraint
ALTER TABLE pcms.contract_bonus_maximums
  DROP CONSTRAINT IF EXISTS contract_bonus_maximums_pkey;

-- Add composite primary key
ALTER TABLE pcms.contract_bonus_maximums
  ADD PRIMARY KEY (contract_id, version_number, bonus_max_id);

-- ============================================================================
-- 4. contract_protections
--    Old PK: protection_id
--    New PK: (contract_id, version_number, protection_id)
--    Already has contract_id, version_number columns
-- ============================================================================

-- Drop existing primary key constraint
ALTER TABLE pcms.contract_protections
  DROP CONSTRAINT IF EXISTS contract_protections_pkey;

-- Add composite primary key
ALTER TABLE pcms.contract_protections
  ADD PRIMARY KEY (contract_id, version_number, protection_id);

-- ============================================================================
-- 5. contract_protection_conditions
--    Old PK: condition_id
--    New PK: (contract_id, version_number, protection_id, condition_id)
--    Need to add contract_id, version_number columns
-- ============================================================================

-- Add missing columns for the composite key
ALTER TABLE pcms.contract_protection_conditions
  ADD COLUMN IF NOT EXISTS contract_id integer,
  ADD COLUMN IF NOT EXISTS version_number integer;

-- Drop existing primary key constraint
ALTER TABLE pcms.contract_protection_conditions
  DROP CONSTRAINT IF EXISTS contract_protection_conditions_pkey;

-- Add composite primary key
ALTER TABLE pcms.contract_protection_conditions
  ADD PRIMARY KEY (contract_id, version_number, protection_id, condition_id);

-- Add foreign key to contract_protections
ALTER TABLE pcms.contract_protection_conditions
  DROP CONSTRAINT IF EXISTS fk_protection_conditions_protection;

ALTER TABLE pcms.contract_protection_conditions
  ADD CONSTRAINT fk_protection_conditions_protection
  FOREIGN KEY (contract_id, version_number, protection_id)
  REFERENCES pcms.contract_protections(contract_id, version_number, protection_id)
  ON DELETE CASCADE;

-- ============================================================================
-- Summary of changes:
--
-- | Table                          | Old PK            | New PK                                              |
-- |--------------------------------|-------------------|-----------------------------------------------------|
-- | contract_bonuses               | bonus_id          | (contract_id, version_number, bonus_id)             |
-- | contract_bonus_criteria        | bonus_criteria_id | (contract_id, version_number, bonus_id, bonus_criteria_id) |
-- | contract_bonus_maximums        | bonus_max_id      | (contract_id, version_number, bonus_max_id)         |
-- | contract_protections           | protection_id     | (contract_id, version_number, protection_id)        |
-- | contract_protection_conditions | condition_id      | (contract_id, version_number, protection_id, condition_id) |
--
-- ============================================================================

COMMIT;
