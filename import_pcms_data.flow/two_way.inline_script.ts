/**
 * Two-Way Import (consolidated)
 *
 * Merges:
 *  - two-way_daily_statuses.inline_script.ts
 *  - two-way_utility.inline_script.ts
 *
 * Upserts into:
 *  - pcms.two_way_daily_statuses   (two_way.json)
 *  - pcms.two_way_contract_utility (two_way.json)
 *  - pcms.two_way_game_utility     (two_way_utility.json)
 *  - pcms.team_two_way_capacity    (two_way_utility.json)
 *
 * Notes:
 *  - Most extracts are already clean JSON (snake_case + nulls).
 *  - The two_way.json extract still sometimes contains XML-style nesting/hyphenated keys.
 *  - Upfront dedupe is performed per-table before batching.
 */

import { SQL } from "bun";
import { readdir } from "node:fs/promises";

const sql = new SQL({ url: Bun.env.POSTGRES_URL!, prepare: false });

// ─────────────────────────────────────────────────────────────────────────────
// Helpers (inline)
// ─────────────────────────────────────────────────────────────────────────────

function asArray<T = any>(val: any): T[] {
  if (val === null || val === undefined || val === "") return [];
  return Array.isArray(val) ? val : [val];
}

function toIntOrNull(val: unknown): number | null {
  if (val === "" || val === null || val === undefined) return null;
  const n = typeof val === "number" ? val : Number(val);
  return Number.isFinite(n) ? Math.trunc(n) : null;
}

function toBoolOrNull(val: unknown): boolean | null {
  if (val === "" || val === null || val === undefined) return null;
  if (typeof val === "boolean") return val;
  const s = String(val).toLowerCase();
  if (s === "true" || s === "t" || s === "1" || s === "y" || s === "yes") return true;
  if (s === "false" || s === "f" || s === "0" || s === "n" || s === "no") return false;
  return null;
}

function toDateOnly(val: unknown): string | null {
  if (val === "" || val === null || val === undefined) return null;
  const s = String(val);
  // Example: 2017-10-17T00:00:00-04:00 -> 2017-10-17
  return s.length >= 10 ? s.slice(0, 10) : null;
}

async function resolveBaseDir(extractDir: string): Promise<string> {
  const entries = await readdir(extractDir, { withFileTypes: true });
  const subDir = entries.find((e) => e.isDirectory());
  return subDir ? `${extractDir}/${subDir.name}` : extractDir;
}

function buildTeamCodeMap(lookups: any): Map<number, string> {
  const teamsData: any[] = lookups?.lk_teams?.lk_team || [];
  const teamCodeMap = new Map<number, string>();
  for (const t of teamsData) {
    const teamId = t?.team_id;
    const teamCode = t?.team_code ?? t?.team_name_short;
    if (teamId && teamCode) teamCodeMap.set(Number(teamId), String(teamCode));
  }
  return teamCodeMap;
}

function dedupeByKey<T>(rows: T[], keyFn: (row: T) => string): T[] {
  const seen = new Map<string, T>();
  for (const r of rows) seen.set(keyFn(r), r);
  return [...seen.values()];
}

// ─────────────────────────────────────────────────────────────────────────────
// Main
// ─────────────────────────────────────────────────────────────────────────────

