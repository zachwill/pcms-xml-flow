import { SQL } from "bun";
import {
  hash,
  upsertBatch,
  createSummary,
  finalizeSummary,
  safeNum,
  UpsertResult,
  PCMSStreamParser,
  resolvePCMSLineageContext
} from "/f/ralph/utils.ts";
import { readdirSync, createReadStream } from "fs";

const sql = new SQL({ url: Bun.env.POSTGRES_URL!, prepare: false });
const PARSER_VERSION = "2.0.0";
const SHARED_DIR = "./shared/pcms";

async function auditUpsert(lineageId: number, result: UpsertResult, pkFields: string[], originalDataMap: Map<string, any>) {
  if (!result.success || !result.rows || result.rows.length === 0) return;
  const audits = result.rows.map((row) => ({
    lineage_id: lineageId,
    table_name: result.table.split('.').pop(),
    source_record_id: pkFields.map(f => String(row[f])).join(':'),
    record_hash: row.source_hash,
    parser_version: PARSER_VERSION,
    operation_type: 'UPSERT',
    source_data_json: originalDataMap.get(pkFields.map(f => String(row[f])).join(':'))
  }));
  if (audits.length > 0) {
    await sql`INSERT INTO pcms.pcms_lineage_audit ${sql(audits)} ON CONFLICT (table_name, source_record_id, record_hash, parser_version) DO NOTHING`;
  }
}

function transformTwoWayStatus(s: any, prov: any) {
  return { player_id: safeNum(s.playerId), status_date: s.statusDate, status_lk: s.twoWayDailyStatusLk, ...prov };
}

export async function main(
  dry_run = false,
  lineage_id?: number,
  s3_key?: string,
  extract_dir: string = SHARED_DIR
) {
  const summary = createSummary(dry_run);

  const extractDir = (extract_dir as any) || SHARED_DIR;
  const row = await resolvePCMSLineageContext(sql, { lineageId: lineage_id, s3Key: s3_key, sharedDir: extractDir });
  const xmlFile = readdirSync(extractDir).find(f => f.includes('two-way') && f.endsWith('.xml'));
  if (!xmlFile) return { ...finalizeSummary(summary), message: "No two-way XML file found." };

  const filePath = `${extractDir}/${xmlFile}`;
  console.log(`Processing ${xmlFile}...`);

  const batch: any[] = [];
  const rawMap = new Map<string, any>();
  const provenance = { source_drop_file: row.s3_key, parser_version: PARSER_VERSION, ingested_at: new Date() };

  const streamParser = new PCMSStreamParser('status', async (s, rawXml) => {
    const transformed = transformTwoWayStatus(s, { ...provenance, source_hash: hash(rawXml) });
    batch.push(transformed);
    rawMap.set(`${transformed.player_id}:${transformed.status_date}`, s);

    if (batch.length >= 500) {
      if (!dry_run) {
        const res = await upsertBatch(sql, 'pcms', 'two_way_daily_statuses', batch, ['player_id', 'status_date']);
        await auditUpsert(row.lineage_id, res, ['player_id', 'status_date'], rawMap);
        summary.tables.push(res);
      } else {
        summary.tables.push({ table: 'pcms.two_way_daily_statuses', attempted: batch.length, success: true });
      }
      batch.length = 0;
      rawMap.clear();
    }
  });

  const stream = createReadStream(filePath);
  for await (const chunk of stream) await streamParser.parseChunk(chunk);

  if (batch.length > 0) {
    if (!dry_run) {
      const res = await upsertBatch(sql, 'pcms', 'two_way_daily_statuses', batch, ['player_id', 'status_date']);
      await auditUpsert(row.lineage_id, res, ['player_id', 'status_date'], rawMap);
      summary.tables.push(res);
    } else {
      summary.tables.push({ table: 'pcms.two_way_daily_statuses', attempted: batch.length, success: true });
    }
  }

  return finalizeSummary(summary);
}
