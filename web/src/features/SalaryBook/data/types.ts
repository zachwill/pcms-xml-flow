/**
 * NBA Salary Book Type Definitions
 *
 * Maps to PostgreSQL tables in the pcms schema:
 * - pcms.salary_book_warehouse
 * - pcms.team_salary_warehouse
 * - pcms.draft_pick_summaries
 * - pcms.agents / pcms.agencies
 */

/**
 * Option type for contract years
 * PO = Player Option, TO = Team Option, ETO = Early Termination Option
 */
export type ContractOption = "PO" | "TO" | "ETO" | null;

/**
 * Guarantee type for contract years
 */
export type GuaranteeType = "GTD" | "PARTIAL" | "NON-GTD" | null;

/**
 * Bird rights status
 */
export type BirdRights = "BIRD" | "EARLY_BIRD" | "NON_BIRD" | null;

/**
 * Free agency type
 */
export type FreeAgencyType = "UFA" | "RFA" | null;

/**
 * Conference for NBA teams
 */
export type Conference = "EAST" | "WEST";

/**
 * Player salary data from pcms.salary_book_warehouse
 * Represents a player's contract with salary figures for years 2025-2030
 */
export interface SalaryBookPlayer {
  id: string;
  player_id: string;
  /** Canonical display name (typically "First Last"), kept for backwards compatibility */
  player_name: string;
  /** Preferred display fields from pcms.people (used for LAST, FIRST formatting in rows) */
  display_first_name: string | null;
  display_last_name: string | null;
  team_code: string;
  position: string | null;
  experience: number | null;
  age: number | null;

  // Salary figures per year (cap_2025..cap_2030)
  cap_2025: number | null;
  cap_2026: number | null;
  cap_2027: number | null;
  cap_2028: number | null;
  cap_2029: number | null;
  cap_2030: number | null;

  // Percent of cap per year (pct_cap_2025..pct_cap_2030)
  pct_cap_2025: number | null;
  pct_cap_2026: number | null;
  pct_cap_2027: number | null;
  pct_cap_2028: number | null;
  pct_cap_2029: number | null;
  pct_cap_2030: number | null;

  // Percentile rank of pct_cap (0.0 = lowest, 1.0 = highest among all players)
  pct_cap_percentile_2025: number | null;
  pct_cap_percentile_2026: number | null;
  pct_cap_percentile_2027: number | null;
  pct_cap_percentile_2028: number | null;
  pct_cap_percentile_2029: number | null;
  pct_cap_percentile_2030: number | null;

  // Option flags per year (option_2025..option_2030)
  option_2025: ContractOption;
  option_2026: ContractOption;
  option_2027: ContractOption;
  option_2028: ContractOption;
  option_2029: ContractOption;
  option_2030: ContractOption;

  // Guarantee structure per year (warehouse stores numeric amounts + booleans)
  guaranteed_amount_2025: number | null;
  guaranteed_amount_2026: number | null;
  guaranteed_amount_2027: number | null;
  guaranteed_amount_2028: number | null;
  guaranteed_amount_2029: number | null;
  guaranteed_amount_2030: number | null;

  is_fully_guaranteed_2025: boolean | null;
  is_fully_guaranteed_2026: boolean | null;
  is_fully_guaranteed_2027: boolean | null;
  is_fully_guaranteed_2028: boolean | null;
  is_fully_guaranteed_2029: boolean | null;
  is_fully_guaranteed_2030: boolean | null;

  is_partially_guaranteed_2025: boolean | null;
  is_partially_guaranteed_2026: boolean | null;
  is_partially_guaranteed_2027: boolean | null;
  is_partially_guaranteed_2028: boolean | null;
  is_partially_guaranteed_2029: boolean | null;
  is_partially_guaranteed_2030: boolean | null;

  is_non_guaranteed_2025: boolean | null;
  is_non_guaranteed_2026: boolean | null;
  is_non_guaranteed_2027: boolean | null;
  is_non_guaranteed_2028: boolean | null;
  is_non_guaranteed_2029: boolean | null;
  is_non_guaranteed_2030: boolean | null;

  // Likely vs unlikely bonuses (per year)
  likely_bonus_2025: number | null;
  likely_bonus_2026: number | null;
  likely_bonus_2027: number | null;
  likely_bonus_2028: number | null;
  likely_bonus_2029: number | null;
  likely_bonus_2030: number | null;

  unlikely_bonus_2025: number | null;
  unlikely_bonus_2026: number | null;
  unlikely_bonus_2027: number | null;
  unlikely_bonus_2028: number | null;
  unlikely_bonus_2029: number | null;
  unlikely_bonus_2030: number | null;

  // Agent/Agency info
  agent_id: string | null;
  agent_name: string | null;
  agency_id: string | null;
  agency_name: string | null;

