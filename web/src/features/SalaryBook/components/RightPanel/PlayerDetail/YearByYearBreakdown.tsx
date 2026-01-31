import { cx, formatters } from "@/lib/utils";
import { OptionBadge } from "../../MainCanvas/badges";
import type { ContractOption } from "../../../data";

interface YearData {
  year: number;
  salary: number | null;
  option: string | null;
  guaranteedAmount?: number | null;
  guaranteeStatus?: "FULL" | "PARTIAL" | "NONE" | "CONDITIONAL" | null;
  likelyBonus?: number | null;
  unlikelyBonus?: number | null;
}

const GUARANTEE_LABELS: Record<string, string> = {
  FULL: "Full",
  PARTIAL: "Partial",
  NONE: "None",
  CONDITIONAL: "Conditional",
};

const formatCurrency = (value: number | null | undefined): string => {
  if (value === null || value === undefined) return "—";
  return formatters.compactCurrency(value);
};

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
        {activeYears.map((yearData) => {
          const guaranteeLabel = yearData.guaranteeStatus
            ? GUARANTEE_LABELS[yearData.guaranteeStatus] ?? yearData.guaranteeStatus
            : null;

          const showGuarantee =
            guaranteeLabel ||
            (yearData.guaranteedAmount !== null && yearData.guaranteedAmount !== undefined);

          const showLikely =
            yearData.likelyBonus !== null &&
            yearData.likelyBonus !== undefined &&
            yearData.likelyBonus !== 0;

          const showUnlikely =
            yearData.unlikelyBonus !== null &&
            yearData.unlikelyBonus !== undefined &&
            yearData.unlikelyBonus !== 0;

          return (
            <div
              key={yearData.year}
              className={cx(
                "space-y-1",
                "py-2 px-3 rounded",
                "hover:bg-muted/30 transition-colors"
              )}
            >
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2">
                  <span className="text-sm text-muted-foreground tabular-nums">
                    {String(yearData.year).slice(-2)}-
                    {String(yearData.year + 1).slice(-2)}
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

              {showGuarantee && (
                <div className="flex items-baseline justify-between text-[11px] text-muted-foreground">
                  <span>
                    Guarantee{guaranteeLabel ? `: ${guaranteeLabel}` : ""}
                  </span>
                  <span className="font-mono tabular-nums">
                    {formatCurrency(yearData.guaranteedAmount)}
                  </span>
                </div>
              )}

              {showLikely && (
                <div className="flex items-baseline justify-between text-[11px] text-muted-foreground">
                  <span>Likely Bonus</span>
                  <span className="font-mono tabular-nums">
                    {formatCurrency(yearData.likelyBonus)}
                  </span>
                </div>
              )}

              {showUnlikely && (
                <div className="flex items-baseline justify-between text-[11px] text-muted-foreground">
                  <span>Unlikely Bonus</span>
                  <span className="font-mono tabular-nums">
                    {formatCurrency(yearData.unlikelyBonus)}
                  </span>
                </div>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}

export type { YearData };
