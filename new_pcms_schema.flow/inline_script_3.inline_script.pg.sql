-- result_collection=last_statement_all_rows
-- database f/env/postgres

SET search_path TO pcms;

-- ==========================================
-- TRADES
-- ==========================================

-- ### trades
CREATE TABLE IF NOT EXISTS trades (
    trade_id integer PRIMARY KEY, -- from tradeId
    trade_date date, -- from tradeDate
    trade_finalized_date date, -- from tradeFinalizedDate
    league_lk text, -- from leagueLk
    record_status_lk text, -- from recordStatusLk
    trade_comments text, -- from tradeComments
    created_at timestamptz, -- from createDate
    updated_at timestamptz, -- from lastChangeDate
    record_changed_at timestamptz, -- from recordChangeDate
    source_drop_file text,
    source_hash text,
    parser_version text,
    ingested_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_trades_trade_date ON trades(trade_date);
CREATE INDEX IF NOT EXISTS idx_trades_record_status_lk ON trades(record_status_lk);

-- ### trade_teams
CREATE TABLE IF NOT EXISTS trade_teams (
    trade_team_id text PRIMARY KEY, -- Generated: trade_id + '_' + team_id
    trade_id integer, -- FK: references trades(trade_id)
    team_id integer, -- FK: references teams(team_id)
    team_salary_change bigint, -- from teamSalaryChange (dollars)
    total_cash_received bigint, -- from totalCashReceived (dollars)
    total_cash_sent bigint, -- from totalCashSent (dollars)
    seqno integer, -- from seqno
    source_drop_file text,
    source_hash text,
    parser_version text,
    ingested_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_trade_teams_trade_id ON trade_teams(trade_id);
CREATE INDEX IF NOT EXISTS idx_trade_teams_team_id ON trade_teams(team_id);

-- ### trade_team_details
CREATE TABLE IF NOT EXISTS trade_team_details (
    trade_team_detail_id text PRIMARY KEY, -- Generated: trade_id + '_' + team_id + '_' + seqno
    trade_id integer, -- FK: references trades(trade_id)
    team_id integer, -- FK: references teams(team_id)
    seqno integer, -- from seqno
    group_number integer, -- from groupNumber
    player_id integer, -- FK: references people(person_id)
    contract_id integer, -- FK: references contracts(contract_id)
    version_number integer, -- from versionNumber
    post_version_number integer, -- from postVersionNumber
    is_sent boolean, -- from sentFlg
    is_sign_and_trade boolean, -- from signAndTradeFlg
    mts_value_override bigint, -- from mtsValueOverride (dollars)
    is_trade_bonus boolean, -- from tradeBonusFlg
    is_no_trade boolean, -- from noTradeFlg
    is_player_consent boolean, -- from playerConsentFlg
    is_poison_pill boolean, -- from poisonPillFlg
    is_incentive_bonus boolean, -- from incentiveBonusFlg
    cash_amount bigint, -- from cashAmount (dollars)
    trade_entry_lk text, -- from tradeEntryLk
    free_agent_designation_lk text, -- from freeAgentDesignationLk
    base_year_amount bigint, -- from baseYearAmount (dollars)
    is_base_year boolean, -- from baseYearFlg
    draft_pick_year integer, -- from draftPickYear
    draft_pick_round integer, -- from draftPickRound
    is_draft_pick_future boolean, -- from draftPickFutureFlg
    is_draft_pick_swap boolean, -- from draftPickSwapFlg
    draft_pick_conditional_lk text, -- from draftPickConditionalLk
    is_draft_year_plus_two boolean, -- from draftYearPlusTwoFlg
    source_drop_file text,
    source_hash text,
    parser_version text,
    ingested_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_trade_team_details_trade_id ON trade_team_details(trade_id);
CREATE INDEX IF NOT EXISTS idx_trade_team_details_player_id ON trade_team_details(player_id);

-- ### trade_groups
CREATE TABLE IF NOT EXISTS trade_groups (
    trade_group_id text PRIMARY KEY, -- Generated: trade_id + '_' + team_id + '_' + trade_group_number
    trade_id integer, -- FK: references trades(trade_id)
    team_id integer, -- FK: references teams(team_id)
    trade_group_number integer, -- from tradeGroupNumber
    trade_group_comments text, -- from tradeGroupComments
    acquired_team_exception_id integer, -- FK: references team_exceptions(team_exception_id)
    generated_team_exception_id integer, -- FK: references team_exceptions(team_exception_id)
    signed_method_lk text, -- from signedMethodLk
    source_drop_file text,
    source_hash text,
    parser_version text,
    ingested_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_trade_groups_trade_id ON trade_groups(trade_id);

-- ==========================================
-- WAIVERS
-- ==========================================

-- ### waiver_priority
CREATE TABLE IF NOT EXISTS waiver_priority (
    waiver_priority_id integer PRIMARY KEY, -- from waiverPriorityId
    priority_date date, -- from priorityDate
    seqno integer, -- from seqno
    status_lk text, -- from recordStatusLk
    comments text,
    created_at timestamptz, -- from createDate
    updated_at timestamptz, -- from lastChangeDate
    record_changed_at timestamptz, -- from recordChangeDate
    source_drop_file text,
    source_hash text,
    parser_version text,
    ingested_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_waiver_priority_priority_date ON waiver_priority(priority_date);

-- ### waiver_priority_ranks
CREATE TABLE IF NOT EXISTS waiver_priority_ranks (
    waiver_priority_rank_id integer PRIMARY KEY, -- from waiverPriorityDetailId
    waiver_priority_id integer NOT NULL, -- FK: references waiver_priority(waiver_priority_id)
    team_id integer NOT NULL, -- FK: references teams(team_id)
    priority_order integer NOT NULL, -- the rank/position in the waiver order
    is_order_priority boolean, -- from orderPriorityFlg
    exclusivity_status_lk text, -- from exclusivityStatusLk
    exclusivity_expiration_date date, -- from exclusivityExpirationDate
    status_lk text, -- from recordStatusLk
    seqno integer, -- from seqno
    comments text,
    created_at timestamptz, -- from createDate
    updated_at timestamptz, -- from lastChangeDate
    record_changed_at timestamptz, -- from recordChangeDate
    source_drop_file text,
    source_hash text,
    parser_version text,
    ingested_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_waiver_priority_ranks_waiver_priority_id ON waiver_priority_ranks(waiver_priority_id);
CREATE INDEX IF NOT EXISTS idx_waiver_priority_ranks_team_id ON waiver_priority_ranks(team_id);

-- ### transaction_waiver_amounts
CREATE TABLE IF NOT EXISTS transaction_waiver_amounts (
    transaction_waiver_amount_id integer PRIMARY KEY, -- from transactionWaiverAmountId
    transaction_id integer NOT NULL, -- FK: references transactions(transaction_id)
    player_id integer NOT NULL, -- FK: references people(person_id)
    team_id integer, -- FK: references teams(team_id)
    contract_id integer, -- FK: references contracts(contract_id)
    salary_year integer NOT NULL, -- the Salary Cap Year this amount applies to
    version_number integer, -- associated contract version
    waive_date timestamptz, -- from waiveDate
    cap_value bigint, -- from capValue (dollars)
    cap_change_value bigint, -- from capChangeValue (dollars)
    is_cap_calculated boolean, -- from capCalculated
    tax_value bigint, -- from taxValue (dollars)
    tax_change_value bigint, -- from taxChangeValue (dollars)
    is_tax_calculated boolean, -- from taxCalculated
    apron_value bigint, -- from apronValue (dollars)
    apron_change_value bigint, -- from apronChangeValue (dollars)
    is_apron_calculated boolean, -- from apronCalculated
    mts_value bigint, -- from mtsValue (dollars)
    mts_change_value bigint, -- from mtsChangeValue (dollars)
    two_way_salary bigint, -- from twoWaySalary (dollars)
    two_way_nba_salary bigint, -- from twoWayNbaSalary (dollars)
    two_way_dlg_salary bigint, -- from twoWayDlgSalary (dollars)
    option_decision_lk text, -- from optionDecisionLk
    wnba_contract_id integer, -- v2+ WNBA only; v1 NBA-only loads as NULL
    wnba_version_number text, -- v2+ WNBA only; v1 NBA-only loads as NULL
    source_drop_file text,
    source_hash text,
    parser_version text,
    ingested_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_transaction_waiver_amounts_transaction_id ON transaction_waiver_amounts(transaction_id);
CREATE INDEX IF NOT EXISTS idx_transaction_waiver_amounts_player_id ON transaction_waiver_amounts(player_id);
CREATE INDEX IF NOT EXISTS idx_transaction_waiver_amounts_salary_year ON transaction_waiver_amounts(salary_year);

-- ==========================================
-- TRANSACTIONS
-- ==========================================

-- ### transactions
CREATE TABLE IF NOT EXISTS transactions (
    transaction_id integer PRIMARY KEY, -- from transactionId
    player_id integer, -- FK: references people(person_id)
    from_team_id integer, -- FK: references teams(team_id)
    to_team_id integer, -- FK: references teams(team_id)
    transaction_date date, -- from transactionDate
    trade_finalized_date date, -- from tradeFinalizedDate
    trade_id integer, -- FK: references trades(trade_id)
    transaction_type_lk text, -- e.g., SIGN, WAIVE, TRADE
    transaction_description_lk text, -- further detail on the move
    record_status_lk text,
    league_lk text, -- v1: NBA only
    seqno integer, -- sequence number for multi-step transactions
    is_in_season boolean,
    contract_id integer, -- FK: references contracts(contract_id)
    original_contract_id integer,
    version_number integer,
    contract_type_lk text,
    min_contract_lk text,
    signed_method_lk text,
    team_exception_id integer, -- FK: references team_exceptions(team_exception_id)
    rights_team_id integer, -- FK: references teams(team_id)
    waiver_clear_date date, -- from waiverClearDate
    is_clear_player_rights boolean,
    free_agent_status_lk text,
    free_agent_designation_lk text,
    from_player_status_lk text,
    to_player_status_lk text,
    option_year integer,
    adjustment_amount bigint, -- (dollars)
    bonus_true_up_amount bigint, -- (dollars)
    draft_amount bigint, -- (dollars)
    draft_pick integer,
    draft_round integer,
    draft_year integer,
    free_agent_amount bigint, -- (dollars)
    qoe_amount bigint, -- (dollars)
    tender_amount bigint, -- (dollars)
    is_divorce boolean, -- relevant for contract terminations/buyouts
    effective_salary_year integer, -- from effectiveSeason
    is_initially_convertible_exception boolean,
    is_sign_and_trade boolean,
    sign_and_trade_team_id integer, -- FK: references teams(team_id)
    sign_and_trade_link_transaction_id integer,
    dlg_contract_id integer,
    dlg_experience_level_lk text,
    dlg_salary_level_lk text,
    comments text,
    created_at timestamptz, -- from createDate
    updated_at timestamptz, -- from lastChangeDate
    record_changed_at timestamptz, -- from recordChangeDate
    source_drop_file text,
    source_hash text,
    parser_version text,
    ingested_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_transactions_player_id ON transactions(player_id);
CREATE INDEX IF NOT EXISTS idx_transactions_transaction_date ON transactions(transaction_date);
CREATE INDEX IF NOT EXISTS idx_transactions_effective_salary_year ON transactions(effective_salary_year);
CREATE INDEX IF NOT EXISTS idx_transactions_transaction_type_lk ON transactions(transaction_type_lk);

-- ==========================================
-- DRAFT
-- ==========================================

-- ### draft_picks
CREATE TABLE IF NOT EXISTS draft_picks (
    draft_pick_id integer PRIMARY KEY, -- from draftPickId
    draft_year integer, -- from year or draftYear
    round integer, -- from round
    pick_number text, -- from pick
    pick_number_int integer, -- numeric version of pick_number
    league_lk text, -- v1: 'NBA' only
    original_team_id integer, -- FK: references teams(team_id)
    current_team_id integer, -- FK: references teams(team_id)
    is_active boolean, -- from activeFlg
    is_protected boolean,
    protection_description text,
    is_swap boolean, -- from draftPickSwapFlg
    swap_type_lk text,
    conveyance_year_range text,
    conveyance_trigger_description text,
    first_round_summary text,
    second_round_summary text,
    history_json jsonb,
    draft_json jsonb,
    summary_json jsonb,
    source_drop_file text,
    source_hash text,
    parser_version text,
    created_at timestamptz, -- from createDate
    updated_at timestamptz, -- from lastChangeDate
    record_changed_at timestamptz, -- from recordChangeDate
    ingested_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_draft_picks_year_round ON draft_picks(draft_year, round);
CREATE INDEX IF NOT EXISTS idx_draft_picks_current_team ON draft_picks(current_team_id);

-- ### draft_rankings
CREATE TABLE IF NOT EXISTS draft_rankings (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    scout_id text NOT NULL,
    draft_year integer NOT NULL,
    player_id text, -- Link to a player entity
    player_name_raw text NOT NULL,
    ranking_position integer,
    tier text,
    evaluation_notes text,
    value_delimiter_rank integer,
    value_delimiter_label text,
    ranking_json jsonb,
    source_drop_file text,
    source_hash text,
    parser_version text,
    ingested_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),

    UNIQUE (scout_id, draft_year, player_name_raw)
);

CREATE INDEX IF NOT EXISTS idx_draft_rankings_year_position ON draft_rankings(draft_year, ranking_position);
CREATE INDEX IF NOT EXISTS idx_draft_rankings_scout_year ON draft_rankings(scout_id, draft_year);

-- ==========================================
-- LEDGER
-- ==========================================

-- ### ledger_entries
CREATE TABLE IF NOT EXISTS ledger_entries (
    transaction_ledger_entry_id numeric PRIMARY KEY, -- from transactionLedgerEntryId
    transaction_id numeric NOT NULL, -- FK: references transactions(transaction_id)
    team_id numeric NOT NULL, -- FK: references teams(team_id)
    player_id numeric, -- FK: references people(person_id)
    contract_id numeric, -- FK: references contracts(contract_id)
    dlg_contract_id numeric,
    salary_year integer NOT NULL, -- from salaryYear
    ledger_date date, -- from ledgerDate
    league_lk text, -- v1: 'NBA' only
    transaction_type_lk text,
    transaction_description_lk text,
    version_number integer,
    seqno integer,
    sub_seqno integer,
    team_ledger_seqno integer,
    is_leaving_team boolean,
    has_no_budget_impact boolean,

    -- MTS (Minimum Team Salary) Impact
    mts_amount bigint, -- (dollars)
    mts_change bigint, -- (dollars)
    mts_value bigint, -- (dollars)

    -- Salary Cap Impact
    cap_amount bigint, -- (dollars)
    cap_change bigint, -- (dollars)
    cap_value bigint, -- (dollars)

    -- Luxury Tax Impact
    tax_amount bigint, -- (dollars)
    tax_change bigint, -- (dollars)
    tax_value bigint, -- (dollars)

    -- Apron Impact
    apron_amount bigint, -- (dollars)
    apron_change bigint, -- (dollars)
    apron_value bigint, -- (dollars)

    trade_bonus_amount bigint, -- (dollars)

    source_drop_file text,
    source_hash text,
    parser_version text,
    ingested_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ledger_entries_transaction_id ON ledger_entries(transaction_id);
CREATE INDEX IF NOT EXISTS idx_ledger_entries_team_id_salary_year ON ledger_entries(team_id, salary_year);
CREATE INDEX IF NOT EXISTS idx_ledger_entries_player_id ON ledger_entries(player_id);