export async function main(dry_run = false, extract_dir = "./shared/pcms") {
  const startedAt = new Date().toISOString();
  const tables: { table: string; attempted: number; success: boolean }[] = [];

  try {
    const baseDir = await resolveBaseDir(extract_dir);

    // Build team_id → team_code lookup map (used by all two-way tables)
    const lookupsFile = Bun.file(`${baseDir}/lookups.json`);
    const lookups: any = (await lookupsFile.exists()) ? await lookupsFile.json() : {};
    const teamCodeMap = buildTeamCodeMap(lookups);

    const twoWayFile = Bun.file(`${baseDir}/two_way.json`);
    if (!(await twoWayFile.exists())) {
      throw new Error(`two_way.json not found in ${baseDir}`);
    }
    const twoWay: any = await twoWayFile.json();

    const utilFile = Bun.file(`${baseDir}/two_way_utility.json`);
    const util: any = (await utilFile.exists()) ? await utilFile.json() : null;

    // ─────────────────────────────────────────────────────────────────────────
    // Extract + transform
    // ─────────────────────────────────────────────────────────────────────────

    const ingestedAt = new Date();

    // two_way_daily_statuses (two_way.json)
    const statuses = asArray<any>(
      twoWay?.daily_statuses?.["daily-status"] ??
        twoWay?.daily_statuses?.daily_status ??
        twoWay?.daily_statuses
    );

    const statusRowsRaw = statuses
      .map((s) => {
        const playerId = toIntOrNull(s?.player_id);
        const statusDate = toDateOnly(s?.status_date);
        const salaryYear =
          toIntOrNull(s?.season_year) ?? (statusDate ? toIntOrNull(statusDate.slice(0, 4)) : null);
        const statusLk = s?.two_way_daily_status_lk ?? null;

        const statusTeamId = toIntOrNull(s?.team_id ?? s?.status_team_id);
        const contractTeamId = toIntOrNull(s?.contract_team_id);
        const signingTeamId = toIntOrNull(s?.signing_team_id);

        // Required by schema PK and core columns
        if (playerId === null || !statusDate || salaryYear === null || !statusLk) return null;

        return {
          player_id: playerId,
          status_date: statusDate,
          salary_year: salaryYear,

          day_of_season: toIntOrNull(s?.day_of_season),
          status_lk: statusLk,

          status_team_id: statusTeamId,
          status_team_code: statusTeamId !== null ? (teamCodeMap.get(statusTeamId) ?? null) : null,

          contract_id: toIntOrNull(s?.contract_id),

          contract_team_id: contractTeamId,
          contract_team_code:
            contractTeamId !== null ? (teamCodeMap.get(contractTeamId) ?? null) : null,

          signing_team_id: signingTeamId,
          signing_team_code:
            signingTeamId !== null ? (teamCodeMap.get(signingTeamId) ?? null) : null,

          nba_service_days: toIntOrNull(s?.nba_service_days),
          nba_service_limit: toIntOrNull(s?.nba_service_limit),
          nba_days_remaining: toIntOrNull(s?.nba_days_remaining),

          // numeric columns (leave as-is if already numeric)
          nba_earned_salary: s?.nba_earned_salary ?? null,
          glg_earned_salary: s?.glg_earned_salary ?? null,

          nba_salary_days: toIntOrNull(s?.nba_salary_days),
          glg_salary_days: toIntOrNull(s?.glg_salary_days),
          unreported_days: toIntOrNull(s?.unreported_days),

          season_active_nba_game_days: toIntOrNull(s?.season_active_nba_game_days),
          season_with_nba_days: toIntOrNull(s?.season_with_nba_days),
          season_travel_with_nba_days: toIntOrNull(s?.season_travel_with_nba_days),
          season_non_nba_days: toIntOrNull(s?.season_non_nba_days),
          season_non_nba_glg_days: toIntOrNull(s?.season_non_nba_glg_days),
          season_total_days: toIntOrNull(s?.season_total_days),

          created_at: s?.create_date ?? null,
          updated_at: s?.last_change_date ?? null,
          record_changed_at: s?.record_change_date ?? null,

          ingested_at: ingestedAt,
        };
      })
      .filter(Boolean) as Record<string, any>[];

    const statusRows = dedupeByKey(statusRowsRaw, (r) => `${r.player_id}|${r.status_date}`);

    // two_way_game_utility + team_two_way_capacity (two_way_utility.json)
    const games = asArray<any>(util?.active_list_by_team?.two_way_util_game);
    const budgets = asArray<any>(util?.under15_games?.under15_team_budget);

    const gameRowsRaw = games
      .flatMap((g: any) => {
        const gameId = toIntOrNull(g?.game_id);
        const teamId = toIntOrNull(g?.team_id);
        const oppositionTeamId = toIntOrNull(g?.opposition_team_id);
        const gameDate = toDateOnly(g?.date_est);
        const standardContractsOnTeam = toIntOrNull(g?.number_of_standard_nba_contracts);

        if (gameId === null || teamId === null) return [];

        const players = asArray<any>(g?.two_way_util_players?.two_way_util_player);

        return players
          .map((p: any) => {
            const playerId = toIntOrNull(p?.player_id);
            if (playerId === null) return null;

            return {
              game_id: gameId,
              team_id: teamId,
              team_code: teamCodeMap.get(teamId) ?? null,

              player_id: playerId,
              game_date_est: gameDate,

              opposition_team_id: oppositionTeamId,
              opposition_team_code:
                oppositionTeamId !== null ? (teamCodeMap.get(oppositionTeamId) ?? null) : null,

              roster_first_name: p?.roster_first_name ?? null,
              roster_last_name: p?.roster_last_name ?? null,
              display_first_name: p?.display_first_name ?? null,
              display_last_name: p?.display_last_name ?? null,
              games_on_active_list: toIntOrNull(p?.number_of_games_on_active_list),
              active_list_games_limit: toIntOrNull(p?.active_list_games_limit),
              standard_nba_contracts_on_team: standardContractsOnTeam,

              ingested_at: ingestedAt,
            };
          })
          .filter(Boolean);
      })
      .filter(Boolean) as Record<string, any>[];

    const gameRows = dedupeByKey(gameRowsRaw, (r) => `${r.game_id}|${r.player_id}`);

    const capacityRowsRaw = budgets
      .map((b: any) => {
        const teamId = toIntOrNull(b?.team_id);
        if (teamId === null) return null;

        return {
          team_id: teamId,
          team_code: teamCodeMap.get(teamId) ?? null,
          current_contract_count: toIntOrNull(b?.current_contract_count),
          games_remaining: toIntOrNull(b?.games_remaining),
          under_15_games_count: toIntOrNull(b?.under15_games_count),
          under_15_games_remaining: toIntOrNull(b?.under15_games_remaining),
          ingested_at: ingestedAt,
        };
      })
      .filter(Boolean) as Record<string, any>[];

    const capacityRows = dedupeByKey(capacityRowsRaw, (r) => String(r.team_id));

    // two_way_contract_utility (two_way.json)
    const seasons = asArray<any>(
      twoWay?.two_way_seasons?.["two-way-season"] ??
        twoWay?.two_way_seasons?.two_way_season ??
        twoWay?.two_way_seasons
    );

    const contractRowsRaw: Record<string, any>[] = [];

    for (const s of seasons) {
      const players = asArray<any>(
        s?.["two-way-players"]?.["two-way-player"] ?? s?.two_way_players?.two_way_player
      );

      for (const p of players) {
        const contracts = asArray<any>(
          p?.["two-way-contracts"]?.["two-way-contract"] ?? p?.two_way_contracts?.two_way_contract
        );

        for (const c of contracts) {
          const contractId = toIntOrNull(c?.contract_id);
          const playerId = toIntOrNull(c?.player_id ?? p?.player_id);
          if (contractId === null || playerId === null) continue;

          const contractTeamId = toIntOrNull(c?.contract_team_id);
          const signingTeamId = toIntOrNull(c?.signing_team_id);

          contractRowsRaw.push({
            contract_id: contractId,
            player_id: playerId,

            contract_team_id: contractTeamId,
            contract_team_code:
              contractTeamId !== null ? (teamCodeMap.get(contractTeamId) ?? null) : null,

            signing_team_id: signingTeamId,
            signing_team_code:
              signingTeamId !== null ? (teamCodeMap.get(signingTeamId) ?? null) : null,

            is_active_two_way_contract: toBoolOrNull(c?.is_active_two_way_contract),
            games_on_active_list: toIntOrNull(c?.number_of_games_on_active_list),
            active_list_games_limit: toIntOrNull(c?.active_list_games_limit),
            remaining_active_list_games: toIntOrNull(c?.remaining_active_list_games),

            ingested_at: ingestedAt,
          });
        }
      }
    }

    const contractRows = dedupeByKey(contractRowsRaw, (r) => String(r.contract_id));

    console.log(`Found ${statusRows.length} two-way daily statuses`);
    console.log(`Found ${contractRows.length} two-way contract utility rows`);
    console.log(`Found ${gameRows.length} two-way utility game/player rows`);
    console.log(`Found ${capacityRows.length} team two-way capacity rows`);

    if (dry_run) {
      return {
        dry_run: true,
        started_at: startedAt,
        finished_at: new Date().toISOString(),
        tables: [
          { table: "pcms.two_way_daily_statuses", attempted: statusRows.length, success: true },
          { table: "pcms.two_way_contract_utility", attempted: contractRows.length, success: true },
          { table: "pcms.two_way_game_utility", attempted: gameRows.length, success: true },
          { table: "pcms.team_two_way_capacity", attempted: capacityRows.length, success: true },
        ],
        errors: [],
      };
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Upsert
    // ─────────────────────────────────────────────────────────────────────────

    const BATCH_SIZE = 200;

    // pcms.two_way_daily_statuses
    for (let i = 0; i < statusRows.length; i += BATCH_SIZE) {
      const batch = statusRows.slice(i, i + BATCH_SIZE);

      await sql`
        INSERT INTO pcms.two_way_daily_statuses ${sql(batch)}
        ON CONFLICT (player_id, status_date) DO UPDATE SET
          salary_year = EXCLUDED.salary_year,
          day_of_season = EXCLUDED.day_of_season,
          status_lk = EXCLUDED.status_lk,
          status_team_id = EXCLUDED.status_team_id,
          status_team_code = EXCLUDED.status_team_code,
          contract_id = EXCLUDED.contract_id,
          contract_team_id = EXCLUDED.contract_team_id,
          contract_team_code = EXCLUDED.contract_team_code,
          signing_team_id = EXCLUDED.signing_team_id,
          signing_team_code = EXCLUDED.signing_team_code,
          nba_service_days = EXCLUDED.nba_service_days,
          nba_service_limit = EXCLUDED.nba_service_limit,
          nba_days_remaining = EXCLUDED.nba_days_remaining,
          nba_earned_salary = EXCLUDED.nba_earned_salary,
          glg_earned_salary = EXCLUDED.glg_earned_salary,
          nba_salary_days = EXCLUDED.nba_salary_days,
          glg_salary_days = EXCLUDED.glg_salary_days,
          unreported_days = EXCLUDED.unreported_days,
          season_active_nba_game_days = EXCLUDED.season_active_nba_game_days,
          season_with_nba_days = EXCLUDED.season_with_nba_days,
          season_travel_with_nba_days = EXCLUDED.season_travel_with_nba_days,
          season_non_nba_days = EXCLUDED.season_non_nba_days,
          season_non_nba_glg_days = EXCLUDED.season_non_nba_glg_days,
          season_total_days = EXCLUDED.season_total_days,
          updated_at = EXCLUDED.updated_at,
          record_changed_at = EXCLUDED.record_changed_at,
          ingested_at = EXCLUDED.ingested_at
      `;
    }
    tables.push({ table: "pcms.two_way_daily_statuses", attempted: statusRows.length, success: true });

    // pcms.two_way_contract_utility
    for (let i = 0; i < contractRows.length; i += BATCH_SIZE) {
      const batch = contractRows.slice(i, i + BATCH_SIZE);

      await sql`
        INSERT INTO pcms.two_way_contract_utility ${sql(batch)}
        ON CONFLICT (contract_id) DO UPDATE SET
          player_id = EXCLUDED.player_id,
          contract_team_id = EXCLUDED.contract_team_id,
          contract_team_code = EXCLUDED.contract_team_code,
          signing_team_id = EXCLUDED.signing_team_id,
          signing_team_code = EXCLUDED.signing_team_code,
          is_active_two_way_contract = EXCLUDED.is_active_two_way_contract,
          games_on_active_list = EXCLUDED.games_on_active_list,
          active_list_games_limit = EXCLUDED.active_list_games_limit,
          remaining_active_list_games = EXCLUDED.remaining_active_list_games,
          ingested_at = EXCLUDED.ingested_at
      `;
    }
    tables.push({ table: "pcms.two_way_contract_utility", attempted: contractRows.length, success: true });

    // pcms.two_way_game_utility
    for (let i = 0; i < gameRows.length; i += BATCH_SIZE) {
      const batch = gameRows.slice(i, i + BATCH_SIZE);

      await sql`
        INSERT INTO pcms.two_way_game_utility ${sql(batch)}
        ON CONFLICT (game_id, player_id) DO UPDATE SET
          team_id = EXCLUDED.team_id,
          team_code = EXCLUDED.team_code,
          game_date_est = EXCLUDED.game_date_est,
          opposition_team_id = EXCLUDED.opposition_team_id,
          opposition_team_code = EXCLUDED.opposition_team_code,
          roster_first_name = EXCLUDED.roster_first_name,
          roster_last_name = EXCLUDED.roster_last_name,
          display_first_name = EXCLUDED.display_first_name,
          display_last_name = EXCLUDED.display_last_name,
          games_on_active_list = EXCLUDED.games_on_active_list,
          active_list_games_limit = EXCLUDED.active_list_games_limit,
          standard_nba_contracts_on_team = EXCLUDED.standard_nba_contracts_on_team,
          ingested_at = EXCLUDED.ingested_at
      `;
    }
    tables.push({ table: "pcms.two_way_game_utility", attempted: gameRows.length, success: true });

    // pcms.team_two_way_capacity
    for (let i = 0; i < capacityRows.length; i += BATCH_SIZE) {
      const batch = capacityRows.slice(i, i + BATCH_SIZE);

      await sql`
        INSERT INTO pcms.team_two_way_capacity ${sql(batch)}
        ON CONFLICT (team_id) DO UPDATE SET
          team_code = EXCLUDED.team_code,
          current_contract_count = EXCLUDED.current_contract_count,
          games_remaining = EXCLUDED.games_remaining,
          under_15_games_count = EXCLUDED.under_15_games_count,
          under_15_games_remaining = EXCLUDED.under_15_games_remaining,
          ingested_at = EXCLUDED.ingested_at
      `;
    }
    tables.push({ table: "pcms.team_two_way_capacity", attempted: capacityRows.length, success: true });

    return {
      dry_run: false,
      started_at: startedAt,
      finished_at: new Date().toISOString(),
      tables,
      errors: [],
    };
  } catch (e: any) {
    return {
      dry_run,
      started_at: startedAt,
      finished_at: new Date().toISOString(),
      tables,
      errors: [e?.message ?? String(e)],
    };
  }
}
