import { cx } from "@/lib/utils";

/**
 * Injuries placeholder for future phase
 * Will include: current injury report, availability tags, minutes restrictions
 */
export function InjuriesTab({ teamCode }: { teamCode: string }) {
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
              d="M12 2v20m10-10H2"
            />
          </svg>
        </div>
        <div className="text-sm font-medium text-foreground mb-1">
          Injury Report Coming Soon
        </div>
        <div className="text-xs text-muted-foreground">
          Availability, rehab timelines, and restrictions will be tracked here.
        </div>
      </div>

      <div className="space-y-3 opacity-50 pointer-events-none">
        <div className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
          Preview
        </div>
        <div className="space-y-2">
          {[
            { label: "Active injuries", value: "—" },
            { label: "Day-to-day", value: "—" },
            { label: "Out for season", value: "—" },
          ].map((entry) => (
            <div key={entry.label} className="flex justify-between items-baseline py-1">
              <span className="text-sm text-muted-foreground">{entry.label}</span>
              <span className="font-mono text-sm text-muted-foreground/50">
                {entry.value}
              </span>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
