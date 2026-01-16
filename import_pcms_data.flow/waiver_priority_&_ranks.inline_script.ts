/**
 * Waiver Priority & Ranks (plus Tax configuration)
 *
 * Reads clean JSON from lineage step and upserts into:
 * - pcms.waiver_priority           (waiver_priority.json)
 * - pcms.waiver_priority_ranks     (waiver_priority.json)
 * - pcms.league_tax_rates          (tax_rates.json)
 * - pcms.tax_team_status           (tax_teams.json)
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
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

function asArray<T = any>(val: any): T[] {
  if (val === null || val === undefined) return [];
  return Array.isArray(val) ? val : [val];
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
    const waiverFile = Bun.file(`${baseDir}/waiver_priority.json`);
    const taxRatesFile = Bun.file(`${baseDir}/tax_rates.json`);
    const taxTeamsFile = Bun.file(`${baseDir}/tax_teams.json`);

    const waiverExtract: any = (await waiverFile.exists()) ? await waiverFile.json() : null;
    const taxRates: any[] = (await taxRatesFile.exists()) ? await taxRatesFile.json() : [];
    const taxTeams: any[] = (await taxTeamsFile.exists()) ? await taxTeamsFile.json() : [];

    const waiverPriorities: any[] = waiverExtract
      ? Array.isArray(waiverExtract)
        ? waiverExtract
        : asArray<any>(waiverExtract?.waiver_priority)
      : [];

    console.log(
      `Found waiver_priorities=${waiverPriorities.length}, tax_rates=${taxRates.length}, tax_teams=${taxTeams.length}`
    );

    const ingestedAt = new Date();
    const provenance = {
      ingested_at: ingestedAt,
    };

    // ─────────────────────────────────────────────────────────────────────────
    // waiver_priority + waiver_priority_ranks
    // ─────────────────────────────────────────────────────────────────────────

    const waiverPriorityRows: Record<string, any>[] = [];
    const waiverPriorityRankRows: Record<string, any>[] = [];

    for (const wp of waiverPriorities) {
      const waiverPriorityId = wp?.waiver_priority_id;
      if (waiverPriorityId === null || waiverPriorityId === undefined) continue;

      waiverPriorityRows.push({
        waiver_priority_id: waiverPriorityId,
        priority_date: wp?.priority_date ?? null,
        seqno: wp?.seqno ?? null,
        status_lk: wp?.record_status_lk ?? wp?.status_lk ?? null,
        comments: wp?.comments ?? null,
        created_at: wp?.create_date ?? null,
        updated_at: wp?.last_change_date ?? null,
        record_changed_at: wp?.record_change_date ?? null,
        ...provenance,
      });

      const ranks = asArray<any>(wp?.waiver_priority_ranks?.waiver_priority_rank);
      for (const r of ranks) {
        const waiverPriorityRankId = r?.waiver_priority_detail_id ?? r?.waiver_priority_rank_id;
        if (waiverPriorityRankId === null || waiverPriorityRankId === undefined) continue;

        waiverPriorityRankRows.push({
          waiver_priority_rank_id: waiverPriorityRankId,
          waiver_priority_id: waiverPriorityId,
          team_id: r?.team_id ?? null,
          priority_order: r?.priority_order ?? null,
          is_order_priority: r?.order_priority_flg ?? null,
          exclusivity_status_lk: r?.exclusivity_status_lk ?? null,
          exclusivity_expiration_date: r?.exclusivity_expiration_date ?? null,
          status_lk: r?.record_status_lk ?? r?.status_lk ?? null,
          seqno: r?.seqno ?? null,
          comments: r?.comments ?? null,
          created_at: r?.create_date ?? null,
          updated_at: r?.last_change_date ?? null,
          record_changed_at: r?.record_change_date ?? null,
          ...provenance,
        });
      }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // league_tax_rates
    // ─────────────────────────────────────────────────────────────────────────

    const leagueTaxRateRows: Record<string, any>[] = taxRates
      .map((tr) => {
        const league_lk = tr?.league_lk ?? "NBA";
        const salary_year = tr?.salary_year ?? null;
        const lower_limit = tr?.lower_limit ?? null;

        if (!league_lk || salary_year === null || salary_year === undefined || lower_limit === null || lower_limit === undefined) {
          return null;
        }

        return {
          league_lk,
          salary_year,
          lower_limit,
          upper_limit: tr?.upper_limit ?? null,
          tax_rate_non_repeater: tr?.tax_rate_non_repeater ?? null,
          tax_rate_repeater: tr?.tax_rate_repeater ?? null,
          base_charge_non_repeater: tr?.base_charge_non_repeater ?? null,
          base_charge_repeater: tr?.base_charge_repeater ?? null,
          created_at: tr?.create_date ?? null,
          updated_at: tr?.last_change_date ?? null,
          record_changed_at: tr?.record_change_date ?? null,
          ...provenance,
        };
      })
      .filter(Boolean) as Record<string, any>[];

    // ─────────────────────────────────────────────────────────────────────────
    // tax_team_status
    // ─────────────────────────────────────────────────────────────────────────

    const taxTeamStatusRows: Record<string, any>[] = taxTeams
      .map((tt) => {
        const team_id = tt?.team_id ?? null;
        const salary_year = tt?.salary_year ?? null;
        if (team_id === null || team_id === undefined || salary_year === null || salary_year === undefined) return null;

        return {
          team_id,
          salary_year,
          is_taxpayer: tt?.taxpayer_flg ?? false,
          is_repeater_taxpayer: tt?.taxpayer_repeater_rate_flg ?? false,
          is_subject_to_apron: tt?.subject_to_apron_flg ?? false,
          apron_level_lk: tt?.apron_level_lk ?? null,
          subject_to_apron_reason_lk: tt?.subject_to_apron_reason_lk ?? null,
          apron1_transaction_id: tt?.apron1_transaction_id ?? null,
          apron2_transaction_id: tt?.apron2_transaction_id ?? null,
          created_at: tt?.create_date ?? null,
          updated_at: tt?.last_change_date ?? null,
          record_changed_at: tt?.record_change_date ?? null,
          ...provenance,
        };
      })
      .filter(Boolean) as Record<string, any>[];

    // ─────────────────────────────────────────────────────────────────────────
    // Dry run summary
    // ─────────────────────────────────────────────────────────────────────────

    if (dry_run) {
      return {
        dry_run: true,
        started_at: startedAt,
        finished_at: new Date().toISOString(),
        tables: [
          { table: "pcms.waiver_priority", attempted: waiverPriorityRows.length, success: true },
          { table: "pcms.waiver_priority_ranks", attempted: waiverPriorityRankRows.length, success: true },
          { table: "pcms.league_tax_rates", attempted: leagueTaxRateRows.length, success: true },
          { table: "pcms.tax_team_status", attempted: taxTeamStatusRows.length, success: true },
        ],
        errors: [],
      };
    }

    const BATCH_SIZE = 1000;

    // ─────────────────────────────────────────────────────────────────────────
    // Upsert: waiver_priority
    // ─────────────────────────────────────────────────────────────────────────

    for (let i = 0; i < waiverPriorityRows.length; i += BATCH_SIZE) {
      const batch = waiverPriorityRows.slice(i, i + BATCH_SIZE);
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

    // ─────────────────────────────────────────────────────────────────────────
    // Upsert: waiver_priority_ranks
    // ─────────────────────────────────────────────────────────────────────────

    for (let i = 0; i < waiverPriorityRankRows.length; i += BATCH_SIZE) {
      const batch = waiverPriorityRankRows.slice(i, i + BATCH_SIZE);
      if (batch.length === 0) continue;

      await sql`
        INSERT INTO pcms.waiver_priority_ranks ${sql(batch)}
        ON CONFLICT (waiver_priority_rank_id) DO UPDATE SET
          waiver_priority_id = EXCLUDED.waiver_priority_id,
          team_id = EXCLUDED.team_id,
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

    // ─────────────────────────────────────────────────────────────────────────
    // Upsert: league_tax_rates
    // ─────────────────────────────────────────────────────────────────────────

    for (let i = 0; i < leagueTaxRateRows.length; i += BATCH_SIZE) {
      const batch = leagueTaxRateRows.slice(i, i + BATCH_SIZE);
      if (batch.length === 0) continue;

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

    // ─────────────────────────────────────────────────────────────────────────
    // Upsert: tax_team_status
    // ─────────────────────────────────────────────────────────────────────────

    for (let i = 0; i < taxTeamStatusRows.length; i += BATCH_SIZE) {
      const batch = taxTeamStatusRows.slice(i, i + BATCH_SIZE);
      if (batch.length === 0) continue;

      await sql`
        INSERT INTO pcms.tax_team_status ${sql(batch)}
        ON CONFLICT (team_id, salary_year) DO UPDATE SET
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

    return {
      dry_run: false,
      started_at: startedAt,
      finished_at: new Date().toISOString(),
      tables: [
        { table: "pcms.waiver_priority", attempted: waiverPriorityRows.length, success: true },
        { table: "pcms.waiver_priority_ranks", attempted: waiverPriorityRankRows.length, success: true },
        { table: "pcms.league_tax_rates", attempted: leagueTaxRateRows.length, success: true },
        { table: "pcms.tax_team_status", attempted: taxTeamStatusRows.length, success: true },
      ],
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