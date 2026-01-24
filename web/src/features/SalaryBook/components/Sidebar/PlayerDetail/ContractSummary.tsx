import { cx, formatters, focusRing } from "@/lib/utils";

/**
 * Contract summary card
 */
export function ContractSummary({
  totalValue,
  contractYears,
  isTwoWay,
  agentName,
  agencyName,
  onAgentClick,
}: {
  totalValue: number;
  contractYears: number;
  isTwoWay: boolean;
  agentName: string | null;
  agencyName: string | null;
  onAgentClick?: () => void;
}) {
  return (
    <div className="space-y-3">
      <div className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
        Contract
      </div>
      <div
        className={cx(
          "p-4 rounded-lg",
          "bg-muted/30 border border-border/50",
          "space-y-3"
        )}
      >
        {/* Contract value headline */}
        <div className="flex items-baseline justify-between">
          <span className="text-sm text-muted-foreground">Total Value</span>
          <span className="font-mono tabular-nums text-lg font-semibold">
            {formatters.compactCurrency(totalValue)}
          </span>
        </div>

        {/* Years */}
        <div className="flex items-baseline justify-between">
          <span className="text-sm text-muted-foreground">Years</span>
          <span className="text-sm font-medium">
            {contractYears} yr{contractYears !== 1 ? "s" : ""}
          </span>
        </div>

        {/* Two-Way Badge */}
        {isTwoWay && (
          <div className="flex items-center justify-between">
            <span className="text-sm text-muted-foreground">Contract Type</span>
            <span
              className={cx(
                "inline-flex px-2 py-0.5 rounded text-xs font-medium",
                "bg-amber-100 text-amber-800",
                "dark:bg-amber-900/30 dark:text-amber-400"
              )}
            >
              Two-Way
            </span>
          </div>
        )}

        {/* Agent */}
        {agentName && (
          <div className="flex items-baseline justify-between">
            <span className="text-sm text-muted-foreground">Agent</span>
            {onAgentClick ? (
              <button
                type="button"
                onClick={onAgentClick}
                className={cx(
                  "text-sm font-medium text-blue-600 dark:text-blue-400",
                  "hover:underline",
                  focusRing()
                )}
              >
                {agentName}
              </button>
            ) : (
              <span className="text-sm font-medium">{agentName}</span>
            )}
          </div>
        )}

        {/* Agency */}
        {agencyName && (
          <div className="flex items-baseline justify-between">
            <span className="text-sm text-muted-foreground">Agency</span>
            <span className="text-sm">{agencyName}</span>
          </div>
        )}
      </div>
    </div>
  );
}
