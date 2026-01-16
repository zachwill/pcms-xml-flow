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

// --- Transformation Logic ---

function transformSystemValues(sv: any, prov: any) {
  return {
    league_lk: sv.leagueLk, salary_year: safeNum(sv.systemYear),
    salary_cap_amount: safeBigInt(sv.capAmount), tax_level_amount: safeBigInt(sv.taxLevel),
    tax_apron_amount: safeBigInt(sv.taxApronAmount), tax_apron2_amount: safeBigInt(sv.taxApron2Amount),
    minimum_team_salary_amount: safeBigInt(sv.minTeamSalary), season_start_at: sv.firstDayOfSeason,
    season_end_at: sv.lastDayOfSeason, trade_deadline_at: sv.tradeDeadlineDate,
    created_at: sv.createDate, updated_at: sv.lastChangeDate, record_changed_at: sv.recordChangeDate, ...prov
  };
}

function transformRookieScale(rs: any, prov: any) {
  return {
    salary_year: safeNum(rs.season), pick_number: safeNum(rs.pick), league_lk: rs.leagueLk,
    salary_year_1: safeBigInt(rs.salaryYear1), salary_year_2: safeBigInt(rs.salaryYear2),
    salary_year_3: safeBigInt(rs.salaryYear3), salary_year_4: safeBigInt(rs.salaryYear4),
    option_amount_year_3: safeBigInt(rs.optionYear3), option_amount_year_4: safeBigInt(rs.optionYear4),
    option_pct_year_3: safeNum(rs.percentYear3), option_pct_year_4: safeNum(rs.percentYear4),
    is_active: safeBool(rs.activeFlg), created_at: rs.createDate, updated_at: rs.lastChangeDate,
    record_changed_at: rs.recordChangeDate, ...prov
  };
}

function transformNonContractAmount(nca: any, prov: any) {
  return {
    non_contract_amount_id: safeNum(nca.nonContractAmountId), player_id: safeNum(nca.playerId),
    team_id: safeNum(nca.teamId), salary_year: safeNum(nca.nonContractYear), amount_type_lk: nca.amountTypeLk,
    cap_amount: safeBigInt(nca.capAmount), tax_amount: safeBigInt(nca.taxAmount),
    apron_amount: safeBigInt(nca.apronAmount), fa_amount: safeBigInt(nca.faAmount),
    contract_id: safeNum(nca.contractId), transaction_id: safeNum(nca.transactionId),
    created_at: nca.createDate, updated_at: nca.lastChangeDate, record_changed_at: nca.recordChangeDate, ...prov
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
  const allFiles = readdirSync(extractDir).filter(f => f.endsWith('.xml'));
  const provenance = { source_drop_file: row.s3_key, parser_version: PARSER_VERSION, ingested_at: new Date() };

  const handlers = [
    { pattern: /yearly-system-values\.xml/, tag: 'systemValue', table: 'league_system_values', pk: ['league_lk', 'salary_year'], transform: transformSystemValues },
    { pattern: /rookie-scale-amounts\.xml/, tag: 'rookieScale', table: 'rookie_scale_amounts', pk: ['salary_year', 'pick_number', 'league_lk'], transform: transformRookieScale },
    { pattern: /nca\.xml/, tag: 'nonContractAmount', table: 'non_contract_amounts', pk: ['non_contract_amount_id'], transform: transformNonContractAmount }
  ];

  for (const h of handlers) {
    const xmlFile = allFiles.find(f => h.pattern.test(f));
    if (!xmlFile) continue;

    const filePath = `${extractDir}/${xmlFile}`;
    console.log(`Processing ${xmlFile}...`);

    const batch: any[] = [];
    const rawMap = new Map<string, any>();

    const streamParser = new PCMSStreamParser(h.tag, async (entity, rawXml) => {
      const transformed = h.transform(entity, { ...provenance, source_hash: hash(rawXml) });
      batch.push(transformed);
      rawMap.set(h.pk.map(f => String(transformed[f])).join(':'), entity);

      if (batch.length >= 100) {
        if (!dry_run) {
          const res = await upsertBatch(sql, 'pcms', h.table, batch, h.pk);
          await auditUpsert(row.lineage_id, res, h.pk, rawMap);
          summary.tables.push(res);
        } else {
          summary.tables.push({ table: `pcms.${h.table}`, attempted: batch.length, success: true });
        }
        batch.length = 0;
        rawMap.clear();
      }
    });

    const stream = createReadStream(filePath);
    for await (const chunk of stream) await streamParser.parseChunk(chunk);

    if (batch.length > 0) {
      if (!dry_run) {
        const res = await upsertBatch(sql, 'pcms', h.table, batch, h.pk);
        await auditUpsert(row.lineage_id, res, h.pk, rawMap);
        summary.tables.push(res);
      } else {
        summary.tables.push({ table: `pcms.${h.table}`, attempted: batch.length, success: true });
      }
    }
  }

  return finalizeSummary(summary);
}
