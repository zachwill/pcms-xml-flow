/**
 * Lookups Import
 *
 * Reads clean JSON from lineage step and normalizes the 43 lookup sub-tables into:
 * - pcms.lookups
 *
 * Clean JSON notes:
 * - snake_case keys
 * - proper nulls
 * - no XML wrapper nesting (but lookups.json is still grouped by lookup type)
 */
import { SQL } from "bun";
import { readdir } from "node:fs/promises";

const sql = new SQL({ url: Bun.env.POSTGRES_URL!, prepare: false });

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

function asArray<T = any>(val: any): T[] {
  if (val === null || val === undefined) return [];
  return Array.isArray(val) ? val : [val];
}

function isPlainObject(val: unknown): val is Record<string, any> {
  return !!val && typeof val === "object" && !Array.isArray(val);
}

function firstMatchingKey(obj: Record<string, any>, predicate: (k: string) => boolean): string | null {
  for (const k of Object.keys(obj)) {
    if (predicate(k)) return k;
  }
  return null;
}

function inferLookupCode(record: Record<string, any>): { code_key: string | null; lookup_code: string | null } {
  // Most lookup records have a single "*_lk" field that represents the code.
  const lkKey = firstMatchingKey(
    record,
    (k) => k.endsWith("_lk") && k !== "record_status_lk" && k !== "league_lk"
  );
  if (lkKey) {
    const v = record[lkKey];
    if (v !== null && v !== undefined && v !== "") return { code_key: lkKey, lookup_code: String(v) };
  }

  // Some lookups are "*_id" based (e.g., agencies, schools).
  const idKey = firstMatchingKey(record, (k) => k.endsWith("_id"));
  if (idKey) {
    const v = record[idKey];
    if (v !== null && v !== undefined && v !== "") return { code_key: idKey, lookup_code: String(v) };
  }

  // Fallbacks for non-standard codes.
  const codeKey = firstMatchingKey(record, (k) => k === "code" || k.endsWith("_code") || k.endsWith("_cd"));
  if (codeKey) {
    const v = record[codeKey];
    if (v !== null && v !== undefined && v !== "") return { code_key: codeKey, lookup_code: String(v) };
  }

  return { code_key: null, lookup_code: null };
}

function inferDescription(record: Record<string, any>): { description: string | null; short_description: string | null } {
  const description =
    (record.description ??
      record.name ??
      record.agency_name ??
      record.team_name ??
      record.school_name ??
      null) as string | null;

  const short_description =
    (record.short_description ?? record.abbreviation ?? record.team_name_short ?? null) as string | null;

  return {
    description: description ?? null,
    short_description: short_description ?? null,
  };
}

function transformLookup(lookupType: string, record: unknown, provenance: Record<string, any>) {
  if (!isPlainObject(record)) return null;

  const { code_key, lookup_code } = inferLookupCode(record);
  if (!lookup_code) return null;

  const { description, short_description } = inferDescription(record);

  const excludeKeys = new Set<string>([
    "description",
    "short_description",
    "abbreviation",
    "name",
    "active_flg",
    "seqno",
    "create_date",
    "last_change_date",
    "record_change_date",
  ]);
  if (code_key) excludeKeys.add(code_key);

  const properties: Record<string, any> = {};
  for (const [k, v] of Object.entries(record)) {
    if (excludeKeys.has(k)) continue;
    properties[k] = v;
  }

  return {
    lookup_type: lookupType,
    lookup_code,
    description,
    short_description,
    is_active: record.active_flg ?? null,
    seqno: record.seqno ?? null,
    properties_json: Object.keys(properties).length > 0 ? properties : null,
    created_at: record.create_date ?? null,
    updated_at: record.last_change_date ?? null,
    record_changed_at: record.record_change_date ?? null,
    ...provenance,
  };
}

function extractRecords(container: unknown): any[] {
  if (container === null || container === undefined) return [];

  if (Array.isArray(container)) return container;

  if (isPlainObject(container)) {
    // Most groups look like: { lk_agency: [...] }
    const out: any[] = [];
    for (const v of Object.values(container)) out.push(...asArray(v));
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
  extract_dir = "./shared/pcms"
) {
  const startedAt = new Date().toISOString();
  void lineage_id;

  try {
    // Find extract directory
    const entries = await readdir(extract_dir, { withFileTypes: true });
    const subDir = entries.find((e) => e.isDirectory());
    const baseDir = subDir ? `${extract_dir}/${subDir.name}` : extract_dir;

    // Read clean JSON (grouped by lookup type)
    const lookupGroups: Record<string, any> = await Bun.file(`${baseDir}/lookups.json`).json();
    console.log(`Found ${Object.keys(lookupGroups).length} lookup groups`);

    const ingestedAt = new Date();
    const provenance = {
      source_drop_file: s3_key,
      ingested_at: ingestedAt,
    };

    const BATCH_SIZE = 1000;
    let attempted = 0;

    for (const [lookupType, container] of Object.entries(lookupGroups)) {
      const records = extractRecords(container);
      if (records.length === 0) continue;

      const transformed = records
        .map((r) => transformLookup(lookupType, r, provenance))
        .filter(Boolean) as Record<string, any>[];

      if (transformed.length === 0) continue;

      attempted += transformed.length;

      if (dry_run) continue;

      for (let i = 0; i < transformed.length; i += BATCH_SIZE) {
        const batch = transformed.slice(i, i + BATCH_SIZE);

        await sql`
          INSERT INTO pcms.lookups ${sql(batch)}
          ON CONFLICT (lookup_type, lookup_code) DO UPDATE SET
            description = EXCLUDED.description,
            short_description = EXCLUDED.short_description,
            is_active = EXCLUDED.is_active,
            seqno = EXCLUDED.seqno,
            properties_json = EXCLUDED.properties_json,
            updated_at = EXCLUDED.updated_at,
            record_changed_at = EXCLUDED.record_changed_at,
            source_drop_file = EXCLUDED.source_drop_file,
            ingested_at = EXCLUDED.ingested_at
        `;
      }
    }

    return {
      dry_run,
      started_at: startedAt,
      finished_at: new Date().toISOString(),
      tables: [{ table: "pcms.lookups", attempted, success: true }],
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
