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
 *
 * Animation pattern (from Silk):
 * - Uses safeToUnmount lifecycle to keep entity visible during exit animation
 * - Entity animates out before unmounting, preventing content flash
 * - TeamContext always renders as base layer — entity overlays on top
 * - All animations are WAAPI-coordinated (no CSS transitions)
 */

import React, { useRef, useEffect, useState } from "react";
import { cx, focusRing } from "@/lib/utils";
import { useShellContext, useSidebarTransition, type SidebarEntity } from "@/state/shell";
import { useTeams } from "../../hooks";
import { animate, durations, easings } from "@/lib/animate";
import { TeamContext } from "./TeamContext";
import { PlayerDetail } from "./PlayerDetail";
import { AgentDetail } from "./AgentDetail";
import { PickDetail } from "./PickDetail";
import { BackButtonTeamBadge } from "./BackButtonTeamBadge";

// ============================================================================
// Constants
// ============================================================================

/** Height of the back button header in pixels */
const HEADER_HEIGHT = 40;

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
 *
 * Animation pattern (Silk-inspired):
 * - All transitions use coordinated WAAPI animations
 * - Header slides left, entity slides right, TeamContext slides up — all together
 * - No CSS transitions that fight with WAAPI
 */
export function SidebarPanel({ className }: SidebarPanelProps) {
  const {
    currentEntity,
    popEntity,
    activeTeam,
  } = useShellContext();

  const {
    stagedEntity,
    transitionState,
    containerRef,
    safeToUnmount,
  } = useSidebarTransition(currentEntity);

  const showEntity = stagedEntity !== null || !safeToUnmount;
  const isEntityMode = currentEntity !== null;
  const isExiting = transitionState === "exiting";

  const { getTeam } = useTeams();
  const team = activeTeam ? getTeam(activeTeam) : null;
  const teamId = team?.team_id ?? null;
  const backLabel = activeTeam || "Back";

  const backButtonRef = useRef<HTMLButtonElement>(null);
  const headerRef = useRef<HTMLDivElement>(null);

  /**
   * Silk Pattern: Layered Coordination
   * 
   * We animate the back button via WAAPI for that high-performance slide,
   * while the header background uses CSS transitions for simplicity.
   */
  useEffect(() => {
    const btn = backButtonRef.current;
    if (!btn) return;

    if (isEntityMode && !isExiting) {
      // ENTERING ENTITY MODE: Back button slides in
      animate(btn, [
        { opacity: 0, transform: "translateX(-12px)" },
        { opacity: 1, transform: "translateX(0)" },
      ], { duration: durations.normal, easing: easings.easeOut });
    } else if (!isEntityMode && isExiting) {
      // EXITING TO TEAM MODE: Back button slides out
      animate(btn, [
        { opacity: 1, transform: "translateX(0)" },
        { opacity: 0, transform: "translateX(-12px)" },
      ], { duration: durations.fast, easing: easings.easeIn });
    }
  }, [isEntityMode, isExiting]);

  return (
    <div
      className={cx(
        "w-[30%] min-w-[320px] max-w-[480px]",
        "border-l border-border",
        "bg-background",
        "overflow-hidden relative", 
        className
      )}
    >
      {/* 
        SILK PATTERN: Absolute Header Overlay
        This sits ON TOP of the content area. It is transparent in team mode
        and becomes opaque in entity mode.
      */}
      <div 
        ref={headerRef}
        className={cx(
          "absolute top-0 left-0 right-0 h-10 px-4 flex items-center z-20",
          "border-b transition-colors duration-200",
          isEntityMode ? "bg-background border-border" : "bg-transparent border-transparent"
        )}
      >
        <button
          ref={backButtonRef}
          type="button"
          onClick={popEntity}
          disabled={!isEntityMode}
          className={cx(
            "flex items-center gap-1.5 text-sm transition-colors",
            "text-muted-foreground hover:text-foreground",
            "disabled:pointer-events-none",
            !isEntityMode && !isExiting ? "opacity-0" : "opacity-100",
            focusRing()
          )}
        >
          <ChevronLeftIcon className="w-4 h-4" />
          <BackButtonTeamBadge
            teamCode={activeTeam}
            teamId={teamId}
            isEntityMode={showEntity}
          />
          <span className="font-medium">{backLabel}</span>
        </button>
      </div>

      {/* 
        CONTENT AREA
        Both layers start at top: 0. 
        TeamContext uses the full height (padding in its own header handles the offset).
        EntityDetail starts with top-14 padding to stay clear of the header.
      */}
      <div className="absolute inset-0 overflow-hidden">
        {/* Base Layer: Team Context (utilizes full height) */}
        <div
          className={cx(
            "absolute inset-0 overflow-y-auto pt-4 px-4 pb-4 transition-opacity duration-300",
            isEntityMode ? "opacity-20 grayscale pointer-events-none" : "opacity-100"
          )}
        >
          <TeamContext />
        </div>

        {/* 
          SILK PATTERN: Persistent Entity Backdrop
          This layer stays solid during entity-to-entity replacements to prevent flicker.
          It only fades out when completely returning to the Team view.
        */}
        <div
          className={cx(
            "absolute inset-0 bg-background z-10 transition-opacity duration-200",
            isEntityMode ? "opacity-100" : "opacity-0 pointer-events-none"
          )}
        />

        {/* Overlay Layer: Entity Detail (Now transparent, uses backdrop above) */}
        {showEntity && stagedEntity && (
          <div
            ref={containerRef}
            className="absolute inset-0 overflow-y-auto z-10"
            data-transition-state={transitionState}
          >
            <div className="pt-14 px-4 pb-4">
              <EntityDetail entity={stagedEntity} />
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
