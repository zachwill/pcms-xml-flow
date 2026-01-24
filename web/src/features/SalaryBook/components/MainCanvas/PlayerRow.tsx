/**
 * PlayerRow — Double-row player design
 *
 * Each player occupies TWO visual rows that behave as ONE unit:
 * - Primary Row (Row A): Name, salary per year (monospace), agent name
 * - Metadata Row (Row B): Position chip, experience, age, guarantee, options, bird rights
 *
 * Interactions:
 * - Hover highlights BOTH rows as one unit
 * - Click anywhere → opens Player entity in sidebar
 * - Click agent/agency name → opens Agent entity (stopPropagation)
 */

import React, { memo } from "react";
import { cx } from "@/lib/utils";
import { Tooltip } from "@/components/ui/Tooltip";
import type { SalaryBookPlayer } from "../../data";
import type { ContractOption, GuaranteeType } from "../../data";
import { PlayerSalary } from "./PlayerSalary";
import {
  PositionChip,
  BirdRightsBadge,
  FreeAgencyBadge,
} from "./badges";
import {
  SALARY_YEARS,
  getSalary,
  getTotalSalary,
  getOption,
  getGuarantee,
  getPctCap,
  getPlayerRowName,
} from "./playerRowHelpers";

// ============================================================================
// Salary Cell Styling (color + tooltip based on guarantee/option/consent)
// ============================================================================

interface SalaryCellStyle {
  bgClass: string;
  textClass: string;
  /** Italicize the salary number (not the pct-cap line) */
  salaryItalic: boolean;
  tooltip: React.ReactNode | null;
}

