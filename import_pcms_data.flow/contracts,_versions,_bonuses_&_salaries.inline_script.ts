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

async function auditUpsert(lineageId: number, result: UpsertResult, naturalKeyField: string, originalDataMap: Map<string, any>) {
  if (!result.success || !result.rows) return;
  const audits = result.rows.map((row) => ({
    lineage_id: lineageId,
    table_name: result.table.split('.').pop(),
    source_record_id: String(row[naturalKeyField]),
    record_hash: row.source_hash,
    parser_version: PARSER_VERSION,
    operation_type: 'UPSERT',
    source_data_json: originalDataMap.get(String(row[naturalKeyField]))
  }));
  if (audits.length > 0) {
    await sql`
      INSERT INTO pcms.pcms_lineage_audit ${sql(audits)} 
      ON CONFLICT (table_name, source_record_id, record_hash, parser_version) DO NOTHING
    `;
  }
}

// --- Transformation Logic ---

function transformContract(c: any, provenance: any) {
  return {
    contract_id: safeNum(c.contractId),
    player_id: safeNum(c.playerId),
    signing_team_id: safeNum(c.signingTeamId),
    signing_date: c.signingDate,
    contract_end_date: c.contractEndDate,
    record_status_lk: c.recordStatusLk,
    signed_method_lk: c.signedMethodLk,
    team_exception_id: safeNum(c.teamExceptionId),
    is_sign_and_trade: safeBool(c.signAndTradeFlg),
    sign_and_trade_date: c.signAndTradeDate,
    sign_and_trade_to_team_id: safeNum(c.signAndTradeToTeamId),
    sign_and_trade_id: safeNum(c.signAndTradeId),
    start_year: safeNum(c.startYear),
    contract_length_wnba: c.contractLength,
    convert_date: c.convertDate,
    two_way_service_limit: safeNum(c.twoWayServiceLimit),
    created_at: c.createDate,
    updated_at: c.lastChangeDate,
    record_changed_at: c.recordChangeDate,
    ...provenance
  };
}

function transformContractVersion(v: any, contractId: number, provenance: any) {
  return {
    contract_id: contractId,
    version_number: safeNum(v.versionNumber),
    transaction_id: safeNum(v.transactionId),
    version_date: v.versionDate,
    start_salary_year: safeNum(v.startYear),
    contract_length: safeNum(v.contractLength),
    contract_type_lk: v.contractTypeLk,
    record_status_lk: v.recordStatusLk,
    agency_id: safeNum(v.agencyId),
    agent_id: safeNum(v.agentId),
    is_full_protection: safeBool(v.fullProtectionFlg),
    is_exhibit_10: safeBool(v.exhibit10),
    exhibit_10_bonus_amount: safeBigInt(v.exhibit10BonusAmount),
    exhibit_10_protection_amount: safeBigInt(v.exhibit10ProtectionAmount),
    exhibit_10_end_date: v.exhibit10EndDate,
    is_two_way: safeBool(v.isTwoWay),
    is_rookie_scale_extension: safeBool(v.dpRookieScaleExtensionFlg),
    is_veteran_extension: safeBool(v.dpVeteranExtensionFlg),
    is_poison_pill: safeBool(v.poisonPillFlg),
    poison_pill_amount: safeBigInt(v.poisonPillAmt),
    trade_bonus_percent: safeNum(v.tradeBonusPercent),
    trade_bonus_amount: safeBigInt(v.tradeBonusAmount),
    is_trade_bonus: safeBool(v.tradeBonusFlg),
    is_no_trade: safeBool(v.noTradeFlg),
    version_json: null,
    created_at: v.createDate,
    updated_at: v.lastChangeDate,
    record_changed_at: v.recordChangeDate,
    ...provenance
  };
}

function transformContractBonus(b: any, contractId: number, versionNumber: number, provenance: any) {
  return {
    bonus_id: safeNum(b.bonusId),
    contract_id: contractId,
    version_number: versionNumber,
    salary_year: safeNum(b.bonusYear),
    bonus_amount: safeBigInt(b.bonusAmount),
    bonus_type_lk: b.contractBonusTypeLk,
    is_likely: safeBool(b.bonusLikelyFlg),
    earned_lk: b.earnedLk,
    paid_by_date: b.bonusPaidByDate,
    clause_name: b.clauseName,
    criteria_description: b.criteriaDescription,
    criteria_json: b.bonusCriteria ? JSON.stringify(b.bonusCriteria) : null,
    ...provenance
  };
}

function transformSalary(s: any, contractId: number, versionNumber: number, provenance: any) {
  return {
    contract_id: contractId,
    version_number: versionNumber,
    salary_year: safeNum(s.salaryYear),
    total_salary: safeBigInt(s.totalSalary),
    total_salary_adjustment: safeBigInt(s.totalSalaryAdjustment),
    total_base_comp: safeBigInt(s.totalBaseComp),
    current_base_comp: safeBigInt(s.currentBaseComp),
    deferred_base_comp: safeBigInt(s.deferredBaseComp),
    signing_bonus: safeBigInt(s.signingBonus),
    likely_bonus: safeBigInt(s.likelyBonus),
    unlikely_bonus: safeBigInt(s.unlikelyBonus),
    contract_cap_salary: safeBigInt(s.contractCapSalary),
    contract_cap_salary_adjustment: safeBigInt(s.contractCapSalaryAdjustment),
    contract_tax_salary: safeBigInt(s.contractTaxSalary),
    contract_tax_salary_adjustment: safeBigInt(s.contractTaxSalaryAdjustment),
    contract_tax_apron_salary: safeBigInt(s.contractTaxApronSalary),
    contract_tax_apron_salary_adjustment: safeBigInt(s.contractTaxApronSalaryAdjustment),
    contract_mts_salary: safeBigInt(s.contractMtsSalary),
    skill_protection_amount: safeBigInt(s.skillProtectionAmount),
    trade_bonus_amount: safeBigInt(s.tradeBonusAmount),
    trade_bonus_amount_calc: safeBigInt(s.tradeBonusAmountCalc),
    cap_raise_percent: safeNum(s.capRaisePercent),
    two_way_nba_salary: safeBigInt(s.twoWayNbaSalary),
    two_way_dlg_salary: safeBigInt(s.twoWayDlgSalary),
    option_lk: s.optionLk,
    option_decision_lk: s.optionDecisionLk,
    is_applicable_min_salary: safeBool(s.applicableMinSalaryFlg),
    created_at: s.createDate,
    updated_at: s.lastChangeDate,
    record_changed_at: s.recordChangeDate,
    ...provenance
  };
}

