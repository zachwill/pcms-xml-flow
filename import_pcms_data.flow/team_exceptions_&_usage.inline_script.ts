/**
 * Team Exceptions & Usage Import
 *
 * Reads clean JSON from lineage step and upserts into:
 * - pcms.team_exceptions
 * - pcms.team_exception_usage
 *
 * Clean JSON notes:
 * - snake_case scalar fields
 * - null values already handled
 * - this extract still contains a small amount of XML-style nesting and
 *   hyphenated keys (e.g. "team-exceptions"), which we flatten here.
 */
import { SQL } from "bun";
import { readdir } from "node:fs/promises";

const sql = new SQL({ url: Bun.env.POSTGRES_URL!, prepare: false });

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

    // Build team_id → team_code lookup map
    const lookups: any = await Bun.file(`${baseDir}/lookups.json`).json();
    const teamsData: any[] = lookups?.lk_teams?.lk_team || [];
    const teamCodeMap = new Map<number, string>();
    for (const t of teamsData) {
      if (t.team_id && t.team_code) {
        teamCodeMap.set(t.team_id, t.team_code);
      }
    }

    // Read clean JSON
    const data: any = await Bun.file(`${baseDir}/team_exceptions.json`).json();

    const ingestedAt = new Date();

    const exceptionTeams = asArray<any>(data?.exception_team);

    const exceptionRows: any[] = [];
    const usageRows: any[] = [];

    for (const et of exceptionTeams) {
      const teamId = et?.team_id ?? null;

      // NOTE: this extract uses hyphenated keys
      const teamExceptions = asArray<any>(et?.["team-exceptions"]?.["team-exception"]);

      for (const te of teamExceptions) {
        const teamExceptionId = te?.team_exception_id;
        if (!teamExceptionId) continue;

        exceptionRows.push({
          team_exception_id: teamExceptionId,
          team_id: teamId,
          team_code: teamCodeMap.get(teamId) ?? null,
          salary_year: te?.team_exception_year ?? null,
          exception_type_lk: te?.exception_type_lk ?? null,
          effective_date: te?.effective_date ?? null,
          expiration_date: te?.expiration_date ?? null,
          original_amount: te?.original_amount ?? null,
          remaining_amount: te?.remaining_amount ?? null,
          proration_rate: te?.proration_rate ?? null,
          is_initially_convertible: te?.initially_convertible_flg ?? null,
          trade_exception_player_id: te?.trade_exception_player_id ?? null,
          trade_id: te?.trade_id ?? null,
          record_status_lk: te?.record_status_lk ?? null,
          created_at: te?.create_date ?? null,
          updated_at: te?.last_change_date ?? null,
          record_changed_at: te?.record_change_date ?? null,
          ingested_at: ingestedAt,
        });

        const details = asArray<any>(te?.exception_details?.exception_detail);
        for (const ed of details) {
          const detailId = ed?.team_exception_detail_id;
          if (!detailId) continue;

          usageRows.push({
            team_exception_detail_id: detailId,
            team_exception_id: teamExceptionId,
            seqno: ed?.seqno ?? null,
            effective_date: ed?.effective_date ?? null,
            exception_action_lk: ed?.exception_action_lk ?? null,
            transaction_type_lk: ed?.transaction_type_lk ?? null,
            transaction_id: ed?.transaction_id ?? null,
            player_id: ed?.player_id ?? null,
            contract_id: ed?.contract_id ?? null,
            change_amount: ed?.change_amount ?? null,
            remaining_exception_amount: ed?.remaining_exception_amount ?? null,
            proration_rate: ed?.proration_rate ?? null,
            prorate_days: ed?.prorate_days ?? null,
            is_convert_exception: ed?.convert_exception_flg ?? null,
            manual_action_text: ed?.manual_action_text ?? null,
            created_at: ed?.create_date ?? null,
            updated_at: ed?.last_change_date ?? null,
            record_changed_at: ed?.record_change_date ?? null,
            ingested_at: ingestedAt,
          });
        }
      }
    }

    console.log(
      `Found ${exceptionRows.length} team exceptions, ${usageRows.length} usage rows`
    );

    if (dry_run) {
      return {
        dry_run: true,
        started_at: startedAt,
        finished_at: new Date().toISOString(),
        tables: [
          { table: "pcms.team_exceptions", attempted: exceptionRows.length, success: true },
          { table: "pcms.team_exception_usage", attempted: usageRows.length, success: true },
        ],
        errors: [],
      };
    }

    const BATCH_SIZE = 1000;

    for (let i = 0; i < exceptionRows.length; i += BATCH_SIZE) {
      const batch = exceptionRows.slice(i, i + BATCH_SIZE);

      await sql`
        INSERT INTO pcms.team_exceptions ${sql(batch)}
        ON CONFLICT (team_exception_id) DO UPDATE SET
          team_id = EXCLUDED.team_id,
          team_code = EXCLUDED.team_code,
          salary_year = EXCLUDED.salary_year,
          exception_type_lk = EXCLUDED.exception_type_lk,
          effective_date = EXCLUDED.effective_date,
          expiration_date = EXCLUDED.expiration_date,
          original_amount = EXCLUDED.original_amount,
          remaining_amount = EXCLUDED.remaining_amount,
          proration_rate = EXCLUDED.proration_rate,
          is_initially_convertible = EXCLUDED.is_initially_convertible,
          trade_exception_player_id = EXCLUDED.trade_exception_player_id,
          trade_id = EXCLUDED.trade_id,
          record_status_lk = EXCLUDED.record_status_lk,
          updated_at = EXCLUDED.updated_at,
          record_changed_at = EXCLUDED.record_changed_at,
          ingested_at = EXCLUDED.ingested_at
      `;
    }

    for (let i = 0; i < usageRows.length; i += BATCH_SIZE) {
      const batch = usageRows.slice(i, i + BATCH_SIZE);

      await sql`
        INSERT INTO pcms.team_exception_usage ${sql(batch)}
        ON CONFLICT (team_exception_detail_id) DO UPDATE SET
          team_exception_id = EXCLUDED.team_exception_id,
          seqno = EXCLUDED.seqno,
          effective_date = EXCLUDED.effective_date,
          exception_action_lk = EXCLUDED.exception_action_lk,
          transaction_type_lk = EXCLUDED.transaction_type_lk,
          transaction_id = EXCLUDED.transaction_id,
          player_id = EXCLUDED.player_id,
          contract_id = EXCLUDED.contract_id,
          change_amount = EXCLUDED.change_amount,
          remaining_exception_amount = EXCLUDED.remaining_exception_amount,
          proration_rate = EXCLUDED.proration_rate,
          prorate_days = EXCLUDED.prorate_days,
          is_convert_exception = EXCLUDED.is_convert_exception,
          manual_action_text = EXCLUDED.manual_action_text,
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
        { table: "pcms.team_exceptions", attempted: exceptionRows.length, success: true },
        { table: "pcms.team_exception_usage", attempted: usageRows.length, success: true },
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