  // Contract metadata
  is_two_way: boolean;
  is_poison_pill: boolean;
  poison_pill_amount: number | null;
  is_no_trade: boolean;
  is_trade_bonus: boolean;
  trade_bonus_percent: number | null;

  /**
   * Contract type metadata (from salary_book_warehouse, sourced from
   * pcms.contract_versions.contract_type_lk joined to pcms.lookups).
   */
  contract_type_code: string | null;
  contract_type_lookup_value: string | null;

  /**
   * How the contract was signed (Bird/MLE/BAE/minimum/etc).
   */
  signed_method_code: string | null;
  signed_method_lookup_value: string | null;

  /**
   * If signed using a specific exception instance (e.g. Taxpayer MLE), capture it.
   */
  team_exception_id: string | null;
  exception_type_code: string | null;
  exception_type_lookup_value: string | null;

  /**
   * Minimum contract classification from the signing transaction.
   */
  min_contract_code: string | null;
  min_contract_lookup_value: string | null;

  /**
   * Convenience boolean derived from min_contract_code.
   */
  is_min_contract: boolean;

  /**
   * Trade restriction metadata (e.g. EX6MO). `is_trade_restricted_now` is a best-effort boolean.
   */
  trade_restriction_code: string | null;
  trade_restriction_lookup_value: string | null;
  trade_restriction_end_date: string | null;
  is_trade_restricted_now: boolean;

  /**
   * Player trade-consent restriction (derived from contract version_json).
   * If true, show the red "Consent" badge under the current season.
   */
  is_trade_consent_required_now: boolean;
  /** Player has pre-consented to a trade (YRKPC code) */
  is_trade_preconsented: boolean;
  /** Raw consent lookup code (YEARK/YRKPC/ROFRE/...) */
  player_consent_lk: string | null;

  bird_rights: BirdRights;
  free_agency_type: FreeAgencyType;
  free_agency_year: number | null;

  // Contract totals
  contract_years: number | null;
  contract_total: number | null;
}

/**
 * Static NBA team data
 * Used because pcms.teams table is empty - we maintain this statically
 */
export interface Team {
  team_id: number; // NBA team_id used by official CDN assets (e.g., 1610612745)
  team_code: string; // 3-letter abbreviation (e.g., "BOS", "LAL")
  name: string; // Full name (e.g., "Boston Celtics")
  nickname: string; // Short name (e.g., "Celtics")
  city: string; // City name (e.g., "Boston")
  conference: Conference;
}

/**
 * Team salary totals from pcms.team_salary_warehouse
 * Aggregated salary figures per team per year
 */
export interface TeamSalary {
  team_code: string;
  year: number; // 2025, 2026, etc.

  // Salary totals
  cap_total: number;
  tax_total: number;
  apron_total: number | null;
  mts_total: number | null;

  // Breakdown totals (optional)
  cap_rost: number | null;
  cap_fa: number | null;
  cap_term: number | null;
  cap_2way: number | null;
  tax_rost: number | null;
  tax_fa: number | null;
  tax_term: number | null;
  tax_2way: number | null;
  apron_rost: number | null;
  apron_fa: number | null;
  apron_term: number | null;
  apron_2way: number | null;

  // Counts
  roster_row_count: number | null;
  fa_row_count: number | null;
  term_row_count: number | null;
  two_way_row_count: number | null;

  // Thresholds
  salary_cap_amount: number | null;
  tax_level_amount: number | null;
  first_apron_amount: number | null;
  second_apron_amount: number | null;
  minimum_team_salary_amount: number | null;

  // Space / overage
  cap_space: number;
  over_cap: number | null;
  room_under_tax: number;
  room_under_first_apron: number;
  room_under_second_apron: number;

  // Status flags
  is_over_cap: boolean;
  is_over_tax: boolean;
  is_over_first_apron: boolean;
  is_over_second_apron: boolean;

  // Raw warehouse flags / metadata
  is_taxpayer: boolean | null;
  is_repeater_taxpayer: boolean | null;
  is_subject_to_apron: boolean | null;
  apron_level_lk: string | null;
  refreshed_at: string | null;

  // Luxury tax bill
  luxury_tax_bill: number | null;

  // Exception availability
  mid_level_exception: number | null;
  bi_annual_exception: number | null;
  traded_player_exception: number | null;
}

/**
 * League system values (pcms.league_system_values)
 * 
 * Used for the "System Values" sidebar view: cap/tax/apron lines, exception constants,
 * and key season calendar dates.
 */
export interface LeagueSystemValues {
  year: number;

  // Core thresholds
  salary_cap_amount: number | null;
  tax_level_amount: number | null;
  first_apron_amount: number | null;
  second_apron_amount: number | null;
  minimum_team_salary_amount: number | null;
  tax_bracket_amount: number | null;

