import { cx, formatters } from "@/lib/utils";
import type { PlayerContractBonus } from "../../../hooks";

function likelihoodLabel(value: boolean | null): { label: string; tone: "green" | "amber" | "muted" } {
  if (value === true) return { label: "Likely", tone: "green" };
  if (value === false) return { label: "Unlikely", tone: "amber" };
  return { label: "Unknown", tone: "muted" };
}

function Badge({ label, tone }: { label: string; tone: "green" | "amber" | "muted" }) {
  const toneClasses = {
    green: "bg-emerald-100 text-emerald-700 dark:bg-emerald-900/40 dark:text-emerald-200",
    amber: "bg-amber-100 text-amber-700 dark:bg-amber-900/40 dark:text-amber-200",
    muted: "bg-muted/60 text-muted-foreground",
  };

  return (
    <span
      className={cx(
        "px-1.5 py-0.5 rounded-full",
        "text-[9px] font-semibold uppercase tracking-wide",
        toneClasses[tone]
      )}
    >
      {label}
    </span>
  );
}

function formatYear(year: number | null): string {
  if (!year) return "—";
  return `${String(year).slice(-2)}-${String(year + 1).slice(-2)}`;
}

function formatAmount(value: number | null): string {
  return value === null ? "—" : formatters.compactCurrency(value);
}

/**
 * ContractBonuses — Detailed incentive rows from pcms.contract_bonuses
 */
export function ContractBonuses({ bonuses }: { bonuses: PlayerContractBonus[] }) {
  if (bonuses.length === 0) {
    return (
      <div className="space-y-3">
        <div className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
          Incentives
        </div>
        <div className="p-3 rounded-lg bg-muted/30 text-sm text-muted-foreground italic">
          No incentive detail on file.
        </div>
      </div>
    );
  }

  const bonusesByYear = bonuses.reduce<Record<string, PlayerContractBonus[]>>(
    (acc, bonus) => {
      const key = bonus.salary_year ? String(bonus.salary_year) : "unknown";
      (acc[key] ||= []).push(bonus);
      return acc;
    },
    {}
  );

  const yearKeys = Object.keys(bonusesByYear).sort((a, b) => Number(a) - Number(b));

  return (
    <div className="space-y-3">
      <div className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
        Incentives
      </div>

      {yearKeys.map((yearKey) => {
        const yearBonuses = bonusesByYear[yearKey] ?? [];
        const yearNumber = yearKey === "unknown" ? null : Number(yearKey);

        const totals = yearBonuses.reduce(
          (acc, bonus) => {
            const amount = bonus.bonus_amount ?? 0;
            if (bonus.is_likely === true) acc.likely += amount;
            else if (bonus.is_likely === false) acc.unlikely += amount;
            return acc;
          },
          { likely: 0, unlikely: 0 }
        );

        return (
          <div key={yearKey} className="space-y-2">
            <div className="flex items-center justify-between">
              <div className="text-[11px] font-semibold text-muted-foreground tabular-nums">
                {yearNumber ? formatYear(yearNumber) : "Year unknown"}
              </div>
              <div className="text-[10px] text-muted-foreground tabular-nums">
                {totals.likely > 0 && `Likely ${formatAmount(totals.likely)}`}
                {totals.likely > 0 && totals.unlikely > 0 ? " · " : ""}
                {totals.unlikely > 0 && `Unlikely ${formatAmount(totals.unlikely)}`}
              </div>
            </div>
            <div className="space-y-2">
              {yearBonuses.map((bonus) => {
                const { label, tone } = likelihoodLabel(bonus.is_likely);
                const title = bonus.clause_name ?? bonus.bonus_type_lk ?? "Bonus";

                return (
                  <div
                    key={bonus.bonus_id}
                    className="rounded-md border border-border/50 bg-muted/30 px-3 py-2 space-y-1"
                  >
                    <div className="flex items-start justify-between gap-2">
                      <div className="space-y-0.5">
                        <div className="text-sm font-medium text-foreground">
                          {title}
                        </div>
                        {bonus.criteria_description && (
                          <div className="text-[11px] text-muted-foreground">
                            {bonus.criteria_description}
                          </div>
                        )}
                        {bonus.bonus_type_lk && bonus.bonus_type_lk !== title && (
                          <div className="text-[10px] text-muted-foreground">
                            {bonus.bonus_type_lk}
                          </div>
                        )}
                      </div>
                      <div className="text-right space-y-1">
                        <div className="font-mono text-xs tabular-nums text-muted-foreground">
                          {formatAmount(bonus.bonus_amount)}
                        </div>
                        <Badge label={label} tone={tone} />
                      </div>
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        );
      })}
    </div>
  );
}
