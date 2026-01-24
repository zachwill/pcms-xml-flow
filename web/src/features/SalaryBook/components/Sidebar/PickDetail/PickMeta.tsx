import { cx } from "@/lib/utils";
import { ShieldIcon } from "./icons";

/**
 * Asset type badge
 */
export function AssetTypeBadge({ assetType }: { assetType: string }) {
  const colorMap: Record<string, string> = {
    OWN: "bg-green-100 text-green-800 dark:bg-green-900/30 dark:text-green-400",
    HAS: "bg-blue-100 text-blue-800 dark:bg-blue-900/30 dark:text-blue-400",
    TO: "bg-purple-100 text-purple-800 dark:bg-purple-900/30 dark:text-purple-400",
    OTHER:
      "bg-orange-100 text-orange-800 dark:bg-orange-900/30 dark:text-orange-400",
  };

  const labelMap: Record<string, string> = {
    OWN: "Own Pick",
    HAS: "Acquired",
    TO: "Traded Away",
    OTHER: "Conditional",
  };

  return (
    <span
      className={cx(
        "inline-flex px-2 py-1 rounded text-xs font-medium",
        colorMap[assetType] ?? "bg-muted text-muted-foreground"
      )}
    >
      {labelMap[assetType] ?? assetType}
    </span>
  );
}

/**
 * Protections display
 */
export function ProtectionsSection({ protections }: { protections: string }) {
  return (
    <div className="space-y-2">
      <div className="flex items-center gap-1.5">
        <ShieldIcon className="w-4 h-4 text-amber-500" />
        <span className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
          Protections
        </span>
      </div>
      <div
        className={cx(
          "p-3 rounded-lg",
          "bg-amber-50 border border-amber-200",
          "dark:bg-amber-900/20 dark:border-amber-800"
        )}
      >
        <span className="text-sm font-medium text-amber-800 dark:text-amber-400">
          {protections}
        </span>
      </div>
    </div>
  );
}

/**
 * Raw pick description
 */
export function PickDescription({ description }: { description: string }) {
  return (
    <div className="space-y-2">
      <div className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
        Pick Details
      </div>
      <div
        className={cx(
          "p-3 rounded-lg",
          "bg-muted/30 border border-border/50"
        )}
      >
        <p className="text-sm text-foreground">{description}</p>
      </div>
    </div>
  );
}
