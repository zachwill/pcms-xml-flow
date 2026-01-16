import { SQL } from "bun";
import {
  hash,
  upsertBatch,
  createSummary,
  finalizeSummary,
  safeNum,
  safeBool,
  safeBigInt,
  UpsertResult,
  PCMSStreamParser,
  resolvePCMSLineageContext
} from "/f/ralph/utils.ts";
import { readdirSync, createReadStream } from "fs";

const sql = new SQL({ url: Bun.env.POSTGRES_URL!, prepare: false });
const PARSER_VERSION = "2.0.0";
const SHARED_DIR = "./shared/pcms";

async function auditUpsert(lineageId: number, result: UpsertResult, naturalKeyField: string, originalDataMap: Map<string, any>) {
  if (!result.success || !result.rows) return;

  const audits = result.rows.map((row) => ({
    lineage_id: lineageId,
    table_name: result.table.split('.').pop(),
    source_record_id: String(row[naturalKeyField]),
    record_hash: row.source_hash,
    parser_version: PARSER_VERSION,
    operation_type: 'UPSERT',
    source_data_json: originalDataMap.get(String(row[naturalKeyField]))
  }));

  if (audits.length > 0) {
    await sql`
      INSERT INTO pcms.pcms_lineage_audit ${sql(audits)}
      ON CONFLICT (table_name, source_record_id, record_hash, parser_version) DO NOTHING
    `;
  }
}

// --- Transformation Logic ---

function transformPerson(p: any, provenance: any) {
  return {
    person_id: safeNum(p.playerId),
    first_name: p.firstName,
    last_name: p.lastName,
    middle_name: p.middleName,
    display_first_name: p.displayFirstName,
    display_last_name: p.displayLastName,
    roster_first_name: p.rosterFirstName,
    roster_last_name: p.rosterLastName,
    birth_date: p.birthDate,
    birth_country_lk: p.birthCountryLk,
    gender: p.gender,
    height: safeNum(p.height),
    weight: safeNum(p.weight),
    person_type_lk: p.personTypeLk,
    player_status_lk: p.playerStatusLk,
    record_status_lk: p.recordStatusLk,
    league_lk: p.leagueLk,
    team_id: safeNum(p.teamId),
    school_id: safeNum(p.schoolId),
    draft_year: safeNum(p.draftYear),
    draft_round: safeNum(p.draftRound),
    draft_pick: safeNum(p.draftPick),
    years_of_service: safeNum(p.yearsOfService),
    service_years_json: p.playerServiceYears ? JSON.stringify(p.playerServiceYears) : null,
    created_at: p.createDate,
    updated_at: p.lastChangeDate,
    record_changed_at: p.recordChangeDate,
    poison_pill_amt: safeBigInt(p.poisonPillAmt),
    ...provenance
  };
}

function transformTeam(t: any, provenance: any) {
  return {
    team_id: safeNum(t.teamId),
    team_name: t.teamName,
    team_name_short: t.teamNameShort,
    team_nickname: t.teamNickname,
    city: t.city,
    state_lk: t.stateLk,
    country_lk: t.countryLk,
    division_name: t.divisionName,
    league_lk: t.leagueLk,
    is_active: safeBool(t.activeFlg),
    record_status_lk: t.recordStatusLk,
    first_game_date: t.firstGameDate,
    created_at: t.createDate,
    updated_at: t.lastChangeDate,
    record_changed_at: t.recordChangeDate,
    ...provenance
  };
}

// --- Main Execution ---

export async function main(
  dry_run = false,
  lineage_id?: number,
  s3_key?: string,
  extract_dir: string = SHARED_DIR
) {
  const summary = createSummary(dry_run);

  const extractDir = (extract_dir as any) || SHARED_DIR;
  const row = await resolvePCMSLineageContext(sql, { lineageId: lineage_id, s3Key: s3_key, sharedDir: extractDir });
  const xmlFiles = readdirSync(extractDir).filter(f => f.endsWith('.xml'));

  const entitiesToProcess = [
    { tag: 'player', table: 'people', transform: transformPerson, pk: 'person_id' },
    { tag: 'lkTeam', table: 'teams', transform: transformTeam, pk: 'team_id' }
  ];

  for (const xmlFile of xmlFiles) {
    const filePath = `${extractDir}/${xmlFile}`;
    console.log(`Processing ${xmlFile}...`);

    const provenance = {
      source_drop_file: row.s3_key,
      parser_version: PARSER_VERSION,
      ingested_at: new Date()
    };

    for (const target of entitiesToProcess) {
      const batch: any[] = [];
      const rawMap = new Map<string, any>();

      const streamParser = new PCMSStreamParser(target.tag, async (entity, rawXml) => {
        const transformed = target.transform(entity, { ...provenance, source_hash: hash(rawXml) });
        batch.push(transformed);
        rawMap.set(String(transformed[target.pk]), entity);

        if (batch.length >= 500) {
          if (!dry_run) {
            const res = await upsertBatch(sql, 'pcms', target.table, batch, [target.pk]);
            await auditUpsert(row.lineage_id, res, target.pk, rawMap);
            summary.tables.push(res);
          } else {
            summary.tables.push({ table: `pcms.${target.table}`, attempted: batch.length, success: true });
          }
          batch.length = 0;
          rawMap.clear();
        }
      }, (name) => ["player", "lkTeam", "playerServiceYear", "personType"].includes(name));

      const stream = createReadStream(filePath);
      for await (const chunk of stream) {
        await streamParser.parseChunk(chunk);
      }

      if (batch.length > 0) {
        if (!dry_run) {
          const res = await upsertBatch(sql, 'pcms', target.table, batch, [target.pk]);
          await auditUpsert(row.lineage_id, res, target.pk, rawMap);
          summary.tables.push(res);
        } else {
          summary.tables.push({ table: `pcms.${target.table}`, attempted: batch.length, success: true });
        }
      }
    }
  }

  return finalizeSummary(summary);
}
