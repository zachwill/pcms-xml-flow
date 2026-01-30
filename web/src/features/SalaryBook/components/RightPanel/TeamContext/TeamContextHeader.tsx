import React from "react";
import { cx } from "@/lib/utils";

/**
 * Team header with logo placeholder and team name
 */
export function TeamContextHeader({
  teamCode,
  teamId,
  teamName,
  conference,
}: {
  teamCode: string;
  teamId?: number | null;
  teamName: string;
  conference: string;
}) {
  const [logoErrored, setLogoErrored] = React.useState(false);

  const logoUrl = teamId
    ? `https://cdn.nba.com/logos/nba/${teamId}/primary/L/logo.svg`
    : null;

  React.useEffect(() => {
    setLogoErrored(false);
  }, [teamId]);

  return (
    <div className="flex items-center gap-3">
      {/* Team logo */}
      <div
        className={cx(
          "w-14 h-14 rounded-lg",
          "bg-background border border-border",
          "flex items-center justify-center",
          "overflow-hidden"
        )}
      >
        {logoUrl && !logoErrored ? (
          <img
            src={logoUrl}
            alt={`${teamName} logo`}
            className="w-full h-full object-contain"
            onError={() => setLogoErrored(true)}
          />
        ) : (
          <span
            className="text-lg font-mono font-bold text-muted-foreground"
            aria-hidden="true"
            title="Team logo unavailable"
          >
            {teamCode}
          </span>
        )}
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
