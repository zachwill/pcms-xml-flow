import { SQL } from "bun";
import {
  hash,
  upsertBatch,
  createSummary,
  finalizeSummary,
  safeNum,
  safeBool,
  UpsertResult,
  PCMSStreamParser,
  resolvePCMSLineageContext
} from "/f/ralph/utils.ts";
import { readdirSync, createReadStream } from "fs";

const sql = new SQL({ url: Bun.env.POSTGRES_URL!, prepare: false });
const PARSER_VERSION = "2.0.0";
const SHARED_DIR = "./shared/pcms";

async function auditUpsert(lineageId: number, result: UpsertResult, pkField: string, originalDataMap: Map<string, any>) {
  if (!result.success || !result.rows || result.rows.length === 0) return;
  const audits = result.rows.map((row) => ({
    lineage_id: lineageId,
    table_name: result.table.split('.').pop(),
    source_record_id: String(row[pkField]),
    record_hash: row.source_hash,
    parser_version: PARSER_VERSION,
    operation_type: 'UPSERT',
    source_data_json: originalDataMap.get(String(row[pkField]))
  }));
  if (audits.length > 0) {
    await sql`INSERT INTO pcms.pcms_lineage_audit ${sql(audits)} ON CONFLICT (table_name, source_record_id, record_hash, parser_version) DO NOTHING`;
  }
}

function transformDraftPick(dp: any, prov: any) {
  return {
    draft_pick_id: safeNum(dp.draftPickId), draft_year: safeNum(dp.year ?? dp.draftYear),
    round: safeNum(dp.round), pick_number: String(dp.pick), pick_number_int: safeNum(dp.pick),
    league_lk: dp.leagueLk ?? 'NBA', original_team_id: safeNum(dp.originalTeamId),
    current_team_id: safeNum(dp.teamId), is_active: safeBool(dp.activeFlg),
    created_at: dp.createDate, updated_at: dp.lastChangeDate, record_changed_at: dp.recordChangeDate, ...prov
  };
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
  const xmlFile = readdirSync(extractDir).find(f => f.includes('_dp') && f.endsWith('.xml'));
  if (!xmlFile) return { ...finalizeSummary(summary), message: "No draft picks XML file found." };

  const filePath = `${extractDir}/${xmlFile}`;
  console.log(`Processing ${xmlFile}...`);

  const batch: any[] = [];
  const rawMap = new Map<string, any>();
  const provenance = { source_drop_file: row.s3_key, parser_version: PARSER_VERSION, ingested_at: new Date() };

  const streamParser = new PCMSStreamParser('draftPick', async (dp, rawXml) => {
    const transformed = transformDraftPick(dp, { ...provenance, source_hash: hash(rawXml) });
    batch.push(transformed);
    rawMap.set(String(transformed.draft_pick_id), dp);

    if (batch.length >= 100) {
      if (!dry_run) {
        const res = await upsertBatch(sql, 'pcms', 'draft_picks', batch, ['draft_pick_id']);
        await auditUpsert(row.lineage_id, res, 'draft_pick_id', rawMap);
        summary.tables.push(res);
      } else {
        summary.tables.push({ table: 'pcms.draft_picks', attempted: batch.length, success: true });
      }
      batch.length = 0;
      rawMap.clear();
    }
  });

  const stream = createReadStream(filePath);
  for await (const chunk of stream) await streamParser.parseChunk(chunk);

  if (batch.length > 0) {
    if (!dry_run) {
      const res = await upsertBatch(sql, 'pcms', 'draft_picks', batch, ['draft_pick_id']);
      await auditUpsert(row.lineage_id, res, 'draft_pick_id', rawMap);
      summary.tables.push(res);
    } else {
      summary.tables.push({ table: 'pcms.draft_picks', attempted: batch.length, success: true });
    }
  }

  return finalizeSummary(summary);
}
