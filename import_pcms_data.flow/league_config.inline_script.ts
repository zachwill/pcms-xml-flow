/**
 * League Config Import (consolidated)
 *
 * Merges:
 *  - system_values,_rookie_scale_&_nca.inline_script.ts
 *  - league_salary_scales_&_protections.inline_script.ts
 *
 * Upserts into:
 *  - pcms.league_system_values          (yearly_system_values.json)
 *  - pcms.rookie_scale_amounts          (rookie_scale_amounts.json)
 *  - pcms.non_contract_amounts          (non_contract_amounts.json)
 *  - pcms.league_salary_scales          (yearly_salary_scales.json)
 *  - pcms.league_salary_cap_projections (cap_projections.json)
 *  - pcms.league_tax_rates              (tax_rates.json)
 *  - pcms.apron_constraints             (derived from lookups × system_values)
 *
 * Clean JSON notes:
 * - snake_case keys
 * - null values already handled
 * - no XML wrapper nesting
 */

import { SQL } from "bun";
import { readdir } from "node:fs/promises";

const sql = new SQL({ url: Bun.env.POSTGRES_URL!, prepare: false });

// ─────────────────────────────────────────────────────────────────────────────
// Helpers (inline)
// ─────────────────────────────────────────────────────────────────────────────

function toIntOrNull(val: unknown): number | null {
  if (val === "" || val === null || val === undefined) return null;
  const n = Number(val);
  return Number.isFinite(n) ? Math.trunc(n) : null;
}

function toNumOrNull(val: unknown): number | null {
  if (val === "" || val === null || val === undefined) return null;
  const n = Number(val);
  return Number.isFinite(n) ? n : null;
}

function toBoolOrNull(val: unknown): boolean | null {
  if (val === null || val === undefined || val === "") return null;
  if (typeof val === "boolean") return val;
  if (val === 0 || val === "0" || val === "false") return false;
  if (val === 1 || val === "1" || val === "true") return true;
  return null;
}

function firstScalar(val: any): any {
  if (val === null || val === undefined) return null;
  if (Array.isArray(val)) return val.length > 0 ? val[0] : null;
  return val;
}

async function resolveBaseDir(extractDir: string): Promise<string> {
  const entries = await readdir(extractDir, { withFileTypes: true });
  const subDir = entries.find((e) => e.isDirectory());
  return subDir ? `${extractDir}/${subDir.name}` : extractDir;
}

