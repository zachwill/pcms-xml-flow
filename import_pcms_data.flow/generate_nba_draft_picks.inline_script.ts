/**
 * Generate NBA Draft Picks
 *
 * PCMS `draft_picks.json` currently contains DLG/WNBA picks only.
 * This script generates historical NBA draft picks based on players' draft info
 * (draft_year, draft_round, draft_pick, draft_team_id).
 *
 * Upserts into:
 * - pcms.draft_picks
 */
import { SQL } from "bun";
import { readdir } from "node:fs/promises";

const sql = new SQL({ url: Bun.env.POSTGRES_URL!, prepare: false });

const toIntOrNull = (val: unknown): number | null => {
  if (val === "" || val === null || val === undefined) return null;
  const num = Number(val);
  return Number.isNaN(num) ? null : Math.trunc(num);
};

// ─────────────────────────────────────────────────────────────────────────────
// Main
// ─────────────────────────────────────────────────────────────────────────────

export async function main(
  dry_run = false,
  extract_dir = "./shared/pcms",
) {
  const startedAt = new Date().toISOString();

  try {
    // Find extract directory
    const entries = await readdir(extract_dir, { withFileTypes: true });
    const subDir = entries.find((e) => e.isDirectory());
    const baseDir = subDir ? `${extract_dir}/${subDir.name}` : extract_dir;

    // Read clean JSON
    const players: any[] = await Bun.file(`${baseDir}/players.json`).json();
    console.log(`Found ${players.length} players`);

    // Build team_id → team_code lookup map
    const lookups: any = await Bun.file(`${baseDir}/lookups.json`).json();
    const teamsData: any[] = lookups?.lk_teams?.lk_team || [];
    const teamCodeMap = new Map<number, string>();
    for (const t of teamsData) {
      const teamId = t?.team_id;
      const teamCode = t?.team_code ?? t?.team_name_short;
      if (teamId && teamCode) {
        teamCodeMap.set(Number(teamId), String(teamCode));
      }
    }

    const ingestedAt = new Date();

    // Generate NBA picks from player draft info
    const generated = players
      .filter((p) => p?.league_lk === "NBA")
      .map((p) => {
        const draftYear = toIntOrNull(p?.draft_year);
        const draftRound = toIntOrNull(p?.draft_round);
        const pickNum = toIntOrNull(Array.isArray(p?.draft_pick) ? p?.draft_pick[0] : p?.draft_pick);

        if (draftYear == null || draftRound == null || pickNum == null) return null;

        const draftTeamId = toIntOrNull(p?.draft_team_id);

        // Synthetic ID: YYYY * 100000 + R * 1000 + PICK
        const syntheticId = draftYear * 100000 + draftRound * 1000 + pickNum;

        return {
          draft_pick_id: syntheticId,
          draft_year: draftYear,
          round: draftRound,
          pick_number: String(pickNum),
          pick_number_int: pickNum,
          league_lk: "NBA",

          original_team_id: draftTeamId,
          original_team_code: draftTeamId != null ? (teamCodeMap.get(draftTeamId) ?? null) : null,
          current_team_id: draftTeamId,
          current_team_code: draftTeamId != null ? (teamCodeMap.get(draftTeamId) ?? null) : null,

          is_active: false,
          player_id: toIntOrNull(p?.player_id),
          ingested_at: ingestedAt,
        };
      })
      .filter(Boolean) as Record<string, any>[];

    // Dedupe by the unique constraint target to avoid:
    // "ON CONFLICT DO UPDATE command cannot affect row a second time"
    const deduped = new Map<string, Record<string, any>>();
    for (const row of generated) {
      const key = `${row.draft_year}|${row.round}|${row.pick_number_int}|${row.league_lk}`;
      deduped.set(key, row);
    }

    const rows = Array.from(deduped.values());
    console.log(`Generated ${rows.length} NBA draft picks from player data`);

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
        ON CONFLICT (draft_year, round, pick_number_int, league_lk) DO UPDATE SET
          player_id = EXCLUDED.player_id,
          original_team_id = EXCLUDED.original_team_id,
          original_team_code = EXCLUDED.original_team_code,
          current_team_id = EXCLUDED.current_team_id,
          current_team_code = EXCLUDED.current_team_code,
          pick_number = EXCLUDED.pick_number,
          is_active = EXCLUDED.is_active,
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
