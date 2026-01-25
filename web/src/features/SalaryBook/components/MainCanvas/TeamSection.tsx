/**
 * TeamSection — Wrapper for one team's salary book
 *
 * Responsibilities:
 * - Fetches team data (players, salary totals, draft picks)
 * - Registers with scroll-spy for active team detection
 * - Builds the iOS Contacts-style sticky header group (TeamHeader + TableHeader)
 * - Delegates horizontal scroll + filtering to SalaryTable
 */

import React, { useCallback } from "react";
import { cx } from "@/lib/utils";
import { useShellContext, type PlayerEntity, type AgentEntity, type PickEntity } from "@/state/shell";
import { useFilters } from "@/state/filters";
import {
  usePlayers,
  useTeamSalary,
  usePicks,
  useCapHolds,
  useExceptions,
  useDeadMoney,
  useTeams,
} from "../../hooks";
import type { SalaryBookPlayer, DraftPick } from "../../data";
import { TeamHeader } from "./TeamHeader";
import { TableHeader } from "./TableHeader";
import { SalaryTable } from "./SalaryTable";

// ============================================================================
// Types
// ============================================================================

interface TeamSectionProps {
  /** 3-letter team code (e.g., "BOS", "LAL") */
  teamCode: string;
}

// ============================================================================
// Helper Components
// ============================================================================

function TeamSectionSkeleton({ teamCode }: { teamCode: string }) {
  return (
    <div className="min-h-[300px] animate-pulse">
      {/* Header skeleton */}
      <div className="h-12 px-4 flex items-center gap-3 bg-muted/50 border-b border-border">
        <div className="w-8 h-8 rounded bg-muted" />
        <div className="h-5 w-32 bg-muted rounded" />
      </div>
      {/* Table header skeleton */}
      <div className="h-10 px-4 bg-muted/20 border-b border-border/50" />
      {/* Row skeletons */}
      {[1, 2, 3, 4].map((i) => (
        <div key={i} className="h-14 px-4 border-b border-border/50">
          <div className="h-4 w-full bg-muted/30 rounded mt-5" />
        </div>
      ))}
    </div>
  );
}

function TeamSectionError({
  teamCode,
  error,
  onRetry,
}: {
  teamCode: string;
  error: Error;
  onRetry: () => void;
}) {
  return (
    <div className="min-h-[200px] flex flex-col items-center justify-center gap-3 text-center p-6">
      <div className="text-destructive text-sm font-medium">
        Failed to load {teamCode} data
      </div>
      <div className="text-muted-foreground text-xs max-w-md">
        {error.message}
      </div>
      <button
        onClick={onRetry}
        className={cx(
          "px-3 py-1.5 text-xs font-medium rounded",
          "bg-muted hover:bg-muted/80 transition-colors"
        )}
      >
        Retry
      </button>
    </div>
  );
}

// ============================================================================
// Main Component
// ============================================================================

export function TeamSection({ teamCode }: TeamSectionProps) {
  const { registerSection, activeTeam, pushEntity } = useShellContext();
  const { filters } = useFilters();

  const { getTeam } = useTeams();

  const {
    players,
    isLoading: playersLoading,
    error: playersError,
    refetch: refetchPlayers,
  } = usePlayers(teamCode);

  const {
    salaryByYear,
    currentYearTotal,
    currentYearCapSpace,
    getSalaryForYear,
    isLoading: salaryLoading,
  } = useTeamSalary(teamCode);

  // Get current year (2025) salary data for KPIs
  const currentYearSalary = getSalaryForYear(2025);

  const { picks, isLoading: picksLoading } = usePicks(teamCode);

  const { capHolds, isLoading: capHoldsLoading } = useCapHolds(
    teamCode,
    filters.display.capHolds
  );

  const { exceptions, isLoading: exceptionsLoading } = useExceptions(
    teamCode,
    filters.display.exceptions
  );

  const { deadMoney, isLoading: deadMoneyLoading } = useDeadMoney(
    teamCode,
    filters.display.deadMoney
  );

  const team = getTeam(teamCode);
  const isActive = activeTeam === teamCode;
  const isLoading =
    playersLoading ||
    salaryLoading ||
    picksLoading ||
    capHoldsLoading ||
    exceptionsLoading ||
    deadMoneyLoading;

  // ========================================================================
  // Sidebar navigation handlers (memoized to prevent PlayerRow re-renders)
  // ========================================================================

  const handlePlayerClick = useCallback((player: SalaryBookPlayer) => {
    const entity: PlayerEntity = {
      type: "player",
      playerId: parseInt(player.id, 10) || 0,
      playerName: player.player_name,
      teamCode: player.team_code,
    };
    pushEntity(entity);
  }, [pushEntity]);

  const handleAgentClick = useCallback((e: React.MouseEvent, player: SalaryBookPlayer) => {
    e.stopPropagation();
    if (!player.agent_id || !player.agent_name) return;

    const entity: AgentEntity = {
      type: "agent",
      agentId: parseInt(player.agent_id, 10) || 0,
      agentName: player.agent_name,
    };
    pushEntity(entity);
  }, [pushEntity]);

  const handlePickClick = useCallback((pick: DraftPick) => {
    const entity: PickEntity = {
      type: "pick",
      teamCode: pick.team_code,
      draftYear: pick.year,
      draftRound: pick.round,
      rawFragment: `${pick.origin_team_code} Round ${pick.round}`,
    };
    pushEntity(entity);
  }, [pushEntity]);

  // ========================================================================
  // Loading / Error
  // ========================================================================

  if (isLoading && players.length === 0) {
    return (
      <div
        ref={(el) => registerSection(teamCode, el)}
        data-team={teamCode}
        className="border-b border-border"
      >
        <TeamSectionSkeleton teamCode={teamCode} />
      </div>
    );
  }

  if (playersError) {
    return (
      <div
        ref={(el) => registerSection(teamCode, el)}
        data-team={teamCode}
        className="border-b border-border"
      >
        <TeamSectionError teamCode={teamCode} error={playersError} onRetry={refetchPlayers} />
      </div>
    );
  }

  // ========================================================================
  // Render
  // ========================================================================

  return (
    <div
      ref={(el) => registerSection(teamCode, el)}
      data-team={teamCode}
      className="border-b border-border"
    >
      <SalaryTable
        teamHeader={
          <TeamHeader
            teamCode={teamCode}
            teamId={team?.team_id ?? null}
            teamName={team?.name || teamCode}
            conference={
              team?.conference === "EAST"
                ? "Eastern Conference"
                : "Western Conference"
            }
            currentYearTotal={currentYearTotal}
            currentYearCapSpace={currentYearCapSpace}
            roomUnderTax={currentYearSalary?.room_under_tax ?? null}
            roomUnderFirstApron={currentYearSalary?.room_under_first_apron ?? null}
            roomUnderSecondApron={currentYearSalary?.room_under_second_apron ?? null}
            rosterCount={currentYearSalary?.roster_row_count ?? null}
            isActive={isActive}
          />
        }
        players={players}
        picks={picks}
        capHolds={capHolds}
        exceptions={exceptions}
        deadMoney={deadMoney}
        salaryByYear={salaryByYear}
        filters={filters}
        onPlayerClick={handlePlayerClick}
        onAgentClick={handleAgentClick}
        onPickClick={handlePickClick}
      />
    </div>
  );
}