function getSalaryCellStyle(
  guarantee: GuaranteeType,
  option: ContractOption,
  isCurrentSeason: boolean,
  isConsentRequired: boolean,
  isNoTrade: boolean,
  isPoisonPill: boolean,
  isTradeBonus: boolean,
  tradeBonusPercent: number | null,
  salary: number,
  pctCap: number | null,
  yosThisYear: number | null,
  priorYearSalary: number | null
): SalaryCellStyle {
  const tooltips: string[] = [];
  let bgClass = "";
  let textClass = "";
  let salaryItalic = false;

  // --------------------------------------------------------------------------
  // Helpers
  // --------------------------------------------------------------------------

  const tradeKickerLabel = (() => {
    const pct = tradeBonusPercent === null ? null : Number(tradeBonusPercent);
    if (pct !== null && Number.isFinite(pct) && pct > 0) {
      const pctLabel = pct % 1 === 0 ? pct.toFixed(0) : String(pct);
      return `${pctLabel}% Trade Kicker`;
    }
    return "Trade Kicker";
  })();

  const maxPctForYos = (yos: number): number => {
    if (yos <= 6) return 0.25;
    if (yos <= 9) return 0.30;
    return 0.35;
  };

  // Returns whether the trade bonus has *any* room to apply for this year.
  // (If the player's salary is already at/over their max salary threshold,
  // the trade kicker effectively cannot be paid.)
  const tradeBonusHasRoom = (() => {
    if (!isTradeBonus) return null;

    if (pctCap === null || !Number.isFinite(Number(pctCap)) || Number(pctCap) <= 0) return null;
    if (yosThisYear === null || !Number.isFinite(Number(yosThisYear))) return null;

    const yosMaxPct = maxPctForYos(Number(yosThisYear));

    // Derive the implied cap for this year from salary + pct_cap.
    // cap = salary / pctCap
    const capThisYear = salary > 0 ? salary / Number(pctCap) : null;

    // 105% fallback (uses prior year's salary, if available).
    const fallbackPct =
      priorYearSalary !== null && capThisYear && Number.isFinite(capThisYear) && capThisYear > 0
        ? (1.05 * Number(priorYearSalary)) / capThisYear
        : null;

    const maxAllowedPct = Math.max(yosMaxPct, fallbackPct ?? 0);

    // If salary is already at/over max, trade bonus can't add anything.
    return Number(pctCap) < maxAllowedPct;
  })();

  // --------------------------------------------------------------------------
  // Base layers: guarantee + option
  // --------------------------------------------------------------------------

  // Guarantee colors (base layer)
  // GTD (fully guaranteed) has no special styling - it's the default/expected state
  // PARTIAL has no special styling for now
  // For option years, only show guarantee tooltip if it's notable (PARTIAL/NON-GTD)
  const hasOption = !!option && !isCurrentSeason;
  
  if (guarantee === "GTD") {
    // Only show "Fully Guaranteed" tooltip if there's no option taking precedence
    if (!hasOption) {
      tooltips.push("Fully Guaranteed");
    }
  } else if (guarantee === "PARTIAL") {
    tooltips.push("Partially Guaranteed");
  } else if (guarantee === "NON-GTD") {
    bgClass = "bg-yellow-100/60 dark:bg-yellow-900/30";
    textClass = "text-yellow-700 dark:text-yellow-300";
    tooltips.push("Non-Guaranteed");
  }

  // Option colors (override guarantee if present, except current season)
  // (Options take precedence visually over trade bonus in future years.)
  if (hasOption) {
    if (option === "PO") {
      bgClass = "bg-blue-100/60 dark:bg-blue-900/30";
      textClass = "text-blue-700 dark:text-blue-300";
      tooltips.push("Player Option");
    } else if (option === "TO") {
      bgClass = "bg-purple-100/60 dark:bg-purple-900/30";
      textClass = "text-purple-700 dark:text-purple-300";
      tooltips.push("Team Option");
    } else if (option === "ETO") {
      bgClass = "bg-orange-100/60 dark:bg-orange-900/30";
      textClass = "text-orange-700 dark:text-orange-300";
      tooltips.push("Early Termination Option");
    }
  }

  // --------------------------------------------------------------------------
  // Trade bonus styling
  // --------------------------------------------------------------------------

  if (isTradeBonus) {
    tooltips.push(tradeKickerLabel);

    const optionTakesPrecedence = !!option && !isCurrentSeason;

    // Only style cells that would otherwise be "plain" (no guarantee/option tint).
    const isVisuallyPlain = !bgClass && !textClass;

    if (!optionTakesPrecedence && isVisuallyPlain) {
      if (tradeBonusHasRoom === false) {
        // Trade bonus exists, but salary is already at/over max threshold → show orange text only.
        textClass = "text-orange-700 dark:text-orange-300";
      } else {
        // Unknown or has room → show orange background.
        bgClass = "bg-orange-100/60 dark:bg-orange-900/30";
        textClass = "text-orange-700 dark:text-orange-300";
      }
    }
  }

  // --------------------------------------------------------------------------
  // No-Trade Clause
  // - Applies to ALL seasons.
  // - Options (PO/TO/ETO) take visual precedence in future years.
  // - Current season continues to show no-trade styling even if an option exists.
  // --------------------------------------------------------------------------

  if (isNoTrade) {
    tooltips.push("No-Trade Clause");

    const optionTakesPrecedence = !!option && !isCurrentSeason;
    if (!optionTakesPrecedence) {
      bgClass = "bg-red-100/60 dark:bg-red-900/30";
      textClass = "text-red-700 dark:text-red-300";
    }
  }

  // --------------------------------------------------------------------------
  // Current-season trade restrictions (override all other coloring)
  // --------------------------------------------------------------------------

  if (isCurrentSeason) {
    if (isConsentRequired) {
      bgClass = "bg-red-100/60 dark:bg-red-900/30";
      textClass = "text-red-700 dark:text-red-300";
      tooltips.push("Player Consent Required");
    }

    if (isPoisonPill) {
      bgClass = "bg-red-100/60 dark:bg-red-900/30";
      textClass = "text-red-700 dark:text-red-300";
      salaryItalic = true;
      tooltips.push("Poison Pill");
    }
  }

  return {
    bgClass,
    textClass,
    salaryItalic,
    tooltip:
      tooltips.length > 0 ? (
        <div className="flex flex-col gap-0.5">
          {tooltips.map((t) => (
            <div key={t}>{t}</div>
          ))}
        </div>
      ) : null,
  };
}

