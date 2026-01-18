/**
 * Team Financials Import (consolidated)
 *
 * Merges:
 *  - team_budgets.inline_script.ts
 *  - waiver_priority_&_ranks.inline_script.ts (waiver tables + tax_team_status only)
 *  - team_transactions.inline_script.ts
 *
 * Upserts into:
 *  - pcms.team_budget_snapshots        (team_budgets.json)
 *  - pcms.team_tax_summary_snapshots   (team_budgets.json -> tax_teams)
 *  - pcms.tax_team_status              (tax_teams.json)
 *  - pcms.waiver_priority              (waiver_priority.json)
 *  - pcms.waiver_priority_ranks        (waiver_priority.json)
 *  - pcms.team_transactions            (team_transactions.json)
 *
 * Notes:
 *  - Clean JSON already has snake_case keys + nulls.
 *  - league_tax_rates is handled by league_config.inline_script.ts.
 */

import { SQL } from "bun";
import { readdir } from "node:fs/promises";

const sql = new SQL({ url: Bun.env.POSTGRES_URL!, prepare: false });

// ─────────────────────────────────────────────────────────────────────────────
// Helpers (inline)
// ─────────────────────────────────────────────────────────────────────────────

function asArray<T = any>(val: any): T[] {
  if (val === null || val === undefined) return [];
  return Array.isArray(val) ? val : [val];
}

function toIntOrNull(val: unknown): number | null {
  if (val === "" || val === null || val === undefined) return null;
  const n = Number(val);
  return Number.isFinite(n) ? Math.trunc(n) : null;
}

function toBoolOrNull(val: unknown): boolean | null {
  if (val === null || val === undefined || val === "") return null;
  if (typeof val === "boolean") return val;
  if (val === 0 || val === "0" || val === "false") return false;
  if (val === 1 || val === "1" || val === "true") return true;
  return null;
}

function normalizeVersionNumber(val: unknown): number | null {
  if (val === null || val === undefined || val === "") return null;

  const n = typeof val === "number" ? val : Number(val);
  if (!Number.isFinite(n)) return null;

  // PCMS sometimes represents version_number as a decimal like 1.01
  // Schema expects an integer (1.01 -> 101)
  return Number.isInteger(n) ? n : Math.round(n * 100);
}

async function resolveBaseDir(extractDir: string): Promise<string> {
  const entries = await readdir(extractDir, { withFileTypes: true });
  const subDir = entries.find((e) => e.isDirectory());
  return subDir ? `${extractDir}/${subDir.name}` : extractDir;
}

function buildTeamCodeMap(lookups: any): Map<number, string> {
  const teamsData: any[] = lookups?.lk_teams?.lk_team || [];
  const teamCodeMap = new Map<number, string>();
  for (const t of teamsData) {
    const teamId = t?.team_id;
    const teamCode = t?.team_code ?? t?.team_name_short;
    if (teamId && teamCode) teamCodeMap.set(Number(teamId), String(teamCode));
  }
  return teamCodeMap;
}

function dedupeByKey<T>(rows: T[], keyFn: (row: T) => string): T[] {
  const seen = new Map<string, T>();
  for (const r of rows) seen.set(keyFn(r), r);
  return [...seen.values()];
}

// ─────────────────────────────────────────────────────────────────────────────
// Main
// ─────────────────────────────────────────────────────────────────────────────

