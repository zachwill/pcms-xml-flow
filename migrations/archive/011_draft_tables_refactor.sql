-- Migration: Refactor draft pick tables
-- 
-- Changes:
-- 1. Drop draft_picks (was DLG/WNBA only, not useful)
-- 2. Drop draft_pick_ownership (was empty)
-- 3. Create draft_selections (NBA draft events from transactions)
-- 4. Create draft_pick_trades (pick ownership changes from trade_team_details)
-- 
-- Keeps: draft_pick_summaries (human-readable snapshots)

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- Drop old tables
-- ─────────────────────────────────────────────────────────────────────────────

DROP TABLE IF EXISTS pcms.draft_picks CASCADE;
DROP TABLE IF EXISTS pcms.draft_pick_ownership CASCADE;

-- ─────────────────────────────────────────────────────────────────────────────
-- Create draft_selections
-- Records when players are drafted (from transactions where type = 'DRAFT')
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE pcms.draft_selections (
    transaction_id integer PRIMARY KEY,
    draft_year integer NOT NULL,
    draft_round integer NOT NULL,
    pick_number integer NOT NULL,
    player_id integer NOT NULL,
    drafting_team_id integer NOT NULL,
    drafting_team_code text,
    draft_amount bigint,
    transaction_date date,
    created_at timestamptz,
    updated_at timestamptz,
    record_changed_at timestamptz,
    ingested_at timestamptz DEFAULT now()
);

-- Indexes for common queries
CREATE INDEX idx_draft_selections_year ON pcms.draft_selections (draft_year);
CREATE INDEX idx_draft_selections_player ON pcms.draft_selections (player_id);
CREATE INDEX idx_draft_selections_team ON pcms.draft_selections (drafting_team_id);
CREATE UNIQUE INDEX idx_draft_selections_natural_key 
    ON pcms.draft_selections (draft_year, draft_round, pick_number);

COMMENT ON TABLE pcms.draft_selections IS 'NBA draft selections extracted from transactions';
COMMENT ON COLUMN pcms.draft_selections.transaction_id IS 'FK to transactions table';
COMMENT ON COLUMN pcms.draft_selections.draft_amount IS 'Rookie scale salary amount';

-- ─────────────────────────────────────────────────────────────────────────────
-- Create draft_pick_trades
-- Records when draft picks change hands via trades
-- Extracted from trade_team_details where trade_entry_lk = 'DRPCK'
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE pcms.draft_pick_trades (
    id serial PRIMARY KEY,
    trade_id integer NOT NULL,
    trade_date date NOT NULL,
    draft_year integer NOT NULL,
    draft_round integer NOT NULL,
    
    -- Who is involved
    from_team_id integer NOT NULL,
    from_team_code text,
    to_team_id integer NOT NULL,
    to_team_code text,
    original_team_id integer,  -- whose pick slot this originally was
    original_team_code text,
    
    -- Pick characteristics
    is_swap boolean DEFAULT false,
    is_future boolean DEFAULT false,
    is_conditional boolean DEFAULT false,
    conditional_type_lk text,  -- YES, NO, RANGE, C2ND, CCASH
    is_draft_year_plus_two boolean DEFAULT false,
    
    ingested_at timestamptz DEFAULT now(),
    
    CONSTRAINT fk_draft_pick_trades_trade 
        FOREIGN KEY (trade_id) REFERENCES pcms.trades(trade_id)
);

-- Indexes for common queries
CREATE INDEX idx_draft_pick_trades_trade ON pcms.draft_pick_trades (trade_id);
CREATE INDEX idx_draft_pick_trades_year ON pcms.draft_pick_trades (draft_year);
CREATE INDEX idx_draft_pick_trades_from_team ON pcms.draft_pick_trades (from_team_id);
CREATE INDEX idx_draft_pick_trades_to_team ON pcms.draft_pick_trades (to_team_id);

COMMENT ON TABLE pcms.draft_pick_trades IS 'Draft pick ownership changes via trades';
COMMENT ON COLUMN pcms.draft_pick_trades.is_swap IS 'Swap rights (teams exchange picks based on standings)';
COMMENT ON COLUMN pcms.draft_pick_trades.is_future IS 'Future pick (year not yet determined)';
COMMENT ON COLUMN pcms.draft_pick_trades.conditional_type_lk IS 'YES=conditional, NO=unconditional, RANGE=pick range protected, C2ND=converts to 2nd, CCASH=converts to cash';

COMMIT;
