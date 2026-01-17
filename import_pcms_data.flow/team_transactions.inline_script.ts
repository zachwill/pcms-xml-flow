/**
 * Team Transactions Import
 *
 * Source: team_transactions.json -> pcms.team_transactions
 */
import { SQL } from "bun";
import { readdir } from "node:fs/promises";

const sql = new SQL({ url: Bun.env.POSTGRES_URL!, prepare: false });

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

function toIntOrNull(val: unknown): number | null {
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

async function resolveBaseDir(extractDir: string): Promise<string> {
  const entries = await readdir(extractDir, { withFileTypes: true });
  const subDir = entries.find((e) => e.isDirectory());
  return subDir ? `${extractDir}/${subDir.name}` : extractDir;
}

// ─────────────────────────────────────────────────────────────────────────────
// Main
// ─────────────────────────────────────────────────────────────────────────────

export async function main(dry_run = false, extract_dir = "./shared/pcms") {
  const startedAt = new Date().toISOString();

  try {
    const baseDir = await resolveBaseDir(extract_dir);

    // Build team_id → team_code lookup map
    const lookups: any = await Bun.file(`${baseDir}/lookups.json`).json();
    const teamsData: any[] = lookups?.lk_teams?.lk_team || [];
    const teamCodeMap = new Map<number, string>();
    for (const t of teamsData) {
      if (t.team_id && t.team_code) {
        teamCodeMap.set(t.team_id, t.team_code);
      }
    }

    const teamTxFile = Bun.file(`${baseDir}/team_transactions.json`);
    const teamTx: any[] = (await teamTxFile.exists()) ? await teamTxFile.json() : [];

    console.log(`Found ${teamTx.length} team transactions`);

    const ingestedAt = new Date();

    const rows = teamTx
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

    if (dry_run) {
      return {
        dry_run: true,
        started_at: startedAt,
        finished_at: new Date().toISOString(),
        tables: [{ table: "pcms.team_transactions", attempted: rows.length, success: true }],
        errors: [],
      };
    }

    const BATCH_SIZE = 500;

    for (let i = 0; i < rows.length; i += BATCH_SIZE) {
      const batch = rows.slice(i, i + BATCH_SIZE);

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

    return {
      dry_run: false,
      started_at: startedAt,
      finished_at: new Date().toISOString(),
      tables: [{ table: "pcms.team_transactions", attempted: rows.length, success: true }],
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
