/**
 * TotalsFooter — Team salary totals, cap space, and tax/apron/luxury-tax lines
 *
 * Non-sticky footer at the bottom of each team section displaying:
 * - Total salary per year (monospace, tabular-nums for alignment)
 * - Cap space per year (green positive, red negative)
 * - Optional financial rows controlled by filters:
 *   - Tax/Aprons (tax line + 1st/2nd apron room)
 *   - Cash vs Cap (tax_total vs cap_total)
 *   - Luxury Tax (luxury tax bill)
 *
 * Design Decision: Non-sticky per spec. Sticky footers create complexity
 * with sticky headers and section-pushing behavior.
 */

import React from "react";
import { cx, formatters } from "@/lib/utils";
import type { TeamSalary } from "../../data";

// ============================================================================
// Types
// ============================================================================

export interface TotalsFooterProps {
  /** Team salary data by year (2025-2030) */
  salaryByYear: Map<number, TeamSalary>;
  /** Show tax line + apron lines */
  showTaxAprons?: boolean;
  /** Show a row with tax_total (useful proxy for "cash vs cap") */
  showCashVsCap?: boolean;
  /** Show luxury tax bill row (when available) */
  showLuxuryTax?: boolean;
}

// Contract years to display (6-year horizon; aligns with salary_book_warehouse cap_2025..cap_2030)
const SALARY_YEARS = [2025, 2026, 2027, 2028, 2029] as const;

// ============================================================================
// Shared pieces
// ============================================================================

function StickyLabelCell({ children }: { children: React.ReactNode }) {
  return (
    <div
      className={cx(
        "w-52 pl-4 shrink-0",
        // Sticky positioning for horizontal scroll
        "sticky left-0 z-[1]",
        // Opaque background matching footer background
        "bg-muted/20 dark:bg-muted/10",
        // Visual separator on right edge
        "after:absolute after:right-0 after:top-0 after:bottom-0 after:w-px",
        "after:bg-border/30",
        "relative"
      )}
    >
      {children}
    </div>
  );
}

function UnderOverCell({
  isOver,
  roomUnder,
}: {
  isOver: boolean;
  roomUnder: number;
}) {
  return (
    <div
      className={cx(
        "w-24 font-mono tabular-nums text-center",
        isOver ? "text-red-500" : "text-green-600 dark:text-green-400"
      )}
    >
      {isOver ? <>-{formatters.compactCurrency(Math.abs(roomUnder))}</> : "UNDER"}
    </div>
  );
}

// ============================================================================
// Rows
// ============================================================================

function TotalSalaryRow({ salaryByYear }: Pick<TotalsFooterProps, "salaryByYear">) {
  return (
    <div className="h-9 flex items-center text-sm font-medium">
      <StickyLabelCell>Total</StickyLabelCell>

      {SALARY_YEARS.map((year) => {
        const data = salaryByYear.get(year);
        return (
          <div key={year} className="w-24 font-mono tabular-nums text-center">
            {data ? formatters.compactCurrency(data.cap_total) : "—"}
          </div>
        );
      })}

      {/* Total column spacer */}
      <div className="w-24" />

      {/* Right spacer (matches agent column width) */}
      <div className="w-40 pr-4" />
    </div>
  );
}

function TaxTotalRow({ salaryByYear }: Pick<TotalsFooterProps, "salaryByYear">) {
  return (
    <div className="h-7 flex items-center text-xs text-muted-foreground">
      <StickyLabelCell>Tax Total</StickyLabelCell>

      {SALARY_YEARS.map((year) => {
        const data = salaryByYear.get(year);
        return (
          <div key={year} className="w-24 font-mono tabular-nums text-center">
            {data ? formatters.compactCurrency(data.tax_total) : "—"}
          </div>
        );
      })}

      <div className="w-24" />
      <div className="w-40 pr-4" />
    </div>
  );
}

