import { useState, useEffect, useCallback } from "react";
import type { Agent, SalaryBookPlayer } from "../data";

/**
 * Agent client from API response (simplified player data)
 */
interface AgentClient {
  id: string;
  player_name: string;
  team_code: string;
  position: string | null;

  // Bun SQL can return Postgres `numeric` values as strings.
  // Keep this loose and coerce in `mapApiToAgentDetail`.
  cap_2025: string | number | null;
  cap_2026: string | number | null;
  cap_2027: string | number | null;
  cap_2028: string | number | null;
  cap_2029: string | number | null;
  cap_2030: string | number | null;
}

/**
 * Agent API response shape (from /api/salary-book/agent/:agentId)
 */
interface AgentApiResponse {
  id: string;
  name: string;
  agency_id: string | null;
  agency_name: string | null;
  email: string | null;
  phone: string | null;
  clients: AgentClient[];
}

/**
 * Agent detail with full client data
 */
export interface AgentDetail extends Agent {
  clients: AgentClientPlayer[];
}

/**
 * Client player info for agent detail view
 */
export interface AgentClientPlayer {
  id: string;
  player_name: string;
  team_code: string;
  position: string | null;
  cap_2025: number | null;
  cap_2026: number | null;
  cap_2027: number | null;
  cap_2028: number | null;
  cap_2029: number | null;
  cap_2030: number | null;
}

/**
 * Return type for useAgent hook
 */
export interface UseAgentReturn {
  /** Agent details including clients */
  agent: AgentDetail | null;
  /** Loading state */
  isLoading: boolean;
  /** Error state */
  error: Error | null;
  /** Refetch agent data */
  refetch: () => Promise<void>;
}

/**
 * Maps API response to AgentDetail type
 */
function mapApiToAgentDetail(data: AgentApiResponse): AgentDetail {
  const asNumberOrNull = (value: unknown): number | null => {
    if (value === null || value === undefined) return null;
    const n = Number(value);
    return Number.isFinite(n) ? n : null;
  };

  return {
    id: data.id,
    name: data.name,
    agency_id: data.agency_id,
    agency_name: data.agency_name,
    email: data.email,
    phone: data.phone,
    clients: data.clients.map((client) => ({
      id: client.id,
      player_name: client.player_name,
      team_code: client.team_code,
      position: client.position,
      cap_2025: asNumberOrNull(client.cap_2025),
      cap_2026: asNumberOrNull(client.cap_2026),
      cap_2027: asNumberOrNull(client.cap_2027),
      cap_2028: asNumberOrNull(client.cap_2028),
      cap_2029: asNumberOrNull(client.cap_2029),
      cap_2030: asNumberOrNull(client.cap_2030),
    })),
  };
}

/**
 * Hook to fetch agent details and their clients
 *
 * Fetches from /api/salary-book/agent/:agentId and provides:
 * - Agent info (name, agency, contact)
 * - Client list with salary data
 * - Loading and error states
 * - Refetch function
 *
 * @param agentId - Agent ID to fetch. Pass null to skip fetch.
 *
 * @example
 * ```tsx
 * const { agent, isLoading, error } = useAgent("12345");
 *
 * if (isLoading) return <Skeleton />;
 * if (error) return <Error message={error.message} />;
 * if (!agent) return <NotFound />;
 *
 * return (
 *   <div>
 *     <h2>{agent.name}</h2>
 *     <p>{agent.agency_name}</p>
 *     <ul>
 *       {agent.clients.map(client => (
 *         <li key={client.id}>{client.player_name}</li>
 *       ))}
 *     </ul>
 *   </div>
 * );
 * ```
 */
export function useAgent(agentId: string | number | null): UseAgentReturn {
  const [agent, setAgent] = useState<AgentDetail | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<Error | null>(null);

  const fetchAgent = useCallback(async () => {
    if (agentId === null) {
      setAgent(null);
      setIsLoading(false);
      setError(null);
      return;
    }

    setIsLoading(true);
    setError(null);

    try {
      const response = await fetch(
        `/api/salary-book/agent/${encodeURIComponent(String(agentId))}`
      );

      if (!response.ok) {
        if (response.status === 404) {
          throw new Error("Agent not found");
        }
        throw new Error(`Failed to fetch agent: ${response.status}`);
      }

      const data: AgentApiResponse = await response.json();
      const mapped = mapApiToAgentDetail(data);

      setAgent(mapped);
    } catch (err) {
      setError(err instanceof Error ? err : new Error(String(err)));
      setAgent(null);
    } finally {
      setIsLoading(false);
    }
  }, [agentId]);

  useEffect(() => {
    fetchAgent();
  }, [fetchAgent]);

  return {
    agent,
    isLoading,
    error,
    refetch: fetchAgent,
  };
}
