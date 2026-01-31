import useSWR from "swr";

/**
 * Player API response from /api/salary-book/player/:playerId
 *
 * Keep this aligned with the backend route in:
 *   web/src/api/routes/salary-book.ts (GET /player/:playerId)
 */
export interface PlayerProtectionCondition {
  condition_id: number;
  amount: number | null;
  clause_name: string | null;
  earned_date: string | null;
  earned_type_lk: string | null;
  is_full_condition: boolean | null;
  criteria_description: string | null;
  criteria_json: string | null;
}

export interface PlayerContractProtection {
  protection_id: number;
  salary_year: number | null;
  protection_coverage_lk: string | null;
  protection_amount: number | null;
  effective_protection_amount: number | null;
  is_conditional_protection: boolean | null;
  protection_types_json: string | null;
  conditional_protection_comments: string | null;
  conditions: PlayerProtectionCondition[];
}

export interface PlayerContractBonus {
  bonus_id: number;
  salary_year: number | null;
  bonus_amount: number | null;
  bonus_type_lk: string | null;
  is_likely: boolean | null;
  earned_lk: string | null;
  paid_by_date: string | null;
  clause_name: string | null;
  criteria_description: string | null;
  criteria_json: string | null;
}

export interface PlayerDetailResponse {
  player_id: number;
  player_name: string;
  team_code: string;
  position: string | null;
  age: number | null;
  years_of_service: number | null;

  bird_rights: "BIRD" | "EARLY_BIRD" | "NON_BIRD" | null;

  cap_2025: number | null;
  cap_2026: number | null;
  cap_2027: number | null;
  cap_2028: number | null;
  cap_2029: number | null;
  cap_2030: number | null;

  option_2025: string | null;
  option_2026: string | null;
  option_2027: string | null;
  option_2028: string | null;
  option_2029: string | null;
  option_2030: string | null;

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

  agent_id: number | null;
  agent_name: string | null;
  agency_id: number | null;
  agency_name: string | null;

  is_two_way: boolean;
  is_poison_pill: boolean;
  poison_pill_amount: number | null;
  is_no_trade: boolean;
  is_trade_bonus: boolean;
  trade_bonus_percent: number | null;

  contract_type_code: string | null;
  contract_type_lookup_value: string | null;

  signed_method_code: string | null;
  signed_method_lookup_value: string | null;
  exception_type_lookup_value: string | null;

  min_contract_lookup_value: string | null;
  is_min_contract: boolean;

  trade_restriction_lookup_value: string | null;
  trade_restriction_end_date: string | null;
  is_trade_restricted_now: boolean;

  is_trade_consent_required_now: boolean;
  is_trade_preconsented: boolean;
  player_consent_lk: string | null;

  contract_protections: PlayerContractProtection[];
  contract_bonuses: PlayerContractBonus[];
}

export interface UsePlayerReturn {
  player: PlayerDetailResponse | null;
  isLoading: boolean;
  error: Error | null;
  refetch: () => Promise<void>;
}

const asNumberOrNull = (value: unknown): number | null => {
  if (value === null || value === undefined) return null;
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
};

const asBooleanOrNull = (value: unknown): boolean | null => {
  if (value === null || value === undefined) return null;
  return Boolean(value);
};

const asNumberArray = (value: unknown): number[] => {
  if (!Array.isArray(value)) return [];
  return value
    .map((item) => Number(item))
    .filter((item) => Number.isFinite(item));
};

const parseJsonArray = (value: unknown): unknown[] => {
  if (Array.isArray(value)) return value;
  if (typeof value === "string") {
    try {
      const parsed = JSON.parse(value);
      return Array.isArray(parsed) ? parsed : [];
    } catch {
      return [];
    }
  }
  return [];
};

function normalizeProtectionCondition(row: any): PlayerProtectionCondition {
  return {
    condition_id: Number(row.condition_id ?? 0),
    amount: asNumberOrNull(row.amount),
    clause_name: row.clause_name ?? null,
    earned_date: row.earned_date ?? null,
    earned_type_lk: row.earned_type_lk ?? null,
    is_full_condition: asBooleanOrNull(row.is_full_condition),
    criteria_description: row.criteria_description ?? null,
    criteria_json: row.criteria_json ?? null,
  };
}

