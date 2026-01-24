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
 * 5. AI insights placeholder
 */

import { useState, useEffect } from "react";
import { cx } from "@/lib/utils";
import { useSalaryBookContext } from "../../../SalaryBook";
import { useTeams } from "../../../hooks";
import type { PlayerEntity } from "../../../hooks";
import { AIInsightsPlaceholder } from "../../shared";
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

/**
 * Player API response from /api/salary-book/player/:playerId
 */
interface PlayerApiResponse {
  player_id: number;
  player_name: string;
  team_code: string;
  age: number | null;
  years_of_service: number | null;
  cap_2025: number | null;
  cap_2026: number | null;
  cap_2027: number | null;
  cap_2028: number | null;
  cap_2029: number | null;
  cap_2030: number | null;
  option_2025: string | null;
  option_2026: string | null;
  option_2027: string | null;
  option_2028: string | null;
  option_2029: string | null;
  option_2030: string | null;
  agent_id: number | null;
  agent_name: string | null;
  agency_id: number | null;
  agency_name: string | null;
  is_two_way: boolean;
  is_no_trade: boolean;
  is_trade_bonus: boolean;
  is_trade_consent_required_now: boolean;
  is_trade_preconsented: boolean;
  player_consent_lk: string | null;
}

// ============================================================================
// Main Component
// ============================================================================

/**
 * PlayerDetail — Full player contract view for sidebar
 *
 * Fetches fresh player data from API to ensure we have complete information.
 * Shows contract breakdown, year-by-year salary, trade restrictions, and
 * an AI insights placeholder.
 */
export function PlayerDetail({ entity, className }: PlayerDetailProps) {
  const { pushEntity } = useSalaryBookContext();
  const { getTeam } = useTeams();

  // State for fetched player data
  const [player, setPlayer] = useState<PlayerApiResponse | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<Error | null>(null);

  // Fetch player data
  useEffect(() => {
    async function fetchPlayer() {
      setIsLoading(true);
      setError(null);

      try {
        const response = await fetch(
          `/api/salary-book/player/${entity.playerId}`
        );
        if (!response.ok) {
          throw new Error(`Failed to fetch player: ${response.status}`);
        }
        const data = await response.json();
        setPlayer(data);
      } catch (err) {
        setError(err instanceof Error ? err : new Error(String(err)));
      } finally {
        setIsLoading(false);
      }
    }

    fetchPlayer();
  }, [entity.playerId]);

  // Get team info
  const team = getTeam(entity.teamCode);
  const teamName = team?.name ?? entity.teamCode;

  // Handle agent click — push agent entity onto stack
  const handleAgentClick = () => {
    if (player?.agent_id && player?.agent_name) {
      pushEntity({
        type: "agent",
        agentId: player.agent_id,
        agentName: player.agent_name,
      });
    }
  };

  // Show skeleton while loading
  if (isLoading) {
    return <PlayerDetailSkeleton />;
  }

  // Show error state
  if (error || !player) {
    return (
      <div className={cx("space-y-4", className)}>
        <PlayerHeader
          playerName={entity.playerName}
          teamCode={entity.teamCode}
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

  // Bun SQL can return Postgres `numeric` values as strings.
  // Coerce to numbers here so we don't accidentally string-concatenate when summing.
  const asNumber = (value: unknown): number | null => {
    if (value === null || value === undefined) return null;
    const n = Number(value);
    return Number.isFinite(n) ? n : null;
  };

  // Build year-by-year data
  const years: YearData[] = [
    { year: 2025, salary: asNumber(player.cap_2025), option: player.option_2025 },
    { year: 2026, salary: asNumber(player.cap_2026), option: player.option_2026 },
    { year: 2027, salary: asNumber(player.cap_2027), option: player.option_2027 },
    { year: 2028, salary: asNumber(player.cap_2028), option: player.option_2028 },
    { year: 2029, salary: asNumber(player.cap_2029), option: player.option_2029 },
    { year: 2030, salary: asNumber(player.cap_2030), option: player.option_2030 },
  ];

  // Calculate contract totals
  const totalValue = years.reduce((sum, y) => sum + Number(y.salary ?? 0), 0);
  const contractYears = years.filter(
    (y) => y.salary !== null && y.salary > 0
  ).length;

  return (
    <div className={cx("space-y-6", className)}>
      {/* Player Header */}
      <PlayerHeader
        playerName={player.player_name}
        teamCode={player.team_code}
        teamName={teamName}
        age={player.age}
        experience={player.years_of_service}
      />

      {/* Contract Summary */}
      <ContractSummary
        totalValue={totalValue}
        contractYears={contractYears}
        isTwoWay={player.is_two_way}
        agentName={player.agent_name}
        agencyName={player.agency_name}
        onAgentClick={player.agent_id ? handleAgentClick : undefined}
      />

      {/* Year-by-Year Breakdown */}
      <YearByYearBreakdown years={years} />

      {/* Trade Restrictions */}
      <TradeRestrictions
        isNoTrade={player.is_no_trade}
        isTradeBonus={player.is_trade_bonus}
        isConsentRequired={player.is_trade_consent_required_now}
        isPreconsented={player.is_trade_preconsented}
      />

      {/* AI Insights Placeholder */}
      <AIInsightsPlaceholder
        description="AI-powered contract analysis, extension eligibility, trade value assessment, and cap impact projections coming soon."
      />
    </div>
  );
}
