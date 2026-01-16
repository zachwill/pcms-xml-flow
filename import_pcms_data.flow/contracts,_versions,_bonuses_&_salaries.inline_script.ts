/**
 * Contracts / Versions / Bonuses / Salaries Import
 *
 * Reads pre-parsed JSON from shared extract dir (created by lineage step), then
 * upserts into:
 * - pcms.contracts
 * - pcms.contract_versions
 * - pcms.contract_bonuses
 * - pcms.salaries
 * - pcms.payment_schedules
 */
import { SQL } from "bun";
import { readdir } from "node:fs/promises";

const sql = new SQL({ url: Bun.env.POSTGRES_URL!, prepare: false });
const PARSER_VERSION = "2.1.0";
const SHARED_DIR = "./shared/pcms";

// ─────────────────────────────────────────────────────────────────────────────
// Types
// ─────────────────────────────────────────────────────────────────────────────

interface LineageContext {
  lineage_id: number;
  s3_key: string;
  source_hash: string;
}

interface UpsertResult {
  table: string;
  attempted: number;
  success: boolean;
  error?: string;
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

function hash(data: string): string {
  return new Bun.CryptoHasher("sha256").update(data).digest("hex");
}

function nilSafe(val: unknown): unknown {
  if (val && typeof val === "object" && "@_xsi:nil" in val) return null;
  return val;
}

function safeNum(val: unknown): number | null {
  const v = nilSafe(val);
  if (v === null || v === undefined || v === "") return null;
  if (typeof v === "object") return null;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

/**
 * PCMS versionNumber is sometimes represented as a decimal like 1.01.
 * The schema uses integer version_number; we normalize by multiplying
 * decimals by 100 (e.g., 1.01 -> 101). Integers are passed through.
 */
function safeVersionNum(val: unknown): number | null {
  const n = safeNum(val);
  if (n === null) return null;
  if (Number.isInteger(n)) return n;
  return Math.round(n * 100);
}

function safeStr(val: unknown): string | null {
  const v = nilSafe(val);
  if (v === null || v === undefined || v === "") return null;
  if (typeof v === "object") return null;
  return String(v);
}

function safeBool(val: unknown): boolean | null {
  const v = nilSafe(val);
  if (v === null || v === undefined) return null;
  if (typeof v === "boolean") return v;
  if (v === 1 || v === "1" || v === "Y" || v === "true" || v === true) return true;
  if (v === 0 || v === "0" || v === "N" || v === "false" || v === false) return false;
  return null;
}

function safeBigInt(val: unknown): string | null {
  const v = nilSafe(val);
  if (v === null || v === undefined || v === "") return null;
  if (typeof v === "object") return null;
  try {
    return BigInt(Math.round(Number(v))).toString();
  } catch {
    return null;
  }
}

function asArray<T = any>(val: unknown): T[] {
  const v = nilSafe(val);
  if (v === null || v === undefined) return [];
  return Array.isArray(v) ? (v as T[]) : ([v] as T[]);
}

async function getLineageContext(extractDir: string): Promise<LineageContext> {
  const lineageFile = `${extractDir}/lineage.json`;
  const file = Bun.file(lineageFile);
  if (await file.exists()) {
    return await file.json();
  }
  throw new Error(`Lineage file not found: ${lineageFile}`);
}

async function upsertBatch<T extends Record<string, unknown>>(
  schema: string,
  table: string,
  rows: T[],
  conflictColumns: string[]
): Promise<UpsertResult> {
  const fullTable = `${schema}.${table}`;
  if (rows.length === 0) {
    return { table: fullTable, attempted: 0, success: true };
  }

  try {
    const allColumns = Object.keys(rows[0]);
    const updateColumns = allColumns.filter((col) => !conflictColumns.includes(col));
    const setClauses = updateColumns.map((col) => `${col} = EXCLUDED.${col}`).join(", ");
    const conflictTarget = conflictColumns.join(", ");

    const query = `
      INSERT INTO ${fullTable} (${allColumns.join(", ")})
      SELECT * FROM jsonb_populate_recordset(null::${fullTable}, $1::jsonb)
      ON CONFLICT (${conflictTarget}) DO UPDATE SET ${setClauses}
      WHERE ${fullTable}.source_hash IS DISTINCT FROM EXCLUDED.source_hash
    `;

    await sql.unsafe(query, [JSON.stringify(rows)]);
    return { table: fullTable, attempted: rows.length, success: true };
  } catch (error) {
    const msg = error instanceof Error ? error.message : String(error);
    return { table: fullTable, attempted: rows.length, success: false, error: msg };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Transformers
// ─────────────────────────────────────────────────────────────────────────────

function transformContract(c: any, provenance: any) {
  return {
    contract_id: safeNum(c.contractId),
    player_id: safeNum(c.playerId),
    signing_team_id: safeNum(c.signingTeamId),
    signing_date: safeStr(c.signingDate),
    contract_end_date: safeStr(c.contractEndDate),
    record_status_lk: safeStr(c.recordStatusLk),
    signed_method_lk: safeStr(c.signedMethodLk),
    team_exception_id: safeNum(c.teamExceptionId),
    is_sign_and_trade: safeBool(c.signAndTradeFlg),
    sign_and_trade_date: safeStr(c.signAndTradeDate),
    sign_and_trade_to_team_id: safeNum(c.signAndTradeToTeamId),
    sign_and_trade_id: safeNum(c.signAndTradeId),
    start_year: safeNum(c.startYear),
    contract_length_wnba: safeStr(c.contractLength),
    convert_date: safeStr(c.convertDate),
    two_way_service_limit: safeNum(c.twoWayServiceLimit),
    created_at: safeStr(c.createDate),
    updated_at: safeStr(c.lastChangeDate),
    record_changed_at: safeStr(c.recordChangeDate),
    ...provenance,
  };
}

function transformContractVersion(v: any, contractId: number, provenance: any) {
  const { salaries: _salaries, bonuses: _bonuses, ...rest } = v ?? {};

  return {
    contract_id: contractId,
    version_number: safeVersionNum(v.versionNumber),
    transaction_id: safeNum(v.transactionId),
    version_date: safeStr(v.versionDate),
    start_salary_year: safeNum(v.startYear),
    contract_length: safeNum(v.contractLength),
    contract_type_lk: safeStr(v.contractTypeLk),
    record_status_lk: safeStr(v.recordStatusLk),
    agency_id: safeNum(v.agencyId),
    agent_id: safeNum(v.agentId),
    is_full_protection: safeBool(v.fullProtectionFlg),
    is_exhibit_10: safeBool(v.exhibit10),
    exhibit_10_bonus_amount: safeBigInt(v.exhibit10BonusAmount),
    exhibit_10_protection_amount: safeBigInt(v.exhibit10ProtectionAmount),
    exhibit_10_end_date: safeStr(v.exhibit10EndDate),
    is_two_way: safeBool(v.isTwoWay),
    is_rookie_scale_extension: safeBool(v.dpRookieScaleExtensionFlg),
    is_veteran_extension: safeBool(v.dpVeteranExtensionFlg),
    is_poison_pill: safeBool(v.poisonPillFlg),
    poison_pill_amount: safeBigInt(v.poisonPillAmt),
    trade_bonus_percent: safeNum(v.tradeBonusPercent),
    trade_bonus_amount: safeBigInt(v.tradeBonusAmount),
    is_trade_bonus: safeBool(v.tradeBonusFlg),
    is_no_trade: safeBool(v.noTradeFlg),
    is_minimum_contract: null,
    is_protected_contract: null,
    version_json: Object.keys(rest).length > 0 ? rest : null,
    created_at: safeStr(v.createDate),
    updated_at: safeStr(v.lastChangeDate),
    record_changed_at: safeStr(v.recordChangeDate),
    ...provenance,
  };
}

function transformContractBonus(b: any, contractId: number, versionNumber: number, provenance: any) {
  return {
    bonus_id: safeNum(b.bonusId),
    contract_id: contractId,
    version_number: versionNumber,
    salary_year: safeNum(b.bonusYear),
    bonus_amount: safeBigInt(b.bonusAmount),
    bonus_type_lk: safeStr(b.contractBonusTypeLk),
    is_likely: safeBool(b.bonusLikelyFlg),
    earned_lk: safeStr(b.earnedLk),
    paid_by_date: safeStr(b.bonusPaidByDate),
    clause_name: safeStr(b.clauseName),
    criteria_description: safeStr(b.criteriaDescription),
    criteria_json: nilSafe(b.bonusCriteria),
    ...provenance,
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
    option_lk: safeStr(s.optionLk),
    option_decision_lk: safeStr(s.optionDecisionLk),
    is_applicable_min_salary: safeBool(s.applicableMinSalaryFlg),
    created_at: safeStr(s.createDate),
    updated_at: safeStr(s.lastChangeDate),
    record_changed_at: safeStr(s.recordChangeDate),
    ...provenance,
  };
}

function transformPaymentSchedule(
  ps: any,
  contractId: number,
  versionNumber: number,
  salaryYear: number,
  provenance: any
) {
  return {
    payment_schedule_id: safeNum(ps.contractPaymentScheduleId),
    contract_id: contractId,
    version_number: versionNumber,
    salary_year: salaryYear,
    payment_amount: safeBigInt(ps.paymentAmount),
    payment_start_date: safeStr(ps.paymentStartDate),
    schedule_type_lk: safeStr(ps.paymentScheduleTypeLk),
    payment_type_lk: safeStr(ps.contractPaymentTypeLk),
    is_default_schedule: safeBool(ps.defaultPaymentScheduleFlg),
    created_at: safeStr(ps.createDate),
    updated_at: safeStr(ps.lastChangeDate),
    record_changed_at: safeStr(ps.recordChangeDate),
    ...provenance,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Main
// ─────────────────────────────────────────────────────────────────────────────

export async function main(
  dry_run = false,
  lineage_id?: number,
  s3_key?: string,
  extract_dir: string = SHARED_DIR
) {
  const startedAt = new Date().toISOString();
  const tables: UpsertResult[] = [];
  const errors: string[] = [];

  try {
    // Find the actual extract directory
    const entries = await readdir(extract_dir, { withFileTypes: true });
    const subDir = entries.find((e) => e.isDirectory());
    const baseDir = subDir ? `${extract_dir}/${subDir.name}` : extract_dir;

    // Get lineage context
    const ctx = await getLineageContext(baseDir);
    const effectiveLineageId = lineage_id ?? ctx.lineage_id;
    const effectiveS3Key = s3_key ?? ctx.s3_key;
    void effectiveLineageId; // lineage_id is not stored on these tables, but available for debugging

    // Find JSON file
    const allFiles = await readdir(baseDir);
    const contractJsonFile = allFiles.find((f) => f.includes("contract") && f.endsWith(".json"));
    if (!contractJsonFile) {
      throw new Error(`No contract JSON file found in ${baseDir}`);
    }

    // Read pre-parsed JSON
    console.log(`Reading ${contractJsonFile}...`);
    const data = await Bun.file(`${baseDir}/${contractJsonFile}`).json();

    // Extract contracts array
    const contracts: any[] = asArray(data?.["xml-extract"]?.["contract-extract"]?.contract);
    console.log(`Found ${contracts.length} contracts`);

    // Build provenance
    const baseProvenance = {
      source_drop_file: effectiveS3Key,
      parser_version: PARSER_VERSION,
      ingested_at: new Date(),
    };

    const contractRows: any[] = [];
    const versionRows: any[] = [];
    const bonusRows: any[] = [];
    const salaryRows: any[] = [];
    const paymentScheduleRows: any[] = [];

    for (const c of contracts) {
      const contractId = safeNum(c.contractId);
      if (!contractId) continue;

      const contractProv = {
        ...baseProvenance,
        source_hash: hash(JSON.stringify(c)),
      };

      contractRows.push(transformContract(c, contractProv));

      const versions = asArray(c?.versions?.version);
      for (const v of versions) {
        const versionNum = safeVersionNum(v?.versionNumber);
        if (!versionNum) continue;

        const versionProv = {
          ...baseProvenance,
          source_hash: hash(JSON.stringify(v)),
        };

        versionRows.push(transformContractVersion(v, contractId, versionProv));

        const bonuses = asArray(v?.bonuses?.bonus);
        for (const b of bonuses) {
          const bonusId = safeNum(b?.bonusId);
          if (!bonusId) continue;

          const bonusProv = {
            ...baseProvenance,
            source_hash: hash(JSON.stringify(b)),
          };

          bonusRows.push(transformContractBonus(b, contractId, versionNum, bonusProv));
        }

        const salaries = asArray(v?.salaries?.salary);
        for (const s of salaries) {
          const salaryYear = safeNum(s?.salaryYear);
          if (!salaryYear) continue;

          const salaryProv = {
            ...baseProvenance,
            source_hash: hash(JSON.stringify(s)),
          };

          salaryRows.push(transformSalary(s, contractId, versionNum, salaryProv));

          const paymentSchedules = asArray(s?.paymentSchedules?.paymentSchedule);
          for (const ps of paymentSchedules) {
            const psId = safeNum(ps?.contractPaymentScheduleId);
            if (!psId) continue;

            const psProv = {
              ...baseProvenance,
              source_hash: hash(JSON.stringify(ps)),
            };

            paymentScheduleRows.push(
              transformPaymentSchedule(ps, contractId, versionNum, salaryYear, psProv)
            );
          }
        }
      }
    }

    console.log(
      `Prepared rows: contracts=${contractRows.length}, versions=${versionRows.length}, bonuses=${bonusRows.length}, salaries=${salaryRows.length}, payment_schedules=${paymentScheduleRows.length}`
    );

    const BATCH_SIZE = 500;

    // Upsert contracts
    for (let i = 0; i < contractRows.length; i += BATCH_SIZE) {
      const rows = contractRows.slice(i, i + BATCH_SIZE);
      if (!dry_run) {
        const result = await upsertBatch("pcms", "contracts", rows, ["contract_id"]);
        tables.push(result);
        if (!result.success) errors.push(result.error!);
      } else {
        tables.push({ table: "pcms.contracts", attempted: rows.length, success: true });
      }
    }

    // Upsert versions
    for (let i = 0; i < versionRows.length; i += BATCH_SIZE) {
      const rows = versionRows.slice(i, i + BATCH_SIZE);
      if (!dry_run) {
        const result = await upsertBatch("pcms", "contract_versions", rows, [
          "contract_id",
          "version_number",
        ]);
        tables.push(result);
        if (!result.success) errors.push(result.error!);
      } else {
        tables.push({ table: "pcms.contract_versions", attempted: rows.length, success: true });
      }
    }

    // Upsert bonuses
    for (let i = 0; i < bonusRows.length; i += BATCH_SIZE) {
      const rows = bonusRows.slice(i, i + BATCH_SIZE);
      if (!dry_run) {
        const result = await upsertBatch("pcms", "contract_bonuses", rows, ["bonus_id"]);
        tables.push(result);
        if (!result.success) errors.push(result.error!);
      } else {
        tables.push({ table: "pcms.contract_bonuses", attempted: rows.length, success: true });
      }
    }

    // Upsert salaries
    for (let i = 0; i < salaryRows.length; i += BATCH_SIZE) {
      const rows = salaryRows.slice(i, i + BATCH_SIZE);
      if (!dry_run) {
        const result = await upsertBatch("pcms", "salaries", rows, [
          "contract_id",
          "version_number",
          "salary_year",
        ]);
        tables.push(result);
        if (!result.success) errors.push(result.error!);
      } else {
        tables.push({ table: "pcms.salaries", attempted: rows.length, success: true });
      }
    }

    // Upsert payment schedules
    for (let i = 0; i < paymentScheduleRows.length; i += BATCH_SIZE) {
      const rows = paymentScheduleRows.slice(i, i + BATCH_SIZE);
      if (!dry_run) {
        const result = await upsertBatch("pcms", "payment_schedules", rows, [
          "payment_schedule_id",
        ]);
        tables.push(result);
        if (!result.success) errors.push(result.error!);
      } else {
        tables.push({ table: "pcms.payment_schedules", attempted: rows.length, success: true });
      }
    }

    return {
      dry_run,
      started_at: startedAt,
      finished_at: new Date().toISOString(),
      tables,
      errors,
    };
  } catch (e: any) {
    errors.push(e.message);
    return {
      dry_run,
      started_at: startedAt,
      finished_at: new Date().toISOString(),
      tables,
      errors,
    };
  }
}
