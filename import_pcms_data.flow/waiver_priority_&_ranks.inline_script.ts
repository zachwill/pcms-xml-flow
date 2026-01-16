import { SQL } from "bun";
import {
  hash,
  upsertBatch,
  createSummary,
  finalizeSummary,
  safeNum,
  safeBigInt,
  safeBool,
  parsePCMSDate,
  UpsertResult,
  PCMSStreamParser,
  resolvePCMSLineageContext
} from "/f/ralph/utils.ts";
import { readdirSync, createReadStream, readFileSync } from "fs";

const sql = new SQL({ url: Bun.env.POSTGRES_URL!, prepare: false });
const PARSER_VERSION = "2.0.0";
const SHARED_DIR = "./shared/pcms";

/**
 * Peek at the beginning of an XML file to find specific tags.
 */
function peekContext(filePath: string, tags: string[]): Record<string, string | null> {
  const results: Record<string, string | null> = {};
  for (const tag of tags) results[tag] = null;

  // Read first 100KB to find context tags
  const buffer = readFileSync(filePath, { encoding: 'utf8', flag: 'r' }).slice(0, 100 * 1024);

  for (const tag of tags) {
    const match = buffer.match(new RegExp(`<${tag}[^>]*>([^<]+)</${tag}>`));
    if (match) results[tag] = match[1];
  }
  return results;
}

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

function transformWaiverPriority(wp: any, prov: any) {
  return {
    waiver_priority_id: safeNum(wp.waiverPriorityId), priority_date: wp.priorityDate,
    seqno: safeNum(wp.seqno), status_lk: wp.recordStatusLk, comments: wp.comments,
    created_at: parsePCMSDate(wp.createDate), updated_at: parsePCMSDate(wp.lastChangeDate),
    record_changed_at: parsePCMSDate(wp.recordChangeDate), ...prov
  };
}

function transformWaiverPriorityRank(wpr: any, wpId: number, prov: any) {
  return {
    waiver_priority_rank_id: safeNum(wpr.waiverPriorityDetailId), waiver_priority_id: wpId,
    team_id: safeNum(wpr.teamId), priority_order: safeNum(wpr.priorityOrder),
    is_order_priority: safeBool(wpr.orderPriorityFlg), exclusivity_status_lk: wpr.exclusivityStatusLk,
    exclusivity_expiration_date: wpr.exclusivityExpirationDate, status_lk: wpr.recordStatusLk,
    seqno: safeNum(wpr.seqno), comments: wpr.comments, created_at: parsePCMSDate(wpr.createDate),
    updated_at: parsePCMSDate(wpr.lastChangeDate), record_changed_at: parsePCMSDate(wpr.recordChangeDate), ...prov
  };
}

function transformTaxRate(tr: any, prov: any) {
  return {
    league_lk: tr.leagueLk, salary_year: safeNum(tr.salaryYear), lower_limit: safeBigInt(tr.lowerLimit),
    upper_limit: safeBigInt(tr.upperLimit), tax_rate_non_repeater: safeNum(tr.taxRateNonRepeater),
    tax_rate_repeater: safeNum(tr.taxRateRepeater), base_charge_non_repeater: safeBigInt(tr.baseChargeNonRepeater),
    base_charge_repeater: safeBigInt(tr.baseChargeRepeater), created_at: parsePCMSDate(tr.createDate),
    updated_at: parsePCMSDate(tr.lastChangeDate), record_changed_at: parsePCMSDate(tr.recordChangeDate), ...prov
  };
}

function transformTaxTeamStatus(tts: any, prov: any) {
  return {
    team_id: safeNum(tts.teamId), salary_year: safeNum(tts.salaryYear), is_taxpayer: safeBool(tts.taxpayerFlg),
    is_repeater_taxpayer: safeBool(tts.repeaterTaxpayerFlg), is_subject_to_apron: safeBool(tts.subjectToApronFlg),
    apron_level_lk: tts.apronLevelLk, subject_to_apron_reason_lk: tts.subjectToApronReasonLk,
    apron1_transaction_id: safeNum(tts.apron1TransactionId), apron2_transaction_id: safeNum(tts.apron2TransactionId),
    created_at: parsePCMSDate(tts.createDate), updated_at: parsePCMSDate(tts.lastChangeDate),
    record_changed_at: parsePCMSDate(tts.recordChangeDate), ...prov
  };
}

