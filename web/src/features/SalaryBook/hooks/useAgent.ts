import useSWR from "swr";
import type { Agent } from "../data";

/**
 * Agent client row from API response (simplified player data)
 *
 * NOTE: /api/salary-book/agent/:agentId currently returns `player_id`, not `id`.
 */
interface AgentClientApiResponse {
  player_id: string | number;
  player_name: string;
  team_code: string;

  // Bun SQL can return Postgres `numeric` values as strings.
  cap_2025: string | number | null;
  cap_2026: string | number | null;
  cap_2027: string | number | null;
  cap_2028: string | number | null;
  cap_2029: string | number | null;
  cap_2030: string | number | null;

  // Flags
  is_two_way?: boolean | null;

  // Optional fields that may appear later
  years_of_service?: number | null;
  position?: string | null;
}

/**
 * Agent API response shape (from /api/salary-book/agent/:agentId)
 */
interface AgentApiResponse {
  // Backend currently uses `agent_id`; tolerate `id` in case it changes.
  agent_id?: string | number;
  id?: string | number;

  name: string;
  agency_id: string | null;
  agency_name: string | null;

  // Not currently returned by the API, but part of our `Agent` type.
  email?: string | null;
  phone?: string | null;

  clients: AgentClientApiResponse[];
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
  is_two_way: boolean;
}

/**
 * Agent detail with full client data
 */
export interface AgentDetail extends Agent {
  clients: AgentClientPlayer[];
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

const asNumberOrNull = (value: unknown): number | null => {
  if (value === null || value === undefined) return null;
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
};

/**
 * Maps API response to AgentDetail type
 */
function mapApiToAgentDetail(data: AgentApiResponse): AgentDetail {
  const idRaw = data.agent_id ?? data.id;

  return {
    id: idRaw === undefined ? "" : String(idRaw),
    name: data.name,
    agency_id: data.agency_id ?? null,
    agency_name: data.agency_name ?? null,
    email: data.email ?? null,
    phone: data.phone ?? null,
    clients: (data.clients ?? []).map((client) => ({
      id: String(client.player_id),
      player_name: client.player_name,
      team_code: client.team_code,
      position: client.position ?? null,
      cap_2025: asNumberOrNull(client.cap_2025),
      cap_2026: asNumberOrNull(client.cap_2026),
      cap_2027: asNumberOrNull(client.cap_2027),
      cap_2028: asNumberOrNull(client.cap_2028),
      cap_2029: asNumberOrNull(client.cap_2029),
      cap_2030: asNumberOrNull(client.cap_2030),
      is_two_way: client.is_two_way === true,
    })),
  };
}

/**
 * SWR fetcher for agent API
 */
async function fetcher(url: string): Promise<AgentDetail> {
  const response = await fetch(url);

  if (!response.ok) {
    if (response.status === 404) {
      throw new Error("Agent not found");
    }
    throw new Error(`Failed to fetch agent: ${response.status}`);
  }

  const data: AgentApiResponse = await response.json();
  return mapApiToAgentDetail(data);
}

/**
 * Hook to fetch agent details and their clients
 *
 * Uses SWR for caching + deduplication.
 */
export function useAgent(agentId: string | number | null): UseAgentReturn {
  const key =
    agentId === null
      ? null
      : `/api/salary-book/agent/${encodeURIComponent(String(agentId))}`;

  const { data, error, isLoading, mutate } = useSWR<AgentDetail, Error>(
    key,
    fetcher,
    {
      revalidateOnFocus: false,
      revalidateOnReconnect: true,
      dedupingInterval: 5000,
      // For sidebar entity detail views, do NOT keep previous agent's data.
      keepPreviousData: false,
    }
  );

  return {
    agent: data ?? null,
    isLoading: isLoading && !data,
    error: error ?? null,
    refetch: async () => {
      await mutate();
    },
  };
}
