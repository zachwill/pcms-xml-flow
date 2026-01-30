/**
 * AgentDetail — Sidebar entity view for a selected agent
 *
 * Shows agency information and client list when an agent is pushed
 * onto the sidebar stack (clicked from PlayerRow agent name).
 *
 * Sections:
 * 1. Agent header (initials avatar, name, agency)
 * 2. Agency info card (agency name)
 * 3. Client roster (clickable player list with salary summaries)
 */

import React from "react";

import { cx, formatters, focusRing } from "@/lib/utils";
import { useShellSidebarContext, type AgentEntity } from "@/features/SalaryBook/shell";
import { TwoWaySalaryBadge } from "../MainCanvas/badges";
import { useAgent, useTeams, type AgentClientPlayer } from "../../hooks";

// ============================================================================
// Types
// ============================================================================

export interface AgentDetailProps {
  /** Agent entity from sidebar stack */
  entity: AgentEntity;
  /** Additional className */
  className?: string;
}

// ============================================================================
// Subcomponents
// ============================================================================

/**
 * Avatar with agent initials
 */
function AgentAvatar({
  agentName,
  className,
}: {
  agentName: string;
  className?: string;
}) {
  // Get initials from agent name
  const initials = agentName
    .split(" ")
    .map((n) => n[0])
    .join("")
    .toUpperCase()
    .slice(0, 2);

  return (
    <div
      className={cx(
        "w-16 h-16 rounded-xl",
        "bg-gradient-to-br from-violet-500/20 to-violet-600/30",
        "flex items-center justify-center",
        "text-xl font-bold text-violet-600 dark:text-violet-400",
        "ring-2 ring-violet-200 dark:ring-violet-800/50",
        className
      )}
    >
      {initials}
    </div>
  );
}

/**
 * Agent header section with avatar, name, agency
 */
function AgentHeader({
  agentName,
  agencyName,
  clientCount,
}: {
  agentName: string;
  agencyName: string | null;
  clientCount: number;
}) {
  return (
    <div className="flex flex-col items-center text-center space-y-3">
      <AgentAvatar agentName={agentName} />
      <div className="space-y-1">
        <h2 className="text-xl font-semibold text-foreground">{agentName}</h2>
        {agencyName && (
          <div className="text-sm text-muted-foreground">{agencyName}</div>
        )}
        <div className="text-xs text-muted-foreground/80">
          {clientCount} NBA client{clientCount !== 1 ? "s" : ""}
        </div>
      </div>
    </div>
  );
}

/**
 * Team avatar (logo) with fallback to tricode
 */
function TeamAvatar({
  teamId,
  teamCode,
  teamName,
  className,
}: {
  teamId: number | null;
  teamCode: string;
  teamName: string;
  className?: string;
}) {
  const [logoErrored, setLogoErrored] = React.useState(false);

  const logoUrl = teamId
    ? `https://cdn.nba.com/logos/nba/${teamId}/primary/L/logo.svg`
    : null;

  React.useEffect(() => {
    setLogoErrored(false);
  }, [teamId]);

  return (
    <div
      className={cx(
        "rounded-full border border-border bg-background overflow-hidden",
        "flex items-center justify-center",
        className
      )}
      title={teamName}
      aria-label={teamName}
    >
      {logoUrl && !logoErrored ? (
        <img
          src={logoUrl}
          alt={`${teamName} logo`}
          className="w-full h-full object-contain p-0.5"
          loading="lazy"
          decoding="async"
          onError={() => setLogoErrored(true)}
        />
      ) : (
        <span className="text-[9px] font-semibold text-muted-foreground">
          {teamCode}
        </span>
      )}
    </div>
  );
}

/** Fallback headshot for when NBA CDN image fails */
const FALLBACK_HEADSHOT_DATA_URI =
  "data:image/svg+xml;utf8," +
  "<svg xmlns='http://www.w3.org/2000/svg' width='64' height='64'>" +
  "<rect width='100%25' height='100%25' fill='%23e5e7eb'/>" +
  "<text x='50%25' y='52%25' dominant-baseline='middle' text-anchor='middle' " +
  "fill='%239ca3af' font-family='ui-sans-serif,system-ui' font-size='10'>" +
  "NBA" +
  "</text>" +
  "</svg>";

/**
 * Format player name for row display
 * Requirement: LAST, FIRST (fallback to player_name)
 */
function getClientRowName(client: AgentClientPlayer): string {
  const last = client.display_last_name?.trim() || "";
  const first = client.display_first_name?.trim() || "";

  if (last && first) return `${last}, ${first}`;
  if (last) return last;
  if (first) return first;
  return client.player_name;
}

/**
 * Client row — single player in the client list
 */
