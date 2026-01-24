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
export type EntityType = "player" | "team" | "agent" | "pick";

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
