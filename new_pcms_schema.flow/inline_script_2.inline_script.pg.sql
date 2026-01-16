-- result_collection=last_statement_all_rows
-- database f/env/postgres

SET search_path TO pcms;

-- ==========================================
-- CONTRACTS & TERMS
-- ==========================================

-- ### contracts
CREATE TABLE IF NOT EXISTS contracts (
    contract_id integer PRIMARY KEY, -- from contractId
    player_id integer NOT NULL, -- from playerId, FK: references people(person_id)
    signing_team_id integer NOT NULL, -- from signingTeamId, FK: references teams(team_id)
    signing_date date NOT NULL,
    contract_end_date date,
    record_status_lk text, -- e.g., ACTIVE, INACTIVE, VOID
    signed_method_lk text, -- e.g., FREE_AGENT, DRAFT, EXTENSION
    team_exception_id integer, -- id of the exception used to sign the player, if applicable
    is_sign_and_trade boolean DEFAULT false,
    sign_and_trade_date date,
    sign_and_trade_to_team_id integer, -- FK: references teams(team_id)
    sign_and_trade_id integer,
    start_year integer, -- v2+ WNBA only; v1 NBA-only loads as NULL
    contract_length_wnba text, -- v2+ WNBA only; v1 NBA-only loads as NULL
    convert_date date, -- date of conversion, e.g., from Two-Way to Standard
    two_way_service_limit integer,
    created_at timestamptz, -- from createDate
    updated_at timestamptz, -- from lastChangeDate
    record_changed_at timestamptz, -- from recordChangeDate
    source_drop_file text,
    source_hash text,
    parser_version text,
    ingested_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_contracts_player_id ON contracts(player_id);
CREATE INDEX IF NOT EXISTS idx_contracts_signing_team_id ON contracts(signing_team_id);
CREATE INDEX IF NOT EXISTS idx_contracts_record_status_lk ON contracts(record_status_lk);

-- ### contract_versions
-- renamed from contract_terms spec to match the internal structure more accurately
CREATE TABLE IF NOT EXISTS contract_versions (
    contract_version_id serial PRIMARY KEY,
    contract_id integer NOT NULL, -- FK: references contracts(contract_id)
    version_number integer NOT NULL, -- from versionNumber
    transaction_id integer, -- from transactionId, FK: references transactions.transaction_id
    version_date date, -- from versionDate
    start_salary_year integer, -- from startYear, the first season year of this version
    contract_length integer, -- from contractLength
    contract_type_lk text, -- from contractTypeLk
    record_status_lk text, -- from recordStatusLk
    agency_id integer, -- from agencyId
    agent_id integer, -- from agentId
    is_full_protection boolean, -- from fullProtectionFlg
    is_exhibit_10 boolean, -- from exhibit10
    exhibit_10_bonus_amount bigint, -- from exhibit10BonusAmount (dollars)
    exhibit_10_protection_amount bigint, -- from exhibit10ProtectionAmount (dollars)
    exhibit_10_end_date date, -- from exhibit10EndDate
    is_two_way boolean, -- derived from contract type or exhibits
    is_rookie_scale_extension boolean, -- from dpRookieScaleExtensionFlg
    is_veteran_extension boolean, -- from dpVeteranExtensionFlg
    is_poison_pill boolean, -- from poisonPillFlg
    poison_pill_amount bigint, -- from poisonPillAmt (dollars)
    trade_bonus_percent numeric, -- from tradeBonusPercent
    trade_bonus_amount bigint, -- from tradeBonusAmount (dollars)
    is_trade_bonus boolean, -- from tradeBonusFlg
    is_no_trade boolean, -- from noTradeFlg
    is_minimum_contract boolean, -- v2+ WNBA only; v1 NBA-only loads as NULL
    is_protected_contract boolean, -- v2+ WNBA only; v1 NBA-only loads as NULL
    version_json jsonb, -- stores all other version-level attributes from PCMS
    created_at timestamptz, -- from createDate
    updated_at timestamptz, -- from lastChangeDate
    record_changed_at timestamptz, -- from recordChangeDate
    source_drop_file text,
    source_hash text,
    parser_version text,
    ingested_at timestamptz DEFAULT now(),
    UNIQUE (contract_id, version_number)
);

CREATE INDEX IF NOT EXISTS idx_contract_versions_contract_id ON contract_versions(contract_id);
CREATE INDEX IF NOT EXISTS idx_contract_versions_start_salary_year ON contract_versions(start_salary_year);

-- ### contract_bonuses
CREATE TABLE IF NOT EXISTS contract_bonuses (
    bonus_id integer PRIMARY KEY, -- from bonusId
    contract_id integer NOT NULL, -- FK: references contracts(contract_id)
    version_number integer NOT NULL, -- FK: references contract_versions(version_number)
    salary_year integer, -- from bonusYear, the season year the bonus applies to
    bonus_amount bigint, -- from bonusAmount (dollars)
    bonus_type_lk text, -- from contractBonusTypeLk
    is_likely boolean, -- from bonusLikelyFlg
    earned_lk text, -- from earnedLk, e.g., EARNED, NOT_EARNED
    paid_by_date date, -- from bonusPaidByDate
    clause_name text, -- from clauseName
    criteria_description text, -- from criteriaDescription
    criteria_json jsonb, -- stores the bonusCriteria nested structure
    source_drop_file text,
    source_hash text,
    parser_version text,
    ingested_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_contract_bonuses_contract_id ON contract_bonuses(contract_id);
CREATE INDEX IF NOT EXISTS idx_contract_bonuses_salary_year ON contract_bonuses(salary_year);

-- ### contract_protections
CREATE TABLE IF NOT EXISTS contract_protections (
    protection_id integer PRIMARY KEY, -- from contractProtectionId
    contract_id integer NOT NULL, -- FK: references contracts(contract_id)
    version_number integer NOT NULL, -- FK: references contract_versions(version_number)
    salary_year integer, -- from contractYear, the season year this protection applies to
    protection_amount bigint, -- from protectionAmount (dollars)
    effective_protection_amount bigint, -- from effectiveProtectionAmount (dollars)
    protection_coverage_lk text, -- from protectionCoverageLk
    is_conditional_protection boolean, -- v2+ WNBA only; v1 NBA-only loads as NULL
    conditional_protection_comments text, -- v2+ WNBA only; v1 NBA-only loads as NULL
    protection_types_json jsonb, -- stores the protectionTypes array
    source_drop_file text,
    source_hash text,
    parser_version text,
    ingested_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_contract_protections_contract_id ON contract_protections(contract_id);
CREATE INDEX IF NOT EXISTS idx_contract_protections_salary_year ON contract_protections(salary_year);

-- ### contract_protection_conditions
CREATE TABLE IF NOT EXISTS contract_protection_conditions (
    condition_id integer PRIMARY KEY, -- from contractProtectionConditionId
    protection_id integer NOT NULL, -- FK: references contract_protections(protection_id)
    amount bigint, -- from amount (dollars)
    clause_name text, -- from clauseName
    earned_date date, -- from earnedDate
    earned_type_lk text, -- from earnedTypeLk
    is_full_condition boolean, -- from fullFlg
    criteria_description text, -- from criteriaDescription
    criteria_json jsonb, -- stores the criteria nested structure
    source_drop_file text,
    source_hash text,
    parser_version text,
    ingested_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_contract_protection_conditions_protection_id ON contract_protection_conditions(protection_id);

-- ### contract_bonus_criteria
CREATE TABLE IF NOT EXISTS contract_bonus_criteria (
    bonus_criteria_id integer PRIMARY KEY, -- from bonusCriteriaId
    bonus_id integer NOT NULL, -- FK: references contract_bonuses(bonus_id)
    criteria_lk text, -- from criteriaLk, the metric being measured
    criteria_operator_lk text, -- from criteriaOperatorLk, e.g., GREATER_THAN, EQUAL
    modifier_lk text, -- from modifierLk
    season_type_lk text, -- from seasonTypeLk, e.g., REGULAR_SEASON, PLAYOFFS
    is_player_criteria boolean, -- from playerCriteriaFlg
    is_team_criteria boolean, -- from teamCriteriaFlg
    value_1 numeric, -- from value1
    value_2 numeric, -- from value2
    date_1 date, -- from date1
    date_2 date, -- from date2
    source_drop_file text,
    source_hash text,
    parser_version text,
    ingested_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_contract_bonus_criteria_bonus_id ON contract_bonus_criteria(bonus_id);

-- ### contract_bonus_maximums
CREATE TABLE IF NOT EXISTS contract_bonus_maximums (
    bonus_max_id integer PRIMARY KEY, -- from bonusMaxId
    contract_id integer NOT NULL, -- FK: references contracts(contract_id)
    version_number integer NOT NULL, -- FK: references contract_versions(version_number)
    salary_year integer, -- from bonusYear
    max_amount bigint, -- from maxAmount (dollars)
    bonus_type_lk text, -- from contractBonusTypeLk
    is_likely boolean, -- from bonusLikelyFlg
    source_drop_file text,
    source_hash text,
    parser_version text,
    ingested_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_contract_bonus_maximums_contract_id ON contract_bonus_maximums(contract_id);

-- ==========================================
-- SALARIES
-- ==========================================

-- ### salaries
CREATE TABLE IF NOT EXISTS salaries (
    salary_id serial PRIMARY KEY,
    contract_id integer NOT NULL, -- FK: references contracts(contract_id)
    version_number integer NOT NULL, -- FK: references contract_versions(version_number)
    salary_year integer NOT NULL, -- from salaryYear (e.g., 2023 for 2023-24)
    total_salary bigint, -- from totalSalary (dollars)
    total_salary_adjustment bigint, -- (dollars)
    total_base_comp bigint, -- (dollars)
    current_base_comp bigint, -- (dollars)
    deferred_base_comp bigint, -- (dollars)
    signing_bonus bigint, -- (dollars)
    likely_bonus bigint, -- (dollars)
    unlikely_bonus bigint, -- (dollars)
    contract_cap_salary bigint, -- from contractCapSalary (dollars)
    contract_cap_salary_adjustment bigint, -- (dollars)
    contract_tax_salary bigint, -- (dollars)
    contract_tax_salary_adjustment bigint, -- (dollars)
    contract_tax_apron_salary bigint, -- (dollars)
    contract_tax_apron_salary_adjustment bigint, -- (dollars)
    contract_mts_salary bigint, -- (dollars)
    skill_protection_amount bigint, -- (dollars)
    trade_bonus_amount bigint, -- (dollars)
    trade_bonus_amount_calc bigint, -- (dollars)
    cap_raise_percent numeric,
    two_way_nba_salary bigint, -- (dollars)
    two_way_dlg_salary bigint, -- (dollars)
    wnba_salary bigint, -- v2+ WNBA only; v1 NBA-only loads as NULL
    wnba_time_off_bonus_amount bigint, -- v2+ WNBA only; v1 NBA-only loads as NULL
    wnba_merit_bonus_amount bigint, -- v2+ WNBA only; v1 NBA-only loads as NULL
    wnba_time_off_bonus_days integer, -- v2+ WNBA only; v1 NBA-only loads as NULL
    option_lk text, -- e.g., PLAYER_OPTION, TEAM_OPTION
    option_decision_lk text, -- e.g., EXERCISED, DECLINED
    is_applicable_min_salary boolean, -- from applicableMinSalaryFlg
    created_at timestamptz, -- from createDate
    updated_at timestamptz, -- from lastChangeDate
    record_changed_at timestamptz, -- from recordChangeDate
    source_drop_file text,
    source_hash text,
    parser_version text,
    ingested_at timestamptz DEFAULT now(),
    UNIQUE (contract_id, version_number, salary_year)
);

CREATE INDEX IF NOT EXISTS idx_salaries_contract_id ON salaries(contract_id);
CREATE INDEX IF NOT EXISTS idx_salaries_salary_year ON salaries(salary_year);

-- ### payment_schedules
CREATE TABLE IF NOT EXISTS payment_schedules (
    payment_schedule_id integer PRIMARY KEY, -- from contractPaymentScheduleId
    contract_id integer NOT NULL, -- FK: references contracts(contract_id)
    version_number integer NOT NULL, -- FK: references contract_versions(version_number)
    salary_year integer NOT NULL, -- from salaryYear
    payment_amount bigint, -- from paymentAmount (dollars)
    payment_start_date date, -- from paymentStartDate
    schedule_type_lk text, -- from paymentScheduleTypeLk
    payment_type_lk text, -- from contractPaymentTypeLk
    is_default_schedule boolean, -- from defaultPaymentScheduleFlg
    created_at timestamptz, -- from createDate
    updated_at timestamptz, -- from lastChangeDate
    record_changed_at timestamptz, -- from recordChangeDate
    source_drop_file text,
    source_hash text,
    parser_version text,
    ingested_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_payment_schedules_contract_id ON payment_schedules(contract_id);

-- ### payment_schedule_details
CREATE TABLE IF NOT EXISTS payment_schedule_details (
    payment_detail_id integer PRIMARY KEY, -- from contractPaymentScheduleDetailId
    payment_schedule_id integer NOT NULL, -- FK: references payment_schedules(payment_schedule_id)
    payment_date date, -- from paymentDate
    payment_amount bigint, -- from paymentAmount (dollars)
    number_of_days integer, -- from numberOfDays
    payment_type_lk text, -- from contractPaymentTypeLk
    within_days_lk text, -- from withinDaysLk
    is_scheduled boolean, -- from scheduledPaymentFlg
    created_at timestamptz, -- from createDate
    updated_at timestamptz, -- from lastChangeDate
    record_changed_at timestamptz, -- from recordChangeDate
    source_drop_file text,
    source_hash text,
    parser_version text,
    ingested_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_payment_schedule_details_schedule_id ON payment_schedule_details(payment_schedule_id);

-- ==========================================
-- EXCEPTIONS
-- ==========================================

-- ### team_exceptions
CREATE TABLE IF NOT EXISTS team_exceptions (
    team_exception_id integer PRIMARY KEY, -- from teamExceptionId
    team_id integer, -- FK: references teams(team_id)
    salary_year integer, -- e.g., 2023 for 2023-24 season
    exception_type_lk text, -- e.g., NON_TAX_MLE, TAX_MLE, ROOM_MLE, BAE, TRADE_EXCEPTION
    effective_date date,
    expiration_date date,
    original_amount bigint, -- (dollars)
    remaining_amount bigint, -- (dollars)
    proration_rate numeric,
    is_initially_convertible boolean,
    trade_exception_player_id integer, -- FK: references people(person_id)
    trade_id integer, -- FK: references trades(trade_id)
    record_status_lk text, -- e.g., ACTIVE, EXPIRED
    created_at timestamptz, -- from createDate
    updated_at timestamptz, -- from lastChangeDate
    record_changed_at timestamptz, -- from recordChangeDate
    source_drop_file text,
    source_hash text,
    parser_version text,
    ingested_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_team_exceptions_team_id ON team_exceptions(team_id);
CREATE INDEX IF NOT EXISTS idx_team_exceptions_salary_year ON team_exceptions(salary_year);

-- ### team_exception_usage
CREATE TABLE IF NOT EXISTS team_exception_usage (
    team_exception_detail_id integer PRIMARY KEY, -- from teamExceptionDetailId
    team_exception_id integer, -- FK: references team_exceptions(team_exception_id)
    seqno integer, -- from seqno
    effective_date date,
    exception_action_lk text, -- e.g., USE, CONVERT, PRORATE, EXPIRE
    transaction_type_lk text,
    transaction_id integer, -- FK: references transactions(transaction_id)
    player_id integer, -- FK: references people(person_id)
    contract_id integer, -- FK: references contracts(contract_id)
    change_amount bigint, -- (dollars)
    remaining_exception_amount bigint, -- (dollars)
    proration_rate numeric,
    prorate_days numeric,
    is_convert_exception boolean,
    manual_action_text text,
    created_at timestamptz, -- from createDate
    updated_at timestamptz, -- from lastChangeDate
    record_changed_at timestamptz, -- from recordChangeDate
    source_drop_file text,
    source_hash text,
    parser_version text,
    ingested_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_team_exception_usage_exception_id ON team_exception_usage(team_exception_id);
CREATE INDEX IF NOT EXISTS idx_team_exception_usage_player_id ON team_exception_usage(player_id);