// ============================================================================
// Types
// ============================================================================

export interface PlayerRowProps {
  /** Player data from salary_book_warehouse */
  player: SalaryBookPlayer;
  /** Called when the row is clicked (opens player detail) */
  onClick: () => void;
  /** Called when agent name is clicked (opens agent detail) */
  onAgentClick: (e: React.MouseEvent) => void;
  /** Whether to show option badges (PO, TO, ETO) */
  showOptions?: boolean;
  /** Whether to show two-way contract badges */
  showTwoWay?: boolean;
}

// ============================================================================
// Main Component
// ============================================================================

function PlayerRowInner({
  player,
  onClick,
  onAgentClick,
  showOptions = true,
  showTwoWay = true,
}: PlayerRowProps) {
  const headshotUrl = `https://cdn.nba.com/headshots/nba/latest/1040x760/${player.player_id}.png`;
  // Simple inline SVG fallback so we don't collapse layout on 404s.
  const fallbackHeadshot =
    "data:image/svg+xml;utf8," +
    "<svg xmlns='http://www.w3.org/2000/svg' width='64' height='64'>" +
    "<rect width='100%25' height='100%25' fill='%23e5e7eb'/>" +
    "<text x='50%25' y='52%25' dominant-baseline='middle' text-anchor='middle' " +
    "fill='%239ca3af' font-family='ui-sans-serif,system-ui' font-size='10'>" +
    "NBA" +
    "</text>" +
    "</svg>";

  const rowName = getPlayerRowName(player);

  return (
    <div
      onClick={onClick}
      className={cx(
        // Group for hover state coordination
        "group cursor-pointer",
        // Border between rows
        "border-b border-border/50",
        // Hover highlights BOTH rows as one unit (subtle yellow)
        "hover:bg-yellow-50/70 dark:hover:bg-yellow-900/10",
        // Smooth transition for hover
        "transition-colors duration-75"
      )}
      role="button"
      tabIndex={0}
      onKeyDown={(e) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          onClick();
        }
      }}
    >
      {/*
        Layout note:
        Keep the entire "Player" area as ONE sticky column (w-52).
        Headshot is part of that sticky cell (not its own column), so the sticky
        area doesn't encroach into the first salary year when horizontally scrolling.
      */}
      <div className="flex">
        {/* Sticky Player column (Headshot + Name + Details) */}
        <div
          className={cx(
            "w-52 shrink-0 pl-4",
            "sticky left-0 z-20",
            "relative",
            // Opaque background to prevent bleed-through while scrolling
            "bg-background",
            // Match row hover/transition (subtle yellow)
            "group-hover:bg-yellow-50/70 dark:group-hover:bg-yellow-900/10",
            "transition-colors duration-75",
            // Separator on the right edge of the sticky column
            "after:absolute after:right-0 after:top-0 after:bottom-0 after:w-px",
            "after:bg-border/30"
          )}
        >
          <div
            className="grid grid-cols-[40px_1fr] grid-rows-[28px_20px]"
            aria-label={`${rowName} player info`}
          >
            {/* Headshot spans both sub-rows */}
            <div className="row-span-2 flex items-center justify-start">
              <div className="w-7 h-7 rounded border border-border bg-background overflow-hidden">
                <img
                  src={headshotUrl}
                  alt={rowName}
                  className="w-full h-full object-cover object-top bg-muted"
                  loading="lazy"
                  decoding="async"
                  onError={(e) => {
                    // Avoid infinite loop if fallback fails for some reason
                    if (e.currentTarget.src !== fallbackHeadshot) {
                      e.currentTarget.src = fallbackHeadshot;
                    }
                  }}
                />
              </div>
            </div>

            {/* Row A: Name */}
            <div className="h-7 flex items-end min-w-0 pl-1 pr-2">
              <span className="truncate font-medium text-[14px] group-hover:text-primary transition-colors">
                {rowName}
              </span>

            </div>

            {/* Row B: Details */}
            <div className="h-5 -mt-0.5 flex items-start gap-2 min-w-0 pl-1 pr-2 leading-none text-xs text-muted-foreground">
              {player.position && <PositionChip position={player.position} />}
              <span className="tabular-nums">
                {player.age !== null && <>{Number(player.age).toFixed(1)} YRS</>}
                {player.age !== null && player.experience !== null && player.experience !== undefined && " · "}
                {player.experience !== null && player.experience !== undefined && <>{player.experience === 0 ? "Rookie" : `${player.experience} YOS`}</>}
              </span>
            </div>
          </div>
        </div>

        {/* Non-sticky columns (Contract Years + Management) */}
        <div className="min-w-0 flex">
          {/* Salary year columns — each spans both rows */}
          {SALARY_YEARS.map((year) => {
            const salary = getSalary(player, year);
            const showTwoWayBadge = showTwoWay && player.is_two_way && salary == 0;
            const option = showOptions ? getOption(player, year) : null;
            const guarantee = getGuarantee(player, year);
            const isCurrentSeason = year === SALARY_YEARS[0];
            const pctCap = getPctCap(player, year);
            
            const yosThisYear =
              player.experience !== null && player.experience !== undefined
                ? Number(player.experience) + (year - SALARY_YEARS[0])
                : null;

            // Poison Pill only meaningfully applies in the current season and only for 3 YOS players.
            // (Warehouse flag can be historically true even when it's no longer relevant.)
            const isPoisonPillNow =
              isCurrentSeason &&
              player.is_poison_pill &&
              yosThisYear !== null &&
              Number(yosThisYear) === 3;

            const priorYearSalary = getSalary(player, year - 1);

            const cellStyle = salary !== null
              ? getSalaryCellStyle(
                  guarantee,
                  option,
                  isCurrentSeason,
                  player.is_trade_consent_required_now,
                  player.is_no_trade,
                  isPoisonPillNow,
                  player.is_trade_bonus,
                  player.trade_bonus_percent,
                  Number(salary) || 0,
                  pctCap,
                  yosThisYear,
                  priorYearSalary
                )
              : { bgClass: "", textClass: "", salaryItalic: false, tooltip: null };

            // Format pct cap as rounded percentage (e.g., "32%")
            const pctCapLabel = pctCap !== null ? `${Math.round(pctCap * 100)}%` : null;

            const cell = (
              <div
                key={year}
                className={cx(
                  "w-24 shrink-0",
                  showTwoWayBadge
                    ? "grid place-items-center h-[calc(1.75rem+1.25rem-0.125rem)]"
                    : "flex flex-col",
                  cellStyle.bgClass,
                  cellStyle.textClass
                )}
              >
                {showTwoWayBadge ? (
                  <PlayerSalary amount={salary} showTwoWayBadge />
                ) : (
                  <>
                    {/* Row A: Salary */}
                    <div
                      className={cx(
                        "h-7 flex items-end justify-center text-sm",
                        salary === null && "text-muted-foreground/50"
                      )}
                    >
                      <PlayerSalary
                        amount={salary}
                        className={cellStyle.salaryItalic ? "italic" : undefined}
                      />
                    </div>
                    {/* Row B: Percent of cap */}
                    <div className="h-5 -mt-0.5 flex items-start justify-center">
                      {pctCapLabel && (
                        <span className="text-[10px] tabular-nums italic opacity-70">{pctCapLabel}</span>
                      )}
                    </div>
                  </>
                )}
              </div>
            );

            return cellStyle.tooltip ? (
              <Tooltip triggerAsChild content={cellStyle.tooltip} side="top" sideOffset={6}>
                {cell}
              </Tooltip>
            ) : (
              cell
            );
          })}

          {/* Total salary column */}
          {(() => {
            const totalSalary = getTotalSalary(player);
            const showTotalTwoWay = showTwoWay && player.is_two_way && totalSalary === 0;
            return (
              <div
                className={cx(
                  "w-24 shrink-0",
                  showTotalTwoWay
                    ? "grid place-items-center h-[calc(1.75rem+1.25rem-0.125rem)]"
                    : "flex flex-col"
                )}
              >
                {showTotalTwoWay ? (
                  <PlayerSalary amount={totalSalary} showTwoWayBadge slotWidth="7ch" className="font-semibold" />
                ) : (
                  <>
                    <div className="h-7 flex items-end justify-center text-sm">
                      <PlayerSalary
                        amount={totalSalary}
                        slotWidth="7ch"
                        className="font-semibold"
                      />
                    </div>
                    <div className="h-5" />
                  </>
                )}
              </div>
            );
          })()}

          {/* Agent + Agency column */}
          <div className="w-40 shrink-0 flex flex-col pr-4">
            {/* Row A: Agent name (baseline-aligned with player name + total) */}
            <div className="h-7 flex items-end justify-start min-w-0">
              {player.agent_name ? (
                <button
                  onClick={onAgentClick}
                  className={cx(
                    "text-xs truncate mb-px",
                    "text-gray-400 dark:text-gray-500",
                    "hover:text-muted-foreground hover:underline",
                    "focus:outline-none focus-visible:underline focus-visible:text-muted-foreground",
                    "transition-colors"
                  )}
                >
                  {player.agent_name}
                </button>
              ) : (
                <span className="text-xs text-muted-foreground/50">—</span>
              )}
            </div>
            {/* Row B: Agency + Bird rights + Free agency */}
            <div className="h-5 -mt-0.5 flex items-start justify-start gap-1.5 leading-none text-xs text-muted-foreground min-w-0">
              {player.agency_name && (
                <span className="text-gray-400 dark:text-gray-500 truncate italic">
                  {player.agency_name}
                </span>
              )}
              {player.bird_rights && <BirdRightsBadge birdRights={player.bird_rights} />}
              {player.free_agency_type && (
                <FreeAgencyBadge
                  type={player.free_agency_type}
                  year={player.free_agency_year}
                />
              )}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