function normalizeContractProtection(row: any): PlayerContractProtection {
  return {
    protection_id: Number(row.protection_id ?? 0),
    salary_year: asNumberOrNull(row.salary_year),
    protection_coverage_lk: row.protection_coverage_lk ?? null,
    protection_amount: asNumberOrNull(row.protection_amount),
    effective_protection_amount: asNumberOrNull(row.effective_protection_amount),
    is_conditional_protection: asBooleanOrNull(row.is_conditional_protection),
    protection_types_json: row.protection_types_json ?? null,
    conditional_protection_comments: row.conditional_protection_comments ?? null,
    conditions: parseJsonArray(row.conditions).map(normalizeProtectionCondition),
  };
}

function normalizeContractBonus(row: any): PlayerContractBonus {
  return {
    bonus_id: Number(row.bonus_id ?? 0),
    salary_year: asNumberOrNull(row.salary_year),
    bonus_amount: asNumberOrNull(row.bonus_amount),
    bonus_type_lk: row.bonus_type_lk ?? null,
    is_likely: asBooleanOrNull(row.is_likely),
    earned_lk: row.earned_lk ?? null,
    paid_by_date: row.paid_by_date ?? null,
    clause_name: row.clause_name ?? null,
    criteria_description: row.criteria_description ?? null,
    criteria_json: row.criteria_json ?? null,
  };
}

