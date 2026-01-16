import { SQL } from "bun";
import { createSummary, finalizeSummary } from "/f/ralph/utils.ts";

const sql = new SQL({ url: Bun.env.POSTGRES_URL!, prepare: false });

type AnySummary = {
  dry_run?: boolean;
  tables?: Array<{ table: string; attempted: number; success: boolean; error?: string }>;
  errors?: string[];
};

export async function main(
  dry_run = false,
  lineage_id?: number,
  summaries: AnySummary[] = []
) {
  const summary = createSummary(dry_run);

  if (dry_run) {
    return { ...finalizeSummary(summary), message: "dry_run=true; skipping lineage finalization." };
  }

  if (!lineage_id) {
    return { ...finalizeSummary(summary), message: "No lineage_id provided; skipping lineage finalization." };
  }

  const allErrors: string[] = [];
  let recordCount = 0;

  for (const s of summaries) {
    for (const err of s?.errors ?? []) allErrors.push(err);

    for (const t of s?.tables ?? []) {
      recordCount += Number(t.attempted ?? 0);
      if (!t.success) {
        allErrors.push(`${t.table}: ${t.error ?? "unknown error"}`);
      }
    }
  }

  const status = allErrors.length > 0 ? "FAILED" : "SUCCESS";
  const errorLog = allErrors.length > 0 ? JSON.stringify({ errors: allErrors }, null, 2) : null;

  await sql`
    UPDATE pcms.pcms_lineage
    SET
      record_count = ${recordCount},
      ingestion_status = ${status},
      error_log = ${errorLog},
      ingested_at = now()
    WHERE lineage_id = ${lineage_id}
  `;

  summary.tables.push({ table: "pcms.pcms_lineage", attempted: 1, success: true });
  return { ...finalizeSummary(summary), lineage_id, status, record_count: recordCount, error_count: allErrors.length };
}
