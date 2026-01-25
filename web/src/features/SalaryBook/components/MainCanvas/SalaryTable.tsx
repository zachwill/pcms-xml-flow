/**
 * SalaryTable — Table body + horizontal scroll container
 *
 * Key layout constraints:
 * - Vertical stickiness must be relative to the MainCanvas scroll container.
 * - Horizontal scrolling must not break `position: sticky` for the header group.
 *
 * Implementation:
 * - A sticky (vertical) header group that contains:
 *   - TeamHeader (not horizontally scrollable)
 *   - TableHeader inside its own horizontal scroller
 * - A separate horizontal scroller for the table body
 * - Header/body horizontal scroll positions are synced
 */

import React, { useRef, useState, useCallback, useEffect, useMemo } from "react";
import { cx } from "@/lib/utils";
import type {
  SalaryBookPlayer,
  DraftPick,
  TeamSalary,
  CapHold,
  TeamException,
  DeadMoney,
} from "../../data";
import type { FilterState } from "@/state/filters";
import { TableHeader } from "./TableHeader";
import { PlayerRow } from "./PlayerRow";
import { DraftAssetsRow } from "./DraftAssetsRow";
import { TotalsFooter } from "./TotalsFooter";
import { CapHoldsSection } from "./CapHoldsSection";
import { ExceptionsSection } from "./ExceptionsSection";
import { DeadMoneySection } from "./DeadMoneySection";

// ============================================================================
// Types
// ============================================================================

export interface SalaryTableProps {
  /** Team header (sticky; does not horizontally scroll) */
  teamHeader: React.ReactNode;
  /** List of players to display */
  players: SalaryBookPlayer[];
  /** Draft picks for the team */
  picks: DraftPick[];
  /** Cap holds (warehouse-backed) */
  capHolds: CapHold[];
  /** Exceptions (warehouse-backed) */
  exceptions: TeamException[];
  /** Dead money (warehouse-backed) */
  deadMoney: DeadMoney[];
  /** Team salary data by year (2025-2030) */
  salaryByYear: Map<number, TeamSalary>;
  /** Active filter state */
  filters: FilterState;
  /** Called when a player row is clicked */
  onPlayerClick: (player: SalaryBookPlayer) => void;
  /** Called when agent name is clicked */
  onAgentClick: (e: React.MouseEvent, player: SalaryBookPlayer) => void;
  /** Called when a pick pill is clicked */
  onPickClick: (pick: DraftPick) => void;
}

// Contract years to display (6-year horizon; aligns with salary_book_warehouse cap_2025..cap_2030)
const SALARY_YEARS = [2025, 2026, 2027, 2028, 2029] as const;

// Sticky left block width: w-52 = 13rem = 208px
const STICKY_LEFT_WIDTH_PX = 208;

// w-52 (208) + 6 years (6*96=576) + total (96) + agent (160) = 1040
const MIN_TABLE_WIDTH = "1040px";

// ============================================================================
// Helpers
// ============================================================================

function getCapValue(player: SalaryBookPlayer, year: (typeof SALARY_YEARS)[number]): number {
  const key = `cap_${year}` as const;
  // API can return numeric-ish values; ensure number
  return Number((player as any)[key] ?? 0) || 0;
}

function isTwoWayContract(player: SalaryBookPlayer): boolean {
  if (!player.is_two_way) return false;
  // We treat "two-way" rows as the contracts that show as $0 across the horizon.
  const total = SALARY_YEARS.reduce((sum, year) => sum + getCapValue(player, year), 0);
  return total === 0;
}

function PlaceholderSectionRow({ label }: { label: string }) {
  return (
    <div className={cx("bg-muted/10 dark:bg-muted/5", "border-b border-border/50")}>
      <div className="h-8 flex items-center text-xs">
        {/* Label column (sticky left) */}
        <div
          className={cx(
            "w-52 pl-4 shrink-0",
            "sticky left-0 z-[2]",
            "bg-muted/10 dark:bg-muted/5",
            "after:absolute after:right-0 after:top-0 after:bottom-0 after:w-px",
            "after:bg-border/30",
            "relative"
          )}
        >
          <span className="text-[10px] font-semibold uppercase tracking-wide text-muted-foreground">
            {label}
          </span>
        </div>

        {/* Year columns (placeholder for future data integration) */}
        {SALARY_YEARS.map((year) => (
          <div
            key={year}
            className="w-24 font-mono tabular-nums text-center text-muted-foreground/50"
          >
            —
          </div>
        ))}

        {/* Total spacer column */}
        <div className="w-24" />

        {/* Right spacer (matches agent column width) */}
        <div className="w-40 pr-4" />
      </div>
    </div>
  );
}

// ============================================================================
// Component
// ============================================================================