function transformBudgetSnapshot(be: any, teamId: number, salaryYear: number, prov: any) {
  const base: any = {
    team_id: teamId, salary_year: salaryYear, player_id: safeNum(be.playerId),
    contract_id: safeNum(be.contractId), transaction_id: safeNum(be.transactionId),
    transaction_type_lk: be.transactionTypeLk, transaction_description_lk: be.transactionDescriptionLk,
    budget_group_lk: be.budgetGroupLk, contract_type_lk: be.contractTypeLk,
    free_agent_designation_lk: be.freeAgentDesignationLk, free_agent_status_lk: be.freeAgentStatusLk,
    signing_method_lk: be.signingMethodLk, overall_contract_bonus_type_lk: be.overallContractBonusTypeLk,
    overall_protection_coverage_lk: be.overallProtectionCoverageLk, max_contract_lk: be.maxContractLk,
    years_of_service: safeNum(be.yearsOfService), ledger_date: be.ledgerDate, signing_date: be.signingDate,
    version_number: safeNum(be.versionNumber), ...prov
  };

  const amounts = Array.isArray(be.budgetAmounts?.budgetAmount)
    ? be.budgetAmounts.budgetAmount
    : (be.budgetAmounts?.budgetAmount ? [be.budgetAmounts.budgetAmount] : []);

  const amount = amounts.find((a: any) => safeNum(a.year) === salaryYear) || amounts[0];
  if (amount) {
    return {
      ...base, cap_amount: safeBigInt(amount.capAmount), tax_amount: safeBigInt(amount.taxAmount),
      mts_amount: safeBigInt(amount.mtsAmount), apron_amount: safeBigInt(amount.apronAmount),
      is_fa_amount: safeBool(amount.faAmountFlg), option_lk: amount.optionLk, option_decision_lk: amount.optionDecisionLk,
    };
  }
  return base;
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
  const xmlFiles = readdirSync(extractDir).filter(f => f.endsWith('.xml'));
  const provenance = { source_drop_file: row.s3_key, parser_version: PARSER_VERSION, ingested_at: new Date() };

  for (const xmlFile of xmlFiles) {
    const filePath = `${extractDir}/${xmlFile}`;

    // 1. Waiver Priority
    if (xmlFile.includes('waiver-priority')) {
      console.log(`Processing ${xmlFile} (waiver priority)...`);
      const priorities: any[] = [];
      const ranks: any[] = [];
      const rawPriorities = new Map<string, any>();
      const rawRanks = new Map<string, any>();

      async function flush() {
        if (priorities.length === 0) return;
        if (!dry_run) {
          const res = await upsertBatch(sql, 'pcms', 'waiver_priority', priorities, ['waiver_priority_id']);
          await auditUpsert(row.lineage_id, res, ['waiver_priority_id'], rawPriorities);
          summary.tables.push(res);
          if (ranks.length > 0) {
            const rRes = await upsertBatch(sql, 'pcms', 'waiver_priority_ranks', ranks, ['waiver_priority_rank_id']);
            await auditUpsert(row.lineage_id, rRes, ['waiver_priority_rank_id'], rawRanks);
            summary.tables.push(rRes);
          }
        } else {
          summary.tables.push({ table: 'pcms.waiver_priority', attempted: priorities.length, success: true });
          if (ranks.length > 0) summary.tables.push({ table: 'pcms.waiver_priority_ranks', attempted: ranks.length, success: true });
        }
        priorities.length = 0; ranks.length = 0; rawPriorities.clear(); rawRanks.clear();
      }

      const streamParser = new PCMSStreamParser('waiverPriority', async (wp, rawXml) => {
        const pRow = transformWaiverPriority(wp, { ...provenance, source_hash: hash(rawXml) });
        priorities.push(pRow);
        rawPriorities.set(String(pRow.waiver_priority_id), wp);

        if (wp.waiverPriorityRanks?.waiverPriorityRank) {
          const rList = Array.isArray(wp.waiverPriorityRanks.waiverPriorityRank) ? wp.waiverPriorityRanks.waiverPriorityRank : [wp.waiverPriorityRanks.waiverPriorityRank];
          for (const r of rList) {
            const rRow = transformWaiverPriorityRank(r, pRow.waiver_priority_id, { ...provenance, source_hash: hash(rawXml) });
            ranks.push(rRow);
            rawRanks.set(String(rRow.waiver_priority_rank_id), r);
          }
        }
        if (priorities.length >= 500) await flush();
      });

      const stream = createReadStream(filePath);
      for await (const chunk of stream) await streamParser.parseChunk(chunk);
      await flush();
    }

    // 2. Tax Rates
    if (xmlFile.includes('tax-rates')) {
      console.log(`Processing ${xmlFile} (tax rates)...`);
      const batch: any[] = [];
      const rawMap = new Map<string, any>();
      const pkFields = ['league_lk', 'salary_year', 'lower_limit'];

      const streamParser = new PCMSStreamParser('taxRate', async (tr, rawXml) => {
        const transformed = transformTaxRate(tr, { ...provenance, source_hash: hash(rawXml) });
        batch.push(transformed);
        rawMap.set(pkFields.map(f => String(transformed[f])).join(':'), tr);
        if (batch.length >= 500) {
          if (!dry_run) {
            const res = await upsertBatch(sql, 'pcms', 'league_tax_rates', batch, pkFields);
            await auditUpsert(row.lineage_id, res, pkFields, rawMap);
            summary.tables.push(res);
          } else {
            summary.tables.push({ table: 'pcms.league_tax_rates', attempted: batch.length, success: true });
          }
          batch.length = 0; rawMap.clear();
        }
      });

      const stream = createReadStream(filePath);
      for await (const chunk of stream) await streamParser.parseChunk(chunk);
      if (batch.length > 0) {
        if (!dry_run) {
          const res = await upsertBatch(sql, 'pcms', 'league_tax_rates', batch, pkFields);
          await auditUpsert(row.lineage_id, res, pkFields, rawMap);
          summary.tables.push(res);
        } else {
          summary.tables.push({ table: 'pcms.league_tax_rates', attempted: batch.length, success: true });
        }
      }
    }

    // 3. Tax Team Status
    if (xmlFile.includes('tax-teams')) {
      console.log(`Processing ${xmlFile} (tax team status)...`);
      const batch: any[] = [];
      const rawMap = new Map<string, any>();
      const pkFields = ['team_id', 'salary_year'];

      const streamParser = new PCMSStreamParser('taxTeamStatus', async (tts, rawXml) => {
        const transformed = transformTaxTeamStatus(tts, { ...provenance, source_hash: hash(rawXml) });
        batch.push(transformed);
        rawMap.set(pkFields.map(f => String(transformed[f])).join(':'), tts);
        if (batch.length >= 500) {
          if (!dry_run) {
            const res = await upsertBatch(sql, 'pcms', 'tax_team_status', batch, pkFields);
            await auditUpsert(row.lineage_id, res, pkFields, rawMap);
            summary.tables.push(res);
          } else {
            summary.tables.push({ table: 'pcms.tax_team_status', attempted: batch.length, success: true });
          }
          batch.length = 0; rawMap.clear();
        }
      });

      const stream = createReadStream(filePath);
      for await (const chunk of stream) await streamParser.parseChunk(chunk);
      if (batch.length > 0) {
        if (!dry_run) {
          const res = await upsertBatch(sql, 'pcms', 'tax_team_status', batch, pkFields);
          await auditUpsert(row.lineage_id, res, pkFields, rawMap);
          summary.tables.push(res);
        } else {
          summary.tables.push({ table: 'pcms.tax_team_status', attempted: batch.length, success: true });
        }
      }
    }

    // 4. Team Budget
    if (xmlFile.includes('team-budget')) {
      console.log(`Processing ${xmlFile} (team budget)...`);
      const context = peekContext(filePath, ['teamId', 'salaryYear']);
      const teamId = safeNum(context.teamId);
      const salaryYear = safeNum(context.salaryYear);

      if (!teamId || !salaryYear) {
        summary.errors.push(`${xmlFile}: Missing teamId or salaryYear`);
        continue;
      }

      const batch: any[] = [];
      const rawMap = new Map<string, any>();
      const pkFields = ['team_id', 'salary_year', 'transaction_id', 'budget_group_lk', 'player_id', 'contract_id', 'version_number'];

      const streamParser = new PCMSStreamParser('teamBudgetEntry', async (be, rawXml) => {
        const transformed = transformBudgetSnapshot(be, teamId, salaryYear, { ...provenance, source_hash: hash(rawXml) });
        batch.push(transformed);
        rawMap.set(pkFields.map(f => String(transformed[f])).join(':'), be);
        if (batch.length >= 500) {
          if (!dry_run) {
            const res = await upsertBatch(sql, 'pcms', 'team_budget_snapshots', batch, pkFields);
            await auditUpsert(row.lineage_id, res, pkFields, rawMap);
            summary.tables.push(res);
          } else {
            summary.tables.push({ table: 'pcms.team_budget_snapshots', attempted: batch.length, success: true });
          }
          batch.length = 0; rawMap.clear();
        }
      });

      const stream = createReadStream(filePath);
      for await (const chunk of stream) await streamParser.parseChunk(chunk);
      if (batch.length > 0) {
        if (!dry_run) {
          const res = await upsertBatch(sql, 'pcms', 'team_budget_snapshots', batch, pkFields);
          await auditUpsert(row.lineage_id, res, pkFields, rawMap);
          summary.tables.push(res);
        } else {
          summary.tables.push({ table: 'pcms.team_budget_snapshots', attempted: batch.length, success: true });
        }
      }
    }
  }

  return finalizeSummary(summary);
}