export async function main(dry_run = false, extract_dir = "./shared/pcms") {
  const startedAt = new Date().toISOString();
  const tables: { table: string; attempted: number; success: boolean }[] = [];

  try {
    const baseDir = await resolveBaseDir(extract_dir);

    // Build team_id → team_code lookup map (used in multiple tables)
    const lookupsFile = Bun.file(`${baseDir}/lookups.json`);
    const lookups: any = (await lookupsFile.exists()) ? await lookupsFile.json() : {};
    const teamCodeMap = buildTeamCodeMap(lookups);

    // Files
    const teamBudgetsFile = Bun.file(`${baseDir}/team_budgets.json`);
    if (!(await teamBudgetsFile.exists())) {
      throw new Error(`team_budgets.json not found in ${baseDir}`);
    }

    const waiverFile = Bun.file(`${baseDir}/waiver_priority.json`);
    const taxTeamsFile = Bun.file(`${baseDir}/tax_teams.json`);
    const teamTxFile = Bun.file(`${baseDir}/team_transactions.json`);

    // Read clean JSON
    const teamBudgetsData: any = await teamBudgetsFile.json();

    const waiverExtract: any = (await waiverFile.exists()) ? await waiverFile.json() : null;
    const taxTeams: any[] = (await taxTeamsFile.exists()) ? await taxTeamsFile.json() : [];
    const teamTx: any[] = (await teamTxFile.exists()) ? await teamTxFile.json() : [];

    const budgetTeams = asArray<any>(teamBudgetsData?.budget_teams?.budget_team);
    const taxSummaryTeams = asArray<any>(teamBudgetsData?.tax_teams?.tax_team);

    const waiverPriorities: any[] = waiverExtract
      ? Array.isArray(waiverExtract)
        ? waiverExtract
        : asArray<any>(waiverExtract?.waiver_priority)
      : [];

    console.log(
      `Found budget_teams=${budgetTeams.length}, tax_summary_teams=${taxSummaryTeams.length}, waiver_priorities=${waiverPriorities.length}, tax_teams=${taxTeams.length}, team_transactions=${teamTx.length}`
    );

    const ingestedAt = new Date();

    // ─────────────────────────────────────────────────────────────────────────
    // team_budget_snapshots + team_tax_summary_snapshots (from team_budgets.json)
    // ─────────────────────────────────────────────────────────────────────────

    const teamBudgetSnapshotRows: Record<string, any>[] = [];

    for (const bt of budgetTeams) {
      const teamIdRaw = bt?.team_id;
      const teamId = teamIdRaw === null || teamIdRaw === undefined ? null : Number(teamIdRaw);
      if (!teamId) continue;

      const budgetEntries = asArray<any>(bt?.["budget-entries"]?.["budget-entry"]);

      for (const entry of budgetEntries) {
        const amounts = asArray<any>(entry?.budget_amounts_per_year?.budget_amount);
        for (const amount of amounts) {
          teamBudgetSnapshotRows.push({
            team_id: teamId,
            team_code: teamCodeMap.get(teamId) ?? null,
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
            is_fa_amount: toBoolOrNull(amount?.fa_amount_flg),
            option_lk: amount?.option_lk ?? null,
            option_decision_lk: amount?.option_decision_lk ?? null,
            ingested_at: ingestedAt,
          });
        }
      }
    }

    const teamTaxSummarySnapshotRows: Record<string, any>[] = taxSummaryTeams
      .filter((t) => t?.team_id && t?.salary_year)
      .map((t) => {
        const teamId = Number(t.team_id);
        return {
          team_id: teamId,
          team_code: teamCodeMap.get(teamId) ?? null,
          salary_year: t.salary_year,
          is_taxpayer: toBoolOrNull(t.taxpayer_flg),
          is_repeater_taxpayer: toBoolOrNull(t.taxpayer_repeater_rate_flg),
          is_subject_to_apron: toBoolOrNull(t.subject_to_apron_flg),
          subject_to_apron_reason_lk: t.subject_to_apron_reason_lk ?? null,
          apron_level_lk: t.apron_level_lk ?? null,
          apron1_transaction_id: t.apron1_transaction_id ?? null,
          apron2_transaction_id: t.apron2_transaction_id ?? null,
          record_changed_at: t.record_change_date ?? null,
          created_at: t.create_date ?? null,
          updated_at: t.last_change_date ?? null,
          ingested_at: ingestedAt,
        };
      });

    // Dedupe by ON CONFLICT targets to avoid:
    // "ON CONFLICT DO UPDATE command cannot affect row a second time"
    const budgetKey = (r: any) =>
      [
        r.team_id,
        r.salary_year,
        r.transaction_id ?? "∅",
        r.budget_group_lk ?? "∅",
        r.player_id ?? "∅",
        r.contract_id ?? "∅",
        r.version_number ?? "∅",
      ].join("|");

    const budgetDeduped = dedupeByKey(teamBudgetSnapshotRows, budgetKey);
    const taxSummaryDeduped = dedupeByKey(teamTaxSummarySnapshotRows, (r) => `${r.team_id}|${r.salary_year}`);

    // ─────────────────────────────────────────────────────────────────────────
    // waiver_priority + waiver_priority_ranks (waiver_priority.json)
    // ─────────────────────────────────────────────────────────────────────────

    const waiverPriorityRows: Record<string, any>[] = [];
    const waiverPriorityRankRows: Record<string, any>[] = [];

    for (const wp of waiverPriorities) {
      const waiverPriorityId = toIntOrNull(wp?.waiver_priority_id);
      if (waiverPriorityId === null) continue;

      waiverPriorityRows.push({
        waiver_priority_id: waiverPriorityId,
        priority_date: wp?.priority_date ?? null,
        seqno: toIntOrNull(wp?.seqno),
        status_lk: wp?.record_status_lk ?? wp?.status_lk ?? null,
        comments: wp?.comments ?? null,
        created_at: wp?.create_date ?? null,
        updated_at: wp?.last_change_date ?? null,
        record_changed_at: wp?.record_change_date ?? null,
        ingested_at: ingestedAt,
      });

      const ranks = asArray<any>(wp?.waiver_priority_ranks?.waiver_priority_rank);
      for (const r of ranks) {
        const waiverPriorityRankId = toIntOrNull(r?.waiver_priority_detail_id ?? r?.waiver_priority_rank_id);
        if (waiverPriorityRankId === null) continue;

        const teamId = toIntOrNull(r?.team_id);

        waiverPriorityRankRows.push({
          waiver_priority_rank_id: waiverPriorityRankId,
          waiver_priority_id: waiverPriorityId,
          team_id: teamId,
          team_code: teamId !== null ? (teamCodeMap.get(teamId) ?? null) : null,
          priority_order: toIntOrNull(r?.priority_order),
          is_order_priority: toBoolOrNull(r?.order_priority_flg),
          exclusivity_status_lk: r?.exclusivity_status_lk ?? null,
          exclusivity_expiration_date: r?.exclusivity_expiration_date ?? null,
          status_lk: r?.record_status_lk ?? r?.status_lk ?? null,
          seqno: toIntOrNull(r?.seqno),
          comments: r?.comments ?? null,
          created_at: r?.create_date ?? null,
          updated_at: r?.last_change_date ?? null,
          record_changed_at: r?.record_change_date ?? null,
          ingested_at: ingestedAt,
        });
      }
    }

    const waiverPriorityDeduped = dedupeByKey(waiverPriorityRows, (r) => String(r.waiver_priority_id));
    const waiverPriorityRankDeduped = dedupeByKey(waiverPriorityRankRows, (r) => String(r.waiver_priority_rank_id));

    // ─────────────────────────────────────────────────────────────────────────
    // tax_team_status (tax_teams.json)
    // ─────────────────────────────────────────────────────────────────────────

    const taxTeamStatusRows: Record<string, any>[] = taxTeams
      .map((tt) => {
        const team_id = toIntOrNull(tt?.team_id);
        const salary_year = toIntOrNull(tt?.salary_year);
        if (team_id === null || salary_year === null) return null;

        return {
          team_id,
          team_code: teamCodeMap.get(team_id) ?? null,
          salary_year,
          is_taxpayer: toBoolOrNull(tt?.taxpayer_flg) ?? false,
          is_repeater_taxpayer: toBoolOrNull(tt?.taxpayer_repeater_rate_flg) ?? false,
          is_subject_to_apron: toBoolOrNull(tt?.subject_to_apron_flg) ?? false,
          apron_level_lk: tt?.apron_level_lk ?? null,
          subject_to_apron_reason_lk: tt?.subject_to_apron_reason_lk ?? null,
          apron1_transaction_id: toIntOrNull(tt?.apron1_transaction_id),
          apron2_transaction_id: toIntOrNull(tt?.apron2_transaction_id),
          created_at: tt?.create_date ?? null,
          updated_at: tt?.last_change_date ?? null,
          record_changed_at: tt?.record_change_date ?? null,
          ingested_at: ingestedAt,
        };
      })
      .filter(Boolean) as Record<string, any>[];

    const taxTeamStatusDeduped = dedupeByKey(taxTeamStatusRows, (r) => `${r.team_id}|${r.salary_year}`);

    // ─────────────────────────────────────────────────────────────────────────
    // team_transactions (team_transactions.json)
    // ─────────────────────────────────────────────────────────────────────────

    const teamTransactionRows: Record<string, any>[] = teamTx
      .map((t) => {
        const id = toIntOrNull(t?.team_transaction_id);
        if (id === null) return null;

        const teamId = toIntOrNull(t?.team_id);

        return {
          team_transaction_id: id,
          team_id: teamId,
          team_code: teamId !== null ? (teamCodeMap.get(teamId) ?? null) : null,
          team_transaction_type_lk: t?.team_transaction_type_lk ?? null,
          team_ledger_seqno: toIntOrNull(t?.team_ledger_seqno),
          transaction_date: t?.transaction_date ?? null,
          cap_adjustment: toIntOrNull(t?.cap_adjustment),
          cap_hold_adjustment: toIntOrNull(t?.cap_hold_adjustment),
          tax_adjustment: toIntOrNull(t?.tax_adjustment),
          tax_apron_adjustment: toIntOrNull(t?.tax_apron_adjustment),
          mts_adjustment: toIntOrNull(t?.mts_adjustment),
          protection_count_flg: toBoolOrNull(t?.protection_count_flg),
          comments: t?.comments ?? null,
          record_status_lk: t?.record_status_lk ?? null,
          created_at: t?.create_date ?? null,
          updated_at: t?.last_change_date ?? null,
          record_changed_at: t?.record_change_date ?? null,
          ingested_at: ingestedAt,
        };
      })
      .filter(Boolean) as Record<string, any>[];

    const teamTransactionDeduped = dedupeByKey(teamTransactionRows, (r) => String(r.team_transaction_id));

    console.log(
      `Prepared rows: team_budget_snapshots=${budgetDeduped.length}, team_tax_summary_snapshots=${taxSummaryDeduped.length}, waiver_priority=${waiverPriorityDeduped.length}, waiver_priority_ranks=${waiverPriorityRankDeduped.length}, tax_team_status=${taxTeamStatusDeduped.length}, team_transactions=${teamTransactionDeduped.length}`
    );

    // ─────────────────────────────────────────────────────────────────────────
    // Dry run summary
    // ─────────────────────────────────────────────────────────────────────────

    if (dry_run) {
      return {
        dry_run: true,
        started_at: startedAt,
        finished_at: new Date().toISOString(),
        tables: [
          { table: "pcms.team_budget_snapshots", attempted: budgetDeduped.length, success: true },
          { table: "pcms.team_tax_summary_snapshots", attempted: taxSummaryDeduped.length, success: true },
          { table: "pcms.tax_team_status", attempted: taxTeamStatusDeduped.length, success: true },
          { table: "pcms.waiver_priority", attempted: waiverPriorityDeduped.length, success: true },
          { table: "pcms.waiver_priority_ranks", attempted: waiverPriorityRankDeduped.length, success: true },
          { table: "pcms.team_transactions", attempted: teamTransactionDeduped.length, success: true },
        ],
        errors: [],
      };
    }

    const BATCH_SIZE = 500;

    // ─────────────────────────────────────────────────────────────────────────
    // Upsert: team_budget_snapshots
    // Note: Uses TRUNCATE + INSERT since the composite key has nullable columns
    // which don't work well with unique indexes.
    // ─────────────────────────────────────────────────────────────────────────

    await sql`TRUNCATE TABLE pcms.team_budget_snapshots`;

    for (let i = 0; i < budgetDeduped.length; i += BATCH_SIZE) {
      const batch = budgetDeduped.slice(i, i + BATCH_SIZE);
      if (batch.length === 0) continue;

      await sql`INSERT INTO pcms.team_budget_snapshots ${sql(batch)}`;
    }
    tables.push({ table: "pcms.team_budget_snapshots", attempted: budgetDeduped.length, success: true });

    // ─────────────────────────────────────────────────────────────────────────
    // Upsert: team_tax_summary_snapshots
    // ─────────────────────────────────────────────────────────────────────────

    for (let i = 0; i < taxSummaryDeduped.length; i += BATCH_SIZE) {
      const batch = taxSummaryDeduped.slice(i, i + BATCH_SIZE);
      if (batch.length === 0) continue;

      await sql`
        INSERT INTO pcms.team_tax_summary_snapshots ${sql(batch)}
        ON CONFLICT (team_id, salary_year)
        DO UPDATE SET
          team_code = EXCLUDED.team_code,
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
          ingested_at = EXCLUDED.ingested_at
      `;
    }
    tables.push({ table: "pcms.team_tax_summary_snapshots", attempted: taxSummaryDeduped.length, success: true });

    // ─────────────────────────────────────────────────────────────────────────
    // Upsert: tax_team_status
    // ─────────────────────────────────────────────────────────────────────────

    for (let i = 0; i < taxTeamStatusDeduped.length; i += BATCH_SIZE) {
      const batch = taxTeamStatusDeduped.slice(i, i + BATCH_SIZE);
      if (batch.length === 0) continue;

      await sql`
        INSERT INTO pcms.tax_team_status ${sql(batch)}
        ON CONFLICT (team_id, salary_year) DO UPDATE SET
          team_code = EXCLUDED.team_code,
          is_taxpayer = EXCLUDED.is_taxpayer,
          is_repeater_taxpayer = EXCLUDED.is_repeater_taxpayer,
          is_subject_to_apron = EXCLUDED.is_subject_to_apron,
          apron_level_lk = EXCLUDED.apron_level_lk,
          subject_to_apron_reason_lk = EXCLUDED.subject_to_apron_reason_lk,
          apron1_transaction_id = EXCLUDED.apron1_transaction_id,
          apron2_transaction_id = EXCLUDED.apron2_transaction_id,
          updated_at = EXCLUDED.updated_at,
          record_changed_at = EXCLUDED.record_changed_at,
          ingested_at = EXCLUDED.ingested_at
      `;
    }
    tables.push({ table: "pcms.tax_team_status", attempted: taxTeamStatusDeduped.length, success: true });

    // ─────────────────────────────────────────────────────────────────────────
    // Upsert: waiver_priority
    // ─────────────────────────────────────────────────────────────────────────

    for (let i = 0; i < waiverPriorityDeduped.length; i += BATCH_SIZE) {
      const batch = waiverPriorityDeduped.slice(i, i + BATCH_SIZE);
      if (batch.length === 0) continue;

      await sql`
        INSERT INTO pcms.waiver_priority ${sql(batch)}
        ON CONFLICT (waiver_priority_id) DO UPDATE SET
          priority_date = EXCLUDED.priority_date,
          seqno = EXCLUDED.seqno,
          status_lk = EXCLUDED.status_lk,
          comments = EXCLUDED.comments,
          updated_at = EXCLUDED.updated_at,
          record_changed_at = EXCLUDED.record_changed_at,
          ingested_at = EXCLUDED.ingested_at
      `;
    }
    tables.push({ table: "pcms.waiver_priority", attempted: waiverPriorityDeduped.length, success: true });

    // ─────────────────────────────────────────────────────────────────────────
    // Upsert: waiver_priority_ranks
    // ─────────────────────────────────────────────────────────────────────────

    for (let i = 0; i < waiverPriorityRankDeduped.length; i += BATCH_SIZE) {
      const batch = waiverPriorityRankDeduped.slice(i, i + BATCH_SIZE);
      if (batch.length === 0) continue;

      await sql`
        INSERT INTO pcms.waiver_priority_ranks ${sql(batch)}
        ON CONFLICT (waiver_priority_rank_id) DO UPDATE SET
          waiver_priority_id = EXCLUDED.waiver_priority_id,
          team_id = EXCLUDED.team_id,
          team_code = EXCLUDED.team_code,
          priority_order = EXCLUDED.priority_order,
          is_order_priority = EXCLUDED.is_order_priority,
          exclusivity_status_lk = EXCLUDED.exclusivity_status_lk,
          exclusivity_expiration_date = EXCLUDED.exclusivity_expiration_date,
          status_lk = EXCLUDED.status_lk,
          seqno = EXCLUDED.seqno,
          comments = EXCLUDED.comments,
          updated_at = EXCLUDED.updated_at,
          record_changed_at = EXCLUDED.record_changed_at,
          ingested_at = EXCLUDED.ingested_at
      `;
    }
    tables.push({ table: "pcms.waiver_priority_ranks", attempted: waiverPriorityRankDeduped.length, success: true });

    // ─────────────────────────────────────────────────────────────────────────
    // Upsert: team_transactions
    // ─────────────────────────────────────────────────────────────────────────

    for (let i = 0; i < teamTransactionDeduped.length; i += BATCH_SIZE) {
      const batch = teamTransactionDeduped.slice(i, i + BATCH_SIZE);
      if (batch.length === 0) continue;

      await sql`
        INSERT INTO pcms.team_transactions ${sql(batch)}
        ON CONFLICT (team_transaction_id) DO UPDATE SET
          team_id = EXCLUDED.team_id,
          team_code = EXCLUDED.team_code,
          team_transaction_type_lk = EXCLUDED.team_transaction_type_lk,
          team_ledger_seqno = EXCLUDED.team_ledger_seqno,
          transaction_date = EXCLUDED.transaction_date,
          cap_adjustment = EXCLUDED.cap_adjustment,
          cap_hold_adjustment = EXCLUDED.cap_hold_adjustment,
          tax_adjustment = EXCLUDED.tax_adjustment,
          tax_apron_adjustment = EXCLUDED.tax_apron_adjustment,
          mts_adjustment = EXCLUDED.mts_adjustment,
          protection_count_flg = EXCLUDED.protection_count_flg,
          comments = EXCLUDED.comments,
          record_status_lk = EXCLUDED.record_status_lk,
          created_at = EXCLUDED.created_at,
          updated_at = EXCLUDED.updated_at,
          record_changed_at = EXCLUDED.record_changed_at,
          ingested_at = EXCLUDED.ingested_at
      `;
    }
    tables.push({ table: "pcms.team_transactions", attempted: teamTransactionDeduped.length, success: true });

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
      errors: [e?.message ?? String(e)],
    };
  }
}
