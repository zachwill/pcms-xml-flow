/**
 * Agents & Agencies Import
 *
 * - Agencies: lookups.json -> lk_agencies.lk_agency[] -> pcms.agencies
 * - Agents: players.json filtered by person_type_lk == "AGENT" -> pcms.agents
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

function toIntOrNull(val: unknown): number | null {
  if (val === "" || val === null || val === undefined) return null;
  const n = Number(val);
  return Number.isFinite(n) ? n : null;
}

function buildFullName(firstName: unknown, lastName: unknown): string | null {
  const f = (firstName ?? "").toString().trim();
  const l = (lastName ?? "").toString().trim();
  const full = `${f} ${l}`.trim();
  return full.length ? full : null;
}

async function resolveBaseDir(extractDir: string): Promise<string> {
  const entries = await readdir(extractDir, { withFileTypes: true });
  const subDir = entries.find((e) => e.isDirectory());
  return subDir ? `${extractDir}/${subDir.name}` : extractDir;
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
    const baseDir = await resolveBaseDir(extract_dir);

    const lookupGroups: Record<string, any> = await Bun.file(`${baseDir}/lookups.json`).json();
    const players: any[] = await Bun.file(`${baseDir}/players.json`).json();

    const ingestedAt = new Date();
    const provenance = {
      source_drop_file: s3_key ?? null,
      ingested_at: ingestedAt,
    };

    // ─────────────────────────────────────────────────────────────────────────
    // Agencies
    // ─────────────────────────────────────────────────────────────────────────

    const agenciesRaw = asArray<any>(lookupGroups?.lk_agencies?.lk_agency);
    const agencies = agenciesRaw
      .map((a) => {
        const agencyId = toIntOrNull(a?.agency_id);
        if (agencyId === null) return null;

        return {
          agency_id: agencyId,
          agency_name: a?.agency_name ?? null,
          is_active: a?.active_flg ?? null,
          created_at: a?.create_date ?? null,
          updated_at: a?.last_change_date ?? null,
          record_changed_at: a?.record_change_date ?? null,
          agency_json: a ?? null,
          ...provenance,
        };
      })
      .filter(Boolean) as Record<string, any>[];

    const agencyNameById = new Map<number, string>();
    for (const a of agencies) {
      if (a.agency_id !== null && a.agency_name) agencyNameById.set(a.agency_id, a.agency_name);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Agents
    // ─────────────────────────────────────────────────────────────────────────

    const agentsRaw = players.filter((p) => p?.person_type_lk === "AGENT");

    const agents = agentsRaw
      .map((p) => {
        const agentId = toIntOrNull(p?.player_id);
        if (agentId === null) return null;

        const agencyId = toIntOrNull(p?.agency_id);

        return {
          agent_id: agentId,
          agency_id: agencyId,
          agency_name: agencyId !== null ? agencyNameById.get(agencyId) ?? null : null,
          first_name: p?.first_name ?? null,
          last_name: p?.last_name ?? null,
          full_name: buildFullName(p?.first_name, p?.last_name),
          is_active: p?.record_status_lk ? p.record_status_lk === "ACT" : null,
          is_certified: true,
          person_type_lk: p?.person_type_lk ?? null,
          created_at: p?.create_date ?? null,
          updated_at: p?.last_change_date ?? null,
          record_changed_at: p?.record_change_date ?? null,
          agent_json: p ?? null,
          ...provenance,
        };
      })
      .filter(Boolean) as Record<string, any>[];

    console.log(`Found ${agencies.length} agencies`);
    console.log(`Found ${agents.length} agents`);

    if (dry_run) {
      return {
        dry_run: true,
        started_at: startedAt,
        finished_at: new Date().toISOString(),
        tables: [
          { table: "pcms.agencies", attempted: agencies.length, success: true },
          { table: "pcms.agents", attempted: agents.length, success: true },
        ],
        errors: [],
      };
    }

    const BATCH_SIZE = 100;

    // Upsert agencies first (so FK references exist)
    for (let i = 0; i < agencies.length; i += BATCH_SIZE) {
      const batch = agencies.slice(i, i + BATCH_SIZE);

      await sql`
        INSERT INTO pcms.agencies ${sql(batch)}
        ON CONFLICT (agency_id) DO UPDATE SET
          agency_name = EXCLUDED.agency_name,
          is_active = EXCLUDED.is_active,
          created_at = EXCLUDED.created_at,
          updated_at = EXCLUDED.updated_at,
          record_changed_at = EXCLUDED.record_changed_at,
          agency_json = EXCLUDED.agency_json,
          source_drop_file = EXCLUDED.source_drop_file,
          ingested_at = EXCLUDED.ingested_at
      `;
    }

    // Upsert agents
    for (let i = 0; i < agents.length; i += BATCH_SIZE) {
      const batch = agents.slice(i, i + BATCH_SIZE);

      await sql`
        INSERT INTO pcms.agents ${sql(batch)}
        ON CONFLICT (agent_id) DO UPDATE SET
          agency_id = EXCLUDED.agency_id,
          agency_name = EXCLUDED.agency_name,
          first_name = EXCLUDED.first_name,
          last_name = EXCLUDED.last_name,
          full_name = EXCLUDED.full_name,
          is_active = EXCLUDED.is_active,
          is_certified = EXCLUDED.is_certified,
          person_type_lk = EXCLUDED.person_type_lk,
          created_at = EXCLUDED.created_at,
          updated_at = EXCLUDED.updated_at,
          record_changed_at = EXCLUDED.record_changed_at,
          agent_json = EXCLUDED.agent_json,
          source_drop_file = EXCLUDED.source_drop_file,
          ingested_at = EXCLUDED.ingested_at
      `;
    }

    return {
      dry_run: false,
      started_at: startedAt,
      finished_at: new Date().toISOString(),
      tables: [
        { table: "pcms.agencies", attempted: agencies.length, success: true },
        { table: "pcms.agents", attempted: agents.length, success: true },
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