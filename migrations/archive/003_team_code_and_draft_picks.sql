-- Migration: 003_team_code_and_draft_picks.sql
-- Description: Rename team_name_short to team_code, add team_code to ALL tables
--              with team_id references, and add player_id to draft_picks
-- Date: 2026-01-16

BEGIN;

-- =============================================================================
-- 1. Rename team_name_short to team_code in pcms.teams
-- =============================================================================

ALTER TABLE pcms.teams RENAME COLUMN team_name_short TO team_code;

-- =============================================================================
-- 2. CONTRACTS
-- =============================================================================
-- Has: signing_team_id, sign_and_trade_to_team_id

ALTER TABLE pcms.contracts ADD COLUMN IF NOT EXISTS team_code text;
ALTER TABLE pcms.contracts ADD COLUMN IF NOT EXISTS sign_and_trade_to_team_code text;

CREATE INDEX IF NOT EXISTS idx_contracts_team_code ON pcms.contracts(team_code);

UPDATE pcms.contracts c SET team_code = t.team_code
FROM pcms.teams t WHERE c.signing_team_id = t.team_id AND c.team_code IS NULL;

UPDATE pcms.contracts c SET sign_and_trade_to_team_code = t.team_code
FROM pcms.teams t WHERE c.sign_and_trade_to_team_id = t.team_id AND c.sign_and_trade_to_team_code IS NULL;

-- =============================================================================
-- 3. TRANSACTIONS
-- =============================================================================
-- Has: from_team_id, to_team_id, rights_team_id, sign_and_trade_team_id

ALTER TABLE pcms.transactions ADD COLUMN IF NOT EXISTS from_team_code text;
ALTER TABLE pcms.transactions ADD COLUMN IF NOT EXISTS to_team_code text;
ALTER TABLE pcms.transactions ADD COLUMN IF NOT EXISTS rights_team_code text;
ALTER TABLE pcms.transactions ADD COLUMN IF NOT EXISTS sign_and_trade_team_code text;

CREATE INDEX IF NOT EXISTS idx_transactions_from_team_code ON pcms.transactions(from_team_code);
CREATE INDEX IF NOT EXISTS idx_transactions_to_team_code ON pcms.transactions(to_team_code);

UPDATE pcms.transactions tx SET from_team_code = t.team_code
FROM pcms.teams t WHERE tx.from_team_id = t.team_id AND tx.from_team_code IS NULL;

UPDATE pcms.transactions tx SET to_team_code = t.team_code
FROM pcms.teams t WHERE tx.to_team_id = t.team_id AND tx.to_team_code IS NULL;

UPDATE pcms.transactions tx SET rights_team_code = t.team_code
FROM pcms.teams t WHERE tx.rights_team_id = t.team_id AND tx.rights_team_code IS NULL;

UPDATE pcms.transactions tx SET sign_and_trade_team_code = t.team_code
FROM pcms.teams t WHERE tx.sign_and_trade_team_id = t.team_id AND tx.sign_and_trade_team_code IS NULL;

-- =============================================================================
-- 4. LEDGER_ENTRIES
-- =============================================================================
-- Has: team_id

ALTER TABLE pcms.ledger_entries ADD COLUMN IF NOT EXISTS team_code text;

CREATE INDEX IF NOT EXISTS idx_ledger_entries_team_code ON pcms.ledger_entries(team_code);

UPDATE pcms.ledger_entries le SET team_code = t.team_code
FROM pcms.teams t WHERE le.team_id = t.team_id AND le.team_code IS NULL;

-- =============================================================================
-- 5. DRAFT_PICKS
-- =============================================================================
-- Has: original_team_id, current_team_id
-- Adding: player_id for linking picks to players

ALTER TABLE pcms.draft_picks ADD COLUMN IF NOT EXISTS player_id integer;
ALTER TABLE pcms.draft_picks ADD COLUMN IF NOT EXISTS original_team_code text;
ALTER TABLE pcms.draft_picks ADD COLUMN IF NOT EXISTS current_team_code text;

