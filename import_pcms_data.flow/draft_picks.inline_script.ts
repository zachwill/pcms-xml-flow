/**
 * Draft Picks Import
 *
 * Reads pre-parsed JSON from shared extract dir (created by lineage step), then
 * upserts into:
 * - pcms.draft_picks
 *
 * Source JSON: *_dp-extract.json
 * Path:
 *   data["xml-extract"]["dp-extract"]["draftPick"]
 *
 * Optional enrichment (if present in extract dir): *_dps*.json
 * Path:
 *   data["xml-extract"]["dps-extract"]["draft-pick-summary"]
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

function nilSafe(val: unknown): unknown {
  if (val && typeof val === "object" && "@_xsi:nil" in val) return null;
  return val;
}

function safeNum(val: unknown): number | null {
  const v = nilSafe(val);
  if (v === null || v === undefined || v === "") return null;
  if (typeof v === "object") return null;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

function safeStr(val: unknown): string | null {
  const v = nilSafe(val);
  if (v === null || v === undefined || v === "") return null;
  if (typeof v === "object") return null;
  return String(v);
}

function safeBool(val: unknown): boolean | null {
  const v = nilSafe(val);
  if (v === null || v === undefined) return null;
  if (typeof v === "boolean") return v;
  if (v === 1 || v === "1" || v === "Y" || v === "true" || v === true) return true;
  if (v === 0 || v === "0" || v === "N" || v === "false" || v === false) return false;
  return null;
}

function parsePCMSDate(val: unknown): string | null {
  const v = safeStr(val);
  if (!v || v === "0001-01-01") return null;
  return !isNaN(Date.parse(v)) ? v : null;
}

function asArray<T = any>(val: unknown): T[] {
  const v = nilSafe(val);
  if (v === null || v === undefined) return [];
  return Array.isArray(v) ? (v as T[]) : ([v] as T[]);
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
    const updateColumns = allColumns.filter((col) => !conflictColumns.includes(col));
    const setClauses = updateColumns.map((col) => `${col} = EXCLUDED.${col}`).join(", ");
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

function transformDraftPick(dp: any, summary: any | null, provenance: any) {
  const draftYear = safeNum(dp?.year ?? dp?.draftYear);
  const pick = safeStr(dp?.pick);

  // histories can be an object or an array depending on record
  const histories = asArray<any>(dp?.histories);

  return {
    draft_pick_id: safeNum(dp?.draftPickId),
    draft_year: draftYear,
    round: safeNum(dp?.round),
    pick_number: pick,
    pick_number_int: safeNum(dp?.pick),

    league_lk: safeStr(dp?.leagueLk) ?? "NBA",
    original_team_id: safeNum(dp?.originalTeamId),
    current_team_id: safeNum(dp?.teamId),

    is_active: safeBool(dp?.activeFlg),

    // Not always present in dp-extract; keep null unless fields exist
    is_protected: safeBool(dp?.protectedFlg ?? dp?.protectionFlg),
    protection_description: safeStr(dp?.protectionDescription ?? dp?.protectionText),

    is_swap: safeBool(dp?.draftPickSwapFlg ?? dp?.swapFlg),
    swap_type_lk: safeStr(dp?.swapTypeLk),

    conveyance_year_range: safeStr(dp?.conveyanceYearRange ?? dp?.conveyanceYears),
    conveyance_trigger_description: safeStr(
      dp?.conveyanceTriggerDescription ?? dp?.conveyanceTriggerDesc ?? dp?.conveyanceDescription
    ),

    // Optional enrichment from dps-extract (team/year summary)
    first_round_summary: safeStr(summary?.firstRound),
    second_round_summary: safeStr(summary?.secondRound),

    history_json: histories.length > 0 ? histories : null,
    draft_json: dp ?? null,
    summary_json: summary ?? null,

    source_drop_file: provenance.source_drop_file,
    source_hash: provenance.source_hash,
    parser_version: provenance.parser_version,

    created_at: parsePCMSDate(dp?.createDate),
    updated_at: parsePCMSDate(dp?.lastChangeDate),
    record_changed_at: parsePCMSDate(dp?.recordChangeDate),
    ingested_at: provenance.ingested_at,
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
    const subDir = entries.find((e) => e.isDirectory());
    const baseDir = subDir ? `${extract_dir}/${subDir.name}` : extract_dir;

    // Get lineage context
    const ctx = await getLineageContext(baseDir);
    const effectiveLineageId = lineage_id ?? ctx.lineage_id;
    const effectiveS3Key = s3_key ?? ctx.s3_key;
    void effectiveLineageId; // lineage_id is currently only used for consistency across scripts

    // Find JSON files
    const allFiles = await readdir(baseDir);
    const dpJsonFile = allFiles.find((f) => f.includes("dp-extract") && f.endsWith(".json"));

    if (!dpJsonFile) {
      throw new Error(`No dp-extract JSON file found in ${baseDir}`);
    }

    // Optional summary file (dps-extract)
    const dpsJsonFile = allFiles.find(
      (f) =>
        f.endsWith(".json") &&
        !f.includes("dp-extract") &&
        (f.includes("dps-extract") || f.includes("_dps") || f.endsWith("dps.json"))
    );

    console.log(`Reading ${dpJsonFile}...`);
    const dpData = await Bun.file(`${baseDir}/${dpJsonFile}`).json();

    const draftPicks = asArray<any>(dpData?.["xml-extract"]?.["dp-extract"]?.draftPick);
    console.log(`Found ${draftPicks.length} draft picks`);

    // Build optional summary map
    const summaryMap = new Map<string, any>();
    if (dpsJsonFile) {
      console.log(`Reading ${dpsJsonFile} (optional enrichment)...`);
      const dpsData = await Bun.file(`${baseDir}/${dpsJsonFile}`).json();
      const summaries = asArray<any>(dpsData?.["xml-extract"]?.["dps-extract"]?.["draft-pick-summary"]);

      for (const s of summaries) {
        const key = `${safeNum(s?.teamId)}-${safeNum(s?.draftYear)}`;
        summaryMap.set(key, s);
      }

      console.log(`Loaded ${summaries.length} team/year draft pick summaries`);
    }

    const provenanceBase = {
      source_drop_file: effectiveS3Key,
      parser_version: PARSER_VERSION,
      ingested_at: new Date(),
    };

    const BATCH_SIZE = 500;

    for (let i = 0; i < draftPicks.length; i += BATCH_SIZE) {
      const batch = draftPicks.slice(i, i + BATCH_SIZE);

      const rows = batch.map((dp) => {
        const teamId = safeNum(dp?.teamId);
        const year = safeNum(dp?.year ?? dp?.draftYear);
        const summaryKey = `${teamId}-${year}`;
        const summary = summaryMap.get(summaryKey) ?? null;

        // Hash includes both dp record + (optional) summary record
        const sourceHash = hash(
          JSON.stringify({
            dp,
            summary,
          })
        );

        return transformDraftPick(dp, summary, {
          ...provenanceBase,
          source_hash: sourceHash,
        });
      });

      if (!dry_run) {
        const result = await upsertBatch("pcms", "draft_picks", rows, ["draft_pick_id"]);
        tables.push(result);
        if (!result.success) errors.push(result.error!);
      } else {
        tables.push({ table: "pcms.draft_picks", attempted: rows.length, success: true });
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
