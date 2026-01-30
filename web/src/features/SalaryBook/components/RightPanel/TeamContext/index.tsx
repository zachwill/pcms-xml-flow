/**
 * TeamContext — Default sidebar view showing active team from scroll-spy
 *
 * Displays when no entity is pushed onto the sidebar stack.
 * Shows team info with cap outlook (financial health) data.
 * Updates automatically as user scrolls to different teams.
 *
 * Tabs:
 * - Cap: financial health, cap space projections, tax thresholds
 * - Draft: placeholder for future picks/rights view
 * - Injuries: placeholder for future availability view
 * - Stats: record, standings, efficiency metrics (future phase)
 */

import { useState, memo } from "react";
import { cx } from "@/lib/utils";
import { useShellScrollContext } from "@/features/SalaryBook/shell";
import { useTeamSalary, useTeams, useTwoWayCapacity } from "../../../hooks";
import { TeamContextHeader } from "./TeamContextHeader";
import { TabToggle, type TabId } from "./TabToggle";
import { CapOutlookTab } from "./CapOutlookTab";
import { DraftTab } from "./DraftTab";
import { InjuriesTab } from "./InjuriesTab";
import { TeamStatsTab } from "./TeamStatsTab";
import { TeamContextSkeleton, EmptyState } from "./TeamContextSkeleton";

// ============================================================================
// Types
// ============================================================================

export interface TeamContextProps {
  /** Optional: override the team code (otherwise uses activeTeam from scroll-spy) */
  teamCode?: string | null;
  /** Additional className */
  className?: string;
}

// ============================================================================
// Main Component
// ============================================================================

/**
 * TeamContext — Shows active team's financial overview
 *
 * Content:
 * - Team header (logo, name, conference)
 * - Tab toggle (Cap / Draft / Injuries / Stats)
 * - Cap: total salary, cap space, tax status, room under thresholds, projections
 * - Draft: placeholder for pick inventory + protections
 * - Injuries: placeholder for availability report
 * - Stats: placeholder for future phase (record, standings, efficiency)
 *
 * Future additions:
 * - AI Analysis insights
 */
export function TeamContext({ teamCode: teamCodeProp, className }: TeamContextProps) {
  const { activeTeam } = useShellScrollContext();
  const { getTeam, isLoading: teamsLoading } = useTeams();

  // Tab state
  const [activeTab, setActiveTab] = useState<TabId>("cap");

  // Use prop if provided, otherwise fall back to scroll-spy active team
  const teamCode = teamCodeProp ?? activeTeam;

  // Fetch team salary data
  const {
    salaryByYear,
    currentYearTotal,
    currentYearCapSpace,
    isLoading: salaryLoading,
  } = useTeamSalary(teamCode);

  // Fetch two-way capacity data
  const { capacity: twoWayCapacity } = useTwoWayCapacity(teamCode);

  // Get team metadata
  const team = teamCode ? getTeam(teamCode) : undefined;

  // Handle no active team
  if (!teamCode) {
    return <EmptyState />;
  }

  // Show skeleton while loading
  if (teamsLoading || (salaryLoading && !currentYearTotal)) {
    return <TeamContextSkeleton />;
  }

  // Get current year salary data for detailed display
  const currentSalary = salaryByYear.get(2025);

  return (
    <div className={cx("space-y-4", className)}>
      {/* Team Header */}
      <TeamContextHeader
        teamCode={teamCode}
        teamId={team?.team_id ?? null}
        teamName={team?.name ?? `Team ${teamCode}`}
        conference={team?.conference ?? "EAST"}
      />

      {/* Tab Toggle */}
      <TabToggle activeTab={activeTab} onTabChange={setActiveTab} />

      {/* Tab Content */}
      {activeTab === "cap" && (
        <CapOutlookTab
          currentYearTotal={currentYearTotal}
          currentYearCapSpace={currentYearCapSpace}
          currentSalary={currentSalary}
          salaryByYear={salaryByYear}
          twoWayCapacity={twoWayCapacity}
        />
      )}
      {activeTab === "draft" && <DraftTab teamCode={teamCode} />}
      {activeTab === "injuries" && <InjuriesTab teamCode={teamCode} />}
      {activeTab === "stats" && <TeamStatsTab teamCode={teamCode} />}
    </div>
  );
}

/**
 * Memoized TeamContext - prevents re-renders when sidebar mode changes
 * but teamCode hasn't changed
 */
export const MemoizedTeamContext = memo(TeamContext);