CREATE INDEX IF NOT EXISTS idx_draft_picks_player_id ON pcms.draft_picks(player_id);
CREATE INDEX IF NOT EXISTS idx_draft_picks_original_team_code ON pcms.draft_picks(original_team_code);
CREATE INDEX IF NOT EXISTS idx_draft_picks_current_team_code ON pcms.draft_picks(current_team_code);

UPDATE pcms.draft_picks dp SET original_team_code = t.team_code
FROM pcms.teams t WHERE dp.original_team_id = t.team_id AND dp.original_team_code IS NULL;

UPDATE pcms.draft_picks dp SET current_team_code = t.team_code
FROM pcms.teams t WHERE dp.current_team_id = t.team_id AND dp.current_team_code IS NULL;

-- Unique constraint for completed draft picks (prevents duplicates when generating NBA picks)
DO $$
BEGIN
  ALTER TABLE pcms.draft_picks 
    ADD CONSTRAINT uq_draft_picks_completed 
    UNIQUE (draft_year, round, pick_number_int, league_lk);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- =============================================================================
-- 6. DEPTH_CHARTS
-- =============================================================================
-- Has: team_id (part of PK)

ALTER TABLE pcms.depth_charts ADD COLUMN IF NOT EXISTS team_code text;

UPDATE pcms.depth_charts dc SET team_code = t.team_code
FROM pcms.teams t WHERE dc.team_id = t.team_id AND dc.team_code IS NULL;

-- =============================================================================
-- 7. NON_CONTRACT_AMOUNTS
-- =============================================================================
-- Has: team_id

ALTER TABLE pcms.non_contract_amounts ADD COLUMN IF NOT EXISTS team_code text;

CREATE INDEX IF NOT EXISTS idx_non_contract_amounts_team_code ON pcms.non_contract_amounts(team_code);

UPDATE pcms.non_contract_amounts nca SET team_code = t.team_code
FROM pcms.teams t WHERE nca.team_id = t.team_id AND nca.team_code IS NULL;

-- =============================================================================
-- 8. PEOPLE
-- =============================================================================
-- Has: team_id, draft_team_id, dlg_returning_rights_team_id, dlg_team_id

ALTER TABLE pcms.people ADD COLUMN IF NOT EXISTS team_code text;
ALTER TABLE pcms.people ADD COLUMN IF NOT EXISTS draft_team_code text;
ALTER TABLE pcms.people ADD COLUMN IF NOT EXISTS dlg_returning_rights_team_code text;
ALTER TABLE pcms.people ADD COLUMN IF NOT EXISTS dlg_team_code text;

CREATE INDEX IF NOT EXISTS idx_people_team_code ON pcms.people(team_code);
CREATE INDEX IF NOT EXISTS idx_people_draft_team_code ON pcms.people(draft_team_code);

UPDATE pcms.people p SET team_code = t.team_code
FROM pcms.teams t WHERE p.team_id = t.team_id AND p.team_code IS NULL;

UPDATE pcms.people p SET draft_team_code = t.team_code
FROM pcms.teams t WHERE p.draft_team_id = t.team_id AND p.draft_team_code IS NULL;

UPDATE pcms.people p SET dlg_returning_rights_team_code = t.team_code
FROM pcms.teams t WHERE p.dlg_returning_rights_team_id = t.team_id AND p.dlg_returning_rights_team_code IS NULL;

UPDATE pcms.people p SET dlg_team_code = t.team_code
FROM pcms.teams t WHERE p.dlg_team_id = t.team_id AND p.dlg_team_code IS NULL;

-- =============================================================================
-- 9. TAX_TEAM_STATUS
-- =============================================================================
-- Has: team_id

ALTER TABLE pcms.tax_team_status ADD COLUMN IF NOT EXISTS team_code text;

