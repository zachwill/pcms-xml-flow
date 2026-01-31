import { cx, formatters } from "@/lib/utils";
import type { PlayerContractProtection } from "../../../hooks";

const COVERAGE_LABELS: Record<string, string> = {
  FULL: "Full",
  NONE: "None",
  NOCND: "None",
  PARTIAL: "Partial",
  PART: "Partial",
  PARTCND: "Partial/Cond",
  COND: "Conditional",
};

function coverageTone(coverage: string | null | undefined): "green" | "amber" | "red" | "muted" {
  const value = (coverage ?? "").toUpperCase();
  if (value.startsWith("FULL")) return "green";
  if (value.startsWith("NONE") || value.startsWith("NO")) return "red";
  if (value.startsWith("PART") || value.startsWith("COND")) return "amber";
  return "muted";
}

function Badge({ label, tone }: { label: string; tone: "green" | "amber" | "red" | "muted" }) {
  const toneClasses = {
    green: "bg-emerald-100 text-emerald-700 dark:bg-emerald-900/40 dark:text-emerald-200",
    amber: "bg-amber-100 text-amber-700 dark:bg-amber-900/40 dark:text-amber-200",
    red: "bg-red-100 text-red-700 dark:bg-red-900/40 dark:text-red-200",
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

function buildConditionSummary(protection: PlayerContractProtection): string | null {
  const conditionLines = protection.conditions
    .map((cond) => cond.criteria_description || cond.clause_name)
    .filter((text): text is string => Boolean(text));

  if (conditionLines.length > 0) {
    return conditionLines.join(" · ");
  }

  if (protection.conditional_protection_comments) {
    return protection.conditional_protection_comments;
  }

  return null;
}

/**
 * ContractGuarantees — Detailed protection rows from pcms.contract_protections
 */
export function ContractGuarantees({
  protections,
}: {
  protections: PlayerContractProtection[];
}) {
  if (protections.length === 0) {
    return (
      <div className="space-y-3">
        <div className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
          Guarantees
        </div>
        <div className="p-3 rounded-lg bg-muted/30 text-sm text-muted-foreground italic">
          No protection detail on file.
        </div>
      </div>
    );
  }

  const protectionsByYear = protections.reduce<Record<string, PlayerContractProtection[]>>(
    (acc, protection) => {
      const key = protection.salary_year ? String(protection.salary_year) : "unknown";
      (acc[key] ||= []).push(protection);
      return acc;
    },
    {}
  );

  const yearKeys = Object.keys(protectionsByYear).sort((a, b) => Number(a) - Number(b));

  return (
    <div className="space-y-3">
      <div className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
        Guarantees
      </div>

      {yearKeys.map((yearKey) => {
        const yearProtections = protectionsByYear[yearKey] ?? [];
        const yearNumber = yearKey === "unknown" ? null : Number(yearKey);

        return (
          <div key={yearKey} className="space-y-2">
            <div className="text-[11px] font-semibold text-muted-foreground tabular-nums">
              {yearNumber ? formatYear(yearNumber) : "Year unknown"}
            </div>
            <div className="space-y-2">
              {yearProtections.map((protection) => {
                const coverageLabel = protection.protection_coverage_lk
                  ? COVERAGE_LABELS[protection.protection_coverage_lk] ??
                    protection.protection_coverage_lk
                  : "Unknown";
                const tone = coverageTone(protection.protection_coverage_lk);
                const amount =
                  protection.effective_protection_amount ?? protection.protection_amount;
                const conditionSummary = buildConditionSummary(protection);

                return (
                  <div
                    key={protection.protection_id}
                    className="rounded-md border border-border/50 bg-muted/30 px-3 py-2 space-y-1"
                  >
                    <div className="flex items-center justify-between gap-2">
                      <div className="text-sm font-medium text-foreground">
                        Coverage
                      </div>
                      <div className="flex items-center gap-2">
                        <Badge label={coverageLabel} tone={tone} />
                        <span className="font-mono text-xs tabular-nums text-muted-foreground">
                          {formatAmount(amount)}
                        </span>
                      </div>
                    </div>

                    {conditionSummary && (
                      <div className="text-[11px] text-muted-foreground">
                        {conditionSummary}
                      </div>
                    )}
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
