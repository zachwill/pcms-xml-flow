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
import { useSalaryBookContext } from "../../../SalaryBook";
import { usePlayer, useTeams } from "../../../hooks";
import type { PlayerEntity } from "../../../hooks";
import { PlayerHeader } from "./PlayerHeader";
import { ContractSummary } from "./ContractSummary";
import { YearByYearBreakdown, type YearData } from "./YearByYearBreakdown";
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

/**
 * PlayerDetail — Full player contract view for sidebar
 */
export function PlayerDetail({ entity, className }: PlayerDetailProps) {
  const { pushEntity } = useSalaryBookContext();
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
    { year: 2025, salary: player.cap_2025, option: player.option_2025 },
    { year: 2026, salary: player.cap_2026, option: player.option_2026 },
    { year: 2027, salary: player.cap_2027, option: player.option_2027 },
    { year: 2028, salary: player.cap_2028, option: player.option_2028 },
    { year: 2029, salary: player.cap_2029, option: player.option_2029 },
    { year: 2030, salary: player.cap_2030, option: player.option_2030 },
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
      />

      <YearByYearBreakdown years={years} />

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