function ClientRow({
  client,
  teamName,
  teamId,
  onClick,
}: {
  client: AgentClientPlayer;
  teamName: string;
  teamId: number | null;
  onClick: () => void;
}) {
  const rowName = getClientRowName(client);

  // Build headshot URL from player id
  const headshotUrl = `https://cdn.nba.com/headshots/nba/latest/1040x760/${client.id}.png`;

  // Calculate current year salary (2025)
  const currentSalary = client.cap_2025;

  // Calculate total contract value
  const totalValue = [
    client.cap_2025,
    client.cap_2026,
    client.cap_2027,
    client.cap_2028,
    client.cap_2029,
    client.cap_2030,
  ].reduce<number>((sum, val) => sum + Number(val ?? 0), 0);

  // Build metadata line: AGE YRS · YOS (team implied by avatar; fallback to team name)
  const metaParts: string[] = [];

  const age = client.age;
  if (age !== null && age !== undefined) {
    metaParts.push(`${Number(age).toFixed(1)} YRS`);
  }

  const yos = client.years_of_service;
  if (yos !== null && yos !== undefined) {
    const yosNum = Number(yos);
    if (Number.isFinite(yosNum)) {
      metaParts.push(yosNum <= 0 ? "Rookie" : `${yosNum} YOS`);
    }
  }

  const detailLine = metaParts.length > 0 ? metaParts.join(" · ") : teamName;

  return (
    <button
      type="button"
      onClick={onClick}
      className={cx(
        "w-full text-left",
        // Match Main View row density
        "flex items-center justify-between gap-2",
        "py-0.5 px-1.5 rounded-md",
        "hover:bg-muted/50 transition-colors",
        focusRing()
      )}
    >
      {/* Team avatar + player headshot (side-by-side) */}
      <div className="flex items-center gap-1.5 flex-shrink-0">
        <TeamAvatar
          teamId={teamId}
          teamCode={client.team_code}
          teamName={teamName}
          className="w-7 h-7"
        />
        <div className="w-7 h-7 rounded border border-border bg-background overflow-hidden">
          <img
            src={headshotUrl}
            alt={rowName}
            className="w-full h-full object-cover object-top bg-muted"
            loading="lazy"
            decoding="async"
            onError={(e) => {
              if (e.currentTarget.src !== FALLBACK_HEADSHOT_DATA_URI) {
                e.currentTarget.src = FALLBACK_HEADSHOT_DATA_URI;
              }
            }}
          />
        </div>
      </div>

      <div className="flex-1 min-w-0">
        {/* Row A: Name */}
        <div className="h-[26px] flex items-end min-w-0">
          <div className="font-medium text-[14px] truncate">{rowName}</div>
        </div>

        {/* Row B: Details (match Main View secondary line rhythm) */}
        <div className="h-[18px] -mt-px flex items-start min-w-0 leading-none text-[10px] text-muted-foreground/80 tabular-nums">
          <span className="truncate">{detailLine}</span>
        </div>
      </div>

      {/* Salary info */}
      <div className="flex-shrink-0 text-right">
        {client.is_two_way ? (
          <div className="grid place-items-center h-[44px]">
            <TwoWaySalaryBadge />
          </div>
        ) : currentSalary !== null && currentSalary > 0 ? (
          <>
            <div className="h-[26px] flex items-end justify-end">
              <div className="font-mono tabular-nums text-sm font-medium whitespace-nowrap">
                {formatters.compactCurrency(currentSalary)}
              </div>
            </div>
            <div className="h-[18px] -mt-px flex items-start justify-end">
              <div className="text-[10px] leading-none tabular-nums whitespace-nowrap text-gray-400 dark:text-gray-500">
                {formatters.compactCurrency(totalValue)} total
              </div>
            </div>
          </>
        ) : (
          <div className="grid place-items-center h-[44px]">
            <div className="text-[10px] leading-none font-mono tabular-nums text-muted-foreground/60 italic whitespace-nowrap">
              No salary
            </div>
          </div>
        )}
      </div>

      {/* Chevron indicator */}
      <svg
        className="w-4 h-4 text-muted-foreground/50"
        fill="none"
        stroke="currentColor"
        viewBox="0 0 24 24"
        aria-hidden="true"
      >
        <path
          strokeLinecap="round"
          strokeLinejoin="round"
          strokeWidth={2}
          d="M9 5l7 7-7 7"
        />
      </svg>
    </button>
  );
}

/**
 * Client roster list
 */
