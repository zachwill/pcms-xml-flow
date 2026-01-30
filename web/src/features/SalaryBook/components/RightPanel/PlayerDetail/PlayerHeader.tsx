import React from "react";
import { cx } from "@/lib/utils";

/**
 * Player headshot with fallback to initials
 */
export function PlayerPhoto({
  playerId,
  playerName,
  className,
}: {
  playerId?: number | null;
  playerName: string;
  className?: string;
}) {
  const headshotUrl = playerId
    ? `https://cdn.nba.com/headshots/nba/latest/1040x760/${playerId}.png`
    : null;

  // Simple inline SVG fallback so we don't collapse layout on 404s.
  const fallbackHeadshot =
    "data:image/svg+xml;utf8," +
    "<svg xmlns='http://www.w3.org/2000/svg' width='64' height='64'>" +
    "<rect width='100%25' height='100%25' fill='%23e5e7eb'/>" +
    "<text x='50%25' y='52%25' dominant-baseline='middle' text-anchor='middle' " +
    "fill='%239ca3af' font-family='ui-sans-serif,system-ui' font-size='10'>" +
    "NBA" +
    "</text>" +
    "</svg>";

  return (
    <div
      className={cx(
        "w-20 h-20 rounded border border-border bg-background overflow-hidden",
        className
      )}
    >
      <img
        src={headshotUrl || fallbackHeadshot}
        alt={playerName}
        className="w-full h-full object-cover object-top bg-muted"
        onError={(e) => {
          // Avoid infinite loop if fallback fails for some reason
          if (e.currentTarget.src !== fallbackHeadshot) {
            e.currentTarget.src = fallbackHeadshot;
          }
        }}
      />
    </div>
  );
}

/**
 * Player header section with photo, name, team info
 * Horizontal layout: IMAGE | NAME + TEAM + AGE/YOS
 */
export function PlayerHeader({
  playerId,
  playerName,
  teamCode,
  teamName,
  position,
  age,
  experience,
}: {
  playerId?: number | null;
  playerName: string;
  teamCode: string;
  teamName: string;
  position?: string | null;
  age?: number | null;
  experience?: number | null;
}) {
  // Build metadata line (matching PlayerRow format)
  const metaParts: string[] = [];
  if (age) metaParts.push(`${Number(age).toFixed(1)} YRS`);
  if (experience !== null && experience !== undefined)
    metaParts.push(experience === 0 ? "Rookie" : `${experience} YOS`);

  return (
    <div className="flex items-center gap-4">
      <PlayerPhoto playerId={playerId} playerName={playerName} className="shrink-0" />
      <div className="space-y-0.5">
        <h2 className="text-lg font-semibold text-foreground">{playerName}</h2>
        <div className="text-sm text-muted-foreground">{teamName}</div>
        {metaParts.length > 0 && (
          <div className="text-xs text-muted-foreground/80 tabular-nums">
            {metaParts.join(" · ")}
          </div>
        )}
      </div>
    </div>
  );
}
