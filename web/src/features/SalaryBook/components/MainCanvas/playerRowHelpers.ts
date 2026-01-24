/**
 * Helper functions for PlayerRow component
 */
import type { SalaryBookPlayer, ContractOption, GuaranteeType } from "../../data";

// Contract years to display (6-year horizon; aligns with salary_book_warehouse cap_2025..cap_2030)
export const SALARY_YEARS = [2025, 2026, 2027, 2028, 2029] as const;

/**
 * Format salary for display with compact notation
 * Uses monospace tabular-nums for alignment
 */
export function formatSalary(amount: number | null): string {
  if (amount === null) return "—";
  if (amount === 0) return "$0K";
  // Convert to millions with 1 decimal
  const millions = amount / 1_000_000;
  if (millions >= 1) {
    return `$${millions.toFixed(1)}M`;
  }
  // For smaller amounts, show in thousands
  const thousands = amount / 1_000;
  return `$${Math.round(thousands)}K`;
}

/**
 * Get salary for a specific year from player data
 */
export function getSalary(player: SalaryBookPlayer, year: number): number | null {
  switch (year) {
    case 2025:
      return player.cap_2025;
    case 2026:
      return player.cap_2026;
    case 2027:
      return player.cap_2027;
    case 2028:
      return player.cap_2028;
    case 2029:
      return player.cap_2029;
    case 2030:
      return player.cap_2030;
    default:
      return null;
  }
}

/**
 * Get total salary across all displayed years
 */
export function getTotalSalary(player: SalaryBookPlayer): number {
  let total = 0;
  for (const year of SALARY_YEARS) {
    const salary = getSalary(player, year);
    if (salary !== null && salary !== undefined) {
      // Ensure we're adding numbers, not concatenating strings
      total += Number(salary) || 0;
    }
  }
  return total;
}

/**
 * Get option type for a specific year from player data
 */
export function getOption(player: SalaryBookPlayer, year: number): ContractOption {
  switch (year) {
    case 2025:
      return player.option_2025;
    case 2026:
      return player.option_2026;
    case 2027:
      return player.option_2027;
    case 2028:
      return player.option_2028;
    case 2029:
      return player.option_2029;
    case 2030:
      return player.option_2030;
    default:
      return null;
  }
}

/**
 * Get guarantee type for a specific year from player data
 */
export function getGuarantee(player: SalaryBookPlayer, year: number): GuaranteeType {
  switch (year) {
    case 2025:
      return player.guarantee_2025;
    case 2026:
      return player.guarantee_2026;
    case 2027:
      return player.guarantee_2027;
    case 2028:
      return player.guarantee_2028;
    case 2029:
      return player.guarantee_2029;
    case 2030:
      return player.guarantee_2030;
    default:
      return null;
  }
}

/**
 * Get percent of cap for a specific year from player data
 */
export function getPctCap(player: SalaryBookPlayer, year: number): number | null {
  switch (year) {
    case 2025:
      return player.pct_cap_2025;
    case 2026:
      return player.pct_cap_2026;
    case 2027:
      return player.pct_cap_2027;
    case 2028:
      return player.pct_cap_2028;
    case 2029:
      return player.pct_cap_2029;
    case 2030:
      return player.pct_cap_2030;
    default:
      return null;
  }
}

/**
 * Player name formatting for the table row.
 *
 * Requirement: LAST NAME, FIRST NAME (using display_last_name/display_first_name)
 * with a safe fallback to `player_name` if those fields are missing.
 */
export function getPlayerRowName(player: SalaryBookPlayer): string {
  const last = player.display_last_name?.trim() || "";
  const first = player.display_first_name?.trim() || "";

  if (last && first) return `${last}, ${first}`;
  if (last) return last;
  if (first) return first;
  return player.player_name;
}
