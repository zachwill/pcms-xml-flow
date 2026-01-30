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
import type { SalaryBookPlayer } from "../../data";
import type { ContractOption, GuaranteeType } from "../../data";
import { PlayerSalary } from "./PlayerSalary";
import { PositionChip, BirdRightsBadge, FreeAgencyBadge } from "./badges";
import {
  SALARY_YEARS,
  getSalary,
  getTotalSalary,
  getOption,
  getGuarantee,
  getPctCap,
  getPctCapPercentile,
  formatPctCapWithBlocks,
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
  tooltipText: string | null;
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
    if (yos <= 9) return 0.3;
    return 0.35;
  };

  // Returns whether the trade bonus has *any* room to apply for this year.
  // (If the player's salary is already at/over their max salary threshold,
  // the trade kicker effectively cannot be paid.)
  const tradeBonusHasRoom = (() => {
    if (!isTradeBonus) return null;

    if (pctCap === null || !Number.isFinite(Number(pctCap)) || Number(pctCap) <= 0)
      return null;
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
    tooltipText: tooltips.length > 0 ? tooltips.join("\n") : null,
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
// Subcomponents (kept colocated for readability)
// ============================================================================

const FALLBACK_HEADSHOT_DATA_URI =
  "data:image/svg+xml;utf8," +
  "<svg xmlns='http://www.w3.org/2000/svg' width='64' height='64'>" +
  "<rect width='100%25' height='100%25' fill='%23e5e7eb'/>" +
  "<text x='50%25' y='52%25' dominant-baseline='middle' text-anchor='middle' " +
  "fill='%239ca3af' font-family='ui-sans-serif,system-ui' font-size='10'>" +
  "NBA" +
  "</text>" +
  "</svg>";

function PlayerRowContainer({
  onClick,
  children,
}: {
  onClick: () => void;
  children: React.ReactNode;
}) {
  const handleKeyDown = (e: React.KeyboardEvent<HTMLDivElement>) => {
    if (e.key === "Enter" || e.key === " ") {
      e.preventDefault();
      onClick();
    }
  };

  return (
    <div
      onClick={onClick}
      className={cx(
        // Group for hover state coordination
        "group cursor-pointer",
        // Border between rows
        "border-b border-border/50",
        // Silk pattern: disable pointer events (and thus hover/tooltips) during active scroll
        "[[data-scroll-state=scrolling]_&]:pointer-events-none",
        // Hover highlights BOTH rows as one unit (subtle yellow)
        "hover:bg-yellow-50/70 dark:hover:bg-yellow-900/10",
        // Smooth transition for hover
        "transition-colors duration-75"
      )}
      role="button"
      tabIndex={0}
      onKeyDown={handleKeyDown}
    >
      {children}
    </div>
  );
}

function PlayerHeadshot({ headshotUrl, alt }: { headshotUrl: string; alt: string }) {
  return (
    <div className="w-7 h-7 rounded border border-border bg-background overflow-hidden">
      <img
        src={headshotUrl}
        alt={alt}
        className="w-full h-full object-cover object-top bg-muted"
        loading="lazy"
        decoding="async"
        onError={(e) => {
          // Avoid infinite loop if fallback fails for some reason
          if (e.currentTarget.src !== FALLBACK_HEADSHOT_DATA_URI) {
            e.currentTarget.src = FALLBACK_HEADSHOT_DATA_URI;
          }
        }}
      />
    </div>
  );
}

function PlayerStickyColumn({
  player,
  rowName,
}: {
  player: SalaryBookPlayer;
  rowName: string;
}) {
  const headshotUrl = `https://cdn.nba.com/headshots/nba/latest/1040x760/${player.player_id}.png`;

  return (
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
        className="grid grid-cols-[40px_1fr] grid-rows-[24px_16px]"
        aria-label={`${rowName} player info`}
      >
        {/* Headshot spans both sub-rows */}
        <div className="row-span-2 flex items-center justify-start">
          <PlayerHeadshot headshotUrl={headshotUrl} alt={rowName} />
        </div>

        {/* Row A: Name */}
        <div className="h-[24px] flex items-end min-w-0 pl-1 pr-2">
          <span className="truncate font-medium text-[14px] group-hover:text-primary transition-colors">
            {rowName}
          </span>
        </div>

        {/* Row B: Details */}
        <div className="h-[16px] -mt-px flex items-start gap-2 min-w-0 pl-1 pr-2 leading-none text-[10px] text-muted-foreground/80 tabular-nums">
          {player.position && <PositionChip position={player.position} />}
          <span>
            {player.age !== null && <>{Number(player.age).toFixed(1)} YRS</>}
            {player.age !== null &&
              player.experience !== null &&
              player.experience !== undefined &&
              " · "}
            {player.experience !== null && player.experience !== undefined && (
              <>
                {player.experience === 0
                  ? "Rookie"
                  : `${player.experience} YOS`}
              </>
            )}
          </span>
        </div>
      </div>
    </div>
  );
}

function SalaryYearCell({
  player,
  year,
  showOptions,
  showTwoWay,
}: {
  player: SalaryBookPlayer;
  year: (typeof SALARY_YEARS)[number];
  showOptions: boolean;
  showTwoWay: boolean;
}) {
  const salary = getSalary(player, year);
  const showTwoWayBadge = showTwoWay && player.is_two_way && salary == 0;
  const isEmptySalary = salary === null;
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

  const cellStyle =
    salary !== null
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
      : { bgClass: "", textClass: "", salaryItalic: false, tooltipText: null };

  // Get percentile and format pct cap with blocks
  const pctCapPercentile = getPctCapPercentile(player, year);
  const pctCapDisplay = formatPctCapWithBlocks(pctCap, pctCapPercentile);

  const cell = (
    <div
      className={cx(
        "w-24 shrink-0",
        showTwoWayBadge || isEmptySalary
          ? "grid place-items-center h-[40px]"
          : "flex flex-col",
        cellStyle.bgClass,
        cellStyle.textClass
      )}
      title={cellStyle.tooltipText ?? undefined}
    >
      {showTwoWayBadge ? (
        <PlayerSalary amount={salary} showTwoWayBadge />
      ) : isEmptySalary ? (
        <PlayerSalary amount={salary} className="text-sm" />
      ) : (
        <>
          {/* Row A: Salary */}
          <div className={cx("h-[24px] flex items-end justify-center text-sm")}>
            <PlayerSalary
              amount={salary}
              className={cellStyle.salaryItalic ? "italic" : undefined}
            />
          </div>
          {/* Row B: Percent of cap with percentile blocks */}
          <div className="h-[16px] -mt-px flex items-start justify-center">
            {pctCapDisplay && (
              <span
                className={cx(
                  "text-[10px] leading-none tabular-nums whitespace-nowrap",
                  // If the salary cell is tinted (option/guarantee/etc), let the pct-cap
                  // line inherit that color and just soften via opacity.
                  cellStyle.textClass ? "opacity-80" : "text-muted-foreground/80"
                )}
              >
                {pctCapDisplay.label}
                {pctCapDisplay.blocks && (
                  <span className="ml-0.5 opacity-70">{pctCapDisplay.blocks}</span>
                )}
              </span>
            )}
          </div>
        </>
      )}
    </div>
  );

  return cell;
}

function TotalSalaryCell({
  player,
  showTwoWay,
}: {
  player: SalaryBookPlayer;
  showTwoWay: boolean;
}) {
  const totalSalary = getTotalSalary(player);
  const showTotalTwoWay = showTwoWay && player.is_two_way && totalSalary === 0;

  const contractTypeCode = player.contract_type_code;
  const contractTypeLabel = player.contract_type_lookup_value;

  const cell = (
    <div
      className={cx(
        "w-24 shrink-0",
        showTotalTwoWay
          ? "grid place-items-center h-[40px]"
          : "flex flex-col"
      )}
      title={contractTypeLabel ?? undefined}
    >
      {showTotalTwoWay ? (
        <PlayerSalary
          amount={totalSalary}
          showTwoWayBadge
          slotWidth="7ch"
          className="font-semibold"
        />
      ) : (
        <>
          <div className="h-[24px] flex items-end justify-center text-sm">
            <PlayerSalary
              amount={totalSalary}
              slotWidth="7ch"
              className="font-semibold"
            />
          </div>
          <div className="h-[16px] -mt-px flex items-start justify-center">
            {contractTypeCode ? (
              <span className="text-[10px] leading-none tabular-nums whitespace-nowrap text-gray-400 dark:text-gray-500">
                {contractTypeCode}
              </span>
            ) : (
              <span className="text-[10px] leading-none tabular-nums whitespace-nowrap text-gray-400/50 dark:text-gray-500/50">
                —
              </span>
            )}
          </div>
        </>
      )}
    </div>
  );

  return cell;
}

function AgentAgencyColumn({
  player,
  onAgentClick,
}: {
  player: SalaryBookPlayer;
  onAgentClick: (e: React.MouseEvent) => void;
}) {
  return (
    <div className="w-40 shrink-0 flex flex-col pr-4">
      {/* Row A: Agent name (baseline-aligned with player name + total) */}
      <div className="h-[24px] flex items-end justify-start min-w-0">
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
      <div className="h-[16px] -mt-px flex items-start justify-start gap-1.5 leading-none text-[10px] tabular-nums min-w-0">
        {player.agency_name ? (
          <span className="text-gray-400 dark:text-gray-500 truncate">
            {player.agency_name}
          </span>
        ) : (
          <span className="text-gray-400/50 dark:text-gray-500/50">—</span>
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
  );
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
  const rowName = getPlayerRowName(player);

  return (
    <PlayerRowContainer onClick={onClick}>
      {/*
        Layout note:
        Keep the entire "Player" area as ONE sticky column (w-52).
        Headshot is part of that sticky cell (not its own column), so the sticky
        area doesn't encroach into the first salary year when horizontally scrolling.
      */}
      <div className="flex">
        {/* Sticky Player column (Headshot + Name + Details) */}
        <PlayerStickyColumn player={player} rowName={rowName} />

        {/* Non-sticky columns (Contract Years + Management) */}
        <div className="min-w-0 flex">
          {/* Salary year columns — each spans both rows */}
          {SALARY_YEARS.map((year) => (
            <SalaryYearCell
              key={year}
              player={player}
              year={year}
              showOptions={showOptions}
              showTwoWay={showTwoWay}
            />
          ))}

          {/* Total salary column */}
          <TotalSalaryCell player={player} showTwoWay={showTwoWay} />

          {/* Agent + Agency column */}
          <AgentAgencyColumn player={player} onAgentClick={onAgentClick} />
        </div>
      </div>
    </PlayerRowContainer>
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
