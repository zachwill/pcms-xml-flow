/**
 * Team Budgets Import
 *
 * Reads clean JSON from lineage step and upserts into:
 * - pcms.team_budget_snapshots
 * - pcms.team_tax_summary_snapshots
 *
 * Clean JSON: team_budgets.json
 * Shape:
 *   {
 *     budget_teams: { budget_team: [ { team_id, "budget-entries": { "budget-entry": [...] } } ] },
 *     tax_teams: { tax_team: [ ... ] }
 *   }
 */
import { SQL } from "bun";
import { readdir } from "node:fs/promises";

const sql = new SQL({ url: Bun.env.POSTGRES_URL!, prepare: false });

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

function asArray<T = any>(val: any): T[] {
  if (val === null || val === undefined) return [];
  return Array.isArray(val) ? val : [val];
}

function normalizeVersionNumber(val: unknown): number | null {
  if (val === null || val === undefined || val === "") return null;

  const n = typeof val === "number" ? val : Number(val);
  if (!Number.isFinite(n)) return null;

  // PCMS sometimes represents version_number as a decimal like 1.01
  // Schema expects an integer (1.01 -> 101)
  return Number.isInteger(n) ? n : Math.round(n * 100);
}

function sha256(data: string): string {
  return new Bun.CryptoHasher("sha256").update(data).digest("hex");
}

// ─────────────────────────────────────────────────────────────────────────────
// Main
// ─────────────────────────────────────────────────────────────────────────────

