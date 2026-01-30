import { cx } from "@/lib/utils";

/**
 * Conveyance history placeholder
 */
export function ConveyanceHistory() {
  return (
    <div className="space-y-2">
      <div className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
        Conveyance History
      </div>
      <div
        className={cx(
          "p-3 rounded-lg",
          "bg-muted/20 border border-dashed border-border"
        )}
      >
        <p className="text-sm text-muted-foreground italic">
          Pick transaction history will be displayed here when available.
        </p>
      </div>
    </div>
  );
}
