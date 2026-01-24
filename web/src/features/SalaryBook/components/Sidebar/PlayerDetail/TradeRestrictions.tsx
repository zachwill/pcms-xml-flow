import { cx } from "@/lib/utils";

/**
 * Trade restrictions section
 */
export function TradeRestrictions({
  isNoTrade,
  isTradeBonus,
  isConsentRequired,
  isPreconsented,
}: {
  isNoTrade: boolean;
  isTradeBonus: boolean;
  isConsentRequired: boolean;
  isPreconsented: boolean;
}) {
  const restrictions: { label: string; active: boolean }[] = [
    { label: "No-Trade Clause", active: isNoTrade },
    { label: "Trade Bonus", active: isTradeBonus },
    { label: "Consent Required", active: isConsentRequired },
    { label: "Pre-consented", active: isPreconsented },
  ];

  const activeRestrictions = restrictions.filter((r) => r.active);

  if (activeRestrictions.length === 0) {
    return null;
  }

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
              "inline-flex px-2 py-1 rounded text-xs font-medium",
              "bg-red-100 text-red-800",
              "dark:bg-red-900/30 dark:text-red-400"
            )}
          >
            {restriction.label}
          </span>
        ))}
      </div>
    </div>
  );
}