export async function main(
  dry_run = false,
  lineage_id?: number,
  s3_key?: string,
  extract_dir = "./shared/pcms"
) {
  const startedAt = new Date().toISOString();
  void lineage_id;

  try {
    // Find extract directory
    const entries = await readdir(extract_dir, { withFileTypes: true });
    const subDir = entries.find((e) => e.isDirectory());
    const baseDir = subDir ? `${extract_dir}/${subDir.name}` : extract_dir;

    const teamBudgetsFile = Bun.file(`${baseDir}/team_budgets.json`);
    if (!(await teamBudgetsFile.exists())) {
      throw new Error(`team_budgets.json not found in ${baseDir}`);
    }

    // Read clean JSON
    const data: any = await teamBudgetsFile.json();

    const budgetTeams = asArray<any>(data?.budget_teams?.budget_team);
    const taxTeams = asArray<any>(data?.tax_teams?.tax_team);

    const ingestedAt = new Date();
    const provenance = {
      source_drop_file: s3_key,
      ingested_at: ingestedAt,
    };

    // ─────────────────────────────────────────────────────────────────────────
    // Flatten budget teams
    // ─────────────────────────────────────────────────────────────────────────

    const budgetRows: any[] = [];

    for (const bt of budgetTeams) {
      const teamId = bt?.team_id;
      if (!teamId) continue;

      const budgetEntries = asArray<any>(bt?.["budget-entries"]?.["budget-entry"]);

      for (const entry of budgetEntries) {
        const amounts = asArray<any>(entry?.budget_amounts_per_year?.budget_amount);

        for (const amount of amounts) {
          budgetRows.push({
            team_id: teamId,
            salary_year: amount?.year ?? null,

            player_id: entry?.player_id ?? null,
            contract_id: entry?.contract_id ?? null,
            transaction_id: entry?.transaction_id ?? null,
            transaction_type_lk: entry?.transaction_type_lk ?? null,
            transaction_description_lk: entry?.transaction_description_lk ?? null,

            budget_group_lk: entry?.budget_group_lk ?? null,
            contract_type_lk: entry?.contract_type_lk ?? null,
            free_agent_designation_lk: entry?.free_agent_designation_lk ?? null,
            free_agent_status_lk: entry?.free_agent_status_lk ?? null,
            signing_method_lk: entry?.signed_method_lk ?? null,
            overall_contract_bonus_type_lk: entry?.overall_contract_bonus_type_lk ?? null,
            overall_protection_coverage_lk: entry?.overall_protection_coverage_lk ?? null,
            max_contract_lk: entry?.max_contract_lk ?? null,

            years_of_service: entry?.year_of_service ?? null,
            ledger_date: entry?.ledger_date ?? null,
            signing_date: entry?.signing_date ?? null,
            version_number: normalizeVersionNumber(entry?.version_number),

            cap_amount: amount?.cap_amount ?? null,
            tax_amount: amount?.tax_amount ?? null,
            mts_amount: amount?.mts_amount ?? null,
            apron_amount: amount?.apron_amount ?? null,
            is_fa_amount: amount?.fa_amount_flg ?? null,
            option_lk: amount?.option_lk ?? null,
            option_decision_lk: amount?.option_decision_lk ?? null,

            ...provenance,
          });
        }
      }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Flatten tax teams
    // ─────────────────────────────────────────────────────────────────────────

    const taxRows = taxTeams
      .filter((t) => t?.team_id && t?.salary_year)
      .map((t) => ({
        team_id: t.team_id,
        salary_year: t.salary_year,
        is_taxpayer: t.taxpayer_flg ?? null,
        is_repeater_taxpayer: t.taxpayer_repeater_rate_flg ?? null,
        is_subject_to_apron: t.subject_to_apron_flg ?? null,
        subject_to_apron_reason_lk: t.subject_to_apron_reason_lk ?? null,
        apron_level_lk: t.apron_level_lk ?? null,
        apron1_transaction_id: t.apron1_transaction_id ?? null,
        apron2_transaction_id: t.apron2_transaction_id ?? null,
        record_changed_at: t.record_change_date ?? null,
        created_at: t.create_date ?? null,
        updated_at: t.last_change_date ?? null,
        source_hash: sha256(JSON.stringify(t)),
        ...provenance,
      }));

    console.log(
      `Prepared rows: team_budget_snapshots=${budgetRows.length}, team_tax_summary_snapshots=${taxRows.length}`
    );

    // ─────────────────────────────────────────────────────────────────────────
    // Dry run
    // ─────────────────────────────────────────────────────────────────────────

    if (dry_run) {
      return {
        dry_run: true,
        started_at: startedAt,
        finished_at: new Date().toISOString(),
        tables: [
          { table: "pcms.team_budget_snapshots", attempted: budgetRows.length, success: true },
          { table: "pcms.team_tax_summary_snapshots", attempted: taxRows.length, success: true },
        ],
        errors: [],
      };
    }

    const BATCH_SIZE = 1000;
    const tables: { table: string; attempted: number; success: boolean }[] = [];

    // ─────────────────────────────────────────────────────────────────────────
    // Upsert: team_budget_snapshots
    // ─────────────────────────────────────────────────────────────────────────

    for (let i = 0; i < budgetRows.length; i += BATCH_SIZE) {
      const rows = budgetRows.slice(i, i + BATCH_SIZE);
      await sql`
        INSERT INTO pcms.team_budget_snapshots ${sql(rows)}
        ON CONFLICT (team_id, salary_year, transaction_id, budget_group_lk, player_id, contract_id, version_number)
        DO UPDATE SET
          transaction_type_lk = EXCLUDED.transaction_type_lk,
          transaction_description_lk = EXCLUDED.transaction_description_lk,
          contract_type_lk = EXCLUDED.contract_type_lk,
          free_agent_designation_lk = EXCLUDED.free_agent_designation_lk,
          free_agent_status_lk = EXCLUDED.free_agent_status_lk,
          signing_method_lk = EXCLUDED.signing_method_lk,
          overall_contract_bonus_type_lk = EXCLUDED.overall_contract_bonus_type_lk,
          overall_protection_coverage_lk = EXCLUDED.overall_protection_coverage_lk,
          max_contract_lk = EXCLUDED.max_contract_lk,
          years_of_service = EXCLUDED.years_of_service,
          ledger_date = EXCLUDED.ledger_date,
          signing_date = EXCLUDED.signing_date,
          cap_amount = EXCLUDED.cap_amount,
          tax_amount = EXCLUDED.tax_amount,
          mts_amount = EXCLUDED.mts_amount,
          apron_amount = EXCLUDED.apron_amount,
          is_fa_amount = EXCLUDED.is_fa_amount,
          option_lk = EXCLUDED.option_lk,
          option_decision_lk = EXCLUDED.option_decision_lk,
          source_drop_file = EXCLUDED.source_drop_file,
          ingested_at = EXCLUDED.ingested_at
      `;
    }
    tables.push({ table: "pcms.team_budget_snapshots", attempted: budgetRows.length, success: true });

    // ─────────────────────────────────────────────────────────────────────────
    // Upsert: team_tax_summary_snapshots
    // ─────────────────────────────────────────────────────────────────────────

    for (let i = 0; i < taxRows.length; i += BATCH_SIZE) {
      const rows = taxRows.slice(i, i + BATCH_SIZE);
      await sql`
        INSERT INTO pcms.team_tax_summary_snapshots ${sql(rows)}
        ON CONFLICT (team_id, salary_year, source_hash)
        DO UPDATE SET
          is_taxpayer = EXCLUDED.is_taxpayer,
          is_repeater_taxpayer = EXCLUDED.is_repeater_taxpayer,
          is_subject_to_apron = EXCLUDED.is_subject_to_apron,
          subject_to_apron_reason_lk = EXCLUDED.subject_to_apron_reason_lk,
          apron_level_lk = EXCLUDED.apron_level_lk,
          apron1_transaction_id = EXCLUDED.apron1_transaction_id,
          apron2_transaction_id = EXCLUDED.apron2_transaction_id,
          record_changed_at = EXCLUDED.record_changed_at,
          created_at = EXCLUDED.created_at,
          updated_at = EXCLUDED.updated_at,
          source_drop_file = EXCLUDED.source_drop_file,
          ingested_at = EXCLUDED.ingested_at
      `;
    }
    tables.push({ table: "pcms.team_tax_summary_snapshots", attempted: taxRows.length, success: true });

    return {
      dry_run: false,
      started_at: startedAt,
      finished_at: new Date().toISOString(),
      tables,
      errors: [],
    };
  } catch (e: any) {
    return {
      dry_run,
      started_at: startedAt,
      finished_at: new Date().toISOString(),
      tables: [],
      errors: [e.message],
    };
  }
}
