import { SQL } from "bun";
import {
  hash,
  upsertBatch,
  createSummary,
  finalizeSummary,
  safeNum,
  safeBool,
  PCMSStreamParser,
  UpsertResult,
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

function transformLookup(type: string, l: any, prov: any) {
  const codeField = Object.keys(l).find(k => k.endsWith('Lk'));
  const lookup_code = codeField ? l[codeField] : null;
  if (!lookup_code) return null;

  const properties: Record<string, any> = {};
  for (const [k, v] of Object.entries(l)) {
    if (!['description', 'shortDescription', 'activeFlg', 'seqno', 'createDate', 'lastChangeDate', 'recordChangeDate', codeField].includes(k)) {
      properties[k] = v;
    }
  }

  return {
    lookup_type: type, lookup_code, description: l.description, short_description: l.shortDescription,
    is_active: safeBool(l.activeFlg), seqno: safeNum(l.seqno),
    properties_json: Object.keys(properties).length > 0 ? JSON.stringify(properties) : null,
    created_at: l.createDate, updated_at: l.lastChangeDate, record_changed_at: l.recordChangeDate, ...prov
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
  const xmlFile = readdirSync(extractDir).find(f => f.includes('lookup') && f.endsWith('.xml'));
  if (!xmlFile) return { ...finalizeSummary(summary), message: "No lookup XML file found." };

  const filePath = `${extractDir}/${xmlFile}`;
  console.log(`Processing ${xmlFile}...`);

  const provenance = { source_drop_file: row.s3_key, parser_version: PARSER_VERSION, ingested_at: new Date() };

  // First pass: identify lookup tags
  const lkTags = new Set<string>();
  const tagDetector = new PCMSStreamParser('lookups', async (lookups) => {
    for (const key of Object.keys(lookups)) {
      if (key.startsWith('lk') && !['lkTeam', 'lkAgency', 'lkAgent'].includes(key)) {
        lkTags.add(key);
      }
    }
  });

  const detectStream = createReadStream(filePath);
  for await (const chunk of detectStream) await tagDetector.parseChunk(chunk);

  // Second pass: parse each tag
  for (const tag of lkTags) {
    const batch: any[] = [];
    const rawMap = new Map<string, any>();

    const streamParser = new PCMSStreamParser(tag, async (entity, rawXml) => {
      const transformed = transformLookup(tag, entity, { ...provenance, source_hash: hash(rawXml) });
      if (transformed) {
        batch.push(transformed);
        rawMap.set(`${transformed.lookup_type}:${transformed.lookup_code}`, entity);
      }

      if (batch.length >= 500) {
        if (!dry_run) {
          const res = await upsertBatch(sql, 'pcms', 'lookups', batch, ['lookup_type', 'lookup_code']);
          await auditUpsert(row.lineage_id, res, ['lookup_type', 'lookup_code'], rawMap);
          summary.tables.push(res);
        } else {
          summary.tables.push({ table: 'pcms.lookups', attempted: batch.length, success: true });
        }
        batch.length = 0;
        rawMap.clear();
      }
    });

    const stream = createReadStream(filePath);
    for await (const chunk of stream) await streamParser.parseChunk(chunk);

    if (batch.length > 0) {
      if (!dry_run) {
        const res = await upsertBatch(sql, 'pcms', 'lookups', batch, ['lookup_type', 'lookup_code']);
        await auditUpsert(row.lineage_id, res, ['lookup_type', 'lookup_code'], rawMap);
        summary.tables.push(res);
      } else {
        summary.tables.push({ table: 'pcms.lookups', attempted: batch.length, success: true });
      }
    }
  }

  return finalizeSummary(summary);
}