function normalizePlayer(data: any): PlayerDetailResponse {
  return {
    player_id: Number(data.player_id),
    player_name: String(data.player_name ?? ""),
    team_code: String(data.team_code ?? ""),
    position: data.position ?? null,
    age: asNumberOrNull(data.age),
    years_of_service: asNumberOrNull(data.years_of_service),

    bird_rights: data.bird_rights ?? null,

    cap_2025: asNumberOrNull(data.cap_2025),
    cap_2026: asNumberOrNull(data.cap_2026),
    cap_2027: asNumberOrNull(data.cap_2027),
    cap_2028: asNumberOrNull(data.cap_2028),
    cap_2029: asNumberOrNull(data.cap_2029),
    cap_2030: asNumberOrNull(data.cap_2030),

    option_2025: data.option_2025 ?? null,
    option_2026: data.option_2026 ?? null,
    option_2027: data.option_2027 ?? null,
    option_2028: data.option_2028 ?? null,
    option_2029: data.option_2029 ?? null,
    option_2030: data.option_2030 ?? null,

    guaranteed_amount_2025: asNumberOrNull(data.guaranteed_amount_2025),
    guaranteed_amount_2026: asNumberOrNull(data.guaranteed_amount_2026),
    guaranteed_amount_2027: asNumberOrNull(data.guaranteed_amount_2027),
    guaranteed_amount_2028: asNumberOrNull(data.guaranteed_amount_2028),
    guaranteed_amount_2029: asNumberOrNull(data.guaranteed_amount_2029),
    guaranteed_amount_2030: asNumberOrNull(data.guaranteed_amount_2030),

    is_fully_guaranteed_2025: asBooleanOrNull(data.is_fully_guaranteed_2025),
    is_fully_guaranteed_2026: asBooleanOrNull(data.is_fully_guaranteed_2026),
    is_fully_guaranteed_2027: asBooleanOrNull(data.is_fully_guaranteed_2027),
    is_fully_guaranteed_2028: asBooleanOrNull(data.is_fully_guaranteed_2028),
    is_fully_guaranteed_2029: asBooleanOrNull(data.is_fully_guaranteed_2029),
    is_fully_guaranteed_2030: asBooleanOrNull(data.is_fully_guaranteed_2030),

    is_partially_guaranteed_2025: asBooleanOrNull(data.is_partially_guaranteed_2025),
    is_partially_guaranteed_2026: asBooleanOrNull(data.is_partially_guaranteed_2026),
    is_partially_guaranteed_2027: asBooleanOrNull(data.is_partially_guaranteed_2027),
    is_partially_guaranteed_2028: asBooleanOrNull(data.is_partially_guaranteed_2028),
    is_partially_guaranteed_2029: asBooleanOrNull(data.is_partially_guaranteed_2029),
    is_partially_guaranteed_2030: asBooleanOrNull(data.is_partially_guaranteed_2030),

    is_non_guaranteed_2025: asBooleanOrNull(data.is_non_guaranteed_2025),
    is_non_guaranteed_2026: asBooleanOrNull(data.is_non_guaranteed_2026),
    is_non_guaranteed_2027: asBooleanOrNull(data.is_non_guaranteed_2027),
    is_non_guaranteed_2028: asBooleanOrNull(data.is_non_guaranteed_2028),
    is_non_guaranteed_2029: asBooleanOrNull(data.is_non_guaranteed_2029),
    is_non_guaranteed_2030: asBooleanOrNull(data.is_non_guaranteed_2030),

    likely_bonus_2025: asNumberOrNull(data.likely_bonus_2025),
    likely_bonus_2026: asNumberOrNull(data.likely_bonus_2026),
    likely_bonus_2027: asNumberOrNull(data.likely_bonus_2027),
    likely_bonus_2028: asNumberOrNull(data.likely_bonus_2028),
    likely_bonus_2029: asNumberOrNull(data.likely_bonus_2029),
    likely_bonus_2030: asNumberOrNull(data.likely_bonus_2030),

    unlikely_bonus_2025: asNumberOrNull(data.unlikely_bonus_2025),
    unlikely_bonus_2026: asNumberOrNull(data.unlikely_bonus_2026),
    unlikely_bonus_2027: asNumberOrNull(data.unlikely_bonus_2027),
    unlikely_bonus_2028: asNumberOrNull(data.unlikely_bonus_2028),
    unlikely_bonus_2029: asNumberOrNull(data.unlikely_bonus_2029),
    unlikely_bonus_2030: asNumberOrNull(data.unlikely_bonus_2030),

    agent_id: asNumberOrNull(data.agent_id),
    agent_name: data.agent_name ?? null,
    agency_id: asNumberOrNull(data.agency_id),
    agency_name: data.agency_name ?? null,

    is_two_way: !!data.is_two_way,
    is_poison_pill: !!data.is_poison_pill,
    poison_pill_amount: asNumberOrNull(data.poison_pill_amount),
    is_no_trade: !!data.is_no_trade,
    is_trade_bonus: !!data.is_trade_bonus,
    trade_bonus_percent: asNumberOrNull(data.trade_bonus_percent),

    contract_type_code: data.contract_type_code ?? null,
    contract_type_lookup_value: data.contract_type_lookup_value ?? null,

    signed_method_code: data.signed_method_code ?? null,
    signed_method_lookup_value: data.signed_method_lookup_value ?? null,
    exception_type_lookup_value: data.exception_type_lookup_value ?? null,

    min_contract_lookup_value: data.min_contract_lookup_value ?? null,
    is_min_contract: !!data.is_min_contract,

    trade_restriction_lookup_value: data.trade_restriction_lookup_value ?? null,
    trade_restriction_end_date: data.trade_restriction_end_date ?? null,
    is_trade_restricted_now: !!data.is_trade_restricted_now,

    is_trade_consent_required_now: !!data.is_trade_consent_required_now,
    is_trade_preconsented: !!data.is_trade_preconsented,
    player_consent_lk: data.player_consent_lk ?? null,

    contract_protections: Array.isArray(data.contract_protections)
      ? data.contract_protections.map(normalizeContractProtection)
      : [],
    contract_bonuses: Array.isArray(data.contract_bonuses)
      ? data.contract_bonuses.map(normalizeContractBonus)
      : [],
  };
}

async function fetcher(url: string): Promise<PlayerDetailResponse> {
  const response = await fetch(url);

  if (!response.ok) {
    if (response.status === 404) {
      throw new Error("Player not found");
    }
    throw new Error(`Failed to fetch player: ${response.status}`);
  }

  const data = await response.json();
  return normalizePlayer(data);
}

/**
 * Fetch a single player's full details.
 */
export function usePlayer(playerId: number | null): UsePlayerReturn {
  const key = playerId ? `/api/salary-book/player/${playerId}` : null;

  const { data, error, isLoading, mutate } = useSWR<PlayerDetailResponse, Error>(
    key,
    fetcher,
    {
      revalidateOnFocus: false,
      revalidateOnReconnect: true,
      dedupingInterval: 5000,
      // For sidebar entity detail views, do NOT keep previous player's data.
      keepPreviousData: false,
    }
  );

  return {
    player: data ?? null,
    isLoading: isLoading && !data,
    error: error ?? null,
    refetch: async () => {
      await mutate();
    },
  };
}
