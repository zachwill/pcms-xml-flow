import { useMemo } from "react";
import useSWR from "swr";
import type { SetoffAmountRequest, SetoffAmountResponse } from "../data";

interface SetoffAmountApiResponse {
  new_salary: number | string;
  salary_year: number | string;
  years_of_service: number | string;
  league: string;
  minimum_salary: number | string | null;
  setoff_amount: number | string | null;
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

async function fetcher([
  url,
  payload,
]: [string, SetoffAmountRequest]): Promise<SetoffAmountResponse> {
  const response = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify(payload),
  });

  if (!response.ok) {
    throw new Error(`Failed to fetch set-off amount: ${response.status}`);
  }

  const data: SetoffAmountApiResponse = await response.json();

  return {
    new_salary: asNumber(data.new_salary),
    salary_year: asNumber(data.salary_year),
    years_of_service: asNumber(data.years_of_service),
    league: data.league ?? payload.league,
    minimum_salary: asNumberOrNull(data.minimum_salary),
    setoff_amount: asNumberOrNull(data.setoff_amount),
  };
}

export interface UseSetoffAmountReturn {
  setoff: SetoffAmountResponse | null;
  isLoading: boolean;
  error: Error | null;
  isReady: boolean;
  refetch: () => Promise<void>;
}

export function useSetoffAmount(
  request: SetoffAmountRequest | null
): UseSetoffAmountReturn {
  const key = useMemo(
    () => (request ? ["/api/salary-book/setoff-amount", request] : null),
    [request]
  );

  const { data, error, isLoading, mutate } = useSWR<SetoffAmountResponse, Error>(
    key,
    fetcher,
    {
      revalidateOnFocus: false,
      revalidateOnReconnect: true,
      dedupingInterval: 5_000,
    }
  );

  return {
    setoff: data ?? null,
    isLoading: isLoading && !!request,
    error: error ?? null,
    isReady: !!request,
    refetch: async () => {
      await mutate();
    },
  };
}
