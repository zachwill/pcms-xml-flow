import React from "react";
import { cx, formatters } from "@/lib/utils";
import type { CapHold } from "../../data";

const SALARY_YEARS = [2025, 2026, 2027, 2028, 2029] as const;

function getCapAmount(row: CapHold, year: (typeof SALARY_YEARS)[number]): number | null {
  switch (year) {
    case 2025:
      return row.cap_2025;
    case 2026:
      return row.cap_2026;
    case 2027:
      return row.cap_2027;
    case 2028:
      return row.cap_2028;
    case 2029:
      return row.cap_2029;
  }
}

function SectionHeader({ label, count }: { label: string; count: number }) {
  return (
    <div className={cx("bg-muted/10 dark:bg-muted/5", "border-b border-border/50")}>
      <div className="h-8 flex items-center text-xs">
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
                {label}
              </span>
              <span
                className={cx(
                  "inline-flex items-center justify-center",
                  "min-w-[16px] h-4 px-1 rounded-full",
                  "bg-muted text-muted-foreground",
                  "text-[9px] font-medium"
                )}
              >
                {count}
              </span>
            </div>
          </div>
        </div>

        {SALARY_YEARS.map((year) => (
          <div key={year} className="w-24 shrink-0" />
        ))}

        <div className="w-24 shrink-0" />
        <div className="w-40 pr-4 shrink-0" />
      </div>
    </div>
  );
}

export function CapHoldsSection({ capHolds }: { capHolds: CapHold[] }) {
  if (capHolds.length === 0) return null;

  return (
    <div>
      <SectionHeader label="Cap Holds" count={capHolds.length} />

      {capHolds.map((row) => {
        const title = row.player_name ?? row.amount_type_lk ?? "Cap Hold";
        const subtitle = row.amount_type_lk && row.player_name ? row.amount_type_lk : null;

        return (
          <div key={row.id} className={cx("border-b border-border/50", "hover:bg-muted/30 dark:hover:bg-muted/15", "transition-colors")}> 
            <div className="h-8 flex items-center text-xs">
              <div
                className={cx(
                  "w-52 shrink-0 pl-4",
                  "sticky left-0 z-[1]",
                  "bg-background",
                  "after:absolute after:right-0 after:top-0 after:bottom-0 after:w-px",
                  "after:bg-border/30",
                  "relative",
                  "hover:bg-muted/30 dark:hover:bg-muted/15"
                )}
              >
                <div className="grid grid-cols-[40px_1fr] items-center h-full">
                  <div />
                  <div className="pl-1 min-w-0">
                    <div className="truncate font-medium text-[12px]">{title}</div>
                    {subtitle && (
                      <div className="truncate text-[10px] text-muted-foreground">{subtitle}</div>
                    )}
                  </div>
                </div>
              </div>

              {SALARY_YEARS.map((year) => {
                const amt = getCapAmount(row, year);
                const isEmpty = amt === null;
                return (
                  <div
                    key={year}
                    className={cx(
                      "w-24 shrink-0 font-mono tabular-nums text-center",
                      isEmpty && "text-gray-400/50"
                    )}
                  >
                    {isEmpty ? "—" : formatters.compactCurrency(amt)}
                  </div>
                );
              })}

              <div className="w-24 shrink-0" />
              <div className="w-40 pr-4 shrink-0" />
            </div>
          </div>
        );
      })}
    </div>
  );
}

export default CapHoldsSection;
