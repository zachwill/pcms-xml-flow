/**
 * Hooks Barrel Export
 *
 * Exports all hooks for the Salary Book feature.
 */

export {
  useScrollSpy,
  useSidebarStack,
  type EntityType,
  type SidebarEntity,
  type SidebarMode,
  type PlayerEntity,
  type AgentEntity,
  type PickEntity,
  type TeamEntity,
  type ScrollState,
  type ScrollSpyResult,
} from "@/features/SalaryBook/shell";
export { useTeams, type UseTeamsReturn } from "./useTeams";
export { usePlayers, type UsePlayersReturn } from "./usePlayers";
export { useTeamSalary, type UseTeamSalaryReturn } from "./useTeamSalary";
export { usePicks, type UsePicksReturn } from "./usePicks";
export { useCapHolds, type UseCapHoldsReturn } from "./useCapHolds";
export { useExceptions, type UseExceptionsReturn } from "./useExceptions";
export { useDeadMoney, type UseDeadMoneyReturn } from "./useDeadMoney";
export {
  useAgent,
  type UseAgentReturn,
  type AgentDetail,
  type AgentClientPlayer,
} from "./useAgent";
export { usePlayer, type UsePlayerReturn, type PlayerDetailResponse } from "./usePlayer";
export {
  usePickDetail,
  type UsePickDetailReturn,
  type PickDetailParams,
  type PickDetailResponse,
} from "./usePickDetail";
export {
  useTwoWayCapacity,
  type UseTwoWayCapacityReturn,
  type TwoWayCapacity,
} from "./useTwoWayCapacity";
