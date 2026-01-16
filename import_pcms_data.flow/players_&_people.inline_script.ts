/**
 * Players & People Import - Reads pre-parsed JSON from .shared/
 * 
 * Expects lineage step to have already:
 * 1. Extracted XML files to .shared/nba_pcms_full_extract/
 * 2. Parsed XML to JSON (e.g., *_player.json)
 * 3. Written lineage.json with context
 */
import { SQL } from "bun";
import { readdir } from "node:fs/promises";

const sql = new SQL({ url: Bun.env.POSTGRES_URL!, prepare: false });
const PARSER_VERSION = "2.1.0";
const SHARED_DIR = "./shared/pcms";

// ─────────────────────────────────────────────────────────────────────────────
// Types
// ─────────────────────────────────────────────────────────────────────────────

interface LineageContext {
  lineage_id: number;
  s3_key: string;
  source_hash: string;
}

interface UpsertResult {
  table: string;
  attempted: number;
  success: boolean;
  error?: string;
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

function hash(data: string): string {
  return new Bun.CryptoHasher("sha256").update(data).digest("hex");
}

function safeNum(val: unknown): number | null {
  if (val === null || val === undefined || val === "") return null;
  const n = Number(val);
  return isNaN(n) ? null : n;
}

function safeBool(val: unknown): boolean | null {
  if (val === null || val === undefined) return null;
  if (typeof val === "boolean") return val;
  if (val === 1 || val === "1" || val === "Y" || val === "true" || val === true) return true;
  if (val === 0 || val === "0" || val === "N" || val === "false" || val === false) return false;
  return null;
}

function safeBigInt(val: unknown): string | null {
  if (val === null || val === undefined || val === "") return null;
  try {
    return BigInt(Math.round(Number(val))).toString();
  } catch {
    return null;
  }
}

async function getLineageContext(extractDir: string): Promise<LineageContext> {
  const lineageFile = `${extractDir}/lineage.json`;
  const file = Bun.file(lineageFile);
  if (await file.exists()) {
    return await file.json();
  }
  throw new Error(`Lineage file not found: ${lineageFile}`);
}

async function upsertBatch<T extends Record<string, unknown>>(
  schema: string,
  table: string,
  rows: T[],
  conflictColumns: string[]
): Promise<UpsertResult> {
  const fullTable = `${schema}.${table}`;
  if (rows.length === 0) {
    return { table: fullTable, attempted: 0, success: true };
  }

  try {
    const allColumns = Object.keys(rows[0]);
    const updateColumns = allColumns.filter(col => !conflictColumns.includes(col));
    const setClauses = updateColumns.map(col => `${col} = EXCLUDED.${col}`).join(", ");
    const conflictTarget = conflictColumns.join(", ");

    const query = `
      INSERT INTO ${fullTable} (${allColumns.join(", ")})
      SELECT * FROM jsonb_populate_recordset(null::${fullTable}, $1::jsonb)
      ON CONFLICT (${conflictTarget}) DO UPDATE SET ${setClauses}
      WHERE ${fullTable}.source_hash IS DISTINCT FROM EXCLUDED.source_hash
    `;

    await sql.unsafe(query, [JSON.stringify(rows)]);
    return { table: fullTable, attempted: rows.length, success: true };
  } catch (error) {
    const msg = error instanceof Error ? error.message : String(error);
    return { table: fullTable, attempted: rows.length, success: false, error: msg };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Transformers
// ─────────────────────────────────────────────────────────────────────────────

function transformPerson(p: any, provenance: any) {
  return {
    person_id: safeNum(p.playerId),
    first_name: p.firstName,
    last_name: p.lastName,
    middle_name: p.middleName,
    display_first_name: p.displayFirstName,
    display_last_name: p.displayLastName,
    roster_first_name: p.rosterFirstName,
    roster_last_name: p.rosterLastName,
    birth_date: p.birthDate,
    birth_country_lk: p.birthCountryLk,
    gender: p.gender,
    height: safeNum(p.height),
    weight: safeNum(p.weight),
    person_type_lk: p.personTypeLk,
    player_status_lk: p.playerStatusLk,
    record_status_lk: p.recordStatusLk,
    league_lk: p.leagueLk,
    team_id: safeNum(p.teamId),
    school_id: safeNum(p.schoolId),
    draft_year: safeNum(p.draftYear),
    draft_round: safeNum(p.draftRound),
    draft_pick: safeNum(p.draftPick),
    years_of_service: safeNum(p.yearsOfService),
    service_years_json: p.playerServiceYears?.playerServiceYear 
      ? JSON.stringify(p.playerServiceYears.playerServiceYear) 
      : null,
    created_at: p.createDate,
    updated_at: p.lastChangeDate,
    record_changed_at: p.recordChangeDate,
    poison_pill_amt: safeBigInt(p.poisonPillAmt),
    is_two_way: safeBool(p.twoWayFlg),
    is_flex: safeBool(p.flexFlg),
    ...provenance,
  };
}

function transformTeam(t: any, provenance: any) {
  return {
    team_id: safeNum(t.teamId),
    team_name: t.teamName,
    team_name_short: t.teamNameShort,
    team_nickname: t.teamNickname,
    city: t.city,
    state_lk: t.stateLk,
    country_lk: t.countryLk,
    division_name: t.divisionName,
    league_lk: t.leagueLk,
    is_active: safeBool(t.activeFlg),
    record_status_lk: t.recordStatusLk,
    first_game_date: t.firstGameDate,
    created_at: t.createDate,
    updated_at: t.lastChangeDate,
    record_changed_at: t.recordChangeDate,
    ...provenance,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Main
// ─────────────────────────────────────────────────────────────────────────────

export async function main(
  dry_run = false,
  lineage_id?: number,
  s3_key?: string,
  extract_dir: string = SHARED_DIR
) {
  const startedAt = new Date().toISOString();
  const tables: UpsertResult[] = [];
  const errors: string[] = [];

  try {
    // Find the actual extract directory
    const entries = await readdir(extract_dir, { withFileTypes: true });
    const subDir = entries.find(e => e.isDirectory());
    const baseDir = subDir ? `${extract_dir}/${subDir.name}` : extract_dir;

    // Get lineage context
    const ctx = await getLineageContext(baseDir);
    const effectiveLineageId = lineage_id ?? ctx.lineage_id;
    const effectiveS3Key = s3_key ?? ctx.s3_key;

    // Find JSON files for players
    const allFiles = await readdir(baseDir);
    const playerJsonFile = allFiles.find(f => f.includes("player") && f.endsWith(".json"));

    if (!playerJsonFile) {
      throw new Error(`No player JSON file found in ${baseDir}`);
    }

    // Read pre-parsed JSON
    console.log(`Reading ${playerJsonFile}...`);
    const data = await Bun.file(`${baseDir}/${playerJsonFile}`).json();

    // Extract players array (handle various XML structures)
    const root = data.players || data.root || data;
    const players: any[] = root.player || [];
    const teams: any[] = root.lkTeam || [];

    console.log(`Found ${players.length} players, ${teams.length} teams`);

    // Build provenance
    const provenance = {
      source_drop_file: effectiveS3Key,
      parser_version: PARSER_VERSION,
      ingested_at: new Date(),
    };

    // Transform and upsert people
    const BATCH_SIZE = 500;
    for (let i = 0; i < players.length; i += BATCH_SIZE) {
      const batch = players.slice(i, i + BATCH_SIZE);
      const rows = batch.map(p => ({
        ...transformPerson(p, provenance),
        source_hash: hash(JSON.stringify(p)),
      }));

      if (!dry_run) {
        const result = await upsertBatch("pcms", "people", rows, ["person_id"]);
        tables.push(result);
        if (!result.success) errors.push(result.error!);
      } else {
        tables.push({ table: "pcms.people", attempted: rows.length, success: true });
      }
    }

    // Transform and upsert teams
    if (teams.length > 0) {
      const teamRows = teams.map(t => ({
        ...transformTeam(t, provenance),
        source_hash: hash(JSON.stringify(t)),
      }));

      if (!dry_run) {
        const result = await upsertBatch("pcms", "teams", teamRows, ["team_id"]);
        tables.push(result);
        if (!result.success) errors.push(result.error!);
      } else {
        tables.push({ table: "pcms.teams", attempted: teamRows.length, success: true });
      }
    }

    return {
      dry_run,
      started_at: startedAt,
      finished_at: new Date().toISOString(),
      tables,
      errors,
    };
  } catch (e: any) {
    errors.push(e.message);
    return {
      dry_run,
      started_at: startedAt,
      finished_at: new Date().toISOString(),
      tables,
      errors,
    };
  }
}