export function SalaryTable({
  teamHeader,
  players,
  picks,
  capHolds,
  exceptions,
  deadMoney,
  salaryByYear,
  filters,
  onPlayerClick,
  onAgentClick,
  onPickClick,
}: SalaryTableProps) {
  const headerScrollRef = useRef<HTMLDivElement>(null);
  const bodyScrollRef = useRef<HTMLDivElement>(null);
  const syncingRef = useRef<"header" | "body" | null>(null);

  const [isScrolled, setIsScrolled] = useState(false);

  const syncScroll = useCallback((source: "header" | "body") => {
    const headerEl = headerScrollRef.current;
    const bodyEl = bodyScrollRef.current;
    if (!headerEl || !bodyEl) return;

    // Prevent ping-pong.
    if (syncingRef.current && syncingRef.current !== source) return;

    syncingRef.current = source;

    if (source === "body") {
      headerEl.scrollLeft = bodyEl.scrollLeft;
      setIsScrolled(bodyEl.scrollLeft > 2);
    } else {
      bodyEl.scrollLeft = headerEl.scrollLeft;
      setIsScrolled(headerEl.scrollLeft > 2);
    }

    requestAnimationFrame(() => {
      syncingRef.current = null;
    });
  }, []);

  useEffect(() => {
    const headerEl = headerScrollRef.current;
    const bodyEl = bodyScrollRef.current;
    if (!headerEl || !bodyEl) return;

    const onHeaderScroll = () => syncScroll("header");
    const onBodyScroll = () => syncScroll("body");

    headerEl.addEventListener("scroll", onHeaderScroll, { passive: true });
    bodyEl.addEventListener("scroll", onBodyScroll, { passive: true });

    return () => {
      headerEl.removeEventListener("scroll", onHeaderScroll);
      bodyEl.removeEventListener("scroll", onBodyScroll);
    };
  }, [syncScroll]);

  // Memoize filtered players to avoid re-filtering on every render
  const filteredPlayers = useMemo(() => {
    return players.filter((player) => {
      if (!filters.contracts.twoWay && isTwoWayContract(player)) return false;
      return true;
    });
  }, [players, filters.contracts.twoWay]);

  const showDraftPicks = filters.display.draftPicks;
  const showCapHolds = filters.display.capHolds;
  const showExceptions = filters.display.exceptions;
  const showDeadMoney = filters.display.deadMoney;

  return (
    <div className="relative">
      {/* Sticky header group (vertical sticky) */}
      <div
        className={cx(
          "sticky top-0 z-30",
          "shadow-[0_1px_3px_0_rgb(0_0_0/0.1),0_1px_2px_-1px_rgb(0_0_0/0.1)]",
          "bg-background",
          "will-change-transform"
        )}
      >
        {teamHeader}

        {/* TableHeader needs to horizontally scroll with the body, but the sticky
            container itself must NOT live inside an overflow container (otherwise
            position: sticky breaks in some browsers). So we use a second, synced scroller. */}
        <div
          ref={headerScrollRef}
          className={cx(
            "overflow-x-auto overscroll-x-contain",
            // Hide header scrollbar (body scrollbar is the primary)
            "[scrollbar-width:none] [-ms-overflow-style:none] [&::-webkit-scrollbar]:hidden"
          )}
        >
          <div className="min-w-max" style={{ minWidth: MIN_TABLE_WIDTH }}>
            <TableHeader years={SALARY_YEARS} />
          </div>
        </div>
      </div>

      {/* Shadow overlay for sticky column edge - appears when scrolled */}
      <div
        className={cx(
          "absolute top-0 bottom-0 pointer-events-none",
          "z-40",
          "transition-opacity duration-150",
          isScrolled ? "opacity-100" : "opacity-0"
        )}
        style={{
          left: STICKY_LEFT_WIDTH_PX,
          width: 10,
          background:
            "linear-gradient(to right, hsl(var(--border) / 0.35), transparent)",
        }}
      />

      {/* Body horizontal scroller */}
      <div
        ref={bodyScrollRef}
        className={cx(
          "overflow-x-auto",
          "overscroll-x-contain",
          "relative",
          // Hide scrollbar
          "[scrollbar-width:none] [-ms-overflow-style:none] [&::-webkit-scrollbar]:hidden"
        )}
      >
        <div className="min-w-max" style={{ minWidth: MIN_TABLE_WIDTH }}>
          {/* Player rows */}
          <div className="[&>*:first-child]:mt-1">
            {filteredPlayers.map((player) => (
              <PlayerRow
                key={player.id}
                player={player}
                onClick={() => onPlayerClick(player)}
                onAgentClick={(e) => onAgentClick(e, player)}
                showOptions={filters.contracts.options}
                showTwoWay={filters.contracts.twoWay}
              />
            ))}
          </div>

          {/* Empty state */}
          {filteredPlayers.length === 0 && (
            <div className="h-24 flex items-center justify-center text-muted-foreground text-sm">
              No players
            </div>
          )}

          {/* Supplementary rows (visibility controlled by Display filters) */}
          {showCapHolds && (capHolds.length > 0 ? (
            <CapHoldsSection capHolds={capHolds} />
          ) : (
            <PlaceholderSectionRow label="Cap Holds" />
          ))}

          {showExceptions && (exceptions.length > 0 ? (
            <ExceptionsSection exceptions={exceptions} />
          ) : (
            <PlaceholderSectionRow label="Exceptions" />
          ))}

          {showDeadMoney && (deadMoney.length > 0 ? (
            <DeadMoneySection deadMoney={deadMoney} />
          ) : (
            <PlaceholderSectionRow label="Dead Money" />
          ))}

          {/* Draft assets row */}
          {showDraftPicks && <DraftAssetsRow picks={picks} onPickClick={onPickClick} />}

          {/* Totals footer */}
          <TotalsFooter
            salaryByYear={salaryByYear}
            showTaxAprons={filters.financials.taxAprons}
            showCashVsCap={filters.financials.cashVsCap}
            showLuxuryTax={filters.financials.luxuryTax}
          />
        </div>
      </div>
    </div>
  );
}

export default SalaryTable;
