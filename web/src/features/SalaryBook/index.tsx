/**
 * SalaryBook Feature Barrel Export
 *
 * Exports the main SalaryBook component, all hooks, and all types.
 * This is the single entry point for consuming the Salary Book feature.
 *
 * Usage:
 *   import { SalaryBook } from "@/features/SalaryBook";
 *   import { useScrollSpy, useSidebarStack } from "@/features/SalaryBook";
 *   import type { SalaryBookPlayer, Team } from "@/features/SalaryBook";
 */

// Main components
export { SalaryBook } from "./SalaryBook";
export { SalaryBookPage } from "./pages/SalaryBookPage";

// Hooks
export {
  useScrollSpy,
  useSidebarStack,
  useTradeMachineContext,
  type TradeMachineContextValue,
  type EntityType,
  type SidebarEntity,
  type SidebarMode,
  type PlayerEntity,
  type AgentEntity,
  type PickEntity,
  type TeamEntity,
  type TradeEntity,
  type BuyoutEntity,
} from "./hooks";

// Data types
export type {
  // Core entities
  SalaryBookPlayer,
  Team,
  TeamSalary,
  TradeMode,
  TradePlayer,
  TradeState,
  TradeEvaluationRequest,
  TradeEvaluationRequestTeam,
  TradeEvaluationResponse,
  TradeEvaluationTeam,
  TradeReasonCode,
  BuyoutScenarioRequest,
  BuyoutScenarioResponse,
  BuyoutScenarioRow,
  BuyoutScenarioTotals,
  BuyoutStretchSummary,
  BuyoutStretchSchedule,
  SetoffAmountRequest,
  SetoffAmountResponse,
  DraftPick,
  DraftPickSummary,
  PlayerRight,
  PlayerRightsKind,
  Agent,
  Agency,

  // Contract types
  ContractOption,
  GuaranteeType,
  BirdRights,
  FreeAgencyType,

  // UI state types
  Conference,
  EntityRef,
  SalaryBookFilters,
  LoadedTeamsState,
} from "./data";