CREATE INDEX IF NOT EXISTS idx_tax_team_status_team_code ON pcms.tax_team_status(team_code);

UPDATE pcms.tax_team_status tts SET team_code = t.team_code
FROM pcms.teams t WHERE tts.team_id = t.team_id AND tts.team_code IS NULL;

-- =============================================================================
-- 10. TEAM_BUDGET_SNAPSHOTS
-- =============================================================================
-- Has: team_id

ALTER TABLE pcms.team_budget_snapshots ADD COLUMN IF NOT EXISTS team_code text;

CREATE INDEX IF NOT EXISTS idx_team_budget_snapshots_team_code ON pcms.team_budget_snapshots(team_code);

UPDATE pcms.team_budget_snapshots tbs SET team_code = t.team_code
FROM pcms.teams t WHERE tbs.team_id = t.team_id AND tbs.team_code IS NULL;

-- =============================================================================
-- 11. TEAM_EXCEPTIONS
-- =============================================================================
-- Has: team_id

ALTER TABLE pcms.team_exceptions ADD COLUMN IF NOT EXISTS team_code text;

CREATE INDEX IF NOT EXISTS idx_team_exceptions_team_code ON pcms.team_exceptions(team_code);

UPDATE pcms.team_exceptions te SET team_code = t.team_code
FROM pcms.teams t WHERE te.team_id = t.team_id AND te.team_code IS NULL;

-- =============================================================================
-- 12. TEAM_TAX_SUMMARY_SNAPSHOTS
-- =============================================================================
-- Has: team_id

ALTER TABLE pcms.team_tax_summary_snapshots ADD COLUMN IF NOT EXISTS team_code text;

CREATE INDEX IF NOT EXISTS idx_team_tax_summary_snapshots_team_code ON pcms.team_tax_summary_snapshots(team_code);

UPDATE pcms.team_tax_summary_snapshots ttss SET team_code = t.team_code
FROM pcms.teams t WHERE ttss.team_id = t.team_id AND ttss.team_code IS NULL;

-- =============================================================================
-- 13. TEAM_TWO_WAY_CAPACITY
-- =============================================================================
-- Has: team_id (PK)

ALTER TABLE pcms.team_two_way_capacity ADD COLUMN IF NOT EXISTS team_code text;

UPDATE pcms.team_two_way_capacity ttwc SET team_code = t.team_code
FROM pcms.teams t WHERE ttwc.team_id = t.team_id AND ttwc.team_code IS NULL;

-- =============================================================================
-- 14. TRADE_GROUPS
-- =============================================================================
-- Has: team_id

ALTER TABLE pcms.trade_groups ADD COLUMN IF NOT EXISTS team_code text;

CREATE INDEX IF NOT EXISTS idx_trade_groups_team_code ON pcms.trade_groups(team_code);

UPDATE pcms.trade_groups tg SET team_code = t.team_code
FROM pcms.teams t WHERE tg.team_id = t.team_id AND tg.team_code IS NULL;

-- =============================================================================
-- 15. TRADE_TEAM_DETAILS
-- =============================================================================
-- Has: team_id

ALTER TABLE pcms.trade_team_details ADD COLUMN IF NOT EXISTS team_code text;

CREATE INDEX IF NOT EXISTS idx_trade_team_details_team_code ON pcms.trade_team_details(team_code);

UPDATE pcms.trade_team_details ttd SET team_code = t.team_code
FROM pcms.teams t WHERE ttd.team_id = t.team_id AND ttd.team_code IS NULL;

-- =============================================================================
-- 16. TRADE_TEAMS
-- =============================================================================
-- Has: team_id

ALTER TABLE pcms.trade_teams ADD COLUMN IF NOT EXISTS team_code text;

CREATE INDEX IF NOT EXISTS idx_trade_teams_team_code ON pcms.trade_teams(team_code);

