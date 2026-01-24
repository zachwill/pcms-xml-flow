import { cx } from "@/lib/utils";

/**
 * Team Stats placeholder for future phase
 * Will include: record, standings, efficiency metrics
 */
export function TeamStatsTab({ teamCode }: { teamCode: string }) {
  return (
    <div className="space-y-4">
      {/* Coming Soon Notice */}
      <div
        className={cx(
          "p-4 rounded-lg",
          "bg-muted/30 border border-border/50",
          "text-center"
        )}
      >
        <div className="w-10 h-10 rounded-full bg-muted flex items-center justify-center mx-auto mb-3">
          <svg
            className="w-5 h-5 text-muted-foreground"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
          >
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth={1.5}
              d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z"
            />
          </svg>
        </div>
        <div className="text-sm font-medium text-foreground mb-1">
          Team Stats Coming Soon
        </div>
        <div className="text-xs text-muted-foreground">
          Record, standings, and efficiency metrics will be available in a future update.
        </div>
      </div>

      {/* Placeholder Stats Preview */}
      <div className="space-y-3 opacity-50 pointer-events-none">
        <div className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
          Preview
        </div>
        <div className="space-y-2">
          {[
            { label: "Record", value: "— — —" },
            { label: "Conference Rank", value: "—" },
            { label: "Offensive Rating", value: "—" },
            { label: "Defensive Rating", value: "—" },
            { label: "Net Rating", value: "—" },
          ].map((stat) => (
            <div key={stat.label} className="flex justify-between items-baseline py-1">
              <span className="text-sm text-muted-foreground">{stat.label}</span>
              <span className="font-mono text-sm text-muted-foreground/50">
                {stat.value}
              </span>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
