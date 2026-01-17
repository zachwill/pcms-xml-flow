/**
 * Draft Picks Import
 *
 * Reads clean JSON from lineage step and upserts into:
 * - pcms.draft_picks
 *
 * Clean JSON notes:
 * - snake_case keys
 * - null values already handled
 * - no XML wrapper nesting
 *
 * Source JSON: draft_picks.json
 */
import { SQL } from "bun";
import { readdir } from "node:fs/promises";

const sql = new SQL({ url: Bun.env.POSTGRES_URL!, prepare: false });

function asArray<T = any>(val: any): T[] {
  if (val === null || val === undefined) return [];
  return Array.isArray(val) ? val : [val];
}

function normalizePick(val: any): { pick_number: string | null; pick_number_int: number | null } {
  if (val === null || val === undefined || val === "") return { pick_number: null, pick_number_int: null };

  if (typeof val === "number") {
    const intVal = Number.isFinite(val) ? Math.trunc(val) : null;
    return {
      pick_number: Number.isFinite(val) ? String(val) : null,
      pick_number_int: intVal,
    };
  }

  const s = String(val).trim();
  if (!s) return { pick_number: null, pick_number_int: null };

  // Some PCMS values can be non-numeric (e.g. supplemental picks). Keep text,
  // and only populate the int column when it parses cleanly.
  const maybeInt = Number.parseInt(s, 10);
  return {
    pick_number: s,
    pick_number_int: Number.isFinite(maybeInt) && String(maybeInt) === s ? maybeInt : null,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Main
// ─────────────────────────────────────────────────────────────────────────────

export async function main(
  dry_run = false,
  extract_dir = "./shared/pcms"
) {
  const startedAt = new Date().toISOString();

  try {
    // Find extract directory
    const entries = await readdir(extract_dir, { withFileTypes: true });
    const subDir = entries.find((e) => e.isDirectory());
    const baseDir = subDir ? `${extract_dir}/${subDir.name}` : extract_dir;

    // Build team_id → team_code lookup map
    const lookups: any = await Bun.file(`${baseDir}/lookups.json`).json();
    const teamsData: any[] = lookups?.lk_teams?.lk_team || [];
    const teamCodeMap = new Map<number, string>();
    for (const t of teamsData) {
      if (t.team_id && t.team_code) {
        teamCodeMap.set(t.team_id, t.team_code);
      }
    }

    // Read clean JSON
    const draftPicks: any[] = await Bun.file(`${baseDir}/draft_picks.json`).json();
    console.log(`Found ${draftPicks.length} draft picks`);

    const ingestedAt = new Date();

    const rows = draftPicks
      .map((dp) => {
        if (!dp?.draft_pick_id) return null;

        const { pick_number, pick_number_int } = normalizePick(dp?.pick);
        const histories = asArray<any>(dp?.histories);

        const originalTeamId = dp?.original_team_id ?? null;
        const currentTeamId = dp?.current_team_id ?? dp?.team_id ?? null;

        return {
          draft_pick_id: dp.draft_pick_id,
          draft_year: dp?.draft_year ?? dp?.year ?? null,
          round: dp?.round ?? null,
          pick_number,
          pick_number_int,

          league_lk: dp?.league_lk ?? null,
          original_team_id: originalTeamId,
          original_team_code: originalTeamId != null ? (teamCodeMap.get(originalTeamId) ?? null) : null,
          current_team_id: currentTeamId,
          current_team_code: currentTeamId != null ? (teamCodeMap.get(currentTeamId) ?? null) : null,

          is_active: dp?.is_active ?? dp?.active_flg ?? null,

          // These fields are not present in the core dp extract for all leagues.
          is_protected: dp?.is_protected ?? dp?.protected_flg ?? null,
          protection_description: dp?.protection_description ?? null,
          is_swap: dp?.is_swap ?? dp?.draft_pick_swap_flg ?? dp?.swap_flg ?? null,
          swap_type_lk: dp?.swap_type_lk ?? null,
          conveyance_year_range: dp?.conveyance_year_range ?? null,
          conveyance_trigger_description: dp?.conveyance_trigger_description ?? null,
          first_round_summary: dp?.first_round_summary ?? null,
          second_round_summary: dp?.second_round_summary ?? null,

          history_json: histories.length > 0 ? { "history": histories } : null,
          draft_json: dp ?? null,
          summary_json: dp?.summary_json ?? null,

          created_at: dp?.create_date ?? null,
          updated_at: dp?.last_change_date ?? null,
          record_changed_at: dp?.record_change_date ?? null,

          ingested_at: ingestedAt,
        };
      })
      .filter(Boolean) as Record<string, any>[];

    if (dry_run) {
      return {
        dry_run: true,
        started_at: startedAt,
        finished_at: new Date().toISOString(),
        tables: [{ table: "pcms.draft_picks", attempted: rows.length, success: true }],
        errors: [],
      };
    }

    const BATCH_SIZE = 1000;

    for (let i = 0; i < rows.length; i += BATCH_SIZE) {
      const batch = rows.slice(i, i + BATCH_SIZE);

      await sql`
        INSERT INTO pcms.draft_picks ${sql(batch)}
        ON CONFLICT (draft_pick_id) DO UPDATE SET
          draft_year = EXCLUDED.draft_year,
          round = EXCLUDED.round,
          pick_number = EXCLUDED.pick_number,
          pick_number_int = EXCLUDED.pick_number_int,
          league_lk = EXCLUDED.league_lk,
          original_team_id = EXCLUDED.original_team_id,
          original_team_code = EXCLUDED.original_team_code,
          current_team_id = EXCLUDED.current_team_id,
          current_team_code = EXCLUDED.current_team_code,
          is_active = EXCLUDED.is_active,
          is_protected = EXCLUDED.is_protected,
          protection_description = EXCLUDED.protection_description,
          is_swap = EXCLUDED.is_swap,
          swap_type_lk = EXCLUDED.swap_type_lk,
          conveyance_year_range = EXCLUDED.conveyance_year_range,
          conveyance_trigger_description = EXCLUDED.conveyance_trigger_description,
          first_round_summary = EXCLUDED.first_round_summary,
          second_round_summary = EXCLUDED.second_round_summary,
          history_json = EXCLUDED.history_json,
          draft_json = EXCLUDED.draft_json,
          summary_json = EXCLUDED.summary_json,
          updated_at = EXCLUDED.updated_at,
          record_changed_at = EXCLUDED.record_changed_at,
          ingested_at = EXCLUDED.ingested_at
      `;

      console.log(`  Upserted ${Math.min(i + batch.length, rows.length)}/${rows.length}`);
    }

    return {
      dry_run: false,
      started_at: startedAt,
      finished_at: new Date().toISOString(),
      tables: [{ table: "pcms.draft_picks", attempted: rows.length, success: true }],
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
