import useSWR from "swr";
import type { SalaryBookPlayer, ContractOption } from "../data";

/**
 * Player API response shape (from /api/salary-book/players?team=:teamCode)
 */
interface PlayerApiResponse {
  id: string;
  player_id: string;
  player_name: string;
  display_first_name: string | null;
  display_last_name: string | null;
  team_code: string;
  position: string | null;
  years_of_service: number | null;
  age: number | null;
  cap_2025: number | null;
  cap_2026: number | null;
  cap_2027: number | null;
  cap_2028: number | null;
  cap_2029: number | null;
  cap_2030: number | null;
  pct_cap_2025: number | null;
  pct_cap_2026: number | null;
  pct_cap_2027: number | null;
  pct_cap_2028: number | null;
  pct_cap_2029: number | null;
  pct_cap_2030: number | null;
  option_2025: string | null;
  option_2026: string | null;
  option_2027: string | null;
  option_2028: string | null;
  option_2029: string | null;
  option_2030: string | null;

  // Guarantee structure per year (warehouse stores numeric amounts + booleans)
  guaranteed_amount_2025: number | null;
  guaranteed_amount_2026: number | null;
  guaranteed_amount_2027: number | null;
  guaranteed_amount_2028: number | null;
  guaranteed_amount_2029: number | null;
  guaranteed_amount_2030: number | null;

  is_fully_guaranteed_2025: boolean | null;
  is_fully_guaranteed_2026: boolean | null;
  is_fully_guaranteed_2027: boolean | null;
  is_fully_guaranteed_2028: boolean | null;
  is_fully_guaranteed_2029: boolean | null;
  is_fully_guaranteed_2030: boolean | null;

  is_partially_guaranteed_2025: boolean | null;
  is_partially_guaranteed_2026: boolean | null;
  is_partially_guaranteed_2027: boolean | null;
  is_partially_guaranteed_2028: boolean | null;
  is_partially_guaranteed_2029: boolean | null;
  is_partially_guaranteed_2030: boolean | null;

  is_non_guaranteed_2025: boolean | null;
  is_non_guaranteed_2026: boolean | null;
  is_non_guaranteed_2027: boolean | null;
  is_non_guaranteed_2028: boolean | null;
  is_non_guaranteed_2029: boolean | null;
  is_non_guaranteed_2030: boolean | null;

  // Likely vs unlikely bonuses (per year)
  likely_bonus_2025: number | null;
  likely_bonus_2026: number | null;
  likely_bonus_2027: number | null;
  likely_bonus_2028: number | null;
  likely_bonus_2029: number | null;
  likely_bonus_2030: number | null;

  unlikely_bonus_2025: number | null;
  unlikely_bonus_2026: number | null;
  unlikely_bonus_2027: number | null;
  unlikely_bonus_2028: number | null;
  unlikely_bonus_2029: number | null;
  unlikely_bonus_2030: number | null;

  agent_id: string | null;
  agent_name: string | null;
  agency_id: string | null;
  agency_name: string | null;
  is_two_way: boolean;
  is_poison_pill: boolean;
  poison_pill_amount: number | null;

  // Trade restriction flags (from salary_book_warehouse)
  is_no_trade: boolean;
  is_trade_bonus: boolean;
  trade_bonus_percent: number | null;
  is_trade_consent_required_now: boolean;
  is_trade_preconsented: boolean;
  player_consent_lk: string | null;
}

/**
 * Return type for usePlayers hook
 */
export interface UsePlayersReturn {
  /** Players for the given team */
  players: SalaryBookPlayer[];
  /** Loading state */
  isLoading: boolean;
  /** Error state */
  error: Error | null;
  /** Refetch players */
  refetch: () => Promise<void>;
}

/**
 * Normalize option values coming from `pcms.salary_book_warehouse`.
 *
 * Current warehouse values observed:
 * - "NONE" / "" / null
 * - "TEAM" (team option)
 * - "PLYR" (player option)
 * - "PLYTF" (player termination / early termination)
 */
function normalizeOption(value: string | null): ContractOption {
  if (value === null) return null;
  const v = value.trim().toUpperCase();
  if (!v || v === "NONE") return null;
  if (v === "TEAM") return "TO";
  if (v === "PLYR") return "PO";
  if (v === "PLYTF") return "ETO";
  // Unknown value: hide rather than render random text
  return null;
}


/**
 * Maps API response to SalaryBookPlayer type
 */
