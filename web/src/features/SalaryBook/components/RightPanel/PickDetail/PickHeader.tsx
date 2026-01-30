import { cx } from "@/lib/utils";
import { SwapIcon } from "./icons";

/**
 * Round badge with visual styling
 */
function RoundBadge({
  round,
  className,
}: {
  round: number;
  className?: string;
}) {
  const isFirst = round === 1;
  return (
    <div
      className={cx(
        "w-16 h-16 rounded-xl",
        "flex flex-col items-center justify-center",
        "font-bold",
        isFirst
          ? "bg-gradient-to-br from-amber-400 to-amber-600 text-amber-950"
          : "bg-gradient-to-br from-slate-400 to-slate-600 text-slate-950",
        className
      )}
    >
      <span className="text-2xl tabular-nums">{round}</span>
      <span className="text-[10px] uppercase tracking-wide opacity-80">
        {isFirst ? "1st" : "2nd"}
      </span>
    </div>
  );
}

/**
 * Pick header section with year, round badge, team info
 */
export function PickHeader({
  year,
  round,
  teamCode,
  teamName,
  isSwap,
}: {
  year: number;
  round: number;
  teamCode: string;
  teamName: string;
  isSwap: boolean;
}) {
  return (
    <div className="flex items-start gap-4">
      <RoundBadge round={round} />
      <div className="flex-1 space-y-1">
        <h2 className="text-xl font-semibold text-foreground">
          {year} Draft Pick
        </h2>
        <div className="text-sm text-muted-foreground">
          Round {round} • {teamName || teamCode}
        </div>
        {isSwap && (
          <div className="flex items-center gap-1.5 mt-2">
            <SwapIcon className="w-4 h-4 text-purple-500" />
            <span
              className={cx(
                "inline-flex px-2 py-0.5 rounded text-xs font-medium",
                "bg-purple-100 text-purple-800",
                "dark:bg-purple-900/30 dark:text-purple-400"
              )}
            >
              Pick Swap
            </span>
          </div>
        )}
      </div>
    </div>
  );
}
