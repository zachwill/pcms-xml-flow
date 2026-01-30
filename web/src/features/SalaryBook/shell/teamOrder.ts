import { NBA_TEAMS } from "@/features/SalaryBook/data";

/**
 * Canonical team ordering for the scroll canvas.
 *
 * We want a single global alphabetical order (by displayed team name), not
 * conference-block ordering (EAST then WEST). This ensures e.g. Dallas appears
 * above Washington.
 */
const SORTED_TEAMS = [...NBA_TEAMS].sort((a, b) =>
  a.name.localeCompare(b.name)
);

export const TEAM_ORDER = SORTED_TEAMS.map((team) => team.team_code);

const TEAM_INDEX = new Map(TEAM_ORDER.map((code, index) => [code, index]));

export function sortTeamsByOrder(teams: string[]): string[] {
  return [...teams].sort((a, b) => {
    const indexA = TEAM_INDEX.get(a) ?? Number.MAX_SAFE_INTEGER;
    const indexB = TEAM_INDEX.get(b) ?? Number.MAX_SAFE_INTEGER;
    return indexA - indexB;
  });
}