  // Exceptions / constants
  non_taxpayer_mid_level_amount: number | null;
  taxpayer_mid_level_amount: number | null;
  room_mid_level_amount: number | null;
  bi_annual_amount: number | null;
  two_way_salary_amount: number | null;
  tpe_dollar_allowance: number | null;
  max_trade_cash_amount: number | null;
  international_player_payment_limit: number | null;

  // Maximum salary thresholds
  maximum_salary_25_pct: number | null;
  maximum_salary_30_pct: number | null;
  maximum_salary_35_pct: number | null;

  // Season constants
  scale_raise_rate: number | null;
  days_in_season: number | null;

  // Key dates (ISO date strings)
  season_start_at: string | null;
  season_end_at: string | null;
  moratorium_start_at: string | null;
  moratorium_end_at: string | null;
  trade_deadline_at: string | null;
  dec_15_trade_lift_at: string | null;
  jan_15_trade_lift_at: string | null;
  jan_10_guarantee_at: string | null;
}

/**
 * League tax rate brackets (pcms.league_tax_rates)
 * 
 * Brackets are defined in "amount over the tax line" dollars.
 */
export interface LeagueTaxRate {
  year: number;
  lower_limit: number;
  upper_limit: number | null;
  tax_rate_non_repeater: number | null;
  tax_rate_repeater: number | null;
  base_charge_non_repeater: number | null;
  base_charge_repeater: number | null;
}

/**
 * Trade Machine types (Trade Machine v1)
 */
export type TradeMode = "expanded" | "standard";

export interface TradePlayer {
  playerId: number;
  playerName: string;
  teamCode: string;
  cap_2025: number | null;
  cap_2026: number | null;
  cap_2027: number | null;
  cap_2028: number | null;
  cap_2029: number | null;
  cap_2030: number | null;
}

export interface TradeState {
  salaryYear: number;
  mode: TradeMode;
  primaryTeamCode: string | null;
  secondaryTeamCode: string | null;
  players: TradePlayer[];
}

export interface TradeEvaluationRequestTeam {
  teamCode: string;
  outgoingPlayerIds: number[];
  incomingPlayerIds: number[];
}

export interface TradeEvaluationRequest {
  salaryYear: number;
  mode: TradeMode;
  league: string;
  teams: TradeEvaluationRequestTeam[];
}

export type TradeReasonCode =
  | "ALLOWANCE_ZERO_FIRST_APRON"
  | "MISSING_SYSTEM_VALUES"
  | "MISSING_TEAM_SALARY"
  | "MISSING_MATCHING_FORMULA"
  | "INCOMING_EXCEEDS_MAX"
  | "OUTGOING_PLAYERS_NOT_FOUND"
  | "INCOMING_PLAYERS_NOT_FOUND";

export interface TradeEvaluationTeam {
  team_code: string;
  outgoing_salary: number | null;
  incoming_salary: number | null;
  min_incoming: number | null;
  max_incoming: number | null;
  tpe_type: string | null;
  is_trade_valid: boolean;
  reason_codes: TradeReasonCode[];
  baseline_apron_total: number | null;
  post_trade_apron_total: number | null;
  first_apron_amount: number | null;
  is_padding_removed: boolean | null;
  tpe_padding_amount: number | null;
  tpe_dollar_allowance: number | null;
  traded_rows_found: number | null;
  replacement_rows_found: number | null;
}

export interface TradeEvaluationResponse {
  salary_year: number;
  mode: TradeMode;
  league: string;
  teams: TradeEvaluationTeam[];
}

/**
 * Buyout / waiver scenario calculator
 */
export interface BuyoutScenarioRow {
  salary_year: number;
  cap_salary: number | null;
  days_remaining: number | null;
  proration_factor: number | null;
  guaranteed_remaining: number | null;
  give_back_pct: number | null;
  give_back_amount: number | null;
  dead_money: number | null;
}

export interface BuyoutScenarioTotals {
  guaranteed_remaining: number | null;
  give_back_amount: number | null;
  dead_money: number | null;
}

export interface BuyoutStretchSchedule {
  year: number | null;
  amount: number | null;
}

export interface BuyoutStretchSummary {
  stretch_years: number | null;
  annual_amount: number | null;
  remaining_years: number | null;
  start_year: number | null;
  schedule: BuyoutStretchSchedule[];
}

export interface BuyoutScenarioResponse {
  player_id: number;
  player_name: string | null;
  team_code: string | null;
  salary_year: number;
  waive_date: string;
  give_back_amount: number;
  season_start: string | null;
  rows: BuyoutScenarioRow[];
  totals: BuyoutScenarioTotals;
  stretch: BuyoutStretchSummary | null;
}

