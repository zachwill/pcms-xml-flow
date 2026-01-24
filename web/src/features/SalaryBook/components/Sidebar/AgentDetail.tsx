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

import { cx, formatters, focusRing } from "@/lib/utils";
import { useSalaryBookContext } from "../../SalaryBook";
import { useAgent, useTeams, type AgentClientPlayer } from "../../hooks";
import type { AgentEntity } from "../../hooks";

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
 * Client row — single player in the client list
 */
function ClientRow({
  client,
  teamName,
  onClick,
}: {
  client: AgentClientPlayer;
  teamName: string;
  onClick: () => void;
}) {
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

  return (
    <button
      type="button"
      onClick={onClick}
      className={cx(
        "w-full text-left",
        "flex items-center justify-between gap-3",
        "py-3 px-3 rounded-lg",
        "hover:bg-muted/50 transition-colors",
        focusRing()
      )}
    >
      <div className="flex-1 min-w-0">
        {/* Player name */}
        <div className="font-medium text-sm truncate">{client.player_name}</div>

        {/* Team + position */}
        <div className="text-xs text-muted-foreground flex items-center gap-1.5">
          <span className="font-mono">{client.team_code}</span>
          <span>•</span>
          <span>{teamName}</span>
        </div>
      </div>

      {/* Salary info */}
      <div className="flex-shrink-0 text-right">
        {currentSalary !== null && currentSalary > 0 ? (
          <>
            <div className="font-mono tabular-nums text-sm font-medium">
              {formatters.compactCurrency(currentSalary)}
            </div>
            <div className="text-xs text-muted-foreground">
              {formatters.compactCurrency(totalValue)} total
            </div>
          </>
        ) : (
          <div className="text-xs text-muted-foreground italic">No salary</div>
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
  getTeamName,
  onClientClick,
}: {
  clients: AgentClientPlayer[];
  getTeamName: (teamCode: string) => string;
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
        {sortedClients.map((client) => (
          <ClientRow
            key={client.id}
            client={client}
            teamName={getTeamName(client.team_code)}
            onClick={() => onClientClick(client)}
          />
        ))}
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
  const { pushEntity } = useSalaryBookContext();
  const { getTeam } = useTeams();

  // Fetch agent data
  const { agent, isLoading, error } = useAgent(entity.agentId);

  // Helper to get team name from code
  const getTeamName = (teamCode: string): string => {
    return getTeam(teamCode)?.name ?? teamCode;
  };

  // Handle client click — push player entity onto stack
  const handleClientClick = (client: AgentClientPlayer) => {
    pushEntity({
      type: "player",
      playerId: Number(client.id),
      playerName: client.player_name,
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
        getTeamName={getTeamName}
        onClientClick={handleClientClick}
      />
    </div>
  );
}