function CapSpaceRow({ salaryByYear }: Pick<TotalsFooterProps, "salaryByYear">) {
  return (
    <div className="h-7 flex items-center text-xs text-muted-foreground">
      <StickyLabelCell>Cap Space</StickyLabelCell>

      {SALARY_YEARS.map((year) => {
        const data = salaryByYear.get(year);
        const capSpace = data?.cap_space ?? null;

        return (
          <div
            key={year}
            className={cx(
              "w-24 font-mono tabular-nums text-center",
              capSpace !== null && capSpace >= 0 && "text-green-600 dark:text-green-400",
              capSpace !== null && capSpace < 0 && "text-red-500"
            )}
          >
            {capSpace !== null ? (
              <>
                {capSpace >= 0 ? "+" : ""}
                {formatters.compactCurrency(capSpace)}
              </>
            ) : (
              "—"
            )}
          </div>
        );
      })}

      <div className="w-24" />
      <div className="w-40 pr-4" />
    </div>
  );
}

function TaxLineRow({ salaryByYear }: Pick<TotalsFooterProps, "salaryByYear">) {
  return (
    <div className="h-7 flex items-center text-xs text-muted-foreground border-t border-border/30">
      <StickyLabelCell>Tax Line</StickyLabelCell>

      {SALARY_YEARS.map((year) => {
        const data = salaryByYear.get(year);
        if (!data) return <div key={year} className="w-24 text-center">—</div>;
        return (
          <UnderOverCell
            key={year}
            isOver={data.is_over_tax}
            roomUnder={data.room_under_tax}
          />
        );
      })}

      <div className="w-24" />
      <div className="w-40 pr-4" />
    </div>
  );
}

function FirstApronRow({ salaryByYear }: Pick<TotalsFooterProps, "salaryByYear">) {
  return (
    <div className="h-7 flex items-center text-xs text-muted-foreground">
      <StickyLabelCell>1st Apron</StickyLabelCell>

      {SALARY_YEARS.map((year) => {
        const data = salaryByYear.get(year);
        if (!data) return <div key={year} className="w-24 text-center">—</div>;
        return (
          <UnderOverCell
            key={year}
            isOver={data.is_over_first_apron}
            roomUnder={data.room_under_first_apron}
          />
        );
      })}

      <div className="w-24" />
      <div className="w-40 pr-4" />
    </div>
  );
}

function SecondApronRow({ salaryByYear }: Pick<TotalsFooterProps, "salaryByYear">) {
  return (
    <div className="h-7 flex items-center text-xs text-muted-foreground">
      <StickyLabelCell>2nd Apron</StickyLabelCell>

      {SALARY_YEARS.map((year) => {
        const data = salaryByYear.get(year);
        if (!data) return <div key={year} className="w-24 text-center">—</div>;
        return (
          <UnderOverCell
            key={year}
            isOver={data.is_over_second_apron}
            roomUnder={data.room_under_second_apron}
          />
        );
      })}

      <div className="w-24" />
      <div className="w-40 pr-4" />
    </div>
  );
}

function LuxuryTaxRow({ salaryByYear }: Pick<TotalsFooterProps, "salaryByYear">) {
  return (
    <div className="h-7 flex items-center text-xs text-muted-foreground">
      <StickyLabelCell>Luxury Tax</StickyLabelCell>

      {SALARY_YEARS.map((year) => {
        const data = salaryByYear.get(year);
        const bill = data?.luxury_tax_bill ?? null;

        return (
          <div
            key={year}
            className={cx(
              "w-24 font-mono tabular-nums text-center",
              data?.is_over_tax ? "text-red-500" : "text-muted-foreground/60"
            )}
          >
            {bill !== null ? formatters.compactCurrency(bill) : "—"}
          </div>
        );
      })}

      <div className="w-24" />
      <div className="w-40 pr-4" />
    </div>
  );
}

// ============================================================================
// Main
// ============================================================================

export function TotalsFooter({
  salaryByYear,
  showTaxAprons = true,
  showCashVsCap = false,
  showLuxuryTax = false,
}: TotalsFooterProps) {
  return (
    <div className="bg-muted/20 dark:bg-muted/10">
      <TotalSalaryRow salaryByYear={salaryByYear} />
      <CapSpaceRow salaryByYear={salaryByYear} />

      {showCashVsCap && <TaxTotalRow salaryByYear={salaryByYear} />}

      {showTaxAprons && (
        <>
          <TaxLineRow salaryByYear={salaryByYear} />
          <FirstApronRow salaryByYear={salaryByYear} />
          <SecondApronRow salaryByYear={salaryByYear} />
        </>
      )}

      {showLuxuryTax && <LuxuryTaxRow salaryByYear={salaryByYear} />}
    </div>
  );
}

export default TotalsFooter;
