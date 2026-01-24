/**
 * DraftAssetsRow — Pick pills aligned under year columns
 *
 * Displays draft picks owned by the team, organized by year with clickable pills.
 * Each pill shows origin team + round (e.g., "LAL 1").
 *
 * Layout must align with the player rows/table header:
 * - Sticky left block = headshot spacer (w-10) + label column (w-40)
 * - 6 year columns (w-24 each)
 * - total spacer column (w-24)
 * - management spacer (w-40)
 */

import React from "react";
import { cx, focusRing } from "@/lib/utils";
import type { DraftPick } from "../../data";

export interface DraftAssetsRowProps {
  picks: DraftPick[];
  onPickClick: (pick: DraftPick) => void;
}

const SALARY_YEARS = [2025, 2026, 2027, 2028, 2029] as const;

interface PickPillProps {
  pick: DraftPick;
  onClick: (e: React.MouseEvent) => void;
}

function PickPill({ pick, onClick }: PickPillProps) {
  const colorClasses =
    pick.round === 1
      ? "bg-amber-100 dark:bg-amber-900/50 text-amber-800 dark:text-amber-200 hover:bg-amber-200 dark:hover:bg-amber-800/50"
      : "bg-slate-100 dark:bg-slate-800/50 text-slate-700 dark:text-slate-300 hover:bg-slate-200 dark:hover:bg-slate-700/50";

  return (
    <button
      onClick={onClick}
      className={cx(
        "inline-flex items-center gap-0.5",
        "px-1.5 py-0.5 rounded",
        "text-[9px] font-semibold uppercase tracking-wide",
        colorClasses,
        pick.is_swap && "border border-dashed border-current/40",
        "transition-colors cursor-pointer",
        focusRing()
      )}
      title={buildPickTitle(pick)}
    >
      {pick.origin_team_code} {pick.round}
      {pick.is_swap && "s"}
    </button>
  );
}

function buildPickTitle(pick: DraftPick): string {
  const roundLabel = pick.round === 1 ? "1st Round" : "2nd Round";
  const swapLabel = pick.is_swap ? " (Swap)" : "";
  const protectionLabel = pick.protections ? ` - ${pick.protections}` : "";
  return `${pick.year} ${roundLabel} pick from ${pick.origin_team_code}${swapLabel}${protectionLabel}`;
}

export function DraftAssetsRow({ picks, onPickClick }: DraftAssetsRowProps) {
  if (picks.length === 0) return null;

  const picksByYear = picks.reduce<Record<number, DraftPick[]>>((acc, pick) => {
    (acc[pick.year] ||= []).push(pick);
    return acc;
  }, {});

  for (const year of Object.keys(picksByYear)) {
    picksByYear[Number(year)]!.sort((a, b) => {
      if (a.round !== b.round) return a.round - b.round;
      return a.origin_team_code.localeCompare(b.origin_team_code);
    });
  }

  return (
    <div
      className={cx(
        "bg-muted/10 dark:bg-muted/5",
        "border-b border-border/50"
      )}
    >
      <div className="h-8 flex items-center text-xs">
        {/* Label column (STICKY LEFT COLUMN) */}
        <div
          className={cx(
            "w-52 shrink-0 pl-4",
            "sticky left-0 z-[2]",
            "bg-muted/10 dark:bg-muted/5",
            "after:absolute after:right-0 after:top-0 after:bottom-0 after:w-px",
            "after:bg-border/30",
            "relative"
          )}
        >
          <div className="grid grid-cols-[40px_1fr] items-center h-full">
            <div />
            <div className="pl-1 flex items-center gap-2 min-w-0">
              <span className="text-[10px] font-semibold uppercase tracking-wide text-muted-foreground">
                Draft Assets
              </span>
              <span
                className={cx(
                  "inline-flex items-center justify-center",
                  "min-w-[16px] h-4 px-1 rounded-full",
                  "bg-muted text-muted-foreground",
                  "text-[9px] font-medium"
                )}
              >
                {picks.length}
              </span>
            </div>
          </div>
        </div>

        {/* Year columns */}
        {SALARY_YEARS.map((year) => {
          const yearPicks = picksByYear[year] || [];
          return (
            <div
              key={year}
              className={cx(
                "w-24 shrink-0",
                "flex flex-wrap items-center justify-center gap-1",
                "px-0.5"
              )}
            >
              {yearPicks.map((pick) => (
                <PickPill
                  key={pick.id}
                  pick={pick}
                  onClick={(e) => {
                    e.stopPropagation();
                    onPickClick(pick);
                  }}
                />
              ))}
            </div>
          );
        })}

        {/* Total spacer column */}
        <div className="w-24 shrink-0" />

        {/* Management spacer */}
        <div className="w-40 pr-4 shrink-0" />
      </div>
    </div>
  );
}

export default DraftAssetsRow;
