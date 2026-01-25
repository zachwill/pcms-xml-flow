/**
 * TeamHeader — Sticky team header with name, logo, and KPI cards
 *
 * Part of the iOS Contacts-style sticky behavior. This header sticks to
 * the top while scrolling within a team section and gets pushed off by
 * the next team's header.
 *
 * Features:
 * - Team logo placeholder (3-letter code)
 * - Team name (clickable to push Team entity)
 * - Conference label (underneath team name)
 * - KPI cards: Room under Tax/Apron 1/Apron 2, Roster count, etc.
 * - Opaque background to prevent content bleed-through
 */

import React from "react";
import { cx, formatters } from "@/lib/utils";
import { useShellContext, type TeamEntity } from "@/state/shell";

// ============================================================================
// Types
// ============================================================================

export interface TeamHeaderProps {
  /** 3-letter team code (e.g., "BOS", "LAL") */
  teamCode: string;
  /** NBA team_id used by official CDN assets (logos, etc.) */
  teamId?: number | null;
  /** Full team name (e.g., "Boston Celtics") */
  teamName: string;
  /** Conference display text (e.g., "Eastern Conference") */
  conference: string;
  /** Current year total salary (for mini-totals) */
  currentYearTotal: number | null;
  /** Current year cap space (for mini-totals) */
  currentYearCapSpace: number | null;
  /** Room under tax line */
  roomUnderTax: number | null;
  /** Room under first apron */
  roomUnderFirstApron: number | null;
  /** Room under second apron */
  roomUnderSecondApron: number | null;
  /** Number of roster players */
  rosterCount: number | null;
  /** Whether this team is currently active (scroll-spy) */
  isActive?: boolean;
}

// ============================================================================
// Component
// ============================================================================

// ============================================================================
// KPI Card Component
// ============================================================================

interface KpiCardProps {
  label: string;
  value: string;
  title?: string;
  /** Optional color variant for the value */
  variant?: "default" | "positive" | "negative";
}

function KpiCard({ label, value, title, variant = "default" }: KpiCardProps) {
  const valueColorClass = {
    default: "text-foreground",
    positive: "text-green-600 dark:text-green-400",
    negative: "text-red-500",
  }[variant];

  return (
    <div
      className={cx(
        // Size: match salary column width (w-24 = 96px)
        "w-24 h-10",
        // Dark background with minimal border-radius
        "bg-zinc-200/80 dark:bg-zinc-700/80 rounded",
        // Two-level layout: label on top, value below
        "flex flex-col items-center justify-center",
        // Text styling
        "text-center"
      )}
      title={title}
    >
      <span className="text-[9px] uppercase tracking-wide text-muted-foreground font-medium leading-none">
        {label}
      </span>
      <span className={cx("text-xs tabular-nums font-semibold leading-tight mt-0.5", valueColorClass)}>
        {value}
      </span>
    </div>
  );
}

// ============================================================================
// Main Component
// ============================================================================

export function TeamHeader({
  teamCode,
  teamId,
  teamName,
  conference,
  currentYearTotal,
  currentYearCapSpace,
  roomUnderTax,
  roomUnderFirstApron,
  roomUnderSecondApron,
  rosterCount,
  isActive = false,
}: TeamHeaderProps) {
  const { pushEntity } = useShellContext();

  const [logoErrored, setLogoErrored] = React.useState(false);

  const logoUrl = teamId
    ? `https://cdn.nba.com/logos/nba/${teamId}/primary/L/logo.svg`
    : null;

  React.useEffect(() => {
    // Reset error state when switching teams so we retry loading the logo.
    setLogoErrored(false);
  }, [teamId]);

  // Handle team name click → push Team entity to sidebar
  const handleTeamClick = () => {
    const entity: TeamEntity = {
      type: "team",
      teamCode,
      teamName,
    };
    pushEntity(entity);
  };

  // Format room values (show +/- sign)
  const formatRoom = (value: number | null): string => {
    if (value === null) return "—";
    return formatters.compactCurrency(value);
  };

  return (
    <div
      className={cx(
        // Layout - taller to accommodate KPI cards
        "h-14 px-4 flex items-center",
        // Border
        "border-b border-border"
      )}
      style={{ backgroundColor: "var(--muted, #f4f4f5)" }}
    >
      {/* Left section: Logo + Team name — fixed width to align with Player Info column */}
      <div className="w-[190px] shrink-0 flex items-center gap-3">
        {/* Team logo */}
        <div
          className={cx(
            // Match player headshot size (w-8 h-8)
            "w-8 h-8 rounded flex items-center justify-center flex-shrink-0",
            "bg-background border border-border",
            // Prevent SVGs from overflowing and keep things centered
            "overflow-hidden"
          )}
        >
          {logoUrl && !logoErrored ? (
            <img
              src={logoUrl}
              alt={`${teamName} logo`}
              className="w-full h-full object-contain"
              onError={() => setLogoErrored(true)}
            />
          ) : (
            <span
              className="text-[10px] font-mono font-bold uppercase tracking-tight"
              aria-hidden="true"
              title="Team logo unavailable"
            >
              {teamCode}
            </span>
          )}
        </div>

        {/* Team name + Conference (stacked vertically) */}
        <div className="flex flex-col justify-center min-w-0">
          <button
            onClick={handleTeamClick}
            className={cx(
              "font-semibold text-sm leading-tight text-left",
              "hover:text-primary transition-colors",
              "focus:outline-none focus-visible:underline focus-visible:text-primary"
            )}
          >
            {teamName}
          </button>
          {/* Conference label underneath */}
          <span className="text-[10px] text-muted-foreground leading-tight">
            {conference}
          </span>
        </div>
      </div>

      {/* KPI Cards - aligned with year columns below */}
      <div className="flex items-center gap-2">
        {/* Roster Count - above 25-26 */}
        {rosterCount !== null && (
          <KpiCard
            label="Roster"
            value={`${rosterCount}`}
            title="Number of roster players"
          />
        )}

        {/* Total Salary - above 26-27 */}
        {currentYearTotal !== null && (
          <KpiCard
            label="Total"
            value={formatters.compactCurrency(currentYearTotal)}
            title="Current year total salary"
          />
        )}

        {/* Cap Space - above 27-28 (green if positive) */}
        {currentYearCapSpace !== null && (
          <KpiCard
            label="Cap Space"
            value={`${currentYearCapSpace >= 0 ? "+" : ""}${formatters.compactCurrency(currentYearCapSpace)}`}
            title="Cap space (positive = room, negative = over cap)"
            variant={currentYearCapSpace > 0 ? "positive" : "default"}
          />
        )}

        {/* Room Under Tax - above 28-29 (red if negative) */}
        {roomUnderTax !== null && (
          <KpiCard
            label="Tax Room"
            value={formatRoom(roomUnderTax)}
            title="Room under luxury tax line"
            variant={roomUnderTax < 0 ? "negative" : "default"}
          />
        )}

        {/* Room Under 1st Apron - above 29-30 (red if negative) */}
        {roomUnderFirstApron !== null && (
          <KpiCard
            label="Apron 1"
            value={formatRoom(roomUnderFirstApron)}
            title="Room under first apron"
            variant={roomUnderFirstApron < 0 ? "negative" : "default"}
          />
        )}

        {/* Room Under 2nd Apron - above Total column (red if negative) */}
        {roomUnderSecondApron !== null && (
          <KpiCard
            label="Apron 2"
            value={formatRoom(roomUnderSecondApron)}
            title="Room under second apron"
            variant={roomUnderSecondApron < 0 ? "negative" : "default"}
          />
        )}
      </div>
    </div>
  );
}
