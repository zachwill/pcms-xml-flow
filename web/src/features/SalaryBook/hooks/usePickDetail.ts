import useSWR from "swr";

export interface PickDetailParams {
  teamCode: string;
  year: number;
  round: number;
}

export interface PickTeamInfo {
  team_code: string;
  team_name: string;
  team_nickname: string;
}

export interface PickDetailAsset {
  asset_slot: number;
  sub_asset_slot: number;
  asset_type: string;
  is_conditional: boolean;
  is_swap: boolean;
  counterparty_team_code: string | null;
  counterparty_team_codes: string[];
  via_team_codes: string[];
  raw_fragment: string | null;
  raw_part: string | null;
  endnote_refs: number[];
  primary_endnote_id: number | null;
  endnote_trade_date: string | null;
  endnote_explanation: string | null;
  endnote_is_swap: boolean | null;
  endnote_is_conditional: boolean | null;
  endnote_depends_on: number[];
  needs_review: boolean;
}

export interface PickDetailEndnote {
  endnote_id: number;
  trade_id: number | null;
  trade_date: string | null;
  is_swap: boolean | null;
  is_conditional: boolean | null;
  explanation: string | null;
  conditions_json: unknown;
  note_type: string | null;
  status_lk: string | null;
  resolution_lk: string | null;
  resolved_at: string | null;
  draft_years: number[];
  draft_rounds: number[];
  draft_year_start: number | null;
  draft_year_end: number | null;
  has_rollover: boolean | null;
  is_frozen_pick: boolean | null;
  teams_mentioned: string[];
  from_team_codes: string[];
  to_team_codes: string[];
  trade_ids: number[];
  depends_on_endnotes: number[];
  trade_summary: string | null;
  conveyance_text: string | null;
  protections_text: string | null;
  contingency_text: string | null;
  exercise_text: string | null;
}

export interface PickDetailTradeClaim {
  trade_id: number | null;
  trade_date: string | null;
  from_team_id: number | null;
  from_team_code: string | null;
  to_team_id: number | null;
  to_team_code: string | null;
  is_swap: boolean | null;
  is_conditional: boolean | null;
  conditional_type_lk: string | null;
}

export interface PickDetailTradeClaims {
  draft_year: number;
  draft_round: number;
  original_team_code: string;
  claims_count: number;
  distinct_to_teams_count: number;
  has_conditional_claims: boolean;
  has_swap_claims: boolean;
  latest_trade_id: number | null;
  latest_trade_date: string | null;
  needs_review: boolean;
  trade_claims: PickDetailTradeClaim[];
}

/**
 * Pick API response from /api/salary-book/pick
 */
export interface PickDetailResponse {
  team_code: string;
  year: number;
  round: number;
  asset_type: string | null;
  description: string | null;
  origin_team_code: string;
  origin_team: PickTeamInfo | null;
  destination_team: PickTeamInfo | null;
  protections: string | null;
  is_swap: boolean;
  is_conditional: boolean;
  assets: PickDetailAsset[];
  endnotes: PickDetailEndnote[];
  trade_claims: PickDetailTradeClaims | null;
  missing_endnote_refs: number[];
}

