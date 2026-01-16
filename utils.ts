/**
 * Shared utilities for Ralph data import flows.
 * 
 * Usage in flow scripts:
 *   import { hash, upsertBatch, withProvenance, createFetcher } from "/f/ralph/utils.ts";
 */

import { SQL } from "bun";
import { XMLParser } from "fast-xml-parser";
import { existsSync, readFileSync } from "fs";
import * as wmill from "windmill-client";
import type { S3Object } from "windmill-client";

// ─────────────────────────────────────────────────────────────────────────────
// Types
// ─────────────────────────────────────────────────────────────────────────────

export interface Provenance {
  source_api: string;
  source_endpoint: string;
  fetched_at: Date;
  source_hash: string;
}

export interface UpsertResult {
  table: string;
  attempted: number;
  success: boolean;
  error?: string;
  rows?: any[];
}

export interface FetchResult<T> {
  data: T;
  raw: string;
  provenance: Provenance;
}

export interface ImportSummary {
  dry_run: boolean;
  started_at: string;
  finished_at: string;
  tables: UpsertResult[];
  errors: string[];
}

// ─────────────────────────────────────────────────────────────────────────────
// Hashing
// ─────────────────────────────────────────────────────────────────────────────

export function hash(data: string): string {
  return new Bun.CryptoHasher("sha256").update(data).digest("hex");
}

export async function hashStream(stream: ReadableStream<Uint8Array>): Promise<string> {
  const hasher = new Bun.CryptoHasher("sha256");
  for await (const chunk of stream) {
    hasher.update(chunk);
  }
  return hasher.digest("hex");
}

// ─────────────────────────────────────────────────────────────────────────────
// Provenance
// ─────────────────────────────────────────────────────────────────────────────

export function withProvenance<T extends Record<string, unknown>>(
  rows: T[],
  provenance: Provenance
): (T & Provenance)[] {
  return rows.map((row) => ({ ...row, ...provenance }));
}

