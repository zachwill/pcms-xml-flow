/**
 * Trades / Transactions / Ledger Import
 *
 * Reads clean JSON from lineage step and upserts into:
 * - pcms.trades
 * - pcms.trade_teams
 * - pcms.trade_team_details
 * - pcms.trade_groups
 * - pcms.transactions
 * - pcms.ledger_entries
 * - pcms.transaction_waiver_amounts
 *
 * Clean JSON notes:
 * - snake_case keys
 * - proper nulls (no xsi:nil objects)
 * - no XML wrapper nesting
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

function unwrapSingleArray<T = any>(val: any): T | null {
  if (val === null || val === undefined) return null;
  return Array.isArray(val) ? (val.length > 0 ? (val[0] as T) : null) : (val as T);
}

function normalizeVersionNumber(val: unknown): number | null {
  if (val === null || val === undefined || val === "") return null;

  const n = typeof val === "number" ? val : Number(val);
  if (!Number.isFinite(n)) return null;

  // PCMS sometimes represents version_number as a decimal like 1.01
  // Schema expects an integer (1.01 -> 101)
  return Number.isInteger(n) ? n : Math.round(n * 100);
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

    // Read clean JSON
    const trades: any[] = await Bun.file(`${baseDir}/trades.json`).json();
    const transactions: any[] = await Bun.file(`${baseDir}/transactions.json`).json();
    const ledgerEntries: any[] = await Bun.file(`${baseDir}/ledger.json`).json();

    const waiverFile = Bun.file(`${baseDir}/transaction_waiver_amounts.json`);
    const waiverAmounts: any[] = (await waiverFile.exists()) ? await waiverFile.json() : [];

    console.log(
      `Found trades=${trades.length}, transactions=${transactions.length}, ledger_entries=${ledgerEntries.length}, waiver_amounts=${waiverAmounts.length}`
    );

    const ingestedAt = new Date();
    const provenance = {
      source_drop_file: s3_key,
      ingested_at: ingestedAt,
    };

    // ─────────────────────────────────────────────────────────────────────────
    // Flatten trades → (trades, trade_teams, trade_team_details, trade_groups)
    // ─────────────────────────────────────────────────────────────────────────

    const tradeRows: any[] = [];
    const tradeTeamRows: any[] = [];
    const tradeTeamDetailRows: any[] = [];
    const tradeGroupRows: any[] = [];

    for (const t of trades) {
      if (!t?.trade_id) continue;

      tradeRows.push({
        trade_id: t.trade_id,
        trade_date: t.trade_date ?? null,
        trade_finalized_date: t.trade_finalized_date ?? null,
        league_lk: t.league_lk ?? null,
        record_status_lk: t.record_status_lk ?? null,
        trade_comments: t.trade_comments ?? null,
        created_at: t.create_date ?? null,
        updated_at: t.last_change_date ?? null,
        record_changed_at: t.record_change_date ?? null,
        ...provenance,
      });

      const teams = asArray<any>(t?.trade_teams?.trade_team);
      for (const tt of teams) {
        if (!tt?.team_id) continue;

        const tradeTeamId = `${t.trade_id}_${tt.team_id}`;

        tradeTeamRows.push({
          trade_team_id: tradeTeamId,
          trade_id: t.trade_id,
          team_id: tt.team_id,
          team_salary_change: tt.team_salary_change ?? null,
          total_cash_received: tt.total_cash_received ?? null,
          total_cash_sent: tt.total_cash_sent ?? null,
          seqno: tt.seqno ?? null,
          ...provenance,
        });

        const details = asArray<any>(tt?.trade_team_details?.trade_team_detail);
        for (const d of details) {
          if (d?.seqno === null || d?.seqno === undefined) continue;

          tradeTeamDetailRows.push({
            trade_team_detail_id: `${t.trade_id}_${tt.team_id}_${d.seqno}`,
            trade_id: t.trade_id,
            team_id: tt.team_id,
            seqno: d.seqno,
            group_number: d.group_number ?? null,
            player_id: d.player_id ?? null,
            contract_id: d.contract_id ?? null,
            version_number: normalizeVersionNumber(d.version_number),
            post_version_number: normalizeVersionNumber(d.post_version_number),
            is_sent: d.sent_flg ?? null,
            is_sign_and_trade: d.sign_and_trade_flg ?? null,
            mts_value_override: d.mts_value_override ?? null,
            is_trade_bonus: d.trade_bonus_flg ?? null,
            is_no_trade: d.no_trade_flg ?? null,
            is_player_consent: d.player_consent_flg ?? null,
            is_poison_pill: d.poison_pill_flg ?? null,
            is_incentive_bonus: d.incentive_bonus_flg ?? null,
            cash_amount: d.cash_amount ?? null,
            trade_entry_lk: d.trade_entry_lk ?? null,
            free_agent_designation_lk: d.free_agent_designation_lk ?? null,
            base_year_amount: d.base_year_amount ?? null,
            is_base_year: d.base_year_flg ?? null,
            draft_pick_year: d.draft_pick_year ?? null,
            draft_pick_round: d.draft_pick_round ?? null,
            is_draft_pick_future: d.draft_pick_future_flg ?? null,
            is_draft_pick_swap: d.draft_pick_swap_flg ?? null,
            draft_pick_conditional_lk: d.draft_pick_conditional_lk ?? null,
            is_draft_year_plus_two: d.draft_year_plus_two_flg ?? null,
            ...provenance,
          });
        }

        // Trade groups are usually nested under trade_team; fall back to the trade-level group
        const groupsFromTeam = asArray<any>(tt?.trade_groups?.trade_group);
        const groupsFromTrade = asArray<any>(t?.trade_groups?.trade_group);
        const groups = groupsFromTeam.length > 0 ? groupsFromTeam : groupsFromTrade;

        for (const g of groups) {
          const groupNumber = g?.trade_group_number;
          if (groupNumber === null || groupNumber === undefined) continue;

          tradeGroupRows.push({
            trade_group_id: `${t.trade_id}_${tt.team_id}_${groupNumber}`,
            trade_id: t.trade_id,
            team_id: g?.team_id ?? tt.team_id,
            trade_group_number: groupNumber,
            trade_group_comments: g?.trade_group_comments ?? null,
            acquired_team_exception_id: g?.acquired_team_exception_id ?? null,
            generated_team_exception_id: g?.generated_team_exception_id ?? null,
            signed_method_lk: g?.signed_method_lk ?? null,
            ...provenance,
          });
        }
      }
    }

    console.log(
      `Prepared rows: trades=${tradeRows.length}, trade_teams=${tradeTeamRows.length}, trade_team_details=${tradeTeamDetailRows.length}, trade_groups=${tradeGroupRows.length}`
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
          { table: "pcms.trades", attempted: tradeRows.length, success: true },
          { table: "pcms.trade_teams", attempted: tradeTeamRows.length, success: true },
          { table: "pcms.trade_team_details", attempted: tradeTeamDetailRows.length, success: true },
          { table: "pcms.trade_groups", attempted: tradeGroupRows.length, success: true },
          { table: "pcms.transactions", attempted: transactions.length, success: true },
          { table: "pcms.ledger_entries", attempted: ledgerEntries.length, success: true },
          { table: "pcms.transaction_waiver_amounts", attempted: waiverAmounts.length, success: true },
        ],
        errors: [],
      };
    }

    const BATCH_SIZE = 1000;
    const tables: { table: string; attempted: number; success: boolean }[] = [];

    // ─────────────────────────────────────────────────────────────────────────
    // Upsert: trades
    // ─────────────────────────────────────────────────────────────────────────

    for (let i = 0; i < tradeRows.length; i += BATCH_SIZE) {
      const rows = tradeRows.slice(i, i + BATCH_SIZE);
      await sql`
        INSERT INTO pcms.trades ${sql(rows)}
        ON CONFLICT (trade_id) DO UPDATE SET
          trade_date = EXCLUDED.trade_date,
          trade_finalized_date = EXCLUDED.trade_finalized_date,
          league_lk = EXCLUDED.league_lk,
          record_status_lk = EXCLUDED.record_status_lk,
          trade_comments = EXCLUDED.trade_comments,
          updated_at = EXCLUDED.updated_at,
          record_changed_at = EXCLUDED.record_changed_at,
          source_drop_file = EXCLUDED.source_drop_file,
          ingested_at = EXCLUDED.ingested_at
      `;
    }
    tables.push({ table: "pcms.trades", attempted: tradeRows.length, success: true });

    // Upsert: trade_teams
    for (let i = 0; i < tradeTeamRows.length; i += BATCH_SIZE) {
      const rows = tradeTeamRows.slice(i, i + BATCH_SIZE);
      await sql`
        INSERT INTO pcms.trade_teams ${sql(rows)}
        ON CONFLICT (trade_team_id) DO UPDATE SET
          trade_id = EXCLUDED.trade_id,
          team_id = EXCLUDED.team_id,
          team_salary_change = EXCLUDED.team_salary_change,
          total_cash_received = EXCLUDED.total_cash_received,
          total_cash_sent = EXCLUDED.total_cash_sent,
          seqno = EXCLUDED.seqno,
          source_drop_file = EXCLUDED.source_drop_file,
          ingested_at = EXCLUDED.ingested_at
      `;
    }
    tables.push({ table: "pcms.trade_teams", attempted: tradeTeamRows.length, success: true });

    // Upsert: trade_team_details
    for (let i = 0; i < tradeTeamDetailRows.length; i += BATCH_SIZE) {
      const rows = tradeTeamDetailRows.slice(i, i + BATCH_SIZE);
      await sql`
        INSERT INTO pcms.trade_team_details ${sql(rows)}
        ON CONFLICT (trade_team_detail_id) DO UPDATE SET
          trade_id = EXCLUDED.trade_id,
          team_id = EXCLUDED.team_id,
          seqno = EXCLUDED.seqno,
          group_number = EXCLUDED.group_number,
          player_id = EXCLUDED.player_id,
          contract_id = EXCLUDED.contract_id,
          version_number = EXCLUDED.version_number,
          post_version_number = EXCLUDED.post_version_number,
          is_sent = EXCLUDED.is_sent,
          is_sign_and_trade = EXCLUDED.is_sign_and_trade,
          mts_value_override = EXCLUDED.mts_value_override,
          is_trade_bonus = EXCLUDED.is_trade_bonus,
          is_no_trade = EXCLUDED.is_no_trade,
          is_player_consent = EXCLUDED.is_player_consent,
          is_poison_pill = EXCLUDED.is_poison_pill,
          is_incentive_bonus = EXCLUDED.is_incentive_bonus,
          cash_amount = EXCLUDED.cash_amount,
          trade_entry_lk = EXCLUDED.trade_entry_lk,
          free_agent_designation_lk = EXCLUDED.free_agent_designation_lk,
          base_year_amount = EXCLUDED.base_year_amount,
          is_base_year = EXCLUDED.is_base_year,
          draft_pick_year = EXCLUDED.draft_pick_year,
          draft_pick_round = EXCLUDED.draft_pick_round,
          is_draft_pick_future = EXCLUDED.is_draft_pick_future,
          is_draft_pick_swap = EXCLUDED.is_draft_pick_swap,
          draft_pick_conditional_lk = EXCLUDED.draft_pick_conditional_lk,
          is_draft_year_plus_two = EXCLUDED.is_draft_year_plus_two,
          source_drop_file = EXCLUDED.source_drop_file,
          ingested_at = EXCLUDED.ingested_at
      `;
    }
    tables.push({ table: "pcms.trade_team_details", attempted: tradeTeamDetailRows.length, success: true });

    // Upsert: trade_groups
    for (let i = 0; i < tradeGroupRows.length; i += BATCH_SIZE) {
      const rows = tradeGroupRows.slice(i, i + BATCH_SIZE);
      await sql`
        INSERT INTO pcms.trade_groups ${sql(rows)}
        ON CONFLICT (trade_group_id) DO UPDATE SET
          trade_id = EXCLUDED.trade_id,
          team_id = EXCLUDED.team_id,
          trade_group_number = EXCLUDED.trade_group_number,
          trade_group_comments = EXCLUDED.trade_group_comments,
          acquired_team_exception_id = EXCLUDED.acquired_team_exception_id,
          generated_team_exception_id = EXCLUDED.generated_team_exception_id,
          signed_method_lk = EXCLUDED.signed_method_lk,
          source_drop_file = EXCLUDED.source_drop_file,
          ingested_at = EXCLUDED.ingested_at
      `;
    }
    tables.push({ table: "pcms.trade_groups", attempted: tradeGroupRows.length, success: true });

    // ─────────────────────────────────────────────────────────────────────────
    // Upsert: transactions
    // ─────────────────────────────────────────────────────────────────────────

    for (let i = 0; i < transactions.length; i += BATCH_SIZE) {
      const batch = transactions.slice(i, i + BATCH_SIZE);

      const rows = batch
        .filter((t) => t?.transaction_id)
        .map((t) => ({
          transaction_id: t.transaction_id,
          player_id: t.player_id ?? null,
          from_team_id: t.from_team_id ?? null,
          to_team_id: t.to_team_id ?? null,
          transaction_date: t.transaction_date ?? null,
          trade_finalized_date: t.trade_finalized_date ?? null,
          trade_id: t.trade_id ?? null,
          transaction_type_lk: t.transaction_type_lk ?? null,
          transaction_description_lk: t.transaction_description_lk ?? null,
          record_status_lk: t.record_status_lk ?? null,
          league_lk: t.league_lk ?? null,
          seqno: t.seqno ?? null,
          is_in_season: t.in_season_flg ?? null,
          contract_id: t.contract_id ?? null,
          original_contract_id: t.original_contract_id ?? null,
          version_number: normalizeVersionNumber(t.version_number),
          contract_type_lk: t.contract_type_lk ?? null,
          min_contract_lk: t.min_contract_lk ?? null,
          signed_method_lk: t.signed_method_lk ?? null,
          team_exception_id: t.team_exception_id ?? null,
          rights_team_id: t.rights_team_id ?? null,
          waiver_clear_date: t.waiver_clear_date ?? null,
          is_clear_player_rights: t.clear_player_rights_flg ?? null,
          free_agent_status_lk: t.free_agent_status_lk ?? null,
          free_agent_designation_lk: t.free_agent_designation_lk ?? null,
          from_player_status_lk: t.from_player_status_lk ?? null,
          to_player_status_lk: t.to_player_status_lk ?? null,
          option_year: t.option_year ?? null,
          adjustment_amount: t.adjustment_amount ?? null,
          bonus_true_up_amount: t.bonus_true_up_amount ?? null,
          draft_amount: t.draft_amount ?? null,
          draft_pick: unwrapSingleArray<number>(t.draft_pick),
          draft_round: t.draft_round ?? null,
          draft_year: t.draft_year ?? null,
          free_agent_amount: t.free_agent_amount ?? null,
          qoe_amount: t.qoe_amount ?? null,
          tender_amount: t.tender_amount ?? null,
          is_divorce: t.divorce_flg ?? null,
          effective_salary_year: t.effective_salary_year ?? null,
          is_initially_convertible_exception: t.initially_convertible_exception_flg ?? null,
          is_sign_and_trade: t.sign_and_trade_flg ?? null,
          sign_and_trade_team_id: t.sign_and_trade_team_id ?? null,
          sign_and_trade_link_transaction_id: t.sign_and_trade_link_transaction_id ?? null,
          dlg_contract_id: t.dlg_contract_id ?? null,
          dlg_experience_level_lk: t.dlg_experience_level_lk ?? null,
          dlg_salary_level_lk: t.dlg_salary_level_lk ?? null,
          comments: t.comments ?? null,
          created_at: t.create_date ?? null,
          updated_at: t.last_change_date ?? null,
          record_changed_at: t.record_change_date ?? null,
          ...provenance,
        }));

      if (rows.length === 0) continue;

      await sql`
        INSERT INTO pcms.transactions ${sql(rows)}
        ON CONFLICT (transaction_id) DO UPDATE SET
          player_id = EXCLUDED.player_id,
          from_team_id = EXCLUDED.from_team_id,
          to_team_id = EXCLUDED.to_team_id,
          transaction_date = EXCLUDED.transaction_date,
          trade_finalized_date = EXCLUDED.trade_finalized_date,
          trade_id = EXCLUDED.trade_id,
          transaction_type_lk = EXCLUDED.transaction_type_lk,
          transaction_description_lk = EXCLUDED.transaction_description_lk,
          record_status_lk = EXCLUDED.record_status_lk,
          league_lk = EXCLUDED.league_lk,
          seqno = EXCLUDED.seqno,
          is_in_season = EXCLUDED.is_in_season,
          contract_id = EXCLUDED.contract_id,
          original_contract_id = EXCLUDED.original_contract_id,
          version_number = EXCLUDED.version_number,
          contract_type_lk = EXCLUDED.contract_type_lk,
          min_contract_lk = EXCLUDED.min_contract_lk,
          signed_method_lk = EXCLUDED.signed_method_lk,
          team_exception_id = EXCLUDED.team_exception_id,
          rights_team_id = EXCLUDED.rights_team_id,
          waiver_clear_date = EXCLUDED.waiver_clear_date,
          is_clear_player_rights = EXCLUDED.is_clear_player_rights,
          free_agent_status_lk = EXCLUDED.free_agent_status_lk,
          free_agent_designation_lk = EXCLUDED.free_agent_designation_lk,
          from_player_status_lk = EXCLUDED.from_player_status_lk,
          to_player_status_lk = EXCLUDED.to_player_status_lk,
          option_year = EXCLUDED.option_year,
          adjustment_amount = EXCLUDED.adjustment_amount,
          bonus_true_up_amount = EXCLUDED.bonus_true_up_amount,
          draft_amount = EXCLUDED.draft_amount,
          draft_pick = EXCLUDED.draft_pick,
          draft_round = EXCLUDED.draft_round,
          draft_year = EXCLUDED.draft_year,
          free_agent_amount = EXCLUDED.free_agent_amount,
          qoe_amount = EXCLUDED.qoe_amount,
          tender_amount = EXCLUDED.tender_amount,
          is_divorce = EXCLUDED.is_divorce,
          effective_salary_year = EXCLUDED.effective_salary_year,
          is_initially_convertible_exception = EXCLUDED.is_initially_convertible_exception,
          is_sign_and_trade = EXCLUDED.is_sign_and_trade,
          sign_and_trade_team_id = EXCLUDED.sign_and_trade_team_id,
          sign_and_trade_link_transaction_id = EXCLUDED.sign_and_trade_link_transaction_id,
          dlg_contract_id = EXCLUDED.dlg_contract_id,
          dlg_experience_level_lk = EXCLUDED.dlg_experience_level_lk,
          dlg_salary_level_lk = EXCLUDED.dlg_salary_level_lk,
          comments = EXCLUDED.comments,
          updated_at = EXCLUDED.updated_at,
          record_changed_at = EXCLUDED.record_changed_at,
          source_drop_file = EXCLUDED.source_drop_file,
          ingested_at = EXCLUDED.ingested_at
      `;
    }
    tables.push({ table: "pcms.transactions", attempted: transactions.length, success: true });

    // ─────────────────────────────────────────────────────────────────────────
    // Upsert: ledger_entries
    // ─────────────────────────────────────────────────────────────────────────

    for (let i = 0; i < ledgerEntries.length; i += BATCH_SIZE) {
      const batch = ledgerEntries.slice(i, i + BATCH_SIZE);

      const rows = batch
        .filter((le) => le?.transaction_ledger_entry_id !== null && le?.transaction_ledger_entry_id !== undefined)
        .map((le) => ({
          transaction_ledger_entry_id: le.transaction_ledger_entry_id,
          transaction_id: le.transaction_id,
          team_id: le.team_id,
          player_id: le.player_id ?? null,
          contract_id: le.contract_id ?? null,
          dlg_contract_id: le.dlg_contract_id ?? null,
          salary_year: le.salary_year,
          ledger_date: le.ledger_date ?? null,
          league_lk: le.league_lk ?? null,
          transaction_type_lk: le.transaction_type_lk ?? null,
          transaction_description_lk: le.transaction_description_lk ?? null,
          version_number: normalizeVersionNumber(le.version_number),
          seqno: le.seqno ?? null,
          sub_seqno: le.sub_seqno ?? null,
          team_ledger_seqno: le.team_ledger_seqno ?? null,
          is_leaving_team: le.leaving_team_flg ?? null,
          has_no_budget_impact: le.no_budget_impact_flg ?? null,
          mts_amount: le.mts_amount ?? null,
          mts_change: le.mts_change ?? null,
          mts_value: le.mts_value ?? null,
          cap_amount: le.cap_amount ?? null,
          cap_change: le.cap_change ?? null,
          cap_value: le.cap_value ?? null,
          tax_amount: le.tax_amount ?? null,
          tax_change: le.tax_change ?? null,
          tax_value: le.tax_value ?? null,
          apron_amount: le.apron_amount ?? null,
          apron_change: le.apron_change ?? null,
          apron_value: le.apron_value ?? null,
          trade_bonus_amount: le.trade_bonus_amount ?? null,
          ...provenance,
        }));

      if (rows.length === 0) continue;

      await sql`
        INSERT INTO pcms.ledger_entries ${sql(rows)}
        ON CONFLICT (transaction_ledger_entry_id) DO UPDATE SET
          transaction_id = EXCLUDED.transaction_id,
          team_id = EXCLUDED.team_id,
          player_id = EXCLUDED.player_id,
          contract_id = EXCLUDED.contract_id,
          dlg_contract_id = EXCLUDED.dlg_contract_id,
          salary_year = EXCLUDED.salary_year,
          ledger_date = EXCLUDED.ledger_date,
          league_lk = EXCLUDED.league_lk,
          transaction_type_lk = EXCLUDED.transaction_type_lk,
          transaction_description_lk = EXCLUDED.transaction_description_lk,
          version_number = EXCLUDED.version_number,
          seqno = EXCLUDED.seqno,
          sub_seqno = EXCLUDED.sub_seqno,
          team_ledger_seqno = EXCLUDED.team_ledger_seqno,
          is_leaving_team = EXCLUDED.is_leaving_team,
          has_no_budget_impact = EXCLUDED.has_no_budget_impact,
          mts_amount = EXCLUDED.mts_amount,
          mts_change = EXCLUDED.mts_change,
          mts_value = EXCLUDED.mts_value,
          cap_amount = EXCLUDED.cap_amount,
          cap_change = EXCLUDED.cap_change,
          cap_value = EXCLUDED.cap_value,
          tax_amount = EXCLUDED.tax_amount,
          tax_change = EXCLUDED.tax_change,
          tax_value = EXCLUDED.tax_value,
          apron_amount = EXCLUDED.apron_amount,
          apron_change = EXCLUDED.apron_change,
          apron_value = EXCLUDED.apron_value,
          trade_bonus_amount = EXCLUDED.trade_bonus_amount,
          source_drop_file = EXCLUDED.source_drop_file,
          ingested_at = EXCLUDED.ingested_at
      `;
    }
    tables.push({ table: "pcms.ledger_entries", attempted: ledgerEntries.length, success: true });

    // ─────────────────────────────────────────────────────────────────────────
    // Upsert: transaction_waiver_amounts
    // ─────────────────────────────────────────────────────────────────────────

    for (let i = 0; i < waiverAmounts.length; i += BATCH_SIZE) {
      const batch = waiverAmounts.slice(i, i + BATCH_SIZE);

      const rows = batch
        .filter((wa) => wa?.transaction_waiver_amount_id)
        .map((wa) => ({
          transaction_waiver_amount_id: wa.transaction_waiver_amount_id,
          transaction_id: wa.transaction_id,
          player_id: wa.player_id,
          team_id: wa.team_id ?? null,
          contract_id: wa.contract_id ?? null,
          salary_year: wa.salary_year,
          version_number: normalizeVersionNumber(wa.version_number),
          waive_date: wa.waive_date ?? null,
          cap_value: wa.cap_value ?? null,
          cap_change_value: wa.cap_change_value ?? null,
          is_cap_calculated: wa.cap_calculated ?? null,
          tax_value: wa.tax_value ?? null,
          tax_change_value: wa.tax_change_value ?? null,
          is_tax_calculated: wa.tax_calculated ?? null,
          apron_value: wa.apron_value ?? null,
          apron_change_value: wa.apron_change_value ?? null,
          is_apron_calculated: wa.apron_calculated ?? null,
          mts_value: wa.mts_value ?? null,
          mts_change_value: wa.mts_change_value ?? null,
          two_way_salary: wa.two_way_salary ?? null,
          two_way_nba_salary: wa.two_way_nba_salary ?? null,
          two_way_dlg_salary: wa.two_way_dlg_salary ?? null,
          option_decision_lk: wa.option_decision_lk ?? null,
          wnba_contract_id: wa.wnba_contract_id ?? null,
          wnba_version_number: wa.wnba_version_number ?? null,
          ...provenance,
        }));

      if (rows.length === 0) continue;

      await sql`
        INSERT INTO pcms.transaction_waiver_amounts ${sql(rows)}
        ON CONFLICT (transaction_waiver_amount_id) DO UPDATE SET
          transaction_id = EXCLUDED.transaction_id,
          player_id = EXCLUDED.player_id,
          team_id = EXCLUDED.team_id,
          contract_id = EXCLUDED.contract_id,
          salary_year = EXCLUDED.salary_year,
          version_number = EXCLUDED.version_number,
          waive_date = EXCLUDED.waive_date,
          cap_value = EXCLUDED.cap_value,
          cap_change_value = EXCLUDED.cap_change_value,
          is_cap_calculated = EXCLUDED.is_cap_calculated,
          tax_value = EXCLUDED.tax_value,
          tax_change_value = EXCLUDED.tax_change_value,
          is_tax_calculated = EXCLUDED.is_tax_calculated,
          apron_value = EXCLUDED.apron_value,
          apron_change_value = EXCLUDED.apron_change_value,
          is_apron_calculated = EXCLUDED.is_apron_calculated,
          mts_value = EXCLUDED.mts_value,
          mts_change_value = EXCLUDED.mts_change_value,
          two_way_salary = EXCLUDED.two_way_salary,
          two_way_nba_salary = EXCLUDED.two_way_nba_salary,
          two_way_dlg_salary = EXCLUDED.two_way_dlg_salary,
          option_decision_lk = EXCLUDED.option_decision_lk,
          wnba_contract_id = EXCLUDED.wnba_contract_id,
          wnba_version_number = EXCLUDED.wnba_version_number,
          source_drop_file = EXCLUDED.source_drop_file,
          ingested_at = EXCLUDED.ingested_at
      `;
    }
    tables.push({
      table: "pcms.transaction_waiver_amounts",
      attempted: waiverAmounts.length,
      success: true,
    });

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
