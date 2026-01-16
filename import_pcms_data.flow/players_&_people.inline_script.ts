/**
 * Players & People Import
 * 
 * Reads clean JSON from lineage step, inserts to pcms.people
 */
import { SQL } from "bun";
import { readdir } from "node:fs/promises";

const sql = new SQL({ url: Bun.env.POSTGRES_URL!, prepare: false });

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

  try {
    // Find extract directory
    const entries = await readdir(extract_dir, { withFileTypes: true });
    const subDir = entries.find(e => e.isDirectory());
    const baseDir = subDir ? `${extract_dir}/${subDir.name}` : extract_dir;

    // Read clean JSON (already snake_case, nulls handled)
    const players: any[] = await Bun.file(`${baseDir}/players.json`).json();
    console.log(`Found ${players.length} players`);

    if (dry_run) {
      return {
        dry_run: true,
        started_at: startedAt,
        finished_at: new Date().toISOString(),
        tables: [{ table: "pcms.people", attempted: players.length, success: true }],
        errors: [],
      };
    }

    // Upsert in batches
    const BATCH_SIZE = 100;
    let total = 0;

    for (let i = 0; i < players.length; i += BATCH_SIZE) {
      const batch = players.slice(i, i + BATCH_SIZE);

    /** Convert empty strings/invalid values to null for integer columns */
    const toIntOrNull = (val: unknown): number | null => {
      if (val === "" || val === null || val === undefined) return null;
      const num = Number(val);
      return Number.isNaN(num) ? null : num;
    };
    
    // Then in your row mapping:
    const rows = batch.map(p => ({
      person_id: p.player_id,
      first_name: p.first_name,
      last_name: p.last_name,
      middle_name: p.middle_name || null,
      display_first_name: p.display_first_name,
      display_last_name: p.display_last_name,
      roster_first_name: p.roster_first_name,
      roster_last_name: p.roster_last_name,
      birth_date: p.birth_date || null,
      birth_country_lk: p.birth_country_lk,
      gender: p.gender,
      height: toIntOrNull(p.height),
      weight: toIntOrNull(p.weight),
      person_type_lk: p.person_type_lk,
      player_status_lk: p.player_status_lk,
      record_status_lk: p.record_status_lk,
      league_lk: p.league_lk,
      team_id: toIntOrNull(p.team_id),
      school_id: toIntOrNull(p.school_id),
      draft_year: toIntOrNull(p.draft_year),
      draft_round: toIntOrNull(p.draft_round),                              // ← Fixed
      draft_pick: toIntOrNull(Array.isArray(p.draft_pick) ? p.draft_pick[0] : p.draft_pick),
      years_of_service: toIntOrNull(p.years_of_service),
      service_years_json: p.player_service_years ?? null,
      created_at: p.create_date || null,
      updated_at: p.last_change_date || null,
      record_changed_at: p.record_change_date || null,
      poison_pill_amt: toIntOrNull(p.poison_pill_amt),
      is_two_way: p.two_way_flg ?? false,
      is_flex: p.flex_flg ?? false,
      source_drop_file: s3_key ?? null,
      ingested_at: new Date(),
    }));

      try {
        await sql`
          INSERT INTO pcms.people ${sql(rows)}
          ON CONFLICT (person_id) DO UPDATE SET
            first_name = EXCLUDED.first_name,
            last_name = EXCLUDED.last_name,
            middle_name = EXCLUDED.middle_name,
            display_first_name = EXCLUDED.display_first_name,
            display_last_name = EXCLUDED.display_last_name,
            roster_first_name = EXCLUDED.roster_first_name,
            roster_last_name = EXCLUDED.roster_last_name,
            birth_date = EXCLUDED.birth_date,
            birth_country_lk = EXCLUDED.birth_country_lk,
            gender = EXCLUDED.gender,
            height = EXCLUDED.height,
            weight = EXCLUDED.weight,
            person_type_lk = EXCLUDED.person_type_lk,
            player_status_lk = EXCLUDED.player_status_lk,
            record_status_lk = EXCLUDED.record_status_lk,
            league_lk = EXCLUDED.league_lk,
            team_id = EXCLUDED.team_id,
            school_id = EXCLUDED.school_id,
            draft_year = EXCLUDED.draft_year,
            draft_round = EXCLUDED.draft_round,
            draft_pick = EXCLUDED.draft_pick,
            years_of_service = EXCLUDED.years_of_service,
            service_years_json = EXCLUDED.service_years_json,
            poison_pill_amt = EXCLUDED.poison_pill_amt,
            is_two_way = EXCLUDED.is_two_way,
            is_flex = EXCLUDED.is_flex,
            updated_at = EXCLUDED.updated_at,
            record_changed_at = EXCLUDED.record_changed_at,
            source_drop_file = EXCLUDED.source_drop_file,
            ingested_at = EXCLUDED.ingested_at
        `;
      } catch (e) {
        console.error(e);
        console.log(batch);
      }

      total += batch.length;
      // console.log(`  Upserted ${total}/${players.length}`);
    }

    return {
      dry_run: false,
      started_at: startedAt,
      finished_at: new Date().toISOString(),
      tables: [{ table: "pcms.people", attempted: players.length, success: true }],
      errors: [],
    };
  } catch (e: any) {
    return {
      dry_run,
      started_at: startedAt,
      finished_at: new Date().toISOString(),
      tables: [],
      errors: [e.message],
    };
  }
}