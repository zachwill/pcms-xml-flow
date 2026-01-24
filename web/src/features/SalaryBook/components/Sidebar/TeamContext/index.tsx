/**
 * TeamContext — Default sidebar view showing active team from scroll-spy
 *
 * Displays when no entity is pushed onto the sidebar stack.
 * Shows team info with cap outlook (financial health) data.
 * Updates automatically as user scrolls to different teams.
 *
 * Two tabs:
 * - Cap Outlook: financial health, cap space projections, tax thresholds
 * - Team Stats: record, standings, efficiency metrics (future phase)
 */

import { useState, memo } from "react";
import { cx } from "@/lib/utils";
import { useSalaryBookContext } from "../../../SalaryBook";
import { useTeamSalary, useTeams } from "../../../hooks";
import { TeamContextHeader } from "./TeamContextHeader";
import { TabToggle, type TabId } from "./TabToggle";
import { CapOutlookTab } from "./CapOutlookTab";
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
 * - Tab toggle (Cap Outlook / Team Stats)
 * - Cap Outlook: total salary, cap space, tax status, room under thresholds, projections
 * - Team Stats: placeholder for future phase (record, standings, efficiency)
 *
 * Future additions:
 * - AI Analysis insights
 */
export function TeamContext({ teamCode: teamCodeProp, className }: TeamContextProps) {
  const { activeTeam } = useSalaryBookContext();
  const { getTeam, isLoading: teamsLoading } = useTeams();

  // Tab state
  const [activeTab, setActiveTab] = useState<TabId>("cap-outlook");

  // Use prop if provided, otherwise fall back to scroll-spy active team
  const teamCode = teamCodeProp ?? activeTeam;

  // Fetch team salary data
  const {
    salaryByYear,
    currentYearTotal,
    currentYearCapSpace,
    isLoading: salaryLoading,
  } = useTeamSalary(teamCode);

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
        teamName={team?.name ?? `Team ${teamCode}`}
        conference={team?.conference ?? "EAST"}
      />

      {/* Tab Toggle */}
      <TabToggle activeTab={activeTab} onTabChange={setActiveTab} />

      {/* Tab Content */}
      {activeTab === "cap-outlook" ? (
        <CapOutlookTab
          currentYearTotal={currentYearTotal}
          currentYearCapSpace={currentYearCapSpace}
          currentSalary={currentSalary}
          salaryByYear={salaryByYear}
        />
      ) : (
        <TeamStatsTab teamCode={teamCode} />
      )}
    </div>
  );
}

/**
 * Memoized TeamContext - prevents re-renders when sidebar mode changes
 * but teamCode hasn't changed
 */
export const MemoizedTeamContext = memo(TeamContext);
