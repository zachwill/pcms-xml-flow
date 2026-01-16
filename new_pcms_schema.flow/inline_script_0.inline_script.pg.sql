-- result_collection=last_statement_all_rows
-- database f/env/postgres

CREATE SCHEMA IF NOT EXISTS pcms;
SET search_path TO pcms;

-- ==========================================
-- Table: pcms_lineage
-- Source: lineage.txt
-- ==========================================
CREATE TABLE IF NOT EXISTS pcms_lineage (
    lineage_id serial PRIMARY KEY,
    drop_filename text NOT NULL, -- e.g., 'nba_pcms_full_extract_player_20260115.zip'
    source_extract_type text,    -- from 'extractType' in XML
    source_extract_version text, -- from 'extractVersion' in XML
    as_of_date timestamptz,      -- from 'asofDate' in XML
    run_date timestamptz,        -- from 'runDate' in XML
    record_count integer,        -- number of records parsed
    source_hash text NOT NULL,   -- SHA-256 hash of the raw source file/blob
    parser_version text,         -- ingestion logic version
    s3_bucket text,
    s3_key text,
    ingested_at timestamptz DEFAULT now(),
    ingestion_status text DEFAULT 'PENDING', -- PENDING, SUCCESS, FAILED
    error_log text,
    
    UNIQUE (source_hash)
);

CREATE INDEX IF NOT EXISTS idx_pcms_lineage_drop_filename ON pcms_lineage(drop_filename);
CREATE INDEX IF NOT EXISTS idx_pcms_lineage_ingested_at ON pcms_lineage(ingested_at);

-- ==========================================
-- Table: pcms_lineage_audit
-- Source: lineage_audit.txt
-- ==========================================
CREATE TABLE IF NOT EXISTS pcms_lineage_audit (
    audit_id bigserial PRIMARY KEY,
    lineage_id integer NOT NULL, -- FK: references pcms_lineage(lineage_id)
    table_name text NOT NULL,    -- target table (e.g., 'contracts')
    source_record_id text NOT NULL, -- natural key from source (e.g., 'playerId')
    record_hash text NOT NULL,   -- SHA-256 hash of source data to detect changes
    parser_version text NOT NULL,
    operation_type text NOT NULL, -- INSERT, UPDATE, IDEMPOTENT_SKIP, FAILED
    source_data_json jsonb,      -- preserved raw state for replay/debugging
    ingested_at timestamptz DEFAULT now(),
    
    UNIQUE (table_name, source_record_id, record_hash, parser_version)
);

CREATE INDEX IF NOT EXISTS idx_pcms_lineage_audit_lineage_id ON pcms_lineage_audit(lineage_id);
CREATE INDEX IF NOT EXISTS idx_pcms_lineage_audit_lookup ON pcms_lineage_audit(table_name, source_record_id);

-- ==========================================
-- Table: audit_logs
-- Source: audit_logs.txt
-- ==========================================
CREATE TABLE IF NOT EXISTS audit_logs (
    audit_log_id bigserial PRIMARY KEY,
    table_name text NOT NULL,     -- table being modified
    record_id text NOT NULL,      -- primary/natural key of modified record
    field_name text,              -- specific column changed
    old_value_text text,
    new_value_text text,
    change_type text NOT NULL,    -- SYSTEM_UPDATE, MANUAL_OVERRIDE, BULK_IMPORT
    reason_code text,             -- CBA_ADJUSTMENT, DATA_CORRECTION
    user_id text,                 -- user or system process ID
    source_drop_file text,        -- provenance: filename
    source_hash text,             -- provenance: hash
    parser_version text,          -- provenance: parser version
    created_at timestamptz DEFAULT now(),
    record_changed_at timestamptz -- recordChangeDate from source
);

CREATE INDEX IF NOT EXISTS idx_audit_logs_record_lookup ON audit_logs(table_name, record_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at ON audit_logs(created_at);