function ClientRoster({
  clients,
  getTeamInfo,
  onClientClick,
}: {
  clients: AgentClientPlayer[];
  getTeamInfo: (teamCode: string) => { teamName: string; teamId: number | null };
  onClientClick: (client: AgentClientPlayer) => void;
}) {
  if (clients.length === 0) {
    return (
      <div className="space-y-3">
        <div className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
          Client Roster
        </div>
        <div className="p-4 rounded-lg bg-muted/30 text-sm text-muted-foreground italic text-center">
          No NBA clients found
        </div>
      </div>
    );
  }

  // Sort clients by salary (highest first)
  const sortedClients = [...clients].sort((a, b) => {
    const aSalary = Number(a.cap_2025 ?? 0);
    const bSalary = Number(b.cap_2025 ?? 0);
    return bSalary - aSalary;
  });

  // Calculate total book value
  const totalBook = clients.reduce<number>(
    (sum, c) => sum + Number(c.cap_2025 ?? 0),
    0
  );

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <div className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
          Client Roster
        </div>
        <div className="text-xs text-muted-foreground">
          Book: <span className="font-mono tabular-nums font-medium">{formatters.compactCurrency(totalBook)}</span>
        </div>
      </div>

      <div className="divide-y divide-border/50">
        {sortedClients.map((client) => {
          const { teamName, teamId } = getTeamInfo(client.team_code);

          return (
            <ClientRow
              key={client.id}
              client={client}
              teamName={teamName}
              teamId={teamId}
              onClick={() => onClientClick(client)}
            />
          );
        })}
      </div>
    </div>
  );
}

/**
 * Loading skeleton
 */
function AgentDetailSkeleton() {
  return (
    <div className="space-y-6 animate-pulse">
      {/* Header skeleton */}
      <div className="flex flex-col items-center space-y-3">
        <div className="w-16 h-16 rounded-xl bg-muted" />
        <div className="space-y-2 text-center">
          <div className="h-6 w-36 bg-muted rounded mx-auto" />
          <div className="h-4 w-28 bg-muted rounded mx-auto" />
        </div>
      </div>

      {/* Client roster skeleton */}
      <div className="space-y-3">
        <div className="h-3 w-24 bg-muted rounded" />
        <div className="space-y-2">
          {[1, 2, 3, 4, 5].map((i) => (
            <div key={i} className="h-16 bg-muted/30 rounded-lg" />
          ))}
        </div>
      </div>
    </div>
  );
}

/**
 * Error state
 */
function AgentDetailError({
  agentName,
  error,
}: {
  agentName: string;
  error: Error;
}) {
  return (
    <div className="space-y-4">
      <div className="flex flex-col items-center space-y-3">
        <AgentAvatar agentName={agentName} />
        <div className="space-y-1 text-center">
          <h2 className="text-xl font-semibold text-foreground">{agentName}</h2>
          <div className="text-sm text-muted-foreground">Agent</div>
        </div>
      </div>

      <div className="p-4 rounded-lg bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800">
        <div className="text-sm text-red-700 dark:text-red-400">
          {error.message}
        </div>
      </div>
    </div>
  );
}

// ============================================================================
// Main Component
// ============================================================================

/**
 * AgentDetail — Full agent view for sidebar
 *
 * Fetches agent data from API including client list.
 * Each client is clickable to push a PlayerEntity onto the sidebar stack.
 */
export function AgentDetail({ entity, className }: AgentDetailProps) {
  const { pushEntity } = useShellSidebarContext();
  const { getTeam } = useTeams();

  // Fetch agent data
  const { agent, isLoading, error } = useAgent(entity.agentId);

  const getTeamInfo = (teamCode: string): { teamName: string; teamId: number | null } => {
    const team = getTeam(teamCode);
    return {
      teamName: team?.name ?? teamCode,
      teamId: team?.team_id ?? null,
    };
  };

  // Handle client click — push player entity onto stack
  const handleClientClick = (client: AgentClientPlayer) => {
    pushEntity({
      type: "player",
      playerId: Number(client.id),
      playerName: getClientRowName(client),
      teamCode: client.team_code,
    });
  };

  // Show skeleton while loading
  if (isLoading) {
    return <AgentDetailSkeleton />;
  }

  // Show error state
  if (error) {
    return <AgentDetailError agentName={entity.agentName} error={error} />;
  }

  // Fallback if no agent data (shouldn't happen after loading)
  if (!agent) {
    return (
      <AgentDetailError
        agentName={entity.agentName}
        error={new Error("Agent not found")}
      />
    );
  }

  return (
    <div className={cx("space-y-6", className)}>
      {/* Agent Header */}
      <AgentHeader
        agentName={agent.name}
        agencyName={agent.agency_name}
        clientCount={agent.clients.length}
      />

      {/* Client Roster */}
      <ClientRoster
        clients={agent.clients}
        getTeamInfo={getTeamInfo}
        onClientClick={handleClientClick}
      />
    </div>
  );
}
