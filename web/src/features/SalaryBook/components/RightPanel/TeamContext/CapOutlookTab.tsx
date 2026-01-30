import { useMemo } from "react";
import { cx, formatters } from "@/lib/utils";
import type { TeamSalary } from "../../../data";
import type { TwoWayCapacity } from "../../../hooks";

/**
 * Single financial stat row
 */
function StatRow({
  label,
  value,
  valueClassName,
}: {
  label: string;
  value: string | number | null;
  valueClassName?: string;
}) {
  const displayValue =
    value === null ? "—" : typeof value === "number" ? formatters.compactCurrency(value) : value;

  return (
    <div className="flex justify-between items-baseline py-1.5">
      <span className="text-sm text-muted-foreground">{label}</span>
      <span
        className={cx(
          "font-mono tabular-nums text-sm font-medium",
          valueClassName
        )}
      >
        {displayValue}
      </span>
    </div>
  );
}

/**
 * Simple stat row for non-currency values
 */
function SimpleStatRow({
  label,
  value,
  valueClassName,
}: {
  label: string;
  value: string | number | null;
  valueClassName?: string;
}) {
  const displayValue = value === null ? "—" : value;

  return (
    <div className="flex justify-between items-baseline py-1.5">
      <span className="text-sm text-muted-foreground">{label}</span>
      <span
        className={cx(
          "font-mono tabular-nums text-sm font-medium",
          valueClassName
        )}
      >
        {displayValue}
      </span>
    </div>
  );
}

/**
 * Cap space display with color coding
 */
function CapSpaceStat({
  label,
  value,
}: {
  label: string;
  value: number | null;
}) {
  if (value === null) {
    return <StatRow label={label} value="—" />;
  }

  const isPositive = value >= 0;
  const displayValue = isPositive
    ? `+${formatters.compactCurrency(value)}`
    : formatters.compactCurrency(value);

  return (
    <StatRow
      label={label}
      value={displayValue}
      valueClassName={isPositive ? "text-emerald-600 dark:text-emerald-400" : "text-red-500"}
    />
  );
}

/**
 * Get color class for "room under" values:
 * - Green if under by $10M+
 * - Neutral (no color) if under by less than $10M
 * - Red if negative (over)
 */
function getRoomUnderColorClass(value: number | null): string | undefined {
  if (value === null) return undefined;
  if (value < 0) return "text-red-500";
  if (value >= 10_000_000) return "text-emerald-600 dark:text-emerald-400";
  return undefined; // neutral/black for 0 <= value < 10M
}

/**
 * Tax status indicator badge
 */
function TaxStatusBadge({
  isOverTax,
  isOverFirstApron,
  isOverSecondApron,
}: {
  isOverTax: boolean;
  isOverFirstApron: boolean;
  isOverSecondApron: boolean;
}) {
  let status = "Under Tax";
  let colorClass = "bg-emerald-100 text-emerald-800 dark:bg-emerald-900/30 dark:text-emerald-400";

  if (isOverSecondApron) {
    status = "2nd Apron";
    colorClass = "bg-red-100 text-red-800 dark:bg-red-900/30 dark:text-red-400";
  } else if (isOverFirstApron) {
    status = "1st Apron";
    colorClass = "bg-amber-100 text-amber-800 dark:bg-amber-900/30 dark:text-amber-400";
  } else if (isOverTax) {
    status = "Tax Payer";
    colorClass = "bg-orange-100 text-orange-800 dark:bg-orange-900/30 dark:text-orange-400";
  }

  return (
    <span
      className={cx(
        "inline-flex px-2 py-0.5 rounded text-xs font-medium",
        colorClass
      )}
    >
      {status}
    </span>
  );
}

/**
 * Year-by-year salary projections mini-chart
 * 
 * Performance: Bar calculations are memoized to prevent recalculation on parent re-renders.
 * Animation: Uses CSS transitions only. Initial mount animates via CSS, subsequent updates
 * transition smoothly without re-triggering from-zero animation.
 */