export interface BuyoutScenarioRequest {
  playerId: number;
  waiveDate: string;
  giveBackAmount: number;
  salaryYear: number;
  league: string;
}

/**
 * Waiver set-off calculator
 */
export interface SetoffAmountRequest {
  newSalary: number;
  salaryYear: number;
  yearsOfService: number;
  league: string;
}

export interface SetoffAmountResponse {
  new_salary: number;
  salary_year: number;
  years_of_service: number;
  league: string;
  minimum_salary: number | null;
  setoff_amount: number | null;
}

/**
 * Draft pick summaries from pcms.draft_pick_summaries
 * Text descriptions of picks per team per year
 */
export interface DraftPickSummary {
  team_code: string;
  year: number; // 2025, 2026, etc.
  first_round: string | null; // Text description of 1st round picks
  second_round: string | null; // Text description of 2nd round picks
}

/**
 * Parsed draft pick for display
 * Extracted from DraftPickSummary text fields
 */
export interface DraftPick {
  id: string;
  team_code: string; // Team that owns the pick
  origin_team_code: string; // Team the pick originated from
  year: number;
  round: 1 | 2;
  protections: string | null; // Protection description
  is_swap: boolean; // If it's a pick swap
  is_conditional: boolean;
  asset_type: string | null;
  description: string | null;
  conveyance_history: string | null;
}

/**
 * Cap hold rows from pcms.cap_holds_warehouse (pivoted to year columns)
 */
export interface CapHold {
  id: string; // non_contract_amount_id
  team_code: string;
  player_id: number | null;
  player_name: string | null;
  amount_type_lk: string | null;

  cap_2025: number | null;
  cap_2026: number | null;
  cap_2027: number | null;
  cap_2028: number | null;
  cap_2029: number | null;
}

/**
 * Exception rows from pcms.exceptions_warehouse (pivoted to year columns)
 */
export interface TeamException {
  id: string; // team_exception_id
  team_code: string;
  exception_type_lk: string | null;
  exception_type_name: string | null;
  trade_exception_player_id: number | null;
  trade_exception_player_name: string | null;
  expiration_date: string | null;
  is_expired: boolean | null;

  remaining_2025: number | null;
  remaining_2026: number | null;
  remaining_2027: number | null;
  remaining_2028: number | null;
  remaining_2029: number | null;
}

/**
 * Dead money rows from pcms.dead_money_warehouse (pivoted to year columns)
 */
export interface DeadMoney {
  id: string; // transaction_waiver_amount_id
  team_code: string;
  player_id: number | null;
  player_name: string | null;
  waive_date: string | null;

  cap_2025: number | null;
  cap_2026: number | null;
  cap_2027: number | null;
  cap_2028: number | null;
  cap_2029: number | null;
}

/**
 * Player rights rows from pcms.player_rights_warehouse
 */
export type PlayerRightsKind = "NBA_DRAFT_RIGHTS" | "DLG_RETURNING_RIGHTS";

export interface PlayerRight {
  id: string; // player_id
  player_id: number;
  player_name: string | null;
  league_lk: string | null;

  rights_team_id: number | null;
  rights_team_code: string | null;
  rights_kind: PlayerRightsKind;
  rights_source: string | null;

  source_trade_id: number | null;
  source_trade_date: string | null;

  draft_year: number | null;
  draft_round: number | null;
  draft_pick: number | null;
  draft_team_id: number | null;
  draft_team_code: string | null;

  has_active_nba_contract: boolean | null;
  needs_review: boolean | null;
}

/**
 * Agent data from pcms.agents
 */
export interface Agent {
  id: string;
  name: string;
  agency_id: string | null;
  agency_name: string | null;
  email: string | null;
  phone: string | null;
}

/**
 * Agency data from pcms.agencies
 */
export interface Agency {
  id: string;
  name: string;
  location: string | null;
  website: string | null;
}

/**
 * Sidebar entity types for navigation stack
 */
export type EntityType = "player" | "team" | "agent" | "pick" | "trade" | "buyout";

/**
 * Entity reference for sidebar stack
 */
export interface EntityRef {
  type: EntityType;
  id: string;
  label: string; // Display name for back button context
}

/**
 * Filter state for salary book display
 */
export interface SalaryBookFilters {
  // Display filters
  showCapHolds: boolean;
  showExceptions: boolean;
  showDraftPicks: boolean;
  showDeadMoney: boolean;

  // Financial filters
  showTaxAprons: boolean;
  showCashVsCap: boolean;
  showLuxuryTax: boolean;

  // Contract filters
  showOptions: boolean;
  showIncentives: boolean;
  showTwoWay: boolean;
}

/**
 * Loaded teams state
 */
export interface LoadedTeamsState {
  teams: string[]; // Team codes in scroll order
  activeTeam: string | null; // Currently visible team (scroll-spy)
}
