import { cx, formatters } from "@/lib/utils";
import { OptionBadge } from "../../MainCanvas/badges";
import type { ContractOption } from "../../../data";

interface YearData {
  year: number;
  salary: number | null;
  option: string | null;
}

/**
 * Year-by-year breakdown table
 */
export function YearByYearBreakdown({ years }: { years: YearData[] }) {
  // Filter to only years with salary
  const activeYears = years.filter((y) => y.salary !== null && y.salary > 0);

  if (activeYears.length === 0) {
    return (
      <div className="space-y-3">
        <div className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
          Year-by-Year
        </div>
        <div className="p-3 rounded-lg bg-muted/30 text-sm text-muted-foreground italic">
          No salary data available
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-3">
      <div className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
        Year-by-Year
      </div>
      <div className="space-y-1">
        {activeYears.map((yearData) => (
          <div
            key={yearData.year}
            className={cx(
              "flex items-center justify-between",
              "py-2 px-3 rounded",
              "hover:bg-muted/30 transition-colors"
            )}
          >
            <div className="flex items-center gap-2">
              <span className="text-sm text-muted-foreground tabular-nums">
                {String(yearData.year).slice(-2)}-{String(yearData.year + 1).slice(-2)}
              </span>
              {/* Don't show options for the current season (25-26 / cap_2025) */}
              {yearData.option && yearData.year !== 2025 && (
                <OptionBadge option={yearData.option as ContractOption} />
              )}
            </div>
            <span className="font-mono tabular-nums text-sm font-medium">
              {formatters.compactCurrency(yearData.salary!)}
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}

export type { YearData };
