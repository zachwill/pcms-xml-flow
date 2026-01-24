import { cx } from "@/lib/utils";

/**
 * Trade restrictions section
 * 
 * Color coding matches the table:
 * - Trade Kicker: orange
 * - No-Trade Clause: red
 * - Consent Required: red
 * - Pre-consented: green (positive indicator)
 * - Poison Pill: red + italic
 */
export function TradeRestrictions({
  isNoTrade,
  isTradeBonus,
  tradeBonusPercent,
  isConsentRequired,
  isPreconsented,
  isPoisonPill,
}: {
  isNoTrade: boolean;
  isTradeBonus: boolean;
  tradeBonusPercent: number | null;
  isConsentRequired: boolean;
  isPreconsented: boolean;
  isPoisonPill?: boolean;
}) {
  const tradeKickerLabel = (() => {
    const pct = tradeBonusPercent === null ? null : Number(tradeBonusPercent);
    if (pct !== null && Number.isFinite(pct) && pct > 0) {
      const pctLabel = pct % 1 === 0 ? pct.toFixed(0) : String(pct);
      return `${pctLabel}% Trade Kicker`;
    }
    return "Trade Kicker";
  })();

  type Restriction = {
    label: string;
    active: boolean;
    color: "red" | "orange" | "green";
    italic?: boolean;
  };

  const restrictions: Restriction[] = [
    { label: tradeKickerLabel, active: isTradeBonus, color: "orange" },
    { label: "No-Trade Clause", active: isNoTrade, color: "red" },
    { label: "Consent Required", active: isConsentRequired, color: "red" },
    { label: "Poison Pill", active: !!isPoisonPill, color: "red", italic: true },
    { label: "Pre-consented", active: isPreconsented, color: "green" },
  ];

  const activeRestrictions = restrictions.filter((r) => r.active);

  if (activeRestrictions.length === 0) {
    return null;
  }

  const colorClasses = {
    red: "bg-red-100 text-red-700 dark:bg-red-900/50 dark:text-red-300",
    orange: "bg-orange-100 text-orange-700 dark:bg-orange-900/50 dark:text-orange-300",
    green: "bg-green-100 text-green-700 dark:bg-green-900/50 dark:text-green-300",
  };

  return (
    <div className="space-y-3">
      <div className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
        Trade Restrictions
      </div>
      <div className="flex flex-wrap gap-2">
        {activeRestrictions.map((restriction) => (
          <span
            key={restriction.label}
            className={cx(
              "inline-flex items-center",
              "px-1.5 py-0.5 rounded-full",
              "text-[9px] font-semibold uppercase tracking-wide",
              "leading-none",
              colorClasses[restriction.color],
              restriction.italic && "italic"
            )}
          >
            {restriction.label}
          </span>
        ))}
      </div>
    </div>
  );
}