function transformPaymentSchedule(ps: any, contractId: number, versionNumber: number, salaryYear: number, provenance: any) {
  return {
    payment_schedule_id: safeNum(ps.contractPaymentScheduleId),
    contract_id: contractId,
    version_number: versionNumber,
    salary_year: salaryYear,
    payment_amount: safeBigInt(ps.paymentAmount),
    payment_start_date: ps.paymentStartDate,
    schedule_type_lk: ps.paymentScheduleTypeLk,
    payment_type_lk: ps.contractPaymentTypeLk,
    is_default_schedule: safeBool(ps.defaultPaymentScheduleFlg),
    created_at: ps.createDate,
    updated_at: ps.lastChangeDate,
    record_changed_at: ps.recordChangeDate,
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
  const xmlFiles = readdirSync(extractDir).filter(f => f.includes('contract') && f.endsWith('.xml'));

  for (const xmlFile of xmlFiles) {
    const filePath = `${extractDir}/${xmlFile}`;
    console.log(`Processing ${xmlFile}...`);

    const contracts: any[] = [];
    const versions: any[] = [];
    const bonuses: any[] = [];
    const salaries: any[] = [];
    const schedules: any[] = [];
    const rawMap = new Map<string, any>();

    const provenance = {
      source_drop_file: row.s3_key,
      parser_version: PARSER_VERSION,
      ingested_at: new Date()
    };

    async function flush() {
      if (contracts.length === 0) return;
      if (!dry_run) {
        let res = await upsertBatch(sql, 'pcms', 'contracts', contracts, ['contract_id']);
        await auditUpsert(row.lineage_id, res, 'contract_id', rawMap);
        summary.tables.push(res);
        summary.tables.push(await upsertBatch(sql, 'pcms', 'contract_versions', versions, ['contract_id', 'version_number']));
        summary.tables.push(await upsertBatch(sql, 'pcms', 'contract_bonuses', bonuses, ['bonus_id']));
        summary.tables.push(await upsertBatch(sql, 'pcms', 'salaries', salaries, ['contract_id', 'version_number', 'salary_year']));
        summary.tables.push(await upsertBatch(sql, 'pcms', 'payment_schedules', schedules, ['payment_schedule_id']));
      } else {
        summary.tables.push({ table: 'pcms.contracts', attempted: contracts.length, success: true });
        summary.tables.push({ table: 'pcms.contract_versions', attempted: versions.length, success: true });
        summary.tables.push({ table: 'pcms.contract_bonuses', attempted: bonuses.length, success: true });
        summary.tables.push({ table: 'pcms.salaries', attempted: salaries.length, success: true });
        summary.tables.push({ table: 'pcms.payment_schedules', attempted: schedules.length, success: true });
      }
      contracts.length = 0;
      versions.length = 0;
      bonuses.length = 0;
      salaries.length = 0;
      schedules.length = 0;
      rawMap.clear();
    }

    const streamParser = new PCMSStreamParser('contract', async (c, rawXml) => {
      const contractId = safeNum(c.contractId);
      if (!contractId) return;

      const prov = { ...provenance, source_hash: hash(rawXml) };
      contracts.push(transformContract(c, prov));
      rawMap.set(String(contractId), c);

      if (c.versions && c.versions.version) {
        for (const v of c.versions.version) {
          const versionNum = safeNum(v.versionNumber);
          versions.push(transformContractVersion(v, contractId, prov));

          if (v.bonuses && v.bonuses.bonus) {
            for (const b of v.bonuses.bonus) {
              bonuses.push(transformContractBonus(b, contractId, versionNum, prov));
            }
          }

          if (v.salaries && v.salaries.salary) {
            for (const s of v.salaries.salary) {
              const salaryYear = safeNum(s.salaryYear);
              salaries.push(transformSalary(s, contractId, versionNum, prov));

              if (s.paymentSchedules && s.paymentSchedules.paymentSchedule && salaryYear) {
                for (const ps of s.paymentSchedules.paymentSchedule) {
                  schedules.push(transformPaymentSchedule(ps, contractId, versionNum, salaryYear, prov));
                }
              }
            }
          }
        }
      }

      if (contracts.length >= 100) await flush();
    }, (name) => ["version", "bonus", "contractYear", "contractProtection", "contractProtectionCondition",
      "contractBonusCriteria", "contractBonusMax", "salary", "paymentSchedule", "paymentScheduleDetail",
      "contract", "protectionType"].includes(name));

    const stream = createReadStream(filePath);
    for await (const chunk of stream) {
      await streamParser.parseChunk(chunk);
    }
    await flush();
  }

  return finalizeSummary(summary);
}
