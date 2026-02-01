import { useMemo } from "react";
import useSWR from "swr";
import type {
  BuyoutScenarioRequest,
  BuyoutScenarioResponse,
  BuyoutScenarioRow,
  BuyoutScenarioTotals,
  BuyoutStretchSummary,
  BuyoutStretchSchedule,
} from "../data";

interface BuyoutScenarioApiRow {
  salary_year: number | string;
  cap_salary: number | string | null;
  days_remaining: number | string | null;
  proration_factor: number | string | null;
  guaranteed_remaining: number | string | null;
  give_back_pct: number | string | null;
  give_back_amount: number | string | null;
  dead_money: number | string | null;
}

interface BuyoutScenarioApiTotals {
  guaranteed_remaining: number | string | null;
  give_back_amount: number | string | null;
  dead_money: number | string | null;
}

interface BuyoutScenarioApiStretchSchedule {
  year: number | string | null;
  amount: number | string | null;
}

interface BuyoutScenarioApiStretch {
  stretch_years: number | string | null;
  annual_amount: number | string | null;
  remaining_years: number | string | null;
  start_year: number | string | null;
  schedule: BuyoutScenarioApiStretchSchedule[] | null;
}

interface BuyoutScenarioApiResponse {
  player_id: number | string;
  player_name: string | null;
  team_code: string | null;
  salary_year: number | string;
  waive_date: string;
  give_back_amount: number | string;
  season_start: string | null;
  rows: BuyoutScenarioApiRow[];
  totals: BuyoutScenarioApiTotals;
  stretch: BuyoutScenarioApiStretch | null;
}

const asNumberOrNull = (value: unknown): number | null => {
  if (value === null || value === undefined) return null;
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
};

const asNumber = (value: unknown, fallback = 0): number => {
  const n = Number(value);
  return Number.isFinite(n) ? n : fallback;
};

function mapRow(row: BuyoutScenarioApiRow): BuyoutScenarioRow {
  return {
    salary_year: asNumber(row.salary_year),
    cap_salary: asNumberOrNull(row.cap_salary),
    days_remaining: asNumberOrNull(row.days_remaining),
    proration_factor: asNumberOrNull(row.proration_factor),
    guaranteed_remaining: asNumberOrNull(row.guaranteed_remaining),
    give_back_pct: asNumberOrNull(row.give_back_pct),
    give_back_amount: asNumberOrNull(row.give_back_amount),
    dead_money: asNumberOrNull(row.dead_money),
  };
}

function mapTotals(totals: BuyoutScenarioApiTotals): BuyoutScenarioTotals {
  return {
    guaranteed_remaining: asNumberOrNull(totals.guaranteed_remaining),
    give_back_amount: asNumberOrNull(totals.give_back_amount),
    dead_money: asNumberOrNull(totals.dead_money),
  };
}

function mapSchedule(
  schedule: BuyoutScenarioApiStretchSchedule[] | null | undefined
): BuyoutStretchSchedule[] {
  if (!Array.isArray(schedule)) return [];
  return schedule.map((entry) => ({
    year: asNumberOrNull(entry.year),
    amount: asNumberOrNull(entry.amount),
  }));
}

function mapStretch(
  stretch: BuyoutScenarioApiStretch | null
): BuyoutStretchSummary | null {
  if (!stretch) return null;

  return {
    stretch_years: asNumberOrNull(stretch.stretch_years),
    annual_amount: asNumberOrNull(stretch.annual_amount),
    remaining_years: asNumberOrNull(stretch.remaining_years),
    start_year: asNumberOrNull(stretch.start_year),
    schedule: mapSchedule(stretch.schedule),
  };
}

async function fetcher([
  url,
  payload,
]: [string, BuyoutScenarioRequest]): Promise<BuyoutScenarioResponse> {
  const response = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify(payload),
  });

  if (!response.ok) {
    throw new Error(`Failed to fetch buyout scenario: ${response.status}`);
  }

  const data: BuyoutScenarioApiResponse = await response.json();

  return {
    player_id: asNumber(data.player_id),
    player_name: data.player_name ?? null,
    team_code: data.team_code ?? null,
    salary_year: asNumber(data.salary_year),
    waive_date: data.waive_date,
    give_back_amount: asNumber(data.give_back_amount),
    season_start: data.season_start ?? null,
    rows: (data.rows ?? []).map(mapRow),
    totals: mapTotals(
      data.totals ?? {
        guaranteed_remaining: null,
        give_back_amount: null,
        dead_money: null,
      }
    ),
    stretch: mapStretch(data.stretch ?? null),
  };
}

export interface UseBuyoutScenarioReturn {
  scenario: BuyoutScenarioResponse | null;
  isLoading: boolean;
  error: Error | null;
  isReady: boolean;
  refetch: () => Promise<void>;
}

export function useBuyoutScenario(
  request: BuyoutScenarioRequest | null
): UseBuyoutScenarioReturn {
  const key = useMemo(
    () => (request ? ["/api/salary-book/buyout-scenario", request] : null),
    [request]
  );

  const { data, error, isLoading, mutate } = useSWR<BuyoutScenarioResponse, Error>(
    key,
    fetcher,
    {
      revalidateOnFocus: false,
      revalidateOnReconnect: true,
      dedupingInterval: 5_000,
    }
  );

  return {
    scenario: data ?? null,
    isLoading: isLoading && !!request,
    error: error ?? null,
    isReady: !!request,
    refetch: async () => {
      await mutate();
    },
  };
}
