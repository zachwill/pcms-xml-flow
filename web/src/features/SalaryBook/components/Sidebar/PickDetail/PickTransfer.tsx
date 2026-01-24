import { cx } from "@/lib/utils";
import { ArrowRightIcon } from "./icons";

/**
 * Team card for origin/destination
 */
function TeamCard({
  label,
  teamCode,
  teamName,
  isOrigin,
}: {
  label: string;
  teamCode: string;
  teamName: string | null;
  isOrigin?: boolean;
}) {
  return (
    <div
      className={cx(
        "flex-1 p-3 rounded-lg",
        "border border-border/50",
        isOrigin ? "bg-muted/20" : "bg-muted/40"
      )}
    >
      <div className="text-[10px] font-medium uppercase tracking-wide text-muted-foreground mb-1.5">
        {label}
      </div>
      <div className="flex items-center gap-2">
        <div
          className={cx(
            "w-8 h-8 rounded flex items-center justify-center",
            "text-xs font-bold font-mono",
            "bg-muted text-muted-foreground"
          )}
        >
          {teamCode}
        </div>
        <span className="text-sm font-medium truncate">
          {teamName || teamCode}
        </span>
      </div>
    </div>
  );
}

/**
 * Origin/Destination transfer display
 */
export function PickTransfer({
  originTeamCode,
  originTeamName,
  destinationTeamCode,
  destinationTeamName,
}: {
  originTeamCode: string;
  originTeamName: string | null;
  destinationTeamCode: string;
  destinationTeamName: string | null;
}) {
  const isSameTeam = originTeamCode === destinationTeamCode;

  if (isSameTeam) {
    return (
      <div className="space-y-2">
        <div className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
          Ownership
        </div>
        <TeamCard
          label="Own Pick"
          teamCode={originTeamCode}
          teamName={originTeamName}
        />
      </div>
    );
  }

  return (
    <div className="space-y-2">
      <div className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
        Transfer
      </div>
      <div className="flex items-center gap-2">
        <TeamCard
          label="From"
          teamCode={originTeamCode}
          teamName={originTeamName}
          isOrigin
        />
        <ArrowRightIcon className="w-5 h-5 text-muted-foreground flex-shrink-0" />
        <TeamCard
          label="To"
          teamCode={destinationTeamCode}
          teamName={destinationTeamName}
        />
      </div>
    </div>
  );
}
