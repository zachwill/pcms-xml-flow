import { cx } from "@/lib/utils";

/**
 * Photo placeholder with player initials
 */
export function PlayerPhoto({
  playerName,
  className,
}: {
  playerName: string;
  className?: string;
}) {
  // Get initials from player name
  const initials = playerName
    .split(" ")
    .map((n) => n[0])
    .join("")
    .toUpperCase()
    .slice(0, 2);

  return (
    <div
      className={cx(
        "w-20 h-20 rounded-full",
        "bg-gradient-to-br from-muted to-muted/50",
        "flex items-center justify-center",
        "text-2xl font-bold text-muted-foreground",
        "ring-2 ring-border",
        className
      )}
    >
      {initials}
    </div>
  );
}

/**
 * Player header section with photo, name, team info
 */
export function PlayerHeader({
  playerName,
  teamCode,
  teamName,
  position,
  age,
  experience,
}: {
  playerName: string;
  teamCode: string;
  teamName: string;
  position?: string | null;
  age?: number | null;
  experience?: number | null;
}) {
  // Build metadata line
  const metaParts: string[] = [];
  if (position) metaParts.push(position);
  if (age) metaParts.push(`${age} yrs old`);
  if (experience !== null && experience !== undefined)
    metaParts.push(`${experience} yr${experience !== 1 ? "s" : ""} exp`);

  return (
    <div className="flex flex-col items-center text-center space-y-3">
      <PlayerPhoto playerName={playerName} />
      <div className="space-y-1">
        <h2 className="text-xl font-semibold text-foreground">{playerName}</h2>
        <div className="text-sm text-muted-foreground">{teamName}</div>
        {metaParts.length > 0 && (
          <div className="text-xs text-muted-foreground/80">
            {metaParts.join(" • ")}
          </div>
        )}
      </div>
    </div>
  );
}
