import { cx } from "@/lib/utils";

/**
 * Draft placeholder for future phase
 * Will include: incoming picks, protections, swap rights
 */
export function DraftTab({ teamCode }: { teamCode: string }) {
  return (
    <div className="space-y-4">
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
              d="M7 4h10l4 4v12a2 2 0 01-2 2H7a2 2 0 01-2-2V6a2 2 0 012-2z"
            />
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth={1.5}
              d="M13 4v6h6"
            />
          </svg>
        </div>
        <div className="text-sm font-medium text-foreground mb-1">
          Draft Intel Coming Soon
        </div>
        <div className="text-xs text-muted-foreground">
          Pick inventory, protections, and swap rights will appear here once wired up.
        </div>
      </div>

      <div className="space-y-3 opacity-50 pointer-events-none">
        <div className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
          Preview
        </div>
        <div className="space-y-2">
          {[
            { label: "2026 1st", value: "—" },
            { label: "2027 2nd", value: "—" },
            { label: "Pick swaps", value: "—" },
          ].map((pick) => (
            <div key={pick.label} className="flex justify-between items-baseline py-1">
              <span className="text-sm text-muted-foreground">{pick.label}</span>
              <span className="font-mono text-sm text-muted-foreground/50">
                {pick.value}
              </span>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
