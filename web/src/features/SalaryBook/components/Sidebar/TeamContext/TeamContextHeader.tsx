import { cx } from "@/lib/utils";

/**
 * Team header with logo placeholder and team name
 */
export function TeamContextHeader({
  teamCode,
  teamName,
  conference,
}: {
  teamCode: string;
  teamName: string;
  conference: string;
}) {
  return (
    <div className="flex items-center gap-3">
      {/* Team logo placeholder */}
      <div
        className={cx(
          "w-14 h-14 rounded-lg",
          "bg-muted",
          "flex items-center justify-center",
          "text-lg font-mono font-bold text-muted-foreground"
        )}
      >
        {teamCode}
      </div>
      <div>
        <div className="font-semibold text-lg">{teamName}</div>
        <div className="text-sm text-muted-foreground">
          {conference === "EAST" ? "Eastern" : "Western"} Conference
        </div>
      </div>
    </div>
  );
}