function dedupeByKey<T>(rows: T[], keyFn: (row: T) => string): T[] {
  const seen = new Map<string, T>();
  for (const r of rows) seen.set(keyFn(r), r);
  return [...seen.values()];
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

// ─────────────────────────────────────────────────────────────────────────────
// Main
// ─────────────────────────────────────────────────────────────────────────────

export async function main(dry_run = false, extract_dir = "./shared/pcms") {
  const startedAt = new Date().toISOString();
  const tables: { table: string; attempted: number; success: boolean }[] = [];

  try {
    const baseDir = await resolveBaseDir(extract_dir);

    // Build team_id → team_code lookup map (for non_contract_amounts)
    const lookupsFile = Bun.file(`${baseDir}/lookups.json`);
    const lookups: any = (await lookupsFile.exists()) ? await lookupsFile.json() : {};
    const teamCodeMap = buildTeamCodeMap(lookups);

    // Read clean JSON
    const ysvFile = Bun.file(`${baseDir}/yearly_system_values.json`);
    const rookieFile = Bun.file(`${baseDir}/rookie_scale_amounts.json`);
    const ncaFile = Bun.file(`${baseDir}/non_contract_amounts.json`);
    const salaryScalesFile = Bun.file(`${baseDir}/yearly_salary_scales.json`);
    const capProjectionsFile = Bun.file(`${baseDir}/cap_projections.json`);
    const taxRatesFile = Bun.file(`${baseDir}/tax_rates.json`);

    const ysv: any[] = (await ysvFile.exists()) ? await ysvFile.json() : [];
    const rookieScale: any[] = (await rookieFile.exists()) ? await rookieFile.json() : [];
    const ncas: any[] = (await ncaFile.exists()) ? await ncaFile.json() : [];
    const salaryScales: any[] = (await salaryScalesFile.exists()) ? await salaryScalesFile.json() : [];
    const capProjections: any[] = (await capProjectionsFile.exists()) ? await capProjectionsFile.json() : [];
    const taxRates: any[] = (await taxRatesFile.exists()) ? await taxRatesFile.json() : [];

    console.log(
      `Found yearly_system_values=${ysv.length}, rookie_scale_amounts=${rookieScale.length}, non_contract_amounts=${ncas.length}`
    );
    console.log(
      `Found salary_scales=${salaryScales.length}, cap_projections=${capProjections.length}, tax_rates=${taxRates.length}`
    );

    const ingestedAt = new Date();

    // ─────────────────────────────────────────────────────────────────────────
    // Map JSON → DB rows
    // ─────────────────────────────────────────────────────────────────────────

    const leagueSystemValueRows = ysv
      .map((sv) => {
        if (!sv?.league_lk) return null;
        const salaryYear = sv?.system_year ?? null;
        if (salaryYear === null || salaryYear === undefined) return null;

        return {
          league_lk: sv.league_lk,
          salary_year: salaryYear,

          // Financial constants
          salary_cap_amount: sv?.cap_amount ?? null,
          tax_level_amount: sv?.tax_level ?? null,
          tax_apron_amount: sv?.tax_apron ?? null,
          tax_apron2_amount: sv?.tax_apron2 ?? null,
          tax_bracket_amount: sv?.tax_bracket_amount ?? null,
          minimum_team_salary_amount: sv?.minimum_team_salary ?? null,

          maximum_salary_25_pct: sv?.maximum_salary25 ?? null,
          maximum_salary_30_pct: sv?.maximum_salary30 ?? null,
          maximum_salary_35_pct: sv?.maximum_salary35 ?? null,

          average_salary_amount: sv?.average_salary ?? null,
          estimated_average_salary_amount: sv?.estimated_average_salary ?? null,

          non_taxpayer_mid_level_amount: sv?.non_taxpayer_mid_level_amount ?? null,
          taxpayer_mid_level_amount: sv?.taxpayer_mid_level_amount ?? null,
          room_mid_level_amount: sv?.room_mid_level_amount ?? null,
          bi_annual_amount: sv?.bi_annual_amount ?? null,

          two_way_salary_amount: sv?.two_way_salary_amount ?? null,
          two_way_dlg_salary_amount: sv?.two_way_dlg_salary_amount ?? null,

          tpe_dollar_allowance: sv?.tpe_dollar_allowance ?? null,
          max_trade_cash_amount: sv?.max_trade_cash_amount ?? null,
          international_player_payment_limit: sv?.international_player_payment ?? null,

          scale_raise_rate: sv?.scale_raise_rate ?? null,

          // Dates
          days_in_season: sv?.days_in_season ?? null,
          season_start_at: sv?.first_day_of_season ?? null,
          season_end_at: sv?.last_day_of_season ?? null,
          playing_start_at: sv?.playing_start_date ?? null,
          playing_end_at: sv?.playing_end_date ?? null,
          finals_end_at: sv?.last_day_of_finals ?? null,

          training_camp_start_at: sv?.training_camp_start_date ?? null,
          training_camp_end_at: sv?.training_camp_end_date ?? null,
          rookie_camp_start_at: sv?.rookie_camp_start_date ?? null,
          rookie_camp_end_at: sv?.rookie_camp_end_date ?? null,
          draft_at: sv?.draft_date ?? null,
          moratorium_end_at: sv?.moratorium_end_date ?? null,
          trade_deadline_at: sv?.trade_deadline_date ?? null,
          cut_down_at: sv?.cut_down_date ?? null,
          two_way_cut_down_at: sv?.two_way_cut_down_date ?? null,
          notification_start_at: sv?.notification_start_date ?? null,
          notification_end_at: sv?.notification_end_date ?? null,
          exception_start_at: sv?.exception_start_date ?? null,
          exception_prorate_at: sv?.exception_prorate_start_date ?? null,
          exceptions_added_at: sv?.exceptions_added_date ?? null,
          rnd2_pick_exc_zero_cap_end_at: sv?.rnd2_pick_exc_zero_cap_end_date ?? null,

          // Flags
          bonuses_finalized_at: sv?.bonuses_finalized_date ?? null,
          is_bonuses_finalized: sv?.bonuses_finalized_flg ?? null,
          is_cap_projection_generated: sv?.cap_projection_generated_flg ?? null,
          is_exceptions_added: sv?.exceptions_added_flg ?? null,
          free_agent_status_finalized_at: sv?.free_agent_amounts_finalized_date ?? null,
          is_free_agent_amounts_finalized: sv?.free_agent_amounts_finalized_flg ?? null,

          wnba_offseason_end_at: sv?.wnba_offseason_end ?? null,
          wnba_season_finalized_at: sv?.wnba_season_finalized_date ?? null,
          is_wnba_season_finalized: sv?.wnba_season_finalized_flg ?? null,

          // D-League
          dlg_countable_roster_moves: sv?.dlg_countable_roster_moves ?? null,
          dlg_max_level_a_salary_players: sv?.dlg_max_level_a_salary_players ?? null,
          dlg_salary_level_a: sv?.dlg_salary_level_a ?? null,
          dlg_salary_level_b: sv?.dlg_salary_level_b ?? null,
          dlg_salary_level_c: sv?.dlg_salary_level_c ?? null,
          dlg_team_salary_budget: sv?.dlg_team_salary_budget ?? null,

          created_at: sv?.create_date ?? null,
          updated_at: sv?.last_change_date ?? null,
          record_changed_at: sv?.record_change_date ?? null,
          ingested_at: ingestedAt,
        };
      })
      .filter(Boolean) as Record<string, any>[];

    const rookieScaleRows = rookieScale
      .map((rs) => {
        const salaryYear = rs?.season ?? null;
        const pickNumber = rs?.pick ?? null;
        if (salaryYear === null || pickNumber === null) return null;

        return {
          salary_year: salaryYear,
          pick_number: pickNumber,
          league_lk: rs?.league_lk ?? "NBA",

          salary_year_1: rs?.salary_year1 ?? null,
          salary_year_2: rs?.salary_year2 ?? null,
          salary_year_3: rs?.salary_year3 ?? null,
          salary_year_4: rs?.salary_year4 ?? null,

          option_amount_year_3: rs?.option_year3 ?? null,
          option_amount_year_4: rs?.option_year4 ?? null,
          option_pct_year_3: rs?.percent_year3 ?? null,
          option_pct_year_4: rs?.percent_year4 ?? null,

          is_baseline_scale: rs?.baseline_scale_flg ?? null,
          is_active: rs?.active_flg ?? null,

          created_at: rs?.create_date ?? null,
          updated_at: rs?.last_change_date ?? null,
          record_changed_at: rs?.record_change_date ?? null,
          ingested_at: ingestedAt,
        };
      })
      .filter(Boolean) as Record<string, any>[];

    const nonContractAmountRows = ncas
      .map((nca) => {
        if (!nca?.non_contract_amount_id) return null;

        const teamIdRaw = nca?.team_id;
        const teamId = teamIdRaw === null || teamIdRaw === undefined ? null : Number(teamIdRaw);
        const teamIdSafe = teamId === null || Number.isNaN(teamId) ? null : teamId;

        return {
          non_contract_amount_id: nca.non_contract_amount_id,
          player_id: nca?.player_id ?? null,
          team_id: teamIdSafe,
          team_code: teamIdSafe !== null ? (teamCodeMap.get(teamIdSafe) ?? null) : null,
          salary_year: nca?.non_contract_year ?? null,
          amount_type_lk: nca?.non_contract_amount_type_lk ?? nca?.amount_type_lk ?? null,

          cap_amount: nca?.cap_amount ?? null,
          tax_amount: nca?.tax_amount ?? null,
          apron_amount: nca?.apron_amount ?? null,
          fa_amount: nca?.fa_amount ?? null,
          fa_amount_calc: nca?.fa_amount_calc ?? null,
          salary_fa_amount: nca?.salary_fa_amount ?? null,

          qo_amount: nca?.qo_amount ?? null,
          rofr_amount: nca?.rofr_amount ?? null,
          rookie_scale_amount: firstScalar(nca?.rookie_scale_amount),

          carry_over_fa_flg: nca?.carry_over_fa_flg ?? null,
          fa_amount_type_lk: nca?.free_agent_amount_type_lk ?? null,
          fa_amount_type_lk_calc: nca?.free_agent_amount_type_lk_calc ?? null,
          free_agent_designation_lk: nca?.free_agent_designation_lk ?? null,
          free_agent_status_lk: nca?.free_agent_status_lk ?? null,
          min_contract_lk: nca?.min_contract_lk ?? null,

          contract_id: nca?.contract_id ?? null,
          contract_type_lk: nca?.contract_type_lk ?? null,
          transaction_id: nca?.transaction_id ?? null,

          version_number: nca?.version_number ?? null,
          years_of_service: nca?.years_of_service ?? null,

          created_at: nca?.create_date ?? null,
          updated_at: nca?.last_change_date ?? null,
          record_changed_at: nca?.record_change_date ?? null,
          ingested_at: ingestedAt,
        };
      })
      .filter(Boolean) as Record<string, any>[];

    const scaleRows = salaryScales
      .map((s) => {
        const salaryYear = toIntOrNull(s?.salary_year);
        const league = s?.league_lk ?? null;
        const yos = toIntOrNull(s?.years_of_service);

        if (salaryYear === null || league === null || yos === null) return null;

        // The extract provides minimum_salary_year1..year5; schema stores a single minimum.
        // Store minimum_salary_year1 as the minimum salary amount for that season / YOS.
        return {
          salary_year: salaryYear,
          league_lk: league,
          years_of_service: yos,
          minimum_salary_amount: toNumOrNull(s?.minimum_salary_year1),
          created_at: s?.create_date ?? null,
          updated_at: s?.last_change_date ?? null,
          record_changed_at: s?.record_change_date ?? null,
          ingested_at: ingestedAt,
        };
      })
      .filter(Boolean) as Record<string, any>[];

    const projectionRows = capProjections
      .map((p) => {
        const projectionId = toIntOrNull(p?.salary_cap_projection_id);
        const salaryYear = toIntOrNull(p?.season_year);

        if (projectionId === null || salaryYear === null) return null;

        return {
          projection_id: projectionId,
          salary_year: salaryYear,
          cap_amount: toNumOrNull(p?.cap_amount),
          tax_level_amount: toNumOrNull(p?.tax_level),
          estimated_average_player_salary: toNumOrNull(p?.estimated_average_player_salary),
          growth_rate: toNumOrNull(p?.growth_rate),
          effective_date: p?.effective_date ?? null,
          is_generated: toBoolOrNull(p?.generated_flg),
          created_at: p?.create_date ?? null,
          updated_at: p?.last_change_date ?? null,
          record_changed_at: p?.record_change_date ?? null,
          ingested_at: ingestedAt,
        };
      })
      .filter(Boolean) as Record<string, any>[];

    const leagueTaxRateRows = taxRates
      .map((tr) => {
        const league_lk = tr?.league_lk ?? "NBA";
        const salary_year = toIntOrNull(tr?.salary_year);
        const lower_limit = toNumOrNull(tr?.lower_limit);

        if (!league_lk || salary_year === null || lower_limit === null) return null;

        return {
          league_lk,
          salary_year,
          lower_limit,
          upper_limit: toNumOrNull(tr?.upper_limit),
          tax_rate_non_repeater: toNumOrNull(tr?.tax_rate_non_repeater),
          tax_rate_repeater: toNumOrNull(tr?.tax_rate_repeater),
          base_charge_non_repeater: toNumOrNull(tr?.base_charge_non_repeater),
          base_charge_repeater: toNumOrNull(tr?.base_charge_repeater),
          created_at: tr?.create_date ?? null,
          updated_at: tr?.last_change_date ?? null,
          record_changed_at: tr?.record_change_date ?? null,
          ingested_at: ingestedAt,
        };
      })
      .filter(Boolean) as Record<string, any>[];

    // ─────────────────────────────────────────────────────────────────────────
    // Upfront dedupe (entire dataset, then batch)
    // ─────────────────────────────────────────────────────────────────────────

    const leagueSystemValueDeduped = dedupeByKey(
      leagueSystemValueRows,
      (r) => `${r.league_lk}|${r.salary_year}`
    );
    const rookieScaleDeduped = dedupeByKey(
      rookieScaleRows,
      (r) => `${r.salary_year}|${r.pick_number}|${r.league_lk}`
    );
    const nonContractDeduped = dedupeByKey(
      nonContractAmountRows,
      (r) => String(r.non_contract_amount_id)
    );
    const scaleDeduped = dedupeByKey(
      scaleRows,
      (r) => `${r.salary_year}|${r.league_lk}|${r.years_of_service}`
    );
    const projectionDeduped = dedupeByKey(projectionRows, (r) => String(r.projection_id));
    const taxRateDeduped = dedupeByKey(
      leagueTaxRateRows,
      (r) => `${r.league_lk}|${r.salary_year}|${r.lower_limit}`
    );

    if (dry_run) {
      return {
        dry_run: true,
        started_at: startedAt,
        finished_at: new Date().toISOString(),
        tables: [
          { table: "pcms.league_system_values", attempted: leagueSystemValueDeduped.length, success: true },
          { table: "pcms.rookie_scale_amounts", attempted: rookieScaleDeduped.length, success: true },
          { table: "pcms.non_contract_amounts", attempted: nonContractDeduped.length, success: true },
          { table: "pcms.league_salary_scales", attempted: scaleDeduped.length, success: true },
          { table: "pcms.league_salary_cap_projections", attempted: projectionDeduped.length, success: true },
          { table: "pcms.league_tax_rates", attempted: taxRateDeduped.length, success: true },
          { table: "pcms.apron_constraints", attempted: "(derived from lookups × system_values)", success: true },
        ],
        errors: [],
      };
    }

    const BATCH_SIZE_SMALL = 500;
    const BATCH_SIZE_LARGE = 200;

    // ── league_system_values ────────────────────────────────────────────────

    if (leagueSystemValueDeduped.length > 0) {
      for (let i = 0; i < leagueSystemValueDeduped.length; i += BATCH_SIZE_SMALL) {
        const batch = leagueSystemValueDeduped.slice(i, i + BATCH_SIZE_SMALL);

        await sql`
          INSERT INTO pcms.league_system_values ${sql(batch)}
          ON CONFLICT (league_lk, salary_year) DO UPDATE SET
            salary_cap_amount = EXCLUDED.salary_cap_amount,
            tax_level_amount = EXCLUDED.tax_level_amount,
            tax_apron_amount = EXCLUDED.tax_apron_amount,
            tax_apron2_amount = EXCLUDED.tax_apron2_amount,
            tax_bracket_amount = EXCLUDED.tax_bracket_amount,
            minimum_team_salary_amount = EXCLUDED.minimum_team_salary_amount,
            maximum_salary_25_pct = EXCLUDED.maximum_salary_25_pct,
            maximum_salary_30_pct = EXCLUDED.maximum_salary_30_pct,
            maximum_salary_35_pct = EXCLUDED.maximum_salary_35_pct,
            average_salary_amount = EXCLUDED.average_salary_amount,
            estimated_average_salary_amount = EXCLUDED.estimated_average_salary_amount,
            non_taxpayer_mid_level_amount = EXCLUDED.non_taxpayer_mid_level_amount,
            taxpayer_mid_level_amount = EXCLUDED.taxpayer_mid_level_amount,
            room_mid_level_amount = EXCLUDED.room_mid_level_amount,
            bi_annual_amount = EXCLUDED.bi_annual_amount,
            two_way_salary_amount = EXCLUDED.two_way_salary_amount,
            two_way_dlg_salary_amount = EXCLUDED.two_way_dlg_salary_amount,
            wnba_offseason_end_at = EXCLUDED.wnba_offseason_end_at,
            tpe_dollar_allowance = EXCLUDED.tpe_dollar_allowance,
            max_trade_cash_amount = EXCLUDED.max_trade_cash_amount,
            international_player_payment_limit = EXCLUDED.international_player_payment_limit,
            scale_raise_rate = EXCLUDED.scale_raise_rate,
            days_in_season = EXCLUDED.days_in_season,
            season_start_at = EXCLUDED.season_start_at,
            season_end_at = EXCLUDED.season_end_at,
            playing_start_at = EXCLUDED.playing_start_at,
            playing_end_at = EXCLUDED.playing_end_at,
            finals_end_at = EXCLUDED.finals_end_at,
            training_camp_start_at = EXCLUDED.training_camp_start_at,
            training_camp_end_at = EXCLUDED.training_camp_end_at,
            rookie_camp_start_at = EXCLUDED.rookie_camp_start_at,
            rookie_camp_end_at = EXCLUDED.rookie_camp_end_at,
            draft_at = EXCLUDED.draft_at,
            moratorium_end_at = EXCLUDED.moratorium_end_at,
            trade_deadline_at = EXCLUDED.trade_deadline_at,
            cut_down_at = EXCLUDED.cut_down_at,
            two_way_cut_down_at = EXCLUDED.two_way_cut_down_at,
            notification_start_at = EXCLUDED.notification_start_at,
            notification_end_at = EXCLUDED.notification_end_at,
            exception_start_at = EXCLUDED.exception_start_at,
            exception_prorate_at = EXCLUDED.exception_prorate_at,
            exceptions_added_at = EXCLUDED.exceptions_added_at,
            rnd2_pick_exc_zero_cap_end_at = EXCLUDED.rnd2_pick_exc_zero_cap_end_at,
            bonuses_finalized_at = EXCLUDED.bonuses_finalized_at,
            is_bonuses_finalized = EXCLUDED.is_bonuses_finalized,
            is_cap_projection_generated = EXCLUDED.is_cap_projection_generated,
            is_exceptions_added = EXCLUDED.is_exceptions_added,
            free_agent_status_finalized_at = EXCLUDED.free_agent_status_finalized_at,
            is_free_agent_amounts_finalized = EXCLUDED.is_free_agent_amounts_finalized,
            wnba_season_finalized_at = EXCLUDED.wnba_season_finalized_at,
            is_wnba_season_finalized = EXCLUDED.is_wnba_season_finalized,
            dlg_countable_roster_moves = EXCLUDED.dlg_countable_roster_moves,
            dlg_max_level_a_salary_players = EXCLUDED.dlg_max_level_a_salary_players,
            dlg_salary_level_a = EXCLUDED.dlg_salary_level_a,
            dlg_salary_level_b = EXCLUDED.dlg_salary_level_b,
            dlg_salary_level_c = EXCLUDED.dlg_salary_level_c,
            dlg_team_salary_budget = EXCLUDED.dlg_team_salary_budget,
            created_at = EXCLUDED.created_at,
            updated_at = EXCLUDED.updated_at,
            record_changed_at = EXCLUDED.record_changed_at,
            ingested_at = EXCLUDED.ingested_at
        `;
      }
      tables.push({ table: "pcms.league_system_values", attempted: leagueSystemValueDeduped.length, success: true });
    }

    // ── rookie_scale_amounts ────────────────────────────────────────────────

    if (rookieScaleDeduped.length > 0) {
      for (let i = 0; i < rookieScaleDeduped.length; i += BATCH_SIZE_SMALL) {
        const batch = rookieScaleDeduped.slice(i, i + BATCH_SIZE_SMALL);

        await sql`
          INSERT INTO pcms.rookie_scale_amounts ${sql(batch)}
          ON CONFLICT (salary_year, pick_number, league_lk) DO UPDATE SET
            salary_year_1 = EXCLUDED.salary_year_1,
            salary_year_2 = EXCLUDED.salary_year_2,
            salary_year_3 = EXCLUDED.salary_year_3,
            salary_year_4 = EXCLUDED.salary_year_4,
            option_amount_year_3 = EXCLUDED.option_amount_year_3,
            option_amount_year_4 = EXCLUDED.option_amount_year_4,
            option_pct_year_3 = EXCLUDED.option_pct_year_3,
            option_pct_year_4 = EXCLUDED.option_pct_year_4,
            is_baseline_scale = EXCLUDED.is_baseline_scale,
            is_active = EXCLUDED.is_active,
            created_at = EXCLUDED.created_at,
            updated_at = EXCLUDED.updated_at,
            record_changed_at = EXCLUDED.record_changed_at,
            ingested_at = EXCLUDED.ingested_at
        `;
      }
      tables.push({ table: "pcms.rookie_scale_amounts", attempted: rookieScaleDeduped.length, success: true });
    }

    // ── non_contract_amounts ────────────────────────────────────────────────

    if (nonContractDeduped.length > 0) {
      for (let i = 0; i < nonContractDeduped.length; i += BATCH_SIZE_LARGE) {
        const batch = nonContractDeduped.slice(i, i + BATCH_SIZE_LARGE);

        await sql`
          INSERT INTO pcms.non_contract_amounts ${sql(batch)}
          ON CONFLICT (non_contract_amount_id) DO UPDATE SET
            player_id = EXCLUDED.player_id,
            team_id = EXCLUDED.team_id,
            team_code = EXCLUDED.team_code,
            salary_year = EXCLUDED.salary_year,
            amount_type_lk = EXCLUDED.amount_type_lk,
            cap_amount = EXCLUDED.cap_amount,
            tax_amount = EXCLUDED.tax_amount,
            apron_amount = EXCLUDED.apron_amount,
            fa_amount = EXCLUDED.fa_amount,
            fa_amount_calc = EXCLUDED.fa_amount_calc,
            salary_fa_amount = EXCLUDED.salary_fa_amount,
            qo_amount = EXCLUDED.qo_amount,
            rofr_amount = EXCLUDED.rofr_amount,
            rookie_scale_amount = EXCLUDED.rookie_scale_amount,
            carry_over_fa_flg = EXCLUDED.carry_over_fa_flg,
            fa_amount_type_lk = EXCLUDED.fa_amount_type_lk,
            fa_amount_type_lk_calc = EXCLUDED.fa_amount_type_lk_calc,
            free_agent_designation_lk = EXCLUDED.free_agent_designation_lk,
            free_agent_status_lk = EXCLUDED.free_agent_status_lk,
            min_contract_lk = EXCLUDED.min_contract_lk,
            contract_id = EXCLUDED.contract_id,
            contract_type_lk = EXCLUDED.contract_type_lk,
            transaction_id = EXCLUDED.transaction_id,
            version_number = EXCLUDED.version_number,
            years_of_service = EXCLUDED.years_of_service,
            created_at = EXCLUDED.created_at,
            updated_at = EXCLUDED.updated_at,
            record_changed_at = EXCLUDED.record_changed_at,
            ingested_at = EXCLUDED.ingested_at
        `;
      }
      tables.push({ table: "pcms.non_contract_amounts", attempted: nonContractDeduped.length, success: true });
    }

    // ── league_salary_scales ────────────────────────────────────────────────

    if (scaleDeduped.length > 0) {
      for (let i = 0; i < scaleDeduped.length; i += BATCH_SIZE_SMALL) {
        const batch = scaleDeduped.slice(i, i + BATCH_SIZE_SMALL);

        await sql`
          INSERT INTO pcms.league_salary_scales ${sql(batch)}
          ON CONFLICT (salary_year, league_lk, years_of_service) DO UPDATE SET
            minimum_salary_amount = EXCLUDED.minimum_salary_amount,
            created_at = EXCLUDED.created_at,
            updated_at = EXCLUDED.updated_at,
            record_changed_at = EXCLUDED.record_changed_at,
            ingested_at = EXCLUDED.ingested_at
        `;
      }
      tables.push({ table: "pcms.league_salary_scales", attempted: scaleDeduped.length, success: true });
    }

    // ── league_salary_cap_projections ───────────────────────────────────────

    if (projectionDeduped.length > 0) {
      for (let i = 0; i < projectionDeduped.length; i += BATCH_SIZE_SMALL) {
        const batch = projectionDeduped.slice(i, i + BATCH_SIZE_SMALL);

        await sql`
          INSERT INTO pcms.league_salary_cap_projections ${sql(batch)}
          ON CONFLICT (projection_id) DO UPDATE SET
            salary_year = EXCLUDED.salary_year,
            cap_amount = EXCLUDED.cap_amount,
            tax_level_amount = EXCLUDED.tax_level_amount,
            estimated_average_player_salary = EXCLUDED.estimated_average_player_salary,
            growth_rate = EXCLUDED.growth_rate,
            effective_date = EXCLUDED.effective_date,
            is_generated = EXCLUDED.is_generated,
            created_at = EXCLUDED.created_at,
            updated_at = EXCLUDED.updated_at,
            record_changed_at = EXCLUDED.record_changed_at,
            ingested_at = EXCLUDED.ingested_at
        `;
      }
      tables.push({ table: "pcms.league_salary_cap_projections", attempted: projectionDeduped.length, success: true });
    }

    // ── league_tax_rates ────────────────────────────────────────────────────

    if (taxRateDeduped.length > 0) {
      for (let i = 0; i < taxRateDeduped.length; i += BATCH_SIZE_SMALL) {
        const batch = taxRateDeduped.slice(i, i + BATCH_SIZE_SMALL);

        await sql`
          INSERT INTO pcms.league_tax_rates ${sql(batch)}
          ON CONFLICT (league_lk, salary_year, lower_limit) DO UPDATE SET
            upper_limit = EXCLUDED.upper_limit,
            tax_rate_non_repeater = EXCLUDED.tax_rate_non_repeater,
            tax_rate_repeater = EXCLUDED.tax_rate_repeater,
            base_charge_non_repeater = EXCLUDED.base_charge_non_repeater,
            base_charge_repeater = EXCLUDED.base_charge_repeater,
            updated_at = EXCLUDED.updated_at,
            record_changed_at = EXCLUDED.record_changed_at,
            ingested_at = EXCLUDED.ingested_at
        `;
      }
      tables.push({ table: "pcms.league_tax_rates", attempted: taxRateDeduped.length, success: true });
    }

    // ── apron_constraints ───────────────────────────────────────────────────
    // Derived from pcms.lookups (lk_subject_to_apron_reasons) × pcms.league_system_values
    // Creates a row for each constraint × year where aprons are active

    const apronResult = await sql`
      INSERT INTO pcms.apron_constraints (
        apron_level_lk,
        constraint_code,
        effective_salary_year,
        description,
        created_at,
        updated_at,
        ingested_at
      )
      SELECT 
        lk.lookup_code as apron_level_lk,
        lk.properties_json->>'subject_to_apron_reason_lk' as constraint_code,
        ysv.salary_year as effective_salary_year,
        lk.description,
        lk.created_at,
        lk.updated_at,
        NOW() as ingested_at
      FROM pcms.lookups lk
      CROSS JOIN pcms.league_system_values ysv
      WHERE lk.lookup_type = 'lk_subject_to_apron_reasons'
        AND lk.is_active = true
        AND ysv.tax_apron_amount > 0
        AND lk.properties_json->>'subject_to_apron_reason_lk' IS NOT NULL
      ON CONFLICT (apron_level_lk, constraint_code, effective_salary_year) DO NOTHING
      RETURNING 1
    `;
    const apronCount = apronResult?.length ?? 0;
    console.log(`Derived ${apronCount} apron_constraints from lookups × system_values`);
    tables.push({ table: "pcms.apron_constraints", attempted: apronCount, success: true });

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
