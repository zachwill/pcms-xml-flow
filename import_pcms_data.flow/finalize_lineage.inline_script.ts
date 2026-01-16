/**
 * Finalize Lineage - Updates lineage record with final status
 * 
 * This step runs last and:
 * 1. Aggregates errors from all previous steps
 * 2. Counts total records processed
 * 3. Updates pcms_lineage with SUCCESS/FAILED status
 */
import { SQL } from "bun";

const sql = new SQL({ url: Bun.env.POSTGRES_URL!, prepare: false });

// ─────────────────────────────────────────────────────────────────────────────
// Types
// ─────────────────────────────────────────────────────────────────────────────

interface TableResult {
  table: string;
  attempted: number;
  success: boolean;
  error?: string;
}

interface StepSummary {
  dry_run?: boolean;
  tables?: TableResult[];
  errors?: string[];
}

// ─────────────────────────────────────────────────────────────────────────────
// Main
// ─────────────────────────────────────────────────────────────────────────────

export async function main(
  dry_run = false,
  lineage_id?: number,
  summaries: StepSummary[] = []
) {
  const startedAt = new Date().toISOString();
  const tables: TableResult[] = [];
  const errors: string[] = [];

  if (dry_run) {
    return {
      dry_run,
      started_at: startedAt,
      finished_at: new Date().toISOString(),
      tables,
      errors,
      message: "dry_run=true; skipping lineage finalization.",
    };
  }

  if (!lineage_id) {
    return {
      dry_run,
      started_at: startedAt,
      finished_at: new Date().toISOString(),
      tables,
      errors,
      message: "No lineage_id provided; skipping lineage finalization.",
    };
  }

  try {
    // Aggregate errors and record counts from all step summaries
    const allErrors: string[] = [];
    let recordCount = 0;

    for (const s of summaries) {
      // Collect errors array from each step
      for (const err of s?.errors ?? []) {
        allErrors.push(err);
      }

      // Collect table-level errors and count records
      for (const t of s?.tables ?? []) {
        recordCount += Number(t.attempted ?? 0);
        if (!t.success) {
          allErrors.push(`${t.table}: ${t.error ?? "unknown error"}`);
        }
      }
    }

    const status = allErrors.length > 0 ? "FAILED" : "SUCCESS";
    const errorLog = allErrors.length > 0 
      ? JSON.stringify({ errors: allErrors }, null, 2) 
      : null;

    // Update lineage record
    await sql`
      UPDATE pcms.pcms_lineage
      SET
        record_count = ${recordCount},
        ingestion_status = ${status},
        error_log = ${errorLog},
        ingested_at = now()
      WHERE lineage_id = ${lineage_id}
    `;

    tables.push({ table: "pcms.pcms_lineage", attempted: 1, success: true });

    return {
      dry_run,
      started_at: startedAt,
      finished_at: new Date().toISOString(),
      tables,
      errors,
      lineage_id,
      status,
      record_count: recordCount,
      error_count: allErrors.length,
    };
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e);
    errors.push(msg);
    tables.push({ table: "pcms.pcms_lineage", attempted: 1, success: false, error: msg });

    return {
      dry_run,
      started_at: startedAt,
      finished_at: new Date().toISOString(),
      tables,
      errors,
      lineage_id,
      status: "FAILED",
      record_count: 0,
      error_count: errors.length,
    };
  }
}