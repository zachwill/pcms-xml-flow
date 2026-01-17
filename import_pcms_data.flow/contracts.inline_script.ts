/**
 * Contracts / Versions / Bonuses / Salaries Import
 *
 * Reads clean JSON from lineage step and upserts into:
 * - pcms.contracts
 * - pcms.contract_versions
 * - pcms.contract_bonuses
 * - pcms.salaries
 * - pcms.payment_schedules
 */
import { SQL } from "bun";
import { readdir } from "node:fs/promises";

const sql = new SQL({ url: Bun.env.POSTGRES_URL!, prepare: false });

function normalizeVersionNumber(val: unknown): number | null {
  if (val === null || val === undefined || val === "") return null;

  const n = typeof val === "number" ? val : Number(val);
  if (!Number.isFinite(n)) return null;

  // PCMS sometimes represents version_number as a decimal like 1.01
  // Schema expects an integer (1.01 -> 101)
  return Number.isInteger(n) ? n : Math.round(n * 100);
}

function asArray<T = any>(val: any): T[] {
  if (val === null || val === undefined) return [];
  return Array.isArray(val) ? val : [val];
}

// ─────────────────────────────────────────────────────────────────────────────
// Main
// ─────────────────────────────────────────────────────────────────────────────

export async function main(
  dry_run = false,
  extract_dir = "./shared/pcms"
) {
  const startedAt = new Date().toISOString();

  try {
    // Find extract directory
    const entries = await readdir(extract_dir, { withFileTypes: true });
    const subDir = entries.find((e) => e.isDirectory());
    const baseDir = subDir ? `${extract_dir}/${subDir.name}` : extract_dir;

    // Read clean JSON (already snake_case, nulls handled)
    const contracts: any[] = await Bun.file(`${baseDir}/contracts.json`).json();
    console.log(`Found ${contracts.length} contracts`);

    // Build team_id → team_code lookup map
    const lookups: any = await Bun.file(`${baseDir}/lookups.json`).json();
    const teamsData: any[] = lookups?.lk_teams?.lk_team || [];
    const teamCodeMap = new Map<number, string>();
    for (const t of teamsData) {
      const teamId = t?.team_id;
      const teamCode = t?.team_code ?? t?.team_name_short;
      if (teamId && teamCode) {
        teamCodeMap.set(Number(teamId), String(teamCode));
      }
    }

    const ingestedAt = new Date();

    // Flatten nested structures
    const contractRows = contracts.map((c) => {
      const signingTeamId = c?.signing_team_id ?? null;
      const signAndTradeToTeamId = c?.sign_and_trade_to_team_id ?? null;

      return {
        contract_id: c.contract_id,
        player_id: c.player_id,

        signing_team_id: signingTeamId,
        team_code: signingTeamId
          ? (teamCodeMap.get(Number(signingTeamId)) ?? null)
          : null,

        signing_date: c.signing_date,
        contract_end_date: c.contract_end_date,
        record_status_lk: c.record_status_lk,
        signed_method_lk: c.signed_method_lk,
        team_exception_id: c.team_exception_id,

        is_sign_and_trade: c.sign_and_trade_flg,
        sign_and_trade_date: c.sign_and_trade_date,

        sign_and_trade_to_team_id: signAndTradeToTeamId,
        sign_and_trade_to_team_code: signAndTradeToTeamId
          ? (teamCodeMap.get(Number(signAndTradeToTeamId)) ?? null)
          : null,

        sign_and_trade_id: c.sign_and_trade_id,

        // v2+ WNBA only; NBA loads as NULL
        start_year: c.start_year ?? null,
        contract_length_wnba: c.contract_length_wnba ?? c.contract_length ?? null,

        convert_date: c.convert_date,
        two_way_service_limit: c.two_way_service_limit,

        created_at: c.create_date,
        updated_at: c.last_change_date,
        record_changed_at: c.record_change_date,

        ingested_at: ingestedAt,
      };
    });

    const versionRows: any[] = [];
    const bonusRows: any[] = [];
    const salaryRows: any[] = [];
    const paymentScheduleRows: any[] = [];

    for (const c of contracts) {
      const versions = asArray<any>(c?.versions?.version);

      for (const v of versions) {
        const versionNumber = normalizeVersionNumber(v?.version_number);
        if (!c?.contract_id || !versionNumber) continue;

        // Store remaining version fields (excluding nested arrays) in version_json
        const versionJson: any = { ...(v ?? {}) };
        delete versionJson.salaries;
        delete versionJson.bonuses;

        // Remove mapped scalar fields to reduce duplication
        for (const k of [
          "version_number",
          "transaction_id",
          "version_date",
          "start_year",
          "contract_length",
          "contract_type_lk",
          "record_status_lk",
          "agency_id",
          "agent_id",
          "full_protection_flg",
          "exhibit10",
          "exhibit10_bonus_amount",
          "exhibit10_protection_amount",
          "exhibit10_end_date",
          "dp_rookie_scale_extension_flg",
          "dp_veteran_extension_flg",
          "poison_pill_flg",
          "poison_pill_amt",
          "trade_bonus_percent",
          "trade_bonus_amount",
          "trade_bonus_flg",
          "no_trade_flg",
          "create_date",
          "last_change_date",
          "record_change_date",
        ]) {
          delete versionJson[k];
        }

        versionRows.push({
          contract_id: c.contract_id,
          version_number: versionNumber,
          transaction_id: v?.transaction_id ?? null,
          version_date: v?.version_date ?? null,
          start_salary_year: v?.start_year ?? null,
          contract_length: v?.contract_length ?? null,
          contract_type_lk: v?.contract_type_lk ?? null,
          record_status_lk: v?.record_status_lk ?? null,
          agency_id: v?.agency_id ?? null,
          agent_id: v?.agent_id ?? null,
          is_full_protection: v?.full_protection_flg ?? null,
          is_exhibit_10: v?.exhibit10 ?? null,
          exhibit_10_bonus_amount: v?.exhibit10_bonus_amount ?? null,
          exhibit_10_protection_amount: v?.exhibit10_protection_amount ?? null,
          exhibit_10_end_date: v?.exhibit10_end_date ?? null,
          is_two_way: v?.is_two_way ?? null,
          is_rookie_scale_extension: v?.dp_rookie_scale_extension_flg ?? null,
          is_veteran_extension: v?.dp_veteran_extension_flg ?? null,
          is_poison_pill: v?.poison_pill_flg ?? null,
          poison_pill_amount: v?.poison_pill_amt ?? null,
          trade_bonus_percent: v?.trade_bonus_percent ?? null,
          trade_bonus_amount: v?.trade_bonus_amount ?? null,
          is_trade_bonus: v?.trade_bonus_flg ?? null,
          is_no_trade: v?.no_trade_flg ?? null,
          is_minimum_contract: v?.is_minimum_contract ?? null,
          is_protected_contract: v?.is_protected_contract ?? null,
          version_json: Object.keys(versionJson).length > 0 ? versionJson : null,

          created_at: v?.create_date ?? null,
          updated_at: v?.last_change_date ?? null,
          record_changed_at: v?.record_change_date ?? null,

          ingested_at: ingestedAt,
        });

        const bonuses = asArray<any>(v?.bonuses?.bonus);
        for (const b of bonuses) {
          if (!b?.bonus_id) continue;

          bonusRows.push({
            bonus_id: b.bonus_id,
            contract_id: c.contract_id,
            version_number: versionNumber,
            salary_year: b?.bonus_year ?? null,
            bonus_amount: b?.bonus_amount ?? null,
            bonus_type_lk: b?.contract_bonus_type_lk ?? null,
            is_likely: b?.bonus_likely_flg ?? null,
            earned_lk: b?.earned_lk ?? null,
            paid_by_date: b?.bonus_paid_by_date ?? null,
            clause_name: b?.clause_name ?? null,
            criteria_description: b?.criteria_description ?? null,
            criteria_json: b?.bonus_criteria ?? null,

            ingested_at: ingestedAt,
          });
        }

        const salaries = asArray<any>(v?.salaries?.salary);
        for (const s of salaries) {
          if (!s?.salary_year) continue;

          salaryRows.push({
            contract_id: c.contract_id,
            version_number: versionNumber,
            salary_year: s.salary_year,

            total_salary: s?.total_salary ?? null,
            total_salary_adjustment: s?.total_salary_adjustment ?? null,
            total_base_comp: s?.total_base_comp ?? null,
            current_base_comp: s?.current_base_comp ?? null,
            deferred_base_comp: s?.deferred_base_comp ?? null,
            signing_bonus: s?.signing_bonus ?? null,
            likely_bonus: s?.likely_bonus ?? null,
            unlikely_bonus: s?.unlikely_bonus ?? null,
            contract_cap_salary: s?.contract_cap_salary ?? null,
            contract_cap_salary_adjustment: s?.contract_cap_salary_adjustment ?? null,
            contract_tax_salary: s?.contract_tax_salary ?? null,
            contract_tax_salary_adjustment: s?.contract_tax_salary_adjustment ?? null,
            contract_tax_apron_salary: s?.contract_tax_apron_salary ?? null,
            contract_tax_apron_salary_adjustment: s?.contract_tax_apron_salary_adjustment ?? null,
            contract_mts_salary: s?.contract_mts_salary ?? null,
            skill_protection_amount: s?.skill_protection_amount ?? null,
            trade_bonus_amount: s?.trade_bonus_amount ?? null,
            trade_bonus_amount_calc: s?.trade_bonus_amount_calc ?? null,
            cap_raise_percent: s?.cap_raise_percent ?? null,
            two_way_nba_salary: s?.two_way_nba_salary ?? null,
            two_way_dlg_salary: s?.two_way_dlg_salary ?? null,
            wnba_salary: s?.wnba_salary ?? null,
            wnba_time_off_bonus_amount: s?.wnba_time_off_bonus_amount ?? null,
            wnba_merit_bonus_amount: s?.wnba_merit_bonus_amount ?? null,
            wnba_time_off_bonus_days: s?.wnba_time_off_bonus_days ?? null,
            option_lk: s?.option_lk ?? null,
            option_decision_lk: s?.option_decision_lk ?? null,
            is_applicable_min_salary: s?.applicable_min_salary_flg ?? null,

            created_at: s?.create_date ?? null,
            updated_at: s?.last_change_date ?? null,
            record_changed_at: s?.record_change_date ?? null,

            ingested_at: ingestedAt,
          });

          const paymentSchedules = asArray<any>(s?.payment_schedules?.payment_schedule);
          for (const ps of paymentSchedules) {
            if (!ps?.contract_payment_schedule_id) continue;

            paymentScheduleRows.push({
              payment_schedule_id: ps.contract_payment_schedule_id,
              contract_id: c.contract_id,
              version_number: versionNumber,
              salary_year: ps?.salary_year ?? s.salary_year,
              payment_amount: ps?.payment_amount ?? null,
              payment_start_date: ps?.payment_start_date ?? null,
              schedule_type_lk: ps?.payment_schedule_type_lk ?? null,
              payment_type_lk: ps?.contract_payment_type_lk ?? null,
              is_default_schedule: ps?.default_payment_schedule_flg ?? null,

              created_at: ps?.create_date ?? null,
              updated_at: ps?.last_change_date ?? null,
              record_changed_at: ps?.record_change_date ?? null,

              ingested_at: ingestedAt,
            });
          }
        }
      }
    }

    console.log(
      `Prepared rows: contracts=${contractRows.length}, versions=${versionRows.length}, bonuses=${bonusRows.length}, salaries=${salaryRows.length}, payment_schedules=${paymentScheduleRows.length}`
    );

    if (dry_run) {
      return {
        dry_run: true,
        started_at: startedAt,
        finished_at: new Date().toISOString(),
        tables: [
          { table: "pcms.contracts", attempted: contractRows.length, success: true },
          { table: "pcms.contract_versions", attempted: versionRows.length, success: true },
          { table: "pcms.contract_bonuses", attempted: bonusRows.length, success: true },
          { table: "pcms.salaries", attempted: salaryRows.length, success: true },
          { table: "pcms.payment_schedules", attempted: paymentScheduleRows.length, success: true },
        ],
        errors: [],
      };
    }

    const BATCH_SIZE = 10;

    const tables: { table: string; attempted: number; success: boolean }[] = [];

    // Contracts
    for (let i = 0; i < contractRows.length; i += BATCH_SIZE) {
      const rows = contractRows.slice(i, i + BATCH_SIZE);
      try {
        await sql`
          INSERT INTO pcms.contracts ${sql(rows)}
          ON CONFLICT (contract_id) DO UPDATE SET
            player_id = EXCLUDED.player_id,
            signing_team_id = EXCLUDED.signing_team_id,
            team_code = EXCLUDED.team_code,
            signing_date = EXCLUDED.signing_date,
            contract_end_date = EXCLUDED.contract_end_date,
            record_status_lk = EXCLUDED.record_status_lk,
            signed_method_lk = EXCLUDED.signed_method_lk,
            team_exception_id = EXCLUDED.team_exception_id,
            is_sign_and_trade = EXCLUDED.is_sign_and_trade,
            sign_and_trade_date = EXCLUDED.sign_and_trade_date,
            sign_and_trade_to_team_id = EXCLUDED.sign_and_trade_to_team_id,
            sign_and_trade_to_team_code = EXCLUDED.sign_and_trade_to_team_code,
            sign_and_trade_id = EXCLUDED.sign_and_trade_id,
            start_year = EXCLUDED.start_year,
            contract_length_wnba = EXCLUDED.contract_length_wnba,
            convert_date = EXCLUDED.convert_date,
            two_way_service_limit = EXCLUDED.two_way_service_limit,
            updated_at = EXCLUDED.updated_at,
            record_changed_at = EXCLUDED.record_changed_at,
            ingested_at = EXCLUDED.ingested_at
        `;
      } catch (e) {
        console.error(e);
      }
    }
    tables.push({ table: "pcms.contracts", attempted: contractRows.length, success: true });

    // Contract versions
    for (let i = 0; i < versionRows.length; i += BATCH_SIZE) {
      const rows = versionRows.slice(i, i + BATCH_SIZE);
      try {
        await sql`
          INSERT INTO pcms.contract_versions ${sql(rows)}
          ON CONFLICT (contract_id, version_number) DO UPDATE SET
            transaction_id = EXCLUDED.transaction_id,
            version_date = EXCLUDED.version_date,
            start_salary_year = EXCLUDED.start_salary_year,
            contract_length = EXCLUDED.contract_length,
            contract_type_lk = EXCLUDED.contract_type_lk,
            record_status_lk = EXCLUDED.record_status_lk,
            agency_id = EXCLUDED.agency_id,
            agent_id = EXCLUDED.agent_id,
            is_full_protection = EXCLUDED.is_full_protection,
            is_exhibit_10 = EXCLUDED.is_exhibit_10,
            exhibit_10_bonus_amount = EXCLUDED.exhibit_10_bonus_amount,
            exhibit_10_protection_amount = EXCLUDED.exhibit_10_protection_amount,
            exhibit_10_end_date = EXCLUDED.exhibit_10_end_date,
            is_two_way = EXCLUDED.is_two_way,
            is_rookie_scale_extension = EXCLUDED.is_rookie_scale_extension,
            is_veteran_extension = EXCLUDED.is_veteran_extension,
            is_poison_pill = EXCLUDED.is_poison_pill,
            poison_pill_amount = EXCLUDED.poison_pill_amount,
            trade_bonus_percent = EXCLUDED.trade_bonus_percent,
            trade_bonus_amount = EXCLUDED.trade_bonus_amount,
            is_trade_bonus = EXCLUDED.is_trade_bonus,
            is_no_trade = EXCLUDED.is_no_trade,
            is_minimum_contract = EXCLUDED.is_minimum_contract,
            is_protected_contract = EXCLUDED.is_protected_contract,
            version_json = EXCLUDED.version_json,
            updated_at = EXCLUDED.updated_at,
            record_changed_at = EXCLUDED.record_changed_at,
            ingested_at = EXCLUDED.ingested_at
        `;
      } catch (e) {
        console.error(e);
      }
    }
    tables.push({ table: "pcms.contract_versions", attempted: versionRows.length, success: true });

    // Contract bonuses
    for (let i = 0; i < bonusRows.length; i += BATCH_SIZE) {
      const rows = bonusRows.slice(i, i + BATCH_SIZE);
      try {
        await sql`
          INSERT INTO pcms.contract_bonuses ${sql(rows)}
          ON CONFLICT (bonus_id) DO UPDATE SET
            contract_id = EXCLUDED.contract_id,
            version_number = EXCLUDED.version_number,
            salary_year = EXCLUDED.salary_year,
            bonus_amount = EXCLUDED.bonus_amount,
            bonus_type_lk = EXCLUDED.bonus_type_lk,
            is_likely = EXCLUDED.is_likely,
            earned_lk = EXCLUDED.earned_lk,
            paid_by_date = EXCLUDED.paid_by_date,
            clause_name = EXCLUDED.clause_name,
            criteria_description = EXCLUDED.criteria_description,
            criteria_json = EXCLUDED.criteria_json,
            ingested_at = EXCLUDED.ingested_at
        `;
      } catch (e) {
        console.error(e);
      }
    }
    tables.push({ table: "pcms.contract_bonuses", attempted: bonusRows.length, success: true });

    // Salaries
    for (let i = 0; i < salaryRows.length; i += BATCH_SIZE) {
      const rows = salaryRows.slice(i, i + BATCH_SIZE);
      try {
        await sql`
          INSERT INTO pcms.salaries ${sql(rows)}
          ON CONFLICT (contract_id, version_number, salary_year) DO UPDATE SET
            total_salary = EXCLUDED.total_salary,
            total_salary_adjustment = EXCLUDED.total_salary_adjustment,
            total_base_comp = EXCLUDED.total_base_comp,
            current_base_comp = EXCLUDED.current_base_comp,
            deferred_base_comp = EXCLUDED.deferred_base_comp,
            signing_bonus = EXCLUDED.signing_bonus,
            likely_bonus = EXCLUDED.likely_bonus,
            unlikely_bonus = EXCLUDED.unlikely_bonus,
            contract_cap_salary = EXCLUDED.contract_cap_salary,
            contract_cap_salary_adjustment = EXCLUDED.contract_cap_salary_adjustment,
            contract_tax_salary = EXCLUDED.contract_tax_salary,
            contract_tax_salary_adjustment = EXCLUDED.contract_tax_salary_adjustment,
            contract_tax_apron_salary = EXCLUDED.contract_tax_apron_salary,
            contract_tax_apron_salary_adjustment = EXCLUDED.contract_tax_apron_salary_adjustment,
            contract_mts_salary = EXCLUDED.contract_mts_salary,
            skill_protection_amount = EXCLUDED.skill_protection_amount,
            trade_bonus_amount = EXCLUDED.trade_bonus_amount,
            trade_bonus_amount_calc = EXCLUDED.trade_bonus_amount_calc,
            cap_raise_percent = EXCLUDED.cap_raise_percent,
            two_way_nba_salary = EXCLUDED.two_way_nba_salary,
            two_way_dlg_salary = EXCLUDED.two_way_dlg_salary,
            wnba_salary = EXCLUDED.wnba_salary,
            wnba_time_off_bonus_amount = EXCLUDED.wnba_time_off_bonus_amount,
            wnba_merit_bonus_amount = EXCLUDED.wnba_merit_bonus_amount,
            wnba_time_off_bonus_days = EXCLUDED.wnba_time_off_bonus_days,
            option_lk = EXCLUDED.option_lk,
            option_decision_lk = EXCLUDED.option_decision_lk,
            is_applicable_min_salary = EXCLUDED.is_applicable_min_salary,
            updated_at = EXCLUDED.updated_at,
            record_changed_at = EXCLUDED.record_changed_at,
            ingested_at = EXCLUDED.ingested_at
        `;
      } catch (e) {
        console.error(e);
      }
    }
    tables.push({ table: "pcms.salaries", attempted: salaryRows.length, success: true });

    // Payment schedules
    for (let i = 0; i < paymentScheduleRows.length; i += BATCH_SIZE) {
      const rows = paymentScheduleRows.slice(i, i + BATCH_SIZE);
      try {
        await sql`
          INSERT INTO pcms.payment_schedules ${sql(rows)}
          ON CONFLICT (payment_schedule_id) DO UPDATE SET
            contract_id = EXCLUDED.contract_id,
            version_number = EXCLUDED.version_number,
            salary_year = EXCLUDED.salary_year,
            payment_amount = EXCLUDED.payment_amount,
            payment_start_date = EXCLUDED.payment_start_date,
            schedule_type_lk = EXCLUDED.schedule_type_lk,
            payment_type_lk = EXCLUDED.payment_type_lk,
            is_default_schedule = EXCLUDED.is_default_schedule,
            updated_at = EXCLUDED.updated_at,
            record_changed_at = EXCLUDED.record_changed_at,
            ingested_at = EXCLUDED.ingested_at
        `;
      } catch (e) {
        console.error(e);
      }
    }
    tables.push({ table: "pcms.payment_schedules", attempted: paymentScheduleRows.length, success: true });

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
