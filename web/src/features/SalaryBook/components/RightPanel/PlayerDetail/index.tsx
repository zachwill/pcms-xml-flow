/**
 * PlayerDetail — Sidebar entity view for a selected player
 *
 * Shows detailed player contract information when a player is pushed
 * onto the sidebar stack (clicked from PlayerRow).
 *
 * Sections:
 * 1. Player header (photo placeholder, name, team, position)
 * 2. Contract summary (total value, years, bird rights)
 * 3. Year-by-year breakdown (salary, guarantee, option per year)
 * 4. Trade restrictions (if any)
 */

import { cx } from "@/lib/utils";
import { useShellSidebarContext, type PlayerEntity } from "@/features/SalaryBook/shell";
import { usePlayer, useTeams } from "../../../hooks";
import { PlayerHeader } from "./PlayerHeader";
import { ContractSummary } from "./ContractSummary";
import { YearByYearBreakdown, type YearData } from "./YearByYearBreakdown";
import { ContractGuarantees } from "./ContractGuarantees";
import { ContractBonuses } from "./ContractBonuses";
import { TradeRestrictions } from "./TradeRestrictions";
import { PlayerDetailSkeleton } from "./PlayerDetailSkeleton";

// ============================================================================
// Types
// ============================================================================

export interface PlayerDetailProps {
  /** Player entity from sidebar stack */
  entity: PlayerEntity;
  /** Additional className */
  className?: string;
}

// ============================================================================
// Main Component
// ============================================================================

function resolveGuaranteeStatus(
  isFull: boolean | null | undefined,
  isPartial: boolean | null | undefined,
  isNone: boolean | null | undefined
): YearData["guaranteeStatus"] {
  if (isFull) return "FULL";
  if (isPartial) return "PARTIAL";
  if (isNone) return "NONE";
  return null;
}

/**
 * PlayerDetail — Full player contract view for sidebar
 */
export function PlayerDetail({ entity, className }: PlayerDetailProps) {
  const { pushEntity } = useShellSidebarContext();
  const { getTeam } = useTeams();

  const { player, isLoading, error } = usePlayer(entity.playerId);

  const displayTeamCode = player?.team_code ?? entity.teamCode;
  const team = getTeam(displayTeamCode);
  const teamName = team?.name ?? displayTeamCode;

  const handleAgentClick = () => {
    if (player?.agent_id && player?.agent_name) {
      pushEntity({
        type: "agent",
        agentId: player.agent_id,
        agentName: player.agent_name,
      });
    }
  };

  if (isLoading) {
    return <PlayerDetailSkeleton />;
  }

  if (error || !player) {
    return (
      <div className={cx("space-y-4", className)}>
        <PlayerHeader
          playerId={entity.playerId}
          playerName={entity.playerName}
          teamCode={displayTeamCode}
          teamName={teamName}
        />
        <div className="p-4 rounded-lg bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800">
          <div className="text-sm text-red-700 dark:text-red-400">
            {error?.message ?? "Failed to load player data"}
          </div>
        </div>
      </div>
    );
  }

  const years: YearData[] = [
    {
      year: 2025,
      salary: player.cap_2025,
      option: player.option_2025,
      guaranteedAmount: player.guaranteed_amount_2025,
      guaranteeStatus: resolveGuaranteeStatus(
        player.is_fully_guaranteed_2025,
        player.is_partially_guaranteed_2025,
        player.is_non_guaranteed_2025
      ),
      likelyBonus: player.likely_bonus_2025,
      unlikelyBonus: player.unlikely_bonus_2025,
    },
    {
      year: 2026,
      salary: player.cap_2026,
      option: player.option_2026,
      guaranteedAmount: player.guaranteed_amount_2026,
      guaranteeStatus: resolveGuaranteeStatus(
        player.is_fully_guaranteed_2026,
        player.is_partially_guaranteed_2026,
        player.is_non_guaranteed_2026
      ),
      likelyBonus: player.likely_bonus_2026,
      unlikelyBonus: player.unlikely_bonus_2026,
    },
    {
      year: 2027,
      salary: player.cap_2027,
      option: player.option_2027,
      guaranteedAmount: player.guaranteed_amount_2027,
      guaranteeStatus: resolveGuaranteeStatus(
        player.is_fully_guaranteed_2027,
        player.is_partially_guaranteed_2027,
        player.is_non_guaranteed_2027
      ),
      likelyBonus: player.likely_bonus_2027,
      unlikelyBonus: player.unlikely_bonus_2027,
    },
    {
      year: 2028,
      salary: player.cap_2028,
      option: player.option_2028,
      guaranteedAmount: player.guaranteed_amount_2028,
      guaranteeStatus: resolveGuaranteeStatus(
        player.is_fully_guaranteed_2028,
        player.is_partially_guaranteed_2028,
        player.is_non_guaranteed_2028
      ),
      likelyBonus: player.likely_bonus_2028,
      unlikelyBonus: player.unlikely_bonus_2028,
    },
    {
      year: 2029,
      salary: player.cap_2029,
      option: player.option_2029,
      guaranteedAmount: player.guaranteed_amount_2029,
      guaranteeStatus: resolveGuaranteeStatus(
        player.is_fully_guaranteed_2029,
        player.is_partially_guaranteed_2029,
        player.is_non_guaranteed_2029
      ),
      likelyBonus: player.likely_bonus_2029,
      unlikelyBonus: player.unlikely_bonus_2029,
    },
    {
      year: 2030,
      salary: player.cap_2030,
      option: player.option_2030,
      guaranteedAmount: player.guaranteed_amount_2030,
      guaranteeStatus: resolveGuaranteeStatus(
        player.is_fully_guaranteed_2030,
        player.is_partially_guaranteed_2030,
        player.is_non_guaranteed_2030
      ),
      likelyBonus: player.likely_bonus_2030,
      unlikelyBonus: player.unlikely_bonus_2030,
    },
  ];

  const totalValue = years.reduce((sum, y) => sum + Number(y.salary ?? 0), 0);
  const contractYears = years.filter(
    (y) => y.salary !== null && y.salary > 0
  ).length;

  return (
    <div className={cx("space-y-6", className)}>
      <PlayerHeader
        playerId={player.player_id}
        playerName={player.player_name}
        teamCode={player.team_code}
        teamName={teamName}
        position={player.position}
        age={player.age}
        experience={player.years_of_service}
      />

      <ContractSummary
        totalValue={totalValue}
        contractYears={contractYears}
        isTwoWay={player.is_two_way}
        agentName={player.agent_name}
        agencyName={player.agency_name}
        onAgentClick={player.agent_id ? handleAgentClick : undefined}
        contractType={player.contract_type_lookup_value ?? player.contract_type_code}
        signedUsing={player.signed_method_lookup_value}
        exceptionType={player.exception_type_lookup_value}
        minContract={player.is_min_contract ? player.min_contract_lookup_value : null}
        birdRights={player.bird_rights}
      />

      <YearByYearBreakdown years={years} />

      <ContractGuarantees protections={player.contract_protections} />

      <ContractBonuses bonuses={player.contract_bonuses} />

      <TradeRestrictions
        isNoTrade={player.is_no_trade}
        isTradeBonus={player.is_trade_bonus}
        tradeBonusPercent={player.trade_bonus_percent}
        isConsentRequired={player.is_trade_consent_required_now}
        isPreconsented={player.is_trade_preconsented}
        isPoisonPill={player.is_poison_pill}
      />
    </div>
  );
}