function SalaryProjections({
  salaryByYear,
}: {
  salaryByYear: Map<number, { cap_total: number; cap_space: number }>;
}) {
  const years = [2025, 2026, 2027, 2028, 2029, 2030];

  // Memoize bar data to avoid recalculating on every render
  const barData = useMemo(() => {
    const values = years.map((y) => salaryByYear.get(y)?.cap_total ?? 0);
    const maxValue = Math.max(...values, 1);
    
    return years.map((year, i) => {
      const value = values[i] ?? 0;
      const heightPercent = (value / maxValue) * 100;
      const barHeight = Math.max(heightPercent, 4);
      return { year, value, barHeight };
    });
  }, [salaryByYear]);

  return (
    <div className="space-y-2">
      <div className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
        Salary Projection
      </div>
      <div className="flex items-end gap-1 h-20">
        {barData.map(({ year, value, barHeight }) => (
          <div key={year} className="flex-1 flex flex-col items-center gap-1 h-full">
            <div className="flex-1 w-full flex items-end">
              <div
                className={cx(
                  "w-full rounded-t transition-all duration-300",
                  value > 0 ? "bg-blue-500/80" : "bg-muted"
                )}
                style={{ height: `${barHeight}%` }}
              />
            </div>
            <span className="text-[10px] text-muted-foreground tabular-nums">
              {`${year.toString().slice(-2)}-${(year + 1).toString().slice(-2)}`}
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}

/**
 * Two-Way section
 * - Shows the number of two-way players (from team_salary_warehouse)
 * - Shows games remaining context (from team_two_way_capacity)
 */
function TwoWayCapacitySection({
  capacity,
  twoWayPlayerCount,
}: {
  capacity: TwoWayCapacity | null;
  twoWayPlayerCount: number | null;
}) {
  // If we have neither a count nor capacity context, hide the section.
  if (!capacity && twoWayPlayerCount === null) {
    return null;
  }

  const isUnder15Contracts = (capacity?.current_contract_count ?? 0) < 15;
  const gamesRemainingValue = isUnder15Contracts
    ? capacity?.under_15_games_remaining ?? null
    : capacity?.games_remaining ?? null;

  // Red text if games remaining is below 30
  const gamesRemainingColor =
    gamesRemainingValue !== null && gamesRemainingValue < 30
      ? "text-red-500"
      : undefined;

  return (
    <div className="border-t border-border pt-4">
      <div className="text-xs font-medium uppercase tracking-wide text-muted-foreground mb-3">
        Two-Way
      </div>
      <div className="space-y-0.5">
        <SimpleStatRow
          label="Standard Contracts"
          value={capacity?.current_contract_count ?? null}
        />
        <SimpleStatRow
          label="Two-Way Contracts"
          value={twoWayPlayerCount}
        />
        <SimpleStatRow
          label="Games Remaining"
          value={gamesRemainingValue}
          valueClassName={gamesRemainingColor}
        />
      </div>
    </div>
  );
}

/**
 * Cap Outlook tab content
 */
export function CapOutlookTab({
  currentYearTotal,
  currentYearCapSpace,
  currentSalary,
  salaryByYear,
  twoWayCapacity,
}: {
  currentYearTotal: number | null;
  currentYearCapSpace: number | null;
  currentSalary: TeamSalary | undefined;
  salaryByYear: Map<number, TeamSalary>;
  twoWayCapacity: TwoWayCapacity | null;
}) {
  return (
    <>
      {/* Cap Outlook Section */}
      <div className="border-t border-border pt-4">
        <div className="flex items-center justify-between mb-3">
          <div className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
            2025-26 Cap Outlook
          </div>
          {currentSalary && (
            <TaxStatusBadge
              isOverTax={currentSalary.is_over_tax}
              isOverFirstApron={currentSalary.is_over_first_apron}
              isOverSecondApron={currentSalary.is_over_second_apron}
            />
          )}
        </div>

        <div className="space-y-0.5">
          <StatRow label="Total Salary" value={currentYearTotal} />
          <CapSpaceStat label="Cap Space" value={currentYearCapSpace} />

          {currentSalary && (
            <>
              <StatRow
                label="Room Under Tax"
                value={currentSalary.room_under_tax}
                valueClassName={getRoomUnderColorClass(currentSalary.room_under_tax)}
              />
              <StatRow
                label="Room Under 1st Apron"
                value={currentSalary.room_under_first_apron}
                valueClassName={getRoomUnderColorClass(currentSalary.room_under_first_apron)}
              />
              <StatRow
                label="Room Under 2nd Apron"
                value={currentSalary.room_under_second_apron}
                valueClassName={getRoomUnderColorClass(currentSalary.room_under_second_apron)}
              />
            </>
          )}
        </div>
      </div>

      {/* Salary Projections */}
      {salaryByYear.size > 0 && (
        <div className="border-t border-border pt-4">
          <SalaryProjections salaryByYear={salaryByYear} />
        </div>
      )}

      {/* Two-Way */}
      <TwoWayCapacitySection
        capacity={twoWayCapacity}
        twoWayPlayerCount={currentSalary?.two_way_row_count ?? null}
      />
    </>
  );
}
