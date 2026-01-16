import { SQL } from "bun";
import {
  hash,
  upsertBatch,
  createSummary,
  finalizeSummary,
  safeNum,
  safeBigInt,
  safeBool,
  UpsertResult,
  PCMSStreamParser,
  resolvePCMSLineageContext
} from "/f/ralph/utils.ts";
import { readdirSync, createReadStream } from "fs";

const sql = new SQL({ url: Bun.env.POSTGRES_URL!, prepare: false });
const PARSER_VERSION = "2.0.0";
const SHARED_DIR = "./shared/pcms";

async function auditUpsert(lineageId: number, result: UpsertResult,
  pkFields: string | string[], originalDataMap: Map<string, any>) {
  if (!result.success || !result.rows || result.rows.length === 0) return;

  const audits = result.rows.map((row) => {
    const sourceId = Array.isArray(pkFields)
      ? pkFields.map(f => String(row[f])).join(':')
      : String(row[pkFields]);
    return {
      lineage_id: lineageId,
      table_name: result.table.split('.').pop(),
      source_record_id: sourceId,
      record_hash: row.source_hash,
      parser_version: PARSER_VERSION,
      operation_type: 'UPSERT',
      source_data_json: originalDataMap.get(sourceId)
    };
  });

  if (audits.length > 0) {
    await sql`
      INSERT INTO pcms.pcms_lineage_audit ${sql(audits)}
      ON CONFLICT (table_name, source_record_id, record_hash, parser_version) DO NOTHING
    `;
  }
}

// --- Transformation Logic ---

function transformException(te: any, provenance: any) {
  return {
    team_exception_id: safeNum(te.teamExceptionId),
    team_id: safeNum(te.teamId),
    salary_year: safeNum(te.teamExceptionYear),
    exception_type_lk: te.exceptionTypeLk,
    effective_date: te.effectiveDate,
    expiration_date: te.expirationDate,
    original_amount: safeBigInt(te.originalAmount),
    remaining_amount: safeBigInt(te.remainingAmount),
    proration_rate: safeNum(te.prorationRate),
    is_initially_convertible: safeBool(te.initiallyConvertibleFlg),
    trade_exception_player_id: safeNum(te.tradeExceptionPlayerId),
    trade_id: safeNum(te.tradeId),
    record_status_lk: te.recordStatusLk,
    created_at: te.createDate,
    updated_at: te.lastChangeDate,
    record_changed_at: te.recordChangeDate,
    ...provenance
  };
}

function transformUsage(ed: any, teamExceptionId: number, provenance: any) {
  return {
    team_exception_detail_id: safeNum(ed.teamExceptionDetailId),
    team_exception_id: teamExceptionId,
    seqno: safeNum(ed.seqno),
    effective_date: ed.effectiveDate,
    exception_action_lk: ed.exceptionActionLk,
    transaction_type_lk: ed.transaction_type_lk ?? ed.transactionTypeLk,
    transaction_id: safeNum(ed.transactionId),
    player_id: safeNum(ed.playerId),
    contract_id: safeNum(ed.contractId),
    change_amount: safeBigInt(ed.changeAmount),
    remaining_exception_amount: safeBigInt(ed.remainingExceptionAmount),
    proration_rate: safeNum(ed.prorationRate),
    prorate_days: safeNum(ed.prorateDays),
    is_convert_exception: safeBool(ed.convertExceptionFlg),
    manual_action_text: ed.manualActionText,
    created_at: ed.createDate,
    updated_at: ed.lastChangeDate,
    record_changed_at: ed.recordChangeDate,
    ...provenance
  };
}

// --- Main Execution ---

export async function main(
  dry_run = false,
  lineage_id?: number,
  s3_key?: string,
  extract_dir: string = SHARED_DIR
) {
  const summary = createSummary(dry_run);

  const extractDir = (extract_dir as any) || SHARED_DIR;
  const row = await resolvePCMSLineageContext(sql, { lineageId: lineage_id, s3Key: s3_key, sharedDir: extractDir });
  const xmlFiles = readdirSync(extractDir).filter(f => f.includes('team-exception') && f.endsWith('.xml'));

  for (const xmlFile of xmlFiles) {
    const filePath = `${extractDir}/${xmlFile}`;
    console.log(`Processing ${xmlFile}...`);

    const exceptions: any[] = [];
    const usages: any[] = [];
    const rawMap = new Map<string, any>();

    const provenance = {
      source_drop_file: row.s3_key,
      parser_version: PARSER_VERSION,
      ingested_at: new Date()
    };

    async function flush() {
      if (exceptions.length === 0) return;
      if (!dry_run) {
        const resTE = await upsertBatch(sql, 'pcms', 'team_exceptions', exceptions, ['team_exception_id']);
        await auditUpsert(row.lineage_id, resTE, 'team_exception_id', rawMap);
        summary.tables.push(resTE);
        if (usages.length > 0) {
          summary.tables.push(await upsertBatch(sql, 'pcms', 'team_exception_usage', usages, ['team_exception_detail_id']));
        }
      } else {
        summary.tables.push({ table: 'pcms.team_exceptions', attempted: exceptions.length, success: true });
        if (usages.length > 0) {
          summary.tables.push({ table: 'pcms.team_exception_usage', attempted: usages.length, success: true });
        }
      }
      exceptions.length = 0;
      usages.length = 0;
      rawMap.clear();
    }

    const streamParser = new PCMSStreamParser('teamException', async (te, rawXml) => {
      const teId = safeNum(te.teamExceptionId);
      if (!teId) return;

      const prov = { ...provenance, source_hash: hash(rawXml) };
      exceptions.push(transformException(te, prov));
      rawMap.set(String(teId), te);

      if (te.exceptionDetails && te.exceptionDetails.exceptionDetail) {
        const details = Array.isArray(te.exceptionDetails.exceptionDetail)
          ? te.exceptionDetails.exceptionDetail
          : [te.exceptionDetails.exceptionDetail];
        for (const ed of details) {
          usages.push(transformUsage(ed, teId, prov));
        }
      }

      if (exceptions.length >= 100) await flush();
    }, (name) => ["teamException", "exceptionDetail"].includes(name));

    const stream = createReadStream(filePath);
    for await (const chunk of stream) {
      await streamParser.parseChunk(chunk);
    }
    await flush();
  }

  return finalizeSummary(summary);
}