export interface UsePickDetailReturn {
  pick: PickDetailResponse | null;
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

const asStringArray = (value: unknown): string[] => {
  if (!Array.isArray(value)) return [];
  return value
    .filter((item) => item !== null && item !== undefined)
    .map((item) => String(item));
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

function normalizeAsset(row: any): PickDetailAsset {
  return {
    asset_slot: Number(row.asset_slot ?? 0),
    sub_asset_slot: Number(row.sub_asset_slot ?? 0),
    asset_type: String(row.asset_type ?? ""),
    is_conditional: Boolean(row.is_conditional),
    is_swap: Boolean(row.is_swap),
    counterparty_team_code: row.counterparty_team_code ?? null,
    counterparty_team_codes: asStringArray(row.counterparty_team_codes),
    via_team_codes: asStringArray(row.via_team_codes),
    raw_fragment: row.raw_fragment ?? null,
    raw_part: row.raw_part ?? null,
    endnote_refs: asNumberArray(row.endnote_refs),
    primary_endnote_id: asNumberOrNull(row.primary_endnote_id),
    endnote_trade_date: row.endnote_trade_date ?? null,
    endnote_explanation: row.endnote_explanation ?? null,
    endnote_is_swap: asBooleanOrNull(row.endnote_is_swap),
    endnote_is_conditional: asBooleanOrNull(row.endnote_is_conditional),
    endnote_depends_on: asNumberArray(row.endnote_depends_on),
    needs_review: Boolean(row.needs_review),
  };
}

function normalizeEndnote(row: any): PickDetailEndnote {
  return {
    endnote_id: Number(row.endnote_id ?? 0),
    trade_id: asNumberOrNull(row.trade_id),
    trade_date: row.trade_date ?? null,
    is_swap: asBooleanOrNull(row.is_swap),
    is_conditional: asBooleanOrNull(row.is_conditional),
    explanation: row.explanation ?? null,
    conditions_json: row.conditions_json ?? null,
    note_type: row.note_type ?? null,
    status_lk: row.status_lk ?? null,
    resolution_lk: row.resolution_lk ?? null,
    resolved_at: row.resolved_at ?? null,
    draft_years: asNumberArray(row.draft_years),
    draft_rounds: asNumberArray(row.draft_rounds),
    draft_year_start: asNumberOrNull(row.draft_year_start),
    draft_year_end: asNumberOrNull(row.draft_year_end),
    has_rollover: asBooleanOrNull(row.has_rollover),
    is_frozen_pick: asBooleanOrNull(row.is_frozen_pick),
    teams_mentioned: asStringArray(row.teams_mentioned),
    from_team_codes: asStringArray(row.from_team_codes),
    to_team_codes: asStringArray(row.to_team_codes),
    trade_ids: asNumberArray(row.trade_ids),
    depends_on_endnotes: asNumberArray(row.depends_on_endnotes),
    trade_summary: row.trade_summary ?? null,
    conveyance_text: row.conveyance_text ?? null,
    protections_text: row.protections_text ?? null,
    contingency_text: row.contingency_text ?? null,
    exercise_text: row.exercise_text ?? null,
  };
}

function normalizeTradeClaim(row: any): PickDetailTradeClaim {
  return {
    trade_id: asNumberOrNull(row.trade_id),
    trade_date: row.trade_date ?? null,
    from_team_id: asNumberOrNull(row.from_team_id),
    from_team_code: row.from_team_code ?? null,
    to_team_id: asNumberOrNull(row.to_team_id),
    to_team_code: row.to_team_code ?? null,
    is_swap: asBooleanOrNull(row.is_swap),
    is_conditional: asBooleanOrNull(row.is_conditional),
    conditional_type_lk: row.conditional_type_lk ?? null,
  };
}

function normalizeTradeClaims(data: any): PickDetailTradeClaims {
  return {
    draft_year: Number(data.draft_year ?? 0),
    draft_round: Number(data.draft_round ?? 0),
    original_team_code: String(data.original_team_code ?? ""),
    claims_count: Number(data.claims_count ?? 0),
    distinct_to_teams_count: Number(data.distinct_to_teams_count ?? 0),
    has_conditional_claims: Boolean(data.has_conditional_claims),
    has_swap_claims: Boolean(data.has_swap_claims),
    latest_trade_id: asNumberOrNull(data.latest_trade_id),
    latest_trade_date: data.latest_trade_date ?? null,
    needs_review: Boolean(data.needs_review),
    trade_claims: parseJsonArray(data.trade_claims).map(normalizeTradeClaim),
  };
}

function normalizePickDetail(data: any): PickDetailResponse {
  const teamCode = String(data.team_code ?? "");
  const originTeamCode = data.origin_team_code
    ? String(data.origin_team_code)
    : teamCode;

  const normalizeTeamInfo = (value: any): PickTeamInfo | null => {
    if (!value) return null;
    return {
      team_code: String(value.team_code ?? ""),
      team_name: String(value.team_name ?? ""),
      team_nickname: String(value.team_nickname ?? ""),
    };
  };

  return {
    team_code: teamCode,
    year: Number(data.year ?? 0),
    round: Number(data.round ?? 0),
    asset_type: data.asset_type ?? null,
    description: data.description ?? null,
    origin_team_code: originTeamCode,
    origin_team: normalizeTeamInfo(data.origin_team),
    destination_team: normalizeTeamInfo(data.destination_team),
    protections: data.protections ?? null,
    is_swap: Boolean(data.is_swap),
    is_conditional: Boolean(data.is_conditional),
    assets: Array.isArray(data.assets) ? data.assets.map(normalizeAsset) : [],
    endnotes: Array.isArray(data.endnotes) ? data.endnotes.map(normalizeEndnote) : [],
    trade_claims: data.trade_claims ? normalizeTradeClaims(data.trade_claims) : null,
    missing_endnote_refs: asNumberArray(data.missing_endnote_refs),
  };
}

async function fetcher(url: string): Promise<PickDetailResponse | null> {
  const response = await fetch(url);

  if (response.status === 404) {
    // Treat "not found" as a non-error so the UI can show a friendly empty state.
    return null;
  }

  if (!response.ok) {
    throw new Error(`Failed to fetch pick: ${response.status}`);
  }

  const data = await response.json();
  return normalizePickDetail(data);
}

/**
 * Fetch a single pick detail record.
 */
export function usePickDetail(params: PickDetailParams | null): UsePickDetailReturn {
  const key = params
    ? `/api/salary-book/pick?${new URLSearchParams({
        team: params.teamCode,
        year: String(params.year),
        round: String(params.round),
      })}`
    : null;

  const { data, error, isLoading, mutate } = useSWR<PickDetailResponse | null, Error>(
    key,
    fetcher,
    {
      revalidateOnFocus: false,
      revalidateOnReconnect: true,
      dedupingInterval: 5000,
      // For sidebar entity detail views, do NOT keep previous pick's data.
      keepPreviousData: false,
    }
  );

  return {
    pick: data ?? null,
    isLoading: isLoading && data === undefined,
    error: error ?? null,
    refetch: async () => {
      await mutate();
    },
  };
}
