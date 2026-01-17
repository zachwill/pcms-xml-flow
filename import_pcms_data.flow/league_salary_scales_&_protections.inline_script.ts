/**
 * League Salary Scales & Cap Projections Import
 *
 * Sources:
 *  - yearly_salary_scales.json -> pcms.league_salary_scales
 *  - cap_projections.json      -> pcms.league_salary_cap_projections
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

    const salaryScalesFile = Bun.file(`${baseDir}/yearly_salary_scales.json`);
    const capProjectionsFile = Bun.file(`${baseDir}/cap_projections.json`);

    const salaryScales: any[] = (await salaryScalesFile.exists()) ? await salaryScalesFile.json() : [];
    const capProjections: any[] = (await capProjectionsFile.exists()) ? await capProjectionsFile.json() : [];

    console.log(`Found ${salaryScales.length} salary scales`);
    console.log(`Found ${capProjections.length} cap projections`);

    const ingestedAt = new Date();
    const provenance = {
      source_drop_file: s3_key ?? null,
      source_hash: null,
      parser_version: null,
      ingested_at: ingestedAt,
    };

    const scaleRows = salaryScales
      .map((s) => {
        const salaryYear = toIntOrNull(s?.salary_year);
        const league = s?.league_lk ?? null;
        const yos = toIntOrNull(s?.years_of_service);

        if (salaryYear === null || league === null || yos === null) return null;

        // The extract provides minimum_salary_year1..year5; schema stores a single minimum.
        // We store minimum_salary_year1 as the minimum salary amount for that season / YOS.
        return {
          salary_year: salaryYear,
          league_lk: league,
          years_of_service: yos,
          minimum_salary_amount: toNumOrNull(s?.minimum_salary_year1),
          created_at: s?.create_date ?? null,
          updated_at: s?.last_change_date ?? null,
          record_changed_at: s?.record_change_date ?? null,
          ...provenance,
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
          ...provenance,
        };
      })
      .filter(Boolean) as Record<string, any>[];

    if (dry_run) {
      return {
        dry_run: true,
        started_at: startedAt,
        finished_at: new Date().toISOString(),
        tables: [
          { table: "pcms.league_salary_scales", attempted: scaleRows.length, success: true },
          { table: "pcms.league_salary_cap_projections", attempted: projectionRows.length, success: true },
        ],
        errors: [],
      };
    }

    const BATCH_SIZE = 100;

    // league_salary_scales
    for (let i = 0; i < scaleRows.length; i += BATCH_SIZE) {
      const batch = scaleRows.slice(i, i + BATCH_SIZE);

      await sql`
        INSERT INTO pcms.league_salary_scales ${sql(batch)}
        ON CONFLICT (salary_year, league_lk, years_of_service) DO UPDATE SET
          minimum_salary_amount = EXCLUDED.minimum_salary_amount,
          created_at = EXCLUDED.created_at,
          updated_at = EXCLUDED.updated_at,
          record_changed_at = EXCLUDED.record_changed_at,
          source_drop_file = EXCLUDED.source_drop_file,
          source_hash = EXCLUDED.source_hash,
          parser_version = EXCLUDED.parser_version,
          ingested_at = EXCLUDED.ingested_at
      `;
    }

    // league_salary_cap_projections
    for (let i = 0; i < projectionRows.length; i += BATCH_SIZE) {
      const batch = projectionRows.slice(i, i + BATCH_SIZE);

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
          source_drop_file = EXCLUDED.source_drop_file,
          source_hash = EXCLUDED.source_hash,
          parser_version = EXCLUDED.parser_version,
          ingested_at = EXCLUDED.ingested_at
      `;
    }

    return {
      dry_run: false,
      started_at: startedAt,
      finished_at: new Date().toISOString(),
      tables: [
        { table: "pcms.league_salary_scales", attempted: scaleRows.length, success: true },
        { table: "pcms.league_salary_cap_projections", attempted: projectionRows.length, success: true },
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