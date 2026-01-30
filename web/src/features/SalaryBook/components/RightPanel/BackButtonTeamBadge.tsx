/**
 * BackButtonTeamBadge — Team logo with crossfade animation
 *
 * When the underlying team changes (user scrolls while entity is open),
 * the logo crossfades to draw attention to the changed "back" destination.
 *
 * Uses the safeToUnmount pattern from Silk: keep the old logo mounted
 * and visible until the exit animation completes.
 */

import React, { useEffect, useRef, useState } from "react";
import { cx } from "@/lib/utils";
import { animate, durations, easings } from "@/lib/animate";

interface BackButtonTeamBadgeProps {
  /** Current team code (from scroll-spy activeTeam) */
  teamCode: string | null;
  /** NBA team_id for logo URL */
  teamId: number | null;
  /** Whether we're in entity mode (should animate on team change) */
  isEntityMode: boolean;
}

interface TeamBadgeState {
  teamCode: string;
  teamId: number | null;
  isExiting: boolean;
}

/**
 * Individual logo/fallback renderer
 */
function TeamLogo({
  teamCode,
  teamId,
  className,
}: {
  teamCode: string;
  teamId: number | null;
  className?: string;
}) {
  const [logoErrored, setLogoErrored] = useState(false);

  const logoUrl = teamId
    ? `https://cdn.nba.com/logos/nba/${teamId}/primary/L/logo.svg`
    : null;

  // Reset error state when team changes
  useEffect(() => {
    setLogoErrored(false);
  }, [teamId]);

  return (
    <div className={cx("w-full h-full flex items-center justify-center", className)}>
      {logoUrl && !logoErrored ? (
        <img
          src={logoUrl}
          alt=""
          className="w-full h-full object-contain"
          onError={() => setLogoErrored(true)}
        />
      ) : (
        <span
          className="text-[6px] font-mono font-bold uppercase tracking-tight"
          aria-hidden="true"
        >
          {teamCode}
        </span>
      )}
    </div>
  );
}

export function BackButtonTeamBadge({
  teamCode,
  teamId,
  isEntityMode,
}: BackButtonTeamBadgeProps) {
  const containerRef = useRef<HTMLDivElement>(null);

  // Track displayed teams (current + optional exiting)
  const [badges, setBadges] = useState<TeamBadgeState[]>(() =>
    teamCode ? [{ teamCode, teamId, isExiting: false }] : []
  );

  // Track previous team for comparison
  const prevTeamCodeRef = useRef<string | null>(teamCode);

  // Refs for animation targets
  const exitingRef = useRef<HTMLDivElement>(null);
  const enteringRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const prevTeamCode = prevTeamCodeRef.current;
    prevTeamCodeRef.current = teamCode;

    // Case 1: No team — clear everything
    if (!teamCode) {
      setBadges([]);
      return;
    }

    // Case 2: Same team — no change needed
    if (teamCode === prevTeamCode) {
      return;
    }

    // Case 3: First team (no previous) — just set it
    if (!prevTeamCode) {
      setBadges([{ teamCode, teamId, isExiting: false }]);
      return;
    }

    // Case 4: Team changed while NOT in entity mode — instant swap, no animation
    if (!isEntityMode) {
      setBadges([{ teamCode, teamId, isExiting: false }]);
      return;
    }

    // Case 5: Team changed while in entity mode — crossfade!
    // Find the current (now exiting) badge
    const currentBadge = badges.find((b) => !b.isExiting);
    if (!currentBadge) {
      // Edge case: no current badge, just set the new one
      setBadges([{ teamCode, teamId, isExiting: false }]);
      return;
    }

    // Set up both badges: old one exiting, new one entering
    setBadges([
      { ...currentBadge, isExiting: true },
      { teamCode, teamId, isExiting: false },
    ]);

    // Animate after state update
    requestAnimationFrame(() => {
      const exitingEl = exitingRef.current;
      const enteringEl = enteringRef.current;

      const animations: Promise<unknown>[] = [];

      if (exitingEl) {
        animations.push(
          animate(
            exitingEl,
            [
              { opacity: 1, transform: "scale(1)" },
              { opacity: 0, transform: "scale(0.8)" },
            ],
            { duration: 75, easing: easings.easeIn }
          )
        );
      }

      if (enteringEl) {
        animations.push(
          animate(
            enteringEl,
            [
              { opacity: 0, transform: "scale(1.2)" },
              { opacity: 1, transform: "scale(1)" },
            ],
            { duration: durations.fast, easing: easings.easeOut }
          )
        );
      }

      // After animations complete, remove the exiting badge
      Promise.all(animations).then(() => {
        setBadges((prev) => prev.filter((b) => !b.isExiting));
      });
    });
  }, [teamCode, teamId, isEntityMode]);

  // Handle badges array changing (need to reassign refs)
  // Note: We rely on the exiting badge being first in the array when both exist

  if (badges.length === 0) {
    return null;
  }

  return (
    <div
      ref={containerRef}
      className={cx(
        "w-5 h-5 rounded flex items-center justify-center flex-shrink-0",
        "bg-background border border-border",
        "overflow-hidden",
        "relative" // For absolute positioning of stacked badges
      )}
    >
      {badges.map((badge, index) => {
        const isExiting = badge.isExiting;
        const ref = isExiting ? exitingRef : enteringRef;

        return (
          <div
            key={`${badge.teamCode}-${isExiting ? "exit" : "enter"}`}
            ref={ref}
            className={cx(
              "absolute inset-0",
              // Exiting badge should be behind entering badge
              isExiting ? "z-0" : "z-10"
            )}
          >
            <TeamLogo teamCode={badge.teamCode} teamId={badge.teamId} />
          </div>
        );
      })}
    </div>
  );
}

export default BackButtonTeamBadge;
