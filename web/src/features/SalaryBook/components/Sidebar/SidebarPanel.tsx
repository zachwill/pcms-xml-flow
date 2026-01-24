/**
 * SidebarPanel — Main sidebar container with intentionally-shallow navigation
 *
 * Modes:
 * - DEFAULT MODE: Shows team context from scroll-spy active team
 * - ENTITY MODE: Shows a single detail view (player/agent/pick/team)
 *
 * Key behavior:
 * - Clicking around swaps the detail view; it does NOT build up a deep "back" history.
 * - Back returns to the team context in a single step (except when a team is pinned).
 */

import { cx, focusRing } from "@/lib/utils";
import { useSalaryBookContext } from "../../SalaryBook";
import type { SidebarEntity } from "../../hooks";
import { TeamContext } from "./TeamContext";
import { PlayerDetail } from "./PlayerDetail";
import { AgentDetail } from "./AgentDetail";
import { PickDetail } from "./PickDetail";

// ============================================================================
// Icon Components
// ============================================================================

function ChevronLeftIcon({ className }: { className?: string }) {
  return (
    <svg
      className={className}
      fill="none"
      stroke="currentColor"
      viewBox="0 0 24 24"
      aria-hidden="true"
    >
      <path
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeWidth={2}
        d="M15 19l-7-7 7-7"
      />
    </svg>
  );
}

// ============================================================================
// Placeholder Detail Components
// ============================================================================

/**
 * Placeholder for team entity detail view (pinned team)
 * Will be replaced by TeamDetail.tsx
 */
function TeamDetailPlaceholder({ entity }: { entity: Extract<SidebarEntity, { type: "team" }> }) {
  return (
    <div className="space-y-4">
      <div className="flex items-center gap-3">
        <div className="w-12 h-12 rounded-lg bg-muted flex items-center justify-center text-lg font-mono font-bold">
          {entity.teamCode}
        </div>
        <div>
          <div className="font-semibold">{entity.teamName}</div>
          <div className="text-sm text-muted-foreground">Team Report (Pinned)</div>
        </div>
      </div>

      <div className="border-t border-border pt-4">
        <div className="text-xs font-medium uppercase tracking-wide text-muted-foreground mb-2">
          Team Overview
        </div>
        <div className="p-3 bg-muted/30 rounded-lg text-sm text-muted-foreground">
          Full team report will be displayed here. This view is pinned and won't change on scroll.
        </div>
      </div>
    </div>
  );
}

// ============================================================================
// Entity Detail Router
// ============================================================================

/**
 * Routes to the correct entity detail component based on entity type
 */
function EntityDetail({ entity }: { entity: SidebarEntity }) {
  switch (entity.type) {
    case "player":
      return <PlayerDetail entity={entity} />;
    case "agent":
      return <AgentDetail entity={entity} />;
    case "pick":
      return <PickDetail entity={entity} />;
    case "team":
      return <TeamDetailPlaceholder entity={entity} />;
    default:
      // TypeScript exhaustiveness check
      const _exhaustive: never = entity;
      return null;
  }
}

// ============================================================================
// SidebarPanel
// ============================================================================

export interface SidebarPanelProps {
  /** Additional className for the panel container */
  className?: string;
}

/**
 * SidebarPanel — Intelligence panel with stack-based entity navigation
 *
 * State Machine:
 * - Empty stack (default mode): Shows scroll-spy active team context
 * - Stack has items (entity mode): Shows top entity detail with Back button
 *
 * Back navigation returns to CURRENT viewport team via scroll-spy,
 * not the team where you originally started browsing.
 */
export function SidebarPanel({ className }: SidebarPanelProps) {
  const {
    sidebarMode,
    currentEntity,
    popEntity,
    canGoBack,
  } = useSalaryBookContext();

  return (
    <div
      className={cx(
        "w-[30%] min-w-[320px] max-w-[480px]",
        "border-l border-border",
        "bg-background",
        "flex flex-col",
        "overflow-hidden",
        className
      )}
    >
      {/* Back button header (only in entity mode) */}
      {canGoBack && (
        <div className="flex-shrink-0 h-10 px-4 flex items-center border-b border-border">
          <button
            type="button"
            onClick={popEntity}
            className={cx(
              "flex items-center gap-1 text-sm",
              "text-muted-foreground hover:text-foreground",
              "transition-colors duration-150",
              focusRing()
            )}
          >
            <ChevronLeftIcon className="w-4 h-4" />
            <span>Back</span>
          </button>
        </div>
      )}

      {/* Sidebar content - independent scroll */}
      <div className="flex-1 overflow-y-auto p-4">
        {sidebarMode === "entity" && currentEntity ? (
          <EntityDetail entity={currentEntity} />
        ) : (
          <TeamContext />
        )}
      </div>
    </div>
  );
}