UPDATE pcms.trade_teams tt SET team_code = t.team_code
FROM pcms.teams t WHERE tt.team_id = t.team_id AND tt.team_code IS NULL;

-- =============================================================================
-- 17. TRANSACTION_WAIVER_AMOUNTS
-- =============================================================================
-- Has: team_id

ALTER TABLE pcms.transaction_waiver_amounts ADD COLUMN IF NOT EXISTS team_code text;

CREATE INDEX IF NOT EXISTS idx_transaction_waiver_amounts_team_code ON pcms.transaction_waiver_amounts(team_code);

UPDATE pcms.transaction_waiver_amounts twa SET team_code = t.team_code
FROM pcms.teams t WHERE twa.team_id = t.team_id AND twa.team_code IS NULL;

-- =============================================================================
-- 18. TWO_WAY_CONTRACT_UTILITY
-- =============================================================================
-- Has: contract_team_id, signing_team_id

ALTER TABLE pcms.two_way_contract_utility ADD COLUMN IF NOT EXISTS contract_team_code text;
ALTER TABLE pcms.two_way_contract_utility ADD COLUMN IF NOT EXISTS signing_team_code text;

UPDATE pcms.two_way_contract_utility twcu SET contract_team_code = t.team_code
FROM pcms.teams t WHERE twcu.contract_team_id = t.team_id AND twcu.contract_team_code IS NULL;

UPDATE pcms.two_way_contract_utility twcu SET signing_team_code = t.team_code
FROM pcms.teams t WHERE twcu.signing_team_id = t.team_id AND twcu.signing_team_code IS NULL;

-- =============================================================================
-- 19. TWO_WAY_DAILY_STATUSES
-- =============================================================================
-- Has: status_team_id, contract_team_id, signing_team_id

ALTER TABLE pcms.two_way_daily_statuses ADD COLUMN IF NOT EXISTS status_team_code text;
ALTER TABLE pcms.two_way_daily_statuses ADD COLUMN IF NOT EXISTS contract_team_code text;
ALTER TABLE pcms.two_way_daily_statuses ADD COLUMN IF NOT EXISTS signing_team_code text;

UPDATE pcms.two_way_daily_statuses twds SET status_team_code = t.team_code
FROM pcms.teams t WHERE twds.status_team_id = t.team_id AND twds.status_team_code IS NULL;

UPDATE pcms.two_way_daily_statuses twds SET contract_team_code = t.team_code
FROM pcms.teams t WHERE twds.contract_team_id = t.team_id AND twds.contract_team_code IS NULL;

UPDATE pcms.two_way_daily_statuses twds SET signing_team_code = t.team_code
FROM pcms.teams t WHERE twds.signing_team_id = t.team_id AND twds.signing_team_code IS NULL;

-- =============================================================================
-- 20. TWO_WAY_GAME_UTILITY
-- =============================================================================
-- Has: team_id, opposition_team_id

ALTER TABLE pcms.two_way_game_utility ADD COLUMN IF NOT EXISTS team_code text;
ALTER TABLE pcms.two_way_game_utility ADD COLUMN IF NOT EXISTS opposition_team_code text;

UPDATE pcms.two_way_game_utility twgu SET team_code = t.team_code
FROM pcms.teams t WHERE twgu.team_id = t.team_id AND twgu.team_code IS NULL;

UPDATE pcms.two_way_game_utility twgu SET opposition_team_code = t.team_code
FROM pcms.teams t WHERE twgu.opposition_team_id = t.team_id AND twgu.opposition_team_code IS NULL;

-- =============================================================================
-- 21. UI_PROJECTED_SALARIES
-- =============================================================================
-- Has: team_id

ALTER TABLE pcms.ui_projected_salaries ADD COLUMN IF NOT EXISTS team_code text;

CREATE INDEX IF NOT EXISTS idx_ui_projected_salaries_team_code ON pcms.ui_projected_salaries(team_code);

