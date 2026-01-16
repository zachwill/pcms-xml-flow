/**
 * Lookups Import
 *
 * Reads pre-parsed JSON from the shared extract dir (created by lineage step),
 * then normalizes many lookup sub-tables into a single table:
 * - pcms.lookups
 *
 * Source: *_lookup.json
 * Path: data["xml-extract"]["lookups-extract"]
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

function isPlainObject(val: unknown): val is Record<string, unknown> {
  return !!val && typeof val === "object" && !Array.isArray(val);
}

function firstMatchingKey(obj: Record<string, unknown>, predicate: (k: string) => boolean): string | null {
  for (const k of Object.keys(obj)) {
    if (predicate(k)) return k;
  }
  return null;
}

function inferLookupCode(record: Record<string, unknown>): { key: string | null; value: string | null } {
  // Most PCMS lookup records have an "...Lk" field (e.g., contractTypeLk).
  const lkKey = firstMatchingKey(record, (k) => k.endsWith("Lk"));
  if (lkKey) return { key: lkKey, value: safeStr(record[lkKey]) };

  // Some lookup records are "...Id" based (e.g., agencyId, schoolId).
  const idKey = firstMatchingKey(record, (k) => k.endsWith("Id"));
  if (idKey) return { key: idKey, value: safeStr(record[idKey]) };

  // Fallbacks for non-standard codes.
  const codeKey = firstMatchingKey(record, (k) => k === "code" || k.endsWith("Code") || k.endsWith("Cd"));
  if (codeKey) return { key: codeKey, value: safeStr(record[codeKey]) };

  return { key: null, value: null };
}

function inferDescription(record: Record<string, unknown>): { description: string | null; short_description: string | null } {
  const description =
    safeStr(record.description) ??
    safeStr(record.name) ??
    safeStr(record.agencyName) ??
    safeStr(record.teamName) ??
    safeStr(record.schoolName) ??
    (() => {
      const nameKey = firstMatchingKey(record, (k) => /Name$/.test(k));
      return nameKey ? safeStr(record[nameKey]) : null;
    })();

  const short_description =
    safeStr(record.shortDescription) ??
    safeStr(record.short_description) ??
    safeStr(record.abbreviation) ??
    (() => {
      const shortKey = firstMatchingKey(record, (k) => /Short(Name|Description)$/.test(k));
      return shortKey ? safeStr(record[shortKey]) : null;
    })();

  return { description, short_description };
}

// ─────────────────────────────────────────────────────────────────────────────
// Transformers
// ─────────────────────────────────────────────────────────────────────────────

function transformLookup(lookupType: string, record: unknown, provenance: Record<string, unknown>) {
  const rec = nilSafe(record);
  if (!isPlainObject(rec)) return null;

  const { key: codeKey, value: lookup_code } = inferLookupCode(rec);
  if (!lookup_code) return null;

  const { description, short_description } = inferDescription(rec);

  const excludeKeys = new Set<string>([
    "description",
    "shortDescription",
    "short_description",
    "activeFlg",
    "seqno",
    "createDate",
    "lastChangeDate",
    "recordChangeDate",
  ]);
  if (codeKey) excludeKeys.add(codeKey);

  const properties: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(rec)) {
    if (excludeKeys.has(k)) continue;
    if (k.startsWith("@_")) continue;
    properties[k] = nilSafe(v);
  }

  return {
    lookup_type: lookupType,
    lookup_code,
    description,
    short_description,
    is_active: safeBool(rec.activeFlg),
    seqno: safeNum(rec.seqno),
    properties_json: Object.keys(properties).length > 0 ? JSON.stringify(properties) : null,
    created_at: safeStr(rec.createDate),
    updated_at: safeStr(rec.lastChangeDate),
    record_changed_at: safeStr(rec.recordChangeDate),
    ...provenance,
  };
}

function extractLookupRecords(container: unknown): any[] {
  const c = nilSafe(container);
  if (c === null || c === undefined) return [];

  // Some lookups might be represented directly as arrays.
  if (Array.isArray(c)) return c;

  // Most are objects like { lkContractType: [...] }
  if (isPlainObject(c)) {
    const out: any[] = [];
    for (const [k, v] of Object.entries(c)) {
      if (k.startsWith("@_")) continue;
      out.push(...asArray(v));
    }
    return out;
  }

  return [];
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
    void effectiveLineageId; // lineage_id is not stored on these tables, but available for debugging

    // Find JSON file
    const allFiles = await readdir(baseDir);
    const lookupJsonFile = allFiles.find((f) => f.includes("lookup") && f.endsWith(".json"));
    if (!lookupJsonFile) {
      throw new Error(`No lookup JSON file found in ${baseDir}`);
    }

    // Read pre-parsed JSON
    console.log(`Reading ${lookupJsonFile}...`);
    const data = await Bun.file(`${baseDir}/${lookupJsonFile}`).json();

    const lookupsExtract = data?.["xml-extract"]?.["lookups-extract"];
    if (!lookupsExtract || typeof lookupsExtract !== "object") {
      throw new Error("Invalid lookups JSON: missing data[\"xml-extract\"][\"lookups-extract\"]");
    }

    // Build provenance
    const provenance = {
      source_drop_file: effectiveS3Key,
      parser_version: PARSER_VERSION,
      ingested_at: new Date(),
    };

    // Each key under lookups-extract is a lookup-type group.
    const lookupGroups = lookupsExtract as Record<string, unknown>;

    const BATCH_SIZE = 500;
    for (const [lookupType, container] of Object.entries(lookupGroups)) {
      if (lookupType.startsWith("@_")) continue;

      const records = extractLookupRecords(container);
      if (records.length === 0) continue;

      // Transform and upsert in batches for this lookup type
      for (let i = 0; i < records.length; i += BATCH_SIZE) {
        const batch = records.slice(i, i + BATCH_SIZE);
        const rows = batch
          .map((r) => {
            const transformed = transformLookup(lookupType, r, provenance);
            if (!transformed) return null;
            return {
              ...transformed,
              source_hash: hash(JSON.stringify(r)),
            };
          })
          .filter(Boolean) as Record<string, unknown>[];

        if (rows.length === 0) continue;

        if (!dry_run) {
          const result = await upsertBatch("pcms", "lookups", rows, ["lookup_type", "lookup_code"]);
          tables.push(result);
          if (!result.success) errors.push(result.error!);
        } else {
          tables.push({ table: "pcms.lookups", attempted: rows.length, success: true });
        }
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
    errors.push(e?.message ?? String(e));
    return {
      dry_run,
      started_at: startedAt,
      finished_at: new Date().toISOString(),
      tables,
      errors,
    };
  }
}