/**
 * Memoized PlayerRow - only re-renders when player data or callbacks change
 * 
 * Performance note: We use a custom comparison that checks player.id + showOptions/showTwoWay.
 * Callbacks (onClick, onAgentClick) are expected to be stable from the parent.
 */
export const PlayerRow = memo(PlayerRowInner, (prevProps, nextProps) => {
  // Quick bailout: if player ID changed, definitely re-render
  if (prevProps.player.id !== nextProps.player.id) return false;
  
  // Check filter toggles
  if (prevProps.showOptions !== nextProps.showOptions) return false;
  if (prevProps.showTwoWay !== nextProps.showTwoWay) return false;
  
  // Shallow compare the player object by checking key salary fields
  // (Deep compare is expensive, so we check the fields that affect rendering)
  const p1 = prevProps.player;
  const p2 = nextProps.player;
  return (
    p1.cap_2025 === p2.cap_2025 &&
    p1.cap_2026 === p2.cap_2026 &&
    p1.cap_2027 === p2.cap_2027 &&
    p1.cap_2028 === p2.cap_2028 &&
    p1.cap_2029 === p2.cap_2029 &&
    p1.player_name === p2.player_name &&
    p1.agent_name === p2.agent_name &&
    p1.is_two_way === p2.is_two_way &&
    p1.is_trade_consent_required_now === p2.is_trade_consent_required_now &&
    p1.is_no_trade === p2.is_no_trade &&
    p1.is_trade_bonus === p2.is_trade_bonus &&
    p1.trade_bonus_percent === p2.trade_bonus_percent
  );
});

export default PlayerRow;