UPDATE pcms.ui_projected_salaries ups SET team_code = t.team_code
FROM pcms.teams t WHERE ups.team_id = t.team_id AND ups.team_code IS NULL;

-- =============================================================================
-- 22. UI_PROJECTIONS
-- =============================================================================
-- Has: team_id

ALTER TABLE pcms.ui_projections ADD COLUMN IF NOT EXISTS team_code text;

CREATE INDEX IF NOT EXISTS idx_ui_projections_team_code ON pcms.ui_projections(team_code);

UPDATE pcms.ui_projections up SET team_code = t.team_code
FROM pcms.teams t WHERE up.team_id = t.team_id AND up.team_code IS NULL;

-- =============================================================================
-- 23. WAIVER_PRIORITY_RANKS
-- =============================================================================
-- Has: team_id

ALTER TABLE pcms.waiver_priority_ranks ADD COLUMN IF NOT EXISTS team_code text;

CREATE INDEX IF NOT EXISTS idx_waiver_priority_ranks_team_code ON pcms.waiver_priority_ranks(team_code);

UPDATE pcms.waiver_priority_ranks wpr SET team_code = t.team_code
FROM pcms.teams t WHERE wpr.team_id = t.team_id AND wpr.team_code IS NULL;

COMMIT;

-- =============================================================================
-- SUMMARY OF CHANGES
-- =============================================================================
-- 
-- Tables modified (23 total):
-- 
-- | Table                      | Columns Added                                                |
-- |----------------------------|--------------------------------------------------------------|
-- | teams                      | RENAMED: team_name_short → team_code                         |
-- | contracts                  | team_code, sign_and_trade_to_team_code                       |
-- | transactions               | from_team_code, to_team_code, rights_team_code, sign_and_trade_team_code |
-- | ledger_entries             | team_code                                                    |
-- | draft_picks                | player_id, original_team_code, current_team_code             |
-- | depth_charts               | team_code                                                    |
-- | non_contract_amounts       | team_code                                                    |
-- | people                     | team_code, draft_team_code, dlg_returning_rights_team_code, dlg_team_code |
-- | tax_team_status            | team_code                                                    |
-- | team_budget_snapshots      | team_code                                                    |
-- | team_exceptions            | team_code                                                    |
-- | team_tax_summary_snapshots | team_code                                                    |
-- | team_two_way_capacity      | team_code                                                    |
-- | trade_groups               | team_code                                                    |
-- | trade_team_details         | team_code                                                    |
-- | trade_teams                | team_code                                                    |
-- | transaction_waiver_amounts | team_code                                                    |
-- | two_way_contract_utility   | contract_team_code, signing_team_code                        |
-- | two_way_daily_statuses     | status_team_code, contract_team_code, signing_team_code      |
-- | two_way_game_utility       | team_code, opposition_team_code                              |
-- | ui_projected_salaries      | team_code                                                    |
-- | ui_projections             | team_code                                                    |
-- | waiver_priority_ranks      | team_code                                                    |
--
-- =============================================================================
-- VERIFICATION QUERIES
-- =============================================================================
--
-- -- Count team_code columns added
-- SELECT table_name, column_name 
-- FROM information_schema.columns 
-- WHERE table_schema = 'pcms' AND column_name LIKE '%team_code%'
-- ORDER BY table_name;
--
-- -- Verify backfills worked (should return 0 for tables with data)
-- SELECT 'contracts' as tbl, COUNT(*) as missing FROM pcms.contracts WHERE signing_team_id IS NOT NULL AND team_code IS NULL
-- UNION ALL
-- SELECT 'transactions', COUNT(*) FROM pcms.transactions WHERE to_team_id IS NOT NULL AND to_team_code IS NULL
-- UNION ALL
-- SELECT 'people', COUNT(*) FROM pcms.people WHERE team_id IS NOT NULL AND team_code IS NULL;
