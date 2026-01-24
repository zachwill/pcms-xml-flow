import { useMemo, useCallback } from "react";
import useSWR from "swr";
import type { TeamSalary } from "../data";

/**
 * API response shape from /api/salary-book/team-salary
 */
interface TeamSalaryApiResponse {
  team_code: string;
  year: number;

  cap_total: number | string | null;
  tax_total: number | string | null;
  apron_total: number | string | null;
  mts_total: number | string | null;

  cap_rost: number | string | null;
  cap_fa: number | string | null;
  cap_term: number | string | null;
  cap_2way: number | string | null;
  tax_rost: number | string | null;
  tax_fa: number | string | null;
  tax_term: number | string | null;
  tax_2way: number | string | null;
  apron_rost: number | string | null;
  apron_fa: number | string | null;
  apron_term: number | string | null;
  apron_2way: number | string | null;

  roster_row_count: number | null;
  fa_row_count: number | null;
  term_row_count: number | null;
  two_way_row_count: number | null;

  salary_cap_amount: number | string | null;
  tax_level_amount: number | string | null;
  first_apron_amount: number | string | null;
  second_apron_amount: number | string | null;
  minimum_team_salary_amount: number | string | null;

  cap_space: number | string | null;
  over_cap: number | string | null;
  room_under_tax: number | string | null;
  room_under_first_apron: number | string | null;
  room_under_second_apron: number | string | null;

  is_over_cap: boolean;
  is_over_tax: boolean;
  is_over_first_apron: boolean;
  is_over_second_apron: boolean;

  is_taxpayer: boolean | null;
  is_repeater_taxpayer: boolean | null;
  is_subject_to_apron: boolean | null;
  apron_level_lk: string | null;
  refreshed_at: string | null;
}

/**
 * Return type for useTeamSalary hook
 */
export interface UseTeamSalaryReturn {
  /** Team salary data by year (2025-2030) */
  salaryByYear: Map<number, TeamSalary>;
  /** Array of salary records for all years */
  salaries: TeamSalary[];
  /** Get salary for a specific year */
  getSalaryForYear: (year: number) => TeamSalary | undefined;
  /** Current year's total (2025) */
  currentYearTotal: number | null;
  /** Current year's cap space */
  currentYearCapSpace: number | null;
  /** Loading state */
  isLoading: boolean;
  /** Error state */
  error: Error | null;
  /** Refetch data */
  refetch: () => Promise<void>;
}

const asNumber = (value: unknown, fallback = 0): number => {
  if (value === null || value === undefined) return fallback;
  const n = Number(value);
  return Number.isFinite(n) ? n : fallback;
};

/**
 * Maps API response to TeamSalary array
 */
