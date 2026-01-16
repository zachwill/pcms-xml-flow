/**
 * Team Budgets Import
 *
 * Reads pre-parsed JSON from shared extract dir (created by lineage step), then
 * upserts into:
 * - pcms.team_budget_snapshots
 * - pcms.team_tax_summary_snapshots
 *
 * Source JSON: *_team-budget.json
 * Path:
 *   data["xml-extract"]["team-budget-extract"]["budgetTeams"]["budgetTeam"]
 *   data["xml-extract"]["team-budget-extract"]["taxTeams"]["taxTeam"]
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

/**
 * PCMS versionNumber is sometimes represented as a decimal like 1.02.
 * The schema uses integer version_number; we normalize by multiplying
 * decimals by 100 (e.g., 1.02 -> 102). Integers are passed through.
 */
function safeVersionNum(val: unknown): number | null {
  const n = safeNum(val);
  if (n === null) return null;
  if (Number.isInteger(n)) return n;
  return Math.round(n * 100);
}

function parsePCMSDate(val: unknown): string | null {
  const v = safeStr(val);
  if (!v || v === "0001-01-01") return null;
  return !isNaN(Date.parse(v)) ? v : null;
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

function transformBudgetSnapshot(teamId: unknown, entry: any, amount: any, provenance: any) {
  return {
    team_id: safeNum(teamId),
    salary_year: safeNum(amount?.year),

    player_id: safeNum(entry?.playerId),
    contract_id: safeNum(entry?.contractId),
    transaction_id: safeNum(entry?.transactionId),
    transaction_type_lk: safeStr(entry?.transactionTypeLk),
    transaction_description_lk: safeStr(entry?.transactionDescriptionLk),

    budget_group_lk: safeStr(entry?.budgetGroupLk),
    contract_type_lk: safeStr(entry?.contractTypeLk),
    free_agent_designation_lk: safeStr(entry?.freeAgentDesignationLk),
    free_agent_status_lk: safeStr(entry?.freeAgentStatusLk),
    signing_method_lk: safeStr(entry?.signedMethodLk),
    overall_contract_bonus_type_lk: safeStr(entry?.overallContractBonusTypeLk),
    overall_protection_coverage_lk: safeStr(entry?.overallProtectionCoverageLk),
    max_contract_lk: safeStr(entry?.maxContractLk),

    years_of_service: safeNum(entry?.yearOfService),
    ledger_date: parsePCMSDate(entry?.ledgerDate),
    signing_date: parsePCMSDate(entry?.signingDate),
    version_number: safeVersionNum(entry?.versionNumber),

    cap_amount: safeBigInt(amount?.capAmount),
    tax_amount: safeBigInt(amount?.taxAmount),
    mts_amount: safeBigInt(amount?.mtsAmount),
    apron_amount: safeBigInt(amount?.apronAmount),
    is_fa_amount: safeBool(amount?.faAmountFlg),
    option_lk: safeStr(amount?.optionLk),
    option_decision_lk: safeStr(amount?.optionDecisionLk),

    ...provenance,
  };
}

function transformTaxSummarySnapshot(t: any, provenance: any) {
  return {
    team_id: safeNum(t?.teamId),
    salary_year: safeNum(t?.salaryYear),
    is_taxpayer: safeBool(t?.taxpayerFlg),
    is_repeater_taxpayer: safeBool(t?.taxpayerRepeaterRateFlg),
    is_subject_to_apron: safeBool(t?.subjectToApronFlg),
    subject_to_apron_reason_lk: safeStr(t?.subjectToApronReasonLk),
    apron_level_lk: safeStr(t?.apronLevelLk),
    apron1_transaction_id: safeNum(t?.apron1TransactionId),
    apron2_transaction_id: safeNum(t?.apron2TransactionId),
    record_changed_at: parsePCMSDate(t?.recordChangeDate),
    created_at: parsePCMSDate(t?.createDate),
    updated_at: parsePCMSDate(t?.lastChangeDate),
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

    // Find JSON file
    const allFiles = await readdir(baseDir);
    const teamBudgetJsonFile = allFiles.find((f) => f.includes("team-budget") && f.endsWith(".json"));
    if (!teamBudgetJsonFile) {
      throw new Error(`No team-budget JSON file found in ${baseDir}`);
    }

    // Read pre-parsed JSON
    console.log(`Reading ${teamBudgetJsonFile}...`);
    const data = await Bun.file(`${baseDir}/${teamBudgetJsonFile}`).json();

    const budgetTeams = asArray<any>(
      data?.["xml-extract"]?.["team-budget-extract"]?.budgetTeams?.budgetTeam
    );
    const taxTeams = asArray<any>(data?.["xml-extract"]?.["team-budget-extract"]?.taxTeams?.taxTeam);

    console.log(`Found ${budgetTeams.length} budgetTeams, ${taxTeams.length} taxTeams`);

    const provenanceBase = {
      source_drop_file: effectiveS3Key,
      parser_version: PARSER_VERSION,
      ingested_at: new Date(),
    };

    // -------------------------------------------------------------------------
    // team_budget_snapshots
    // -------------------------------------------------------------------------

    const budgetRows: any[] = [];

    for (const bt of budgetTeams) {
      const teamId = bt?.teamId;
      const budgetEntries = asArray<any>(bt?.["budget-entries"]?.["budget-entry"]);

      for (const entry of budgetEntries) {
        const amounts = asArray<any>(entry?.budgetAmountsPerYear?.budgetAmount);
        for (const amount of amounts) {
          const sourceHash = hash(
            JSON.stringify({
              teamId,
              year: amount?.year,
              transactionId: entry?.transactionId,
              playerId: entry?.playerId,
              contractId: entry?.contractId,
              budgetGroupLk: entry?.budgetGroupLk,
              versionNumber: entry?.versionNumber,
              capAmount: amount?.capAmount,
              taxAmount: amount?.taxAmount,
              mtsAmount: amount?.mtsAmount,
              apronAmount: amount?.apronAmount,
              faAmountFlg: amount?.faAmountFlg,
              optionLk: amount?.optionLk,
              optionDecisionLk: amount?.optionDecisionLk,
            })
          );

          const row = transformBudgetSnapshot(teamId, entry, amount, {
            ...provenanceBase,
            source_hash: sourceHash,
          });

          budgetRows.push(row);
        }
      }
    }

    const BATCH_SIZE = 500;
    const budgetPk = [
      "team_id",
      "salary_year",
      "transaction_id",
      "budget_group_lk",
      "player_id",
      "contract_id",
      "version_number",
    ];

    for (let i = 0; i < budgetRows.length; i += BATCH_SIZE) {
      const batch = budgetRows.slice(i, i + BATCH_SIZE);

      if (!dry_run) {
        const result = await upsertBatch("pcms", "team_budget_snapshots", batch, budgetPk);
        tables.push(result);
        if (!result.success) errors.push(result.error!);
      } else {
        tables.push({ table: "pcms.team_budget_snapshots", attempted: batch.length, success: true });
      }
    }

    // -------------------------------------------------------------------------
    // team_tax_summary_snapshots
    // -------------------------------------------------------------------------

    if (taxTeams.length > 0) {
      const taxRows = taxTeams.map((t) => ({
        ...transformTaxSummarySnapshot(t, provenanceBase),
        source_hash: hash(JSON.stringify(t)),
      }));

      for (let i = 0; i < taxRows.length; i += BATCH_SIZE) {
        const batch = taxRows.slice(i, i + BATCH_SIZE);

        if (!dry_run) {
          const result = await upsertBatch("pcms", "team_tax_summary_snapshots", batch, [
            "team_id",
            "salary_year",
            "source_hash",
          ]);
          tables.push(result);
          if (!result.success) errors.push(result.error!);
        } else {
          tables.push({ table: "pcms.team_tax_summary_snapshots", attempted: batch.length, success: true });
        }
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