export function makeProvenance(
  sourceApi: string,
  endpoint: string,
  rawBody: string
): Provenance {
  return {
    source_api: sourceApi,
    source_endpoint: endpoint,
    fetched_at: new Date(),
    source_hash: hash(rawBody),
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Database Operations
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Resilient batch upsert with hash-based change detection.
 * Returns result object instead of throwing on error.
 */
export async function upsertBatch<T extends Record<string, unknown>>(
  sql: SQL,
  schema: string,
  table: string,
  rows: T[],
  conflictColumns: string[],
  options: { hashColumn?: string; skipUnchanged?: boolean } = {}
): Promise<UpsertResult> {
  const { hashColumn = "source_hash", skipUnchanged = true } = options;
  const fullTable = `${schema}.${table}`;

  if (rows.length === 0) {
    return { table: fullTable, attempted: 0, success: true };
  }

  try {
    // Build column lists
    const allColumns = Object.keys(rows[0]);
    const updateColumns = allColumns.filter(
      (col) => !conflictColumns.includes(col)
    );

    // Build the SET clause dynamically
    const setClauses = updateColumns
      .map((col) => `${col} = EXCLUDED.${col}`)
      .join(", ");

    // Build conflict target
    const conflictTarget = conflictColumns.join(", ");

    // Build WHERE clause for hash-based skip
    const whereClause = skipUnchanged && allColumns.includes(hashColumn)
      ? `WHERE ${fullTable}.${hashColumn} IS DISTINCT FROM EXCLUDED.${hashColumn}`
      : "";

    // Execute upsert using tagged template
    const query = `
      INSERT INTO ${fullTable} (${allColumns.join(", ")})
      SELECT * FROM jsonb_populate_recordset(null::${fullTable}, $1::jsonb)
      ON CONFLICT (${conflictTarget}) DO UPDATE SET ${setClauses}
      ${whereClause}
      RETURNING *
    `;

    const resultRows = await sql.unsafe(query, [JSON.stringify(rows)]);

    return { table: fullTable, attempted: rows.length, success: true, rows: resultRows };
  } catch (error) {
    const msg = error instanceof Error ? error.message : String(error);
    return { table: fullTable, attempted: rows.length, success: false, error: msg };
  }
}

/**
 * Simple insert for append-only tables (logs, events).
 */
export async function insertBatch<T extends Record<string, unknown>>(
  sql: SQL,
  schema: string,
  table: string,
  rows: T[]
): Promise<UpsertResult> {
  const fullTable = `${schema}.${table}`;

  if (rows.length === 0) {
    return { table: fullTable, attempted: 0, success: true };
  }

  try {
    await sql`INSERT INTO ${sql(fullTable)} ${sql(rows)}`;
    return { table: fullTable, attempted: rows.length, success: true };
  } catch (error) {
    const msg = error instanceof Error ? error.message : String(error);
    return { table: fullTable, attempted: rows.length, success: false, error: msg };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HTTP Fetching with Rate Limiting
// ─────────────────────────────────────────────────────────────────────────────

interface FetcherConfig {
  baseUrl: string;
  sourceApi: string;
  headers?: Record<string, string>;
  qps?: number;
  retries?: number;
  timeoutMs?: number;
  params?: Record<string, string>;
}

interface Fetcher {
  get: <T = unknown>(endpoint: string, params?: Record<string, string>) => Promise<FetchResult<T>>;
}

/**
 * Creates a rate-limited fetcher with retry logic.
 */
export function createFetcher(config: FetcherConfig): Fetcher {
  const {
    baseUrl,
    sourceApi,
    headers = {},
    qps = 2,
    retries = 3,
    timeoutMs = 30000,
    params = {},
  } = config as any;

  const minInterval = 1000 / qps;
  let lastRequest = 0;

  async function rateLimitedFetch<T>(
    endpoint: string,
    params?: Record<string, string>
  ): Promise<FetchResult<T>> {
    const sql = new SQL({ url: Bun.env.POSTGRES_URL!, prepare: false });

    // Rate limiting
    const now = Date.now();
    const elapsed = now - lastRequest;
    if (elapsed < minInterval) {
      await Bun.sleep(minInterval - elapsed);
    }
    lastRequest = Date.now();

    // Build URL
    const url = new URL(endpoint, baseUrl);
    if (params) {
      Object.entries(params).forEach(([k, v]) => url.searchParams.set(k, v));
    }

    // Fetch with retries
    let lastError: Error | null = null;
    for (let attempt = 1; attempt <= retries; attempt++) {
      try {
        const response = await fetch(url.toString(), {
          headers: {
            Accept: "application/json",
            "User-Agent": "Mozilla/5.0 (compatible; RalphBot/1.0)",
            ...headers,
          },
          signal: AbortSignal.timeout(timeoutMs),
        });

        if (!response.ok) {
          if (response.status >= 500 || response.status === 429) {
            // Retryable errors
            await Bun.sleep(1000 * attempt);
            continue;
          }
          throw new Error(`HTTP ${response.status}: ${response.statusText}`);
        }

        const raw = await response.text();
        const data = JSON.parse(raw) as T;
        const provenance = makeProvenance(sourceApi, endpoint, raw);

        // Automated Infrastructure Logging
        try {
          await recordResponse(sql, {
            source_api: sourceApi,
            source_endpoint: endpoint,
            source_url: url.toString(),
            response_json: raw,
            source_hash: provenance.source_hash,
            status_code: response.status,
          });
        } catch (e) {
          console.error(`Failed to record response: ${e}`);
        }

        return {
          data,
          raw,
          provenance,
        };
      } catch (error) {
        lastError = error instanceof Error ? error : new Error(String(error));

        // Automated Infrastructure Logging for Errors
        try {
          await recordError(sql, {
            source_api: sourceApi,
            source_endpoint: endpoint,
            source_url: url.toString(),
            error_type: "api_fetch",
            error_message: lastError.message,
            stack_trace: lastError.stack,
          });
        } catch (e) {
          console.error(`Failed to record error: ${e}`);
        }

        if (attempt < retries) {
          await Bun.sleep(1000 * attempt);
        }
      }
    }

    throw lastError ?? new Error("Fetch failed");
  }

  return { get: rateLimitedFetch };
}

// ─────────────────────────────────────────────────────────────────────────────
// Infrastructure Logging Helpers (Automated)
// ─────────────────────────────────────────────────────────────────────────────

async function recordResponse(sql: SQL, params: any) {
  const { source_api, source_endpoint, source_url, response_json, source_hash, status_code, etag } = params;

  const row = {
    source_api,
    source_endpoint,
    source_url,
    response_json: typeof response_json === 'string' ? JSON.parse(response_json) : response_json,
    source_hash,
    status_code: status_code || 200,
    etag,
    fetched_at: new Date()
  };

  await upsertBatch(sql, "sr", "api_responses", [row], ["source_hash"]);
}

async function recordError(sql: SQL, params: any) {
  const { source_api, source_endpoint, source_url, error_type, error_message, stack_trace, raw_payload, context } = params;

  const row = {
    source_api,
    source_endpoint,
    source_url,
    error_type,
    error_message,
    stack_trace,
    raw_payload: typeof raw_payload === 'string' ? JSON.parse(raw_payload) : raw_payload,
    context: typeof context === 'string' ? JSON.parse(context) : context,
    occurred_at: new Date()
  };

  await insertBatch(sql, "sr", "ingestion_errors", [row]);
}

// ─────────────────────────────────────────────────────────────────────────────
// S3 Operations (for PCMS) — uses windmill-client
// ─────────────────────────────────────────────────────────────────────────────

export interface S3FileInfo {
  key: string;
  size?: number;
}

/**
 * Read an S3 file as text.
 * Uses windmill-client's S3 integration.
 */
export async function readS3Text(key: string): Promise<string> {
  const s3obj: S3Object = { s3: key };
  const response = await wmill.loadS3File(s3obj);
  return await response.text();
}

/**
 * Read an S3 file as bytes.
 */
export async function readS3Bytes(key: string): Promise<Uint8Array> {
  const s3obj: S3Object = { s3: key };
  const response = await wmill.loadS3File(s3obj);
  return new Uint8Array(await response.arrayBuffer());
}

/**
 * Write content to S3.
 */
export async function writeS3(key: string, content: string | Blob): Promise<void> {
  const s3obj: S3Object = { s3: key };
  const blob = typeof content === "string" ? new Blob([content]) : content;
  await wmill.writeS3File(s3obj, blob);
}

/**
 * Get S3 file as a stream (for large files).
 * Returns the Response object which has .body as ReadableStream.
 */
export async function streamS3File(key: string): Promise<Response> {
  const s3obj: S3Object = { s3: key };
  return await wmill.loadS3File(s3obj);
}

// ─────────────────────────────────────────────────────────────────────────────
// PCMS Lineage Helpers
// ─────────────────────────────────────────────────────────────────────────────

export interface PCMSLineageContext {
  lineage_id: number;
  s3_key: string;
}

export async function resolvePCMSLineageContext(
  sql: SQL,
  opts: { lineageId?: number; s3Key?: string; sharedDir?: string } = {}
): Promise<PCMSLineageContext> {
  // Best case: flow wires these through from step `a`.
  if (opts.lineageId && opts.s3Key) {
    return { lineage_id: opts.lineageId, s3_key: opts.s3Key };
  }

  const sharedDir = opts.sharedDir ?? "./shared/pcms";
  const lineageFile = `${sharedDir}/lineage.json`;

  // Same-worker fallback.
  if (existsSync(lineageFile)) {
    const raw = readFileSync(lineageFile, "utf8");
    const parsed = JSON.parse(raw);
    if (parsed?.lineage_id && parsed?.s3_key) {
      return { lineage_id: Number(parsed.lineage_id), s3_key: String(parsed.s3_key) };
    }
  }

  // DB fallback: if s3_key was provided, restrict to it.
  if (opts.s3Key) {
    const pendingForKey = await sql`
      SELECT lineage_id, s3_key
      FROM pcms.pcms_lineage
      WHERE ingestion_status = 'PROCESSING'
        AND s3_key = ${opts.s3Key}
      ORDER BY ingested_at DESC
      LIMIT 1
    `;

    // If we're in a dry-run or running ad-hoc, we may not have created lineage.
    if (pendingForKey.length === 0) {
      return { lineage_id: opts.lineageId ?? 0, s3_key: opts.s3Key };
    }

    return pendingForKey[0];
  }

  // Final fallback: whatever is currently PROCESSING.
  const pending = await sql`
    SELECT lineage_id, s3_key
    FROM pcms.pcms_lineage
    WHERE ingestion_status = 'PROCESSING'
    ORDER BY ingested_at DESC
    LIMIT 1
  `;

  if (pending.length === 0) {
    throw new Error("No pending pcms.pcms_lineage entries found (ingestion_status='PROCESSING').");
  }

  return pending[0];
}

// ─────────────────────────────────────────────────────────────────────────────
// Streaming Parser
// ─────────────────────────────────────────────────────────────────────────────

export class PCMSStreamParser {
  private buffer = "";
  private decoder = new TextDecoder();
  private parser: XMLParser;
  private targetTag: string;
  private onEntity: (entity: any, rawXml: string) => Promise<void>;

  constructor(targetTag: string, onEntity: (entity: any, rawXml: string) => Promise<void>, isArray: (name: string) => boolean = () => false) {
    this.targetTag = targetTag;
    this.onEntity = onEntity;
    this.parser = createPCMSParser({ isArray });
  }

  async parseChunk(chunk: Uint8Array) {
    this.buffer += this.decoder.decode(chunk, { stream: true });

    const openPrefix = `<${this.targetTag}`;
    const closePrefix = `</${this.targetTag}`;

    // Keep enough tail for partially-read tags/attributes.
    const TAIL_KEEP = 64 * 1024;
    const MAX_BUFFER = 50 * 1024 * 1024;

    if (this.buffer.length > MAX_BUFFER) {
      throw new Error(
        `PCMSStreamParser buffer exceeded ${MAX_BUFFER} bytes while searching for <${this.targetTag}>. ` +
          `Input may be malformed, or the target tag does not exist in this document.`
      );
    }

    const isBoundary = (ch: string | undefined) => {
      if (!ch) return false;
      return ch === ">" || ch === "/" || /\s/.test(ch);
    };

    const findTagEnd = (fromIdx: number): number => {
      let inQuote = false;
      let quoteChar = "";
      for (let i = fromIdx + 1; i < this.buffer.length; i++) {
        const ch = this.buffer[i];
        if (inQuote) {
          if (ch === quoteChar) {
            inQuote = false;
            quoteChar = "";
          }
          continue;
        }

        if (ch === '"' || ch === "'") {
          inQuote = true;
          quoteChar = ch;
          continue;
        }

        if (ch === ">") return i;
      }
      return -1;
    };

    const isSelfClosingTag = (startIdx: number, endIdx: number): boolean => {
      for (let i = endIdx - 1; i > startIdx; i--) {
        const ch = this.buffer[i];
        if (/\s/.test(ch)) continue;
        return ch === "/";
      }
      return false;
    };

    const findNextOpenIdx = (fromIdx: number): number => {
      let searchIdx = fromIdx;
      while (true) {
        const idx = this.buffer.indexOf(openPrefix, searchIdx);
        if (idx === -1) return -1;

        // Prevent prefix collisions (e.g. `<playerServiceYear>` matching `<player`)
        const boundaryChar = this.buffer[idx + openPrefix.length];
        if (isBoundary(boundaryChar)) return idx;

        searchIdx = idx + 1;
      }
    };


    const emitEntity = async (entityXml: string) => {
      const parsed = this.parser.parse(entityXml);
      const entity = parsed[this.targetTag];
      if (entity) {
        await this.onEntity(Array.isArray(entity) ? entity[0] : entity, entityXml);
      }
    };

    while (true) {
      const startIdx = findNextOpenIdx(0);
      if (startIdx === -1) {
        if (this.buffer.length > TAIL_KEEP) {
          this.buffer = this.buffer.substring(this.buffer.length - TAIL_KEEP);
        }
        return;
      }

      // Drop any leading junk before the next open tag.
      if (startIdx > 0) {
        this.buffer = this.buffer.substring(startIdx);
      }

      const openTagEnd = findTagEnd(0);
      if (openTagEnd === -1) {
        // Need more bytes (start tag not complete yet).
        return;
      }

      if (isSelfClosingTag(0, openTagEnd)) {
        const entityXml = this.buffer.substring(0, openTagEnd + 1);
        await emitEntity(entityXml);
        this.buffer = this.buffer.substring(openTagEnd + 1);
        continue;
      }

      // Find matching close tag using nesting depth.
      let depth = 1;
      let scanPos = openTagEnd + 1;

      while (depth > 0) {
        const nextLt = this.buffer.indexOf("<", scanPos);
        if (nextLt === -1) {
          // Need more bytes for a full entity.
          return;
        }

        // Skip comments / CDATA / processing instructions / doctype
        if (this.buffer.startsWith("<!--", nextLt)) {
          const end = this.buffer.indexOf("-->", nextLt + 4);
          if (end === -1) return;
          scanPos = end + 3;
          continue;
        }

        if (this.buffer.startsWith("<![CDATA[", nextLt)) {
          const end = this.buffer.indexOf("]]>", nextLt + 9);
          if (end === -1) return;
          scanPos = end + 3;
          continue;
        }

        if (this.buffer.startsWith("<?", nextLt)) {
          const end = this.buffer.indexOf("?>", nextLt + 2);
          if (end === -1) return;
          scanPos = end + 2;
          continue;
        }

        if (this.buffer.startsWith("<!", nextLt)) {
          const end = this.buffer.indexOf(">", nextLt + 2);
          if (end === -1) return;
          scanPos = end + 1;
          continue;
        }

        const isOpen = this.buffer.startsWith(openPrefix, nextLt) && isBoundary(this.buffer[nextLt + openPrefix.length]);
        const isClose = this.buffer.startsWith(closePrefix, nextLt) && (this.buffer[nextLt + closePrefix.length] === ">" || /\s/.test(this.buffer[nextLt + closePrefix.length]));

        if (isOpen) {
          const end = findTagEnd(nextLt);
          if (end === -1) return;
          if (!isSelfClosingTag(nextLt, end)) depth += 1;
          scanPos = end + 1;
          continue;
        }

        if (isClose) {
          const end = findTagEnd(nextLt);
          if (end === -1) return;
          depth -= 1;
          scanPos = end + 1;

          if (depth === 0) {
            const entityXml = this.buffer.substring(0, end + 1);
            await emitEntity(entityXml);
            this.buffer = this.buffer.substring(end + 1);
            break;
          }

          continue;
        }

        // Not our tag; skip to end of this tag to avoid O(n^2) scanning.
        const otherEnd = findTagEnd(nextLt);
        if (otherEnd === -1) return;
        scanPos = otherEnd + 1;
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Summary Helpers
// ─────────────────────────────────────────────────────────────────────────────

export function createSummary(dryRun: boolean): ImportSummary {
  return {
    dry_run: dryRun,
    started_at: new Date().toISOString(),
    finished_at: "",
    tables: [],
    errors: [],
  };
}

export function finalizeSummary(summary: ImportSummary): ImportSummary {
  return {
    ...summary,
    finished_at: new Date().toISOString(),
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Parsing Helpers
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Parse various SportRadar "minutes" formats to total seconds.
 * Handles:
 * - "PT24M30S" (NBA/GLeague)
 * - "MM:SS" (NCAA)
 * - "MM" (Some season stats)
 */
export function parseSeconds(val: string | number | null | undefined): number | null {
  if (val === null || val === undefined || val === "") return null;
  if (typeof val === "number") return val;

  const s = String(val).trim();
  if (!s) return null;

  // Format: PT24M30S or PT24M
  if (s.startsWith("PT")) {
    let total = 0;
    const m = s.match(/(\d+)M/);
    const sec = s.match(/(\d+(?:\.\d+)?)S/);
    if (m) total += parseInt(m[1]) * 60;
    if (sec) total += parseFloat(sec[1]);
    return total;
  }

  // Format: 24:30
  if (s.includes(":")) {
    const parts = s.split(":");
    if (parts.length === 2) {
      return parseInt(parts[0]) * 60 + parseFloat(parts[1]);
    }
  }

  // Format: "24" (just minutes)
  const n = parseFloat(s);
  if (!isNaN(n)) return n * 60;

  return null;
}

/**
 * Parse NBA "PTmmMss" duration format to total seconds.
 */
export function parseNbaMinutes(pt: string | null | undefined): number | null {
  return parseSeconds(pt);
}

/**
 * Parse NBA "PTmmMss" to Postgres interval string.
 */
export function parseNbaInterval(pt: string | null | undefined): string | null {
  if (!pt) return null;
  const match = pt.match(/PT(\d+)M(\d+(?:\.\d+)?)S/);
  if (!match) return null;
  return `${match[1]} minutes ${match[2]} seconds`;
}

/**
 * Safe number parsing with null fallback.
 */
export function safeNum(val: unknown): number | null {
  if (val === null || val === undefined || val === "") return null;
  const n = Number(val);
  return isNaN(n) ? null : n;
}

/**
 * Safe BIGINT parsing (returns string for large numbers or BigInt, 
 * but since we're using pg-populate-recordset we can pass as number/string)
 */
export function safeBigInt(val: unknown): string | null {
  if (val === null || val === undefined || val === "") return null;
  try {
    return BigInt(Math.round(Number(val))).toString();
  } catch {
    return null;
  }
}

/**
 * Safe date parsing for PCMS date strings.
 */
export function parsePCMSDate(val: string | null | undefined): string | null {
  if (!val || val === "0001-01-01" || val === "" || (typeof val === 'object' && Object.keys(val).length === 0)) return null;
  // If it's already a valid date string, return it
  if (!isNaN(Date.parse(String(val)))) return String(val);
  return null;
}

/**
 * Tag value processor for fast-xml-parser to handle empty tags and xsi:nil.
 */
export function pcmsTagValueProcessor(tagName: string, tagValue: any, jPath: string, hasAttributes: boolean, isLeafNode: boolean) {
  if (tagValue === "") return null;
  return tagValue;
}

/**
 * Attribute value processor for fast-xml-parser.
 */
export function pcmsAttributeValueProcessor(attrName: string, attrValue: any, jPath: string, hasAttributes: boolean, isLeafNode: boolean) {
  if (attrName === "xsi:nil" && attrValue === "true") return null;
  return attrValue;
}

/**
 * Shared XML parser configuration for PCMS.
 */
export function createPCMSParser(options: { isArray?: (name: string) => boolean } = {}) {
  return new XMLParser({
    ignoreAttributes: false,
    attributeNamePrefix: "@_",
    allowBooleanAttributes: true,
    tagValueProcessor: pcmsTagValueProcessor,
    attributeValueProcessor: pcmsAttributeValueProcessor,
    isArray: options.isArray,
  });
}

/**
 * Safe boolean parsing.
 */
export function safeBool(val: unknown): boolean | null {
  if (val === null || val === undefined) return null;
  if (typeof val === "boolean") return val;
  if (val === 1 || val === "1" || val === "Y" || val === "true") return true;
  if (val === 0 || val === "0" || val === "N" || val === "false") return false;
  return null;
}

/**
 * Calculate derived 2-point stats.
 */
export function calc2pt(fgm: number | null, fga: number | null, fg3m: number | null, fg3a: number | null) {
  const fg2m = fgm !== null && fg3m !== null ? fgm - fg3m : null;
  const fg2a = fga !== null && fg3a !== null ? fga - fg3a : null;
  const fg2_pct = fg2m !== null && fg2a !== null && fg2a > 0 ? fg2m / fg2a : null;
  return { fg2m, fg2a, fg2_pct };
}