function mapApiToTeamSalaries(data: TeamSalaryApiResponse[]): TeamSalary[] {
  return data.map((row) => ({
    team_code: row.team_code,
    year: row.year,

    cap_total: asNumber(row.cap_total),
    tax_total: asNumber(row.tax_total),
    apron_total: row.apron_total === null ? null : asNumber(row.apron_total, 0),
    mts_total: row.mts_total === null ? null : asNumber(row.mts_total, 0),

    cap_rost: row.cap_rost === null ? null : asNumber(row.cap_rost, 0),
    cap_fa: row.cap_fa === null ? null : asNumber(row.cap_fa, 0),
    cap_term: row.cap_term === null ? null : asNumber(row.cap_term, 0),
    cap_2way: row.cap_2way === null ? null : asNumber(row.cap_2way, 0),
    tax_rost: row.tax_rost === null ? null : asNumber(row.tax_rost, 0),
    tax_fa: row.tax_fa === null ? null : asNumber(row.tax_fa, 0),
    tax_term: row.tax_term === null ? null : asNumber(row.tax_term, 0),
    tax_2way: row.tax_2way === null ? null : asNumber(row.tax_2way, 0),
    apron_rost: row.apron_rost === null ? null : asNumber(row.apron_rost, 0),
    apron_fa: row.apron_fa === null ? null : asNumber(row.apron_fa, 0),
    apron_term: row.apron_term === null ? null : asNumber(row.apron_term, 0),
    apron_2way: row.apron_2way === null ? null : asNumber(row.apron_2way, 0),

    roster_row_count: row.roster_row_count,
    fa_row_count: row.fa_row_count,
    term_row_count: row.term_row_count,
    two_way_row_count: row.two_way_row_count,

    salary_cap_amount:
      row.salary_cap_amount === null ? null : asNumber(row.salary_cap_amount, 0),
    tax_level_amount:
      row.tax_level_amount === null ? null : asNumber(row.tax_level_amount, 0),
    first_apron_amount:
      row.first_apron_amount === null ? null : asNumber(row.first_apron_amount, 0),
    second_apron_amount:
      row.second_apron_amount === null ? null : asNumber(row.second_apron_amount, 0),
    minimum_team_salary_amount:
      row.minimum_team_salary_amount === null
        ? null
        : asNumber(row.minimum_team_salary_amount, 0),

    cap_space: asNumber(row.cap_space),
    over_cap: row.over_cap === null ? null : asNumber(row.over_cap, 0),
    room_under_tax: asNumber(row.room_under_tax),
    room_under_first_apron: asNumber(row.room_under_first_apron),
    room_under_second_apron: asNumber(row.room_under_second_apron),

    is_over_cap: !!row.is_over_cap,
    is_over_tax: !!row.is_over_tax,
    is_over_first_apron: !!row.is_over_first_apron,
    is_over_second_apron: !!row.is_over_second_apron,

    is_taxpayer: row.is_taxpayer,
    is_repeater_taxpayer: row.is_repeater_taxpayer,
    is_subject_to_apron: row.is_subject_to_apron,
    apron_level_lk: row.apron_level_lk,
    refreshed_at: row.refreshed_at,

    // Not available in current warehouse snapshot
    luxury_tax_bill: null,
    mid_level_exception: null,
    bi_annual_exception: null,
    traded_player_exception: null,
  }));
}

/**
 * SWR fetcher for team salary API
 */
async function fetcher(url: string): Promise<TeamSalary[]> {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`Failed to fetch team salary: ${response.status}`);
  }
  const data: TeamSalaryApiResponse[] = await response.json();
  return mapApiToTeamSalaries(data);
}

/**
 * Hook to fetch team salary totals from the API
 *
 * Uses SWR for automatic caching and deduplication.
 * Salary data for years 2025-2030 is cached globally.
 *
 * @param teamCode - 3-letter team code (e.g., "BOS", "LAL")
 *
 * @example
 * ```tsx
 * const {
 *   salaryByYear,
 *   currentYearTotal,
 *   currentYearCapSpace,
 *   isLoading,
 *   error
 * } = useTeamSalary("BOS");
 *
 * // Get 2026 salary
 * const salary2026 = salaryByYear.get(2026);
 *
 * // Or use the helper
 * const salary2027 = getSalaryForYear(2027);
 * ```
 */
export function useTeamSalary(teamCode: string | null): UseTeamSalaryReturn {
  const { data: salaries, error, isLoading, mutate } = useSWR<TeamSalary[], Error>(
    teamCode ? `/api/salary-book/team-salary?team=${encodeURIComponent(teamCode)}` : null,
    fetcher,
    {
      revalidateOnFocus: false,
      revalidateOnReconnect: true,
      dedupingInterval: 5000,
      keepPreviousData: true,
    }
  );

  // Memoize salary lookup by year
  const salaryByYear = useMemo(() => {
    return new Map((salaries ?? []).map((s) => [s.year, s]));
  }, [salaries]);

  // Memoize lookup function
  const getSalaryForYear = useCallback(
    (year: number) => salaryByYear.get(year),
    [salaryByYear]
  );

  // Current year totals (2025)
  const currentYearSalary = salaryByYear.get(2025);
  const currentYearTotal = currentYearSalary?.cap_total ?? null;
  const currentYearCapSpace = currentYearSalary?.cap_space ?? null;

  return {
    salaryByYear,
    salaries: salaries ?? [],
    getSalaryForYear,
    currentYearTotal,
    currentYearCapSpace,
    isLoading: isLoading && !salaries,
    error: error ?? null,
    refetch: async () => {
      await mutate();
    },
  };
}
