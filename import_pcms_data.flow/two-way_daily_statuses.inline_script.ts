/**
 * Two-Way Daily Statuses Import
 *
 * Reads clean JSON from lineage step and upserts into:
 * - pcms.two_way_daily_statuses
 *
 * Source JSON: two_way.json
 * Notes:
 * - snake_case keys, nulls handled
 * - this extract still has some XML-style nesting/hyphenated keys
 */
import { SQL } from "bun";
import { readdir } from "node:fs/promises";

const sql = new SQL({ url: Bun.env.POSTGRES_URL!, prepare: false });

function asArray<T = any>(val: any): T[] {
  if (val === null || val === undefined) return [];
  return Array.isArray(val) ? val : [val];
}

function toDateOnly(val: any): string | null {
  if (!val) return null;
  if (typeof val !== "string") return null;
  // Example: 2017-10-17T00:00:00-04:00 -> 2017-10-17
  return val.length >= 10 ? val.slice(0, 10) : null;
}

// ─────────────────────────────────────────────────────────────────────────────
// Main
// ─────────────────────────────────────────────────────────────────────────────

export async function main(
  dry_run = false,
  lineage_id?: number,
  s3_key?: string,
  extract_dir = "./shared/pcms"
) {
  const startedAt = new Date().toISOString();
  void lineage_id;

  try {
    // Find extract directory
    const entries = await readdir(extract_dir, { withFileTypes: true });
    const subDir = entries.find((e) => e.isDirectory());
    const baseDir = subDir ? `${extract_dir}/${subDir.name}` : extract_dir;

    // Read clean JSON
    const data: any = await Bun.file(`${baseDir}/two_way.json`).json();

    const statuses = asArray<any>(
      data?.daily_statuses?.["daily-status"] ??
        data?.daily_statuses?.daily_status ??
        data?.daily_statuses
    );

    console.log(`Found ${statuses.length} two-way daily statuses`);

    const ingestedAt = new Date();
    const provenance = {
      source_drop_file: s3_key,
      ingested_at: ingestedAt,
    };

    const rows = statuses
      .map((s) => {
        const player_id = s?.player_id ?? null;
        const status_date = toDateOnly(s?.status_date);
        const salary_year = s?.season_year ?? (status_date ? Number(status_date.slice(0, 4)) : null);
        const status_lk = s?.two_way_daily_status_lk ?? null;

        // Required by schema
        if (!player_id || !status_date || !salary_year || !status_lk) return null;

        return {
          player_id,
          status_date,
          salary_year,

          // Optional columns (only present in some extracts)
          day_of_season: s?.day_of_season ?? null,
          status_lk,
          status_team_id: s?.team_id ?? s?.status_team_id ?? null,
          contract_id: s?.contract_id ?? null,
          contract_team_id: s?.contract_team_id ?? null,
          signing_team_id: s?.signing_team_id ?? null,

          nba_service_days: s?.nba_service_days ?? null,
          nba_service_limit: s?.nba_service_limit ?? null,
          nba_days_remaining: s?.nba_days_remaining ?? null,
          nba_earned_salary: s?.nba_earned_salary ?? null,
          glg_earned_salary: s?.glg_earned_salary ?? null,
          nba_salary_days: s?.nba_salary_days ?? null,
          glg_salary_days: s?.glg_salary_days ?? null,
          unreported_days: s?.unreported_days ?? null,

          season_active_nba_game_days: s?.season_active_nba_game_days ?? null,
          season_with_nba_days: s?.season_with_nba_days ?? null,
          season_travel_with_nba_days: s?.season_travel_with_nba_days ?? null,
          season_non_nba_days: s?.season_non_nba_days ?? null,
          season_non_nba_glg_days: s?.season_non_nba_glg_days ?? null,
          season_total_days: s?.season_total_days ?? null,

          created_at: s?.create_date ?? null,
          updated_at: s?.last_change_date ?? null,
          record_changed_at: s?.record_change_date ?? null,

          ...provenance,
        };
      })
      .filter(Boolean) as Record<string, any>[];

    if (dry_run) {
      return {
        dry_run: true,
        started_at: startedAt,
        finished_at: new Date().toISOString(),
        tables: [{ table: "pcms.two_way_daily_statuses", attempted: rows.length, success: true }],
        errors: [],
      };
    }

    const BATCH_SIZE = 1000;

    for (let i = 0; i < rows.length; i += BATCH_SIZE) {
      const batch = rows.slice(i, i + BATCH_SIZE);

      await sql`
        INSERT INTO pcms.two_way_daily_statuses ${sql(batch)}
        ON CONFLICT (player_id, status_date) DO UPDATE SET
          salary_year = EXCLUDED.salary_year,
          day_of_season = EXCLUDED.day_of_season,
          status_lk = EXCLUDED.status_lk,
          status_team_id = EXCLUDED.status_team_id,
          contract_id = EXCLUDED.contract_id,
          contract_team_id = EXCLUDED.contract_team_id,
          signing_team_id = EXCLUDED.signing_team_id,
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
          source_drop_file = EXCLUDED.source_drop_file,
          ingested_at = EXCLUDED.ingested_at
      `;

      console.log(`  Upserted ${Math.min(i + batch.length, rows.length)}/${rows.length}`);
    }

    return {
      dry_run: false,
      started_at: startedAt,
      finished_at: new Date().toISOString(),
      tables: [{ table: "pcms.two_way_daily_statuses", attempted: rows.length, success: true }],
      errors: [],
    };
  } catch (e: any) {
    return {
      dry_run,
      started_at: startedAt,
      finished_at: new Date().toISOString(),
      tables: [],
      errors: [e?.message ?? String(e)],
    };
  }
}