function mapApiToPlayer(data: PlayerApiResponse): SalaryBookPlayer {
  return {
    id: data.id,
    player_id: data.player_id,
    player_name: data.player_name,
    display_first_name: data.display_first_name,
    display_last_name: data.display_last_name,
    team_code: data.team_code,
    position: data.position,
    experience: data.years_of_service,
    age: data.age,
    cap_2025: data.cap_2025,
    cap_2026: data.cap_2026,
    cap_2027: data.cap_2027,
    cap_2028: data.cap_2028,
    cap_2029: data.cap_2029,
    cap_2030: data.cap_2030,
    pct_cap_2025: data.pct_cap_2025,
    pct_cap_2026: data.pct_cap_2026,
    pct_cap_2027: data.pct_cap_2027,
    pct_cap_2028: data.pct_cap_2028,
    pct_cap_2029: data.pct_cap_2029,
    pct_cap_2030: data.pct_cap_2030,
    option_2025: normalizeOption(data.option_2025),
    option_2026: normalizeOption(data.option_2026),
    option_2027: normalizeOption(data.option_2027),
    option_2028: normalizeOption(data.option_2028),
    option_2029: normalizeOption(data.option_2029),
    option_2030: normalizeOption(data.option_2030),

    guaranteed_amount_2025: data.guaranteed_amount_2025,
    guaranteed_amount_2026: data.guaranteed_amount_2026,
    guaranteed_amount_2027: data.guaranteed_amount_2027,
    guaranteed_amount_2028: data.guaranteed_amount_2028,
    guaranteed_amount_2029: data.guaranteed_amount_2029,
    guaranteed_amount_2030: data.guaranteed_amount_2030,

    is_fully_guaranteed_2025: data.is_fully_guaranteed_2025,
    is_fully_guaranteed_2026: data.is_fully_guaranteed_2026,
    is_fully_guaranteed_2027: data.is_fully_guaranteed_2027,
    is_fully_guaranteed_2028: data.is_fully_guaranteed_2028,
    is_fully_guaranteed_2029: data.is_fully_guaranteed_2029,
    is_fully_guaranteed_2030: data.is_fully_guaranteed_2030,

    is_partially_guaranteed_2025: data.is_partially_guaranteed_2025,
    is_partially_guaranteed_2026: data.is_partially_guaranteed_2026,
    is_partially_guaranteed_2027: data.is_partially_guaranteed_2027,
    is_partially_guaranteed_2028: data.is_partially_guaranteed_2028,
    is_partially_guaranteed_2029: data.is_partially_guaranteed_2029,
    is_partially_guaranteed_2030: data.is_partially_guaranteed_2030,

    is_non_guaranteed_2025: data.is_non_guaranteed_2025,
    is_non_guaranteed_2026: data.is_non_guaranteed_2026,
    is_non_guaranteed_2027: data.is_non_guaranteed_2027,
    is_non_guaranteed_2028: data.is_non_guaranteed_2028,
    is_non_guaranteed_2029: data.is_non_guaranteed_2029,
    is_non_guaranteed_2030: data.is_non_guaranteed_2030,

    likely_bonus_2025: data.likely_bonus_2025,
    likely_bonus_2026: data.likely_bonus_2026,
    likely_bonus_2027: data.likely_bonus_2027,
    likely_bonus_2028: data.likely_bonus_2028,
    likely_bonus_2029: data.likely_bonus_2029,
    likely_bonus_2030: data.likely_bonus_2030,

    unlikely_bonus_2025: data.unlikely_bonus_2025,
    unlikely_bonus_2026: data.unlikely_bonus_2026,
    unlikely_bonus_2027: data.unlikely_bonus_2027,
    unlikely_bonus_2028: data.unlikely_bonus_2028,
    unlikely_bonus_2029: data.unlikely_bonus_2029,
    unlikely_bonus_2030: data.unlikely_bonus_2030,

    agent_id: data.agent_id,
    agent_name: data.agent_name,
    agency_id: data.agency_id,
    agency_name: data.agency_name,
    is_two_way: data.is_two_way,
    is_poison_pill: data.is_poison_pill,
    poison_pill_amount: data.poison_pill_amount,
    is_no_trade: data.is_no_trade,
    is_trade_bonus: data.is_trade_bonus,
    trade_bonus_percent: data.trade_bonus_percent,
    is_trade_consent_required_now: data.is_trade_consent_required_now,
    is_trade_preconsented: data.is_trade_preconsented,
    player_consent_lk: data.player_consent_lk,

    // Fields not returned by current API — set to null
    bird_rights: null,
    free_agency_type: null,
    free_agency_year: null,
    contract_years: null,
    contract_total: null,
  };
}

/**
 * SWR fetcher for players API
 */
async function fetcher(url: string): Promise<SalaryBookPlayer[]> {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`Failed to fetch players: ${response.status}`);
  }
  const data: PlayerApiResponse[] = await response.json();
  return data.map(mapApiToPlayer);
}

/**
 * Hook to fetch players for a specific team
 *
 * Uses SWR for automatic caching, deduplication, and revalidation.
 * When switching teams, cached data is shown immediately while revalidating.
 *
 * Key benefits over manual useState/useEffect:
 * - Global cache: Agent view can reuse player data without re-fetching
 * - Deduplication: Multiple TeamSections mounting won't cause duplicate requests
 * - Stale-while-revalidate: Shows cached data instantly, updates in background
 *
 * @param teamCode - 3-letter team code (e.g., "BOS", "LAL"). Pass null to skip fetch.
 *
 * @example
 * ```tsx
 * const { players, isLoading, error } = usePlayers("BOS");
 *
 * if (isLoading) return <Skeleton />;
 * if (error) return <Error message={error.message} />;
 *
 * return players.map(player => (
 *   <PlayerRow key={player.id} player={player} />
 * ));
 * ```
 */
export function usePlayers(teamCode: string | null): UsePlayersReturn {
  const { data, error, isLoading, mutate } = useSWR<SalaryBookPlayer[], Error>(
    teamCode ? `/api/salary-book/players?team=${encodeURIComponent(teamCode)}` : null,
    fetcher,
    {
      // Keep data fresh but don't refetch too aggressively
      revalidateOnFocus: false,
      revalidateOnReconnect: true,
      dedupingInterval: 5000, // Dedupe requests within 5 seconds
      keepPreviousData: true, // Show previous team's data while loading new team
    }
  );

  return {
    players: data ?? [],
    isLoading: isLoading && !data, // Only show loading if we have no cached data
    error: error ?? null,
    refetch: async () => {
      await mutate();
    },
  };
}
