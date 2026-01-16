/**
 * Team Exceptions & Usage Import
 *
 * Reads pre-parsed JSON from shared extract dir (created by lineage step), then
 * upserts into:
 * - pcms.team_exceptions
 * - pcms.team_exception_usage
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
// Helpers (inline)
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

function safeBigInt(val: unknown): string | null {
  const v = nilSafe(val);
  if (v === null || v === undefined || v === "") return null;
  if (typeof v === "object") return null;
  try {
    return BigInt(Math.round(Number(v))).toString();
  } catch {
    return null;
  }
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

function transformTeamException(te: any, teamId: unknown, provenance: any) {
  return {
    team_exception_id: safeNum(te.teamExceptionId),
    team_id: safeNum(teamId),
    salary_year: safeNum(te.teamExceptionYear),
    exception_type_lk: safeStr(te.exceptionTypeLk),
    effective_date: safeStr(te.effectiveDate),
    expiration_date: safeStr(te.expirationDate),
    original_amount: safeBigInt(te.originalAmount),
    remaining_amount: safeBigInt(te.remainingAmount),
    proration_rate: safeNum(te.prorationRate),
    is_initially_convertible: safeBool(te.initiallyConvertibleFlg),
    trade_exception_player_id: safeNum(te.tradeExceptionPlayerId),
    trade_id: safeNum(te.tradeId),
    record_status_lk: safeStr(te.recordStatusLk),
    created_at: safeStr(te.createDate),
    updated_at: safeStr(te.lastChangeDate),
    record_changed_at: safeStr(te.recordChangeDate),
    ...provenance,
  };
}

function transformTeamExceptionUsage(ed: any, teamExceptionId: number, provenance: any) {
  return {
    team_exception_detail_id: safeNum(ed.teamExceptionDetailId),
    team_exception_id: teamExceptionId,
    seqno: safeNum(ed.seqno),
    effective_date: safeStr(ed.effectiveDate),
    exception_action_lk: safeStr(ed.exceptionActionLk),
    transaction_type_lk: safeStr((ed as any).transaction_type_lk ?? ed.transactionTypeLk),
    transaction_id: safeNum(ed.transactionId),
    player_id: safeNum(ed.playerId),
    contract_id: safeNum(ed.contractId),
    change_amount: safeBigInt(ed.changeAmount),
    remaining_exception_amount: safeBigInt(ed.remainingExceptionAmount),
    proration_rate: safeNum(ed.prorationRate),
    prorate_days: safeNum(ed.prorateDays),
    is_convert_exception: safeBool(ed.convertExceptionFlg),
    manual_action_text: safeStr(ed.manualActionText),
    created_at: safeStr(ed.createDate),
    updated_at: safeStr(ed.lastChangeDate),
    record_changed_at: safeStr(ed.recordChangeDate),
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
    const subDir = entries.find((e) => e.isDirectory());
    const baseDir = subDir ? `${extract_dir}/${subDir.name}` : extract_dir;

    // Get lineage context
    const ctx = await getLineageContext(baseDir);
    const effectiveLineageId = lineage_id ?? ctx.lineage_id;
    const effectiveS3Key = s3_key ?? ctx.s3_key;

    void effectiveLineageId; // lineage_id currently only used for debug/provenance expansion

    // Find JSON file
    const files = await readdir(baseDir);
    const jsonFile = files.find((f) => f.includes("team-exception") && f.endsWith(".json"));
    if (!jsonFile) {
      throw new Error(`No team-exception JSON file found in ${baseDir}`);
    }

    console.log(`Reading ${jsonFile}...`);
    const data = await Bun.file(`${baseDir}/${jsonFile}`).json();

    // Extract exceptionTeams
    const exceptionTeams: any[] =
      data?.["xml-extract"]?.["team-exception-extract"]?.exceptionTeams?.exceptionTeam ?? [];

    const exceptions: any[] = [];
    const usages: any[] = [];

    const provenanceBase = {
      source_drop_file: effectiveS3Key,
      parser_version: PARSER_VERSION,
      ingested_at: new Date(),
    };

    for (const et of exceptionTeams) {
      const teamId = et?.teamId;

      // NOTE: tags are hyphenated in this extract
      const teamExceptions = asArray(et?.["team-exceptions"]?.["team-exception"]);
      for (const te of teamExceptions) {
        const teId = safeNum(te?.teamExceptionId);
        if (!teId) continue;

        const exceptionProv = {
          ...provenanceBase,
          source_hash: hash(JSON.stringify({ teamId, ...te })),
        };

        exceptions.push(transformTeamException(te, teamId, exceptionProv));

        const details = asArray(te?.exceptionDetails?.exceptionDetail);
        for (const ed of details) {
          usages.push({
            ...transformTeamExceptionUsage(ed, teId, {
              ...provenanceBase,
              source_hash: hash(JSON.stringify({ teamExceptionId: teId, ...ed })),
            }),
          });
        }
      }
    }

    console.log(`Found ${exceptions.length} team exceptions, ${usages.length} usage rows`);

    const BATCH_SIZE = 500;

    // Upsert exceptions
    for (let i = 0; i < exceptions.length; i += BATCH_SIZE) {
      const batch = exceptions.slice(i, i + BATCH_SIZE);
      if (!dry_run) {
        const result = await upsertBatch("pcms", "team_exceptions", batch, ["team_exception_id"]);
        tables.push(result);
        if (!result.success) errors.push(result.error!);
      } else {
        tables.push({ table: "pcms.team_exceptions", attempted: batch.length, success: true });
      }
    }

    // Upsert usage
    for (let i = 0; i < usages.length; i += BATCH_SIZE) {
      const batch = usages.slice(i, i + BATCH_SIZE);
      if (!dry_run) {
        const result = await upsertBatch("pcms", "team_exception_usage", batch, [
          "team_exception_detail_id",
        ]);
        tables.push(result);
        if (!result.success) errors.push(result.error!);
      } else {
        tables.push({ table: "pcms.team_exception_usage", attempted: batch.length, success: true });
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
