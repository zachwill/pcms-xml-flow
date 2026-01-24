import { cx, formatters } from "@/lib/utils";

interface YearData {
  year: number;
  salary: number | null;
  option: string | null;
}

/**
 * Option badge component
 */
function OptionBadge({ option }: { option: string }) {
  const colorMap: Record<string, string> = {
    PO: "bg-blue-100 text-blue-800 dark:bg-blue-900/30 dark:text-blue-400",
    TO: "bg-purple-100 text-purple-800 dark:bg-purple-900/30 dark:text-purple-400",
    ETO: "bg-orange-100 text-orange-800 dark:bg-orange-900/30 dark:text-orange-400",
  };

  return (
    <span
      className={cx(
        "inline-flex px-1.5 py-0.5 rounded text-[10px] font-medium",
        colorMap[option] ?? "bg-muted text-muted-foreground"
      )}
    >
      {option}
    </span>
  );
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
                {yearData.year - 1}-{String(yearData.year).slice(-2)}
              </span>
              {/* Don't show options for the current season (25-26 / cap_2025) */}
              {yearData.option && yearData.year !== 2025 && (
                <OptionBadge option={yearData.option} />
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
