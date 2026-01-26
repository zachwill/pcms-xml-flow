-- Migration 006: Team Transactions
-- 
-- Source: team_transactions.json (80,130 records)
-- Contains cap hold adjustments, tax adjustments, and other team-level transaction records
--
-- Key fields:
--   team_transaction_type_lk: ADJCH (cap hold adjustment), ADJTM (team adjustment), WADJT (waiver adjustment)
--   cap_hold_adjustment: +1/-1 for cap hold changes
--   cap_adjustment, tax_adjustment, tax_apron_adjustment, mts_adjustment: amount changes

CREATE TABLE IF NOT EXISTS pcms.team_transactions (
  team_transaction_id integer PRIMARY KEY,
  team_id integer,
  team_code text,
  team_transaction_type_lk text,
  team_ledger_seqno integer,
  transaction_date date,
  cap_adjustment bigint,
  cap_hold_adjustment integer,
  tax_adjustment bigint,
  tax_apron_adjustment bigint,
  mts_adjustment bigint,
  protection_count_flg boolean,
  comments text,
  record_status_lk text,
  created_at timestamp with time zone,
  updated_at timestamp with time zone,
  record_changed_at timestamp with time zone,
  ingested_at timestamp with time zone DEFAULT now()
);

-- Indexes for common queries
CREATE INDEX IF NOT EXISTS idx_team_transactions_team_id
  ON pcms.team_transactions (team_id);

CREATE INDEX IF NOT EXISTS idx_team_transactions_team_date
  ON pcms.team_transactions (team_id, transaction_date);

CREATE INDEX IF NOT EXISTS idx_team_transactions_type
  ON pcms.team_transactions (team_transaction_type_lk);

CREATE INDEX IF NOT EXISTS idx_team_transactions_team_code
  ON pcms.team_transactions (team_code);

-- Comment on table
COMMENT ON TABLE pcms.team_transactions IS 'Team-level transactions including cap hold adjustments, tax adjustments, and manual overrides from PCMS';
COMMENT ON COLUMN pcms.team_transactions.team_transaction_type_lk IS 'ADJCH=cap hold adjustment, ADJTM=team adjustment, WADJT=waiver adjustment';
COMMENT ON COLUMN pcms.team_transactions.cap_hold_adjustment IS 'Cap hold change (+1 add, -1 remove)';
