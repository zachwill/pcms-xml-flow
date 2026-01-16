import { SQL } from "bun";
import {
  hash,
  upsertBatch,
  createSummary,
  finalizeSummary,
  safeNum,
  safeBool,
  parsePCMSDate,
  UpsertResult,
  PCMSStreamParser,
  resolvePCMSLineageContext
} from "/f/ralph/utils.ts";
import { readdirSync, createReadStream } from "fs";

const sql = new SQL({ url: Bun.env.POSTGRES_URL!, prepare: false });
const PARSER_VERSION = "2.0.0";
const SHARED_DIR = "./shared/pcms";

async function auditUpsert(lineageId: number, result: UpsertResult, pkFields: string[], originalDataMap: Map<string, any>) {
  if (!result.success || !result.rows || result.rows.length === 0) return;
  const audits = result.rows.map((row) => ({
    lineage_id: lineageId,
    table_name: result.table.split('.').pop(),
    source_record_id: pkFields.map(f => String(row[f])).join(':'),
    record_hash: row.source_hash,
    parser_version: PARSER_VERSION,
    operation_type: 'UPSERT',
    source_data_json: originalDataMap.get(pkFields.map(f => String(row[f])).join(':'))
  }));
  if (audits.length > 0) {
    await sql`INSERT INTO pcms.pcms_lineage_audit ${sql(audits)} ON CONFLICT (table_name, source_record_id, record_hash, parser_version) DO NOTHING`;
  }
}

// --- Transformation Logic ---

function transformAgency(a: any, prov: any) {
  return {
    agency_id: safeNum(a.agencyId), agency_name: a.agencyName, is_active: safeBool(a.activeFlg),
    created_at: parsePCMSDate(a.createDate), updated_at: parsePCMSDate(a.lastChangeDate),
    record_changed_at: parsePCMSDate(a.recordChangeDate), agency_json: JSON.stringify(a), ...prov
  };
}

function transformAgent(a: any, prov: any) {
  return {
    agent_id: safeNum(a.agentId), agency_id: safeNum(a.agencyId), agency_name: a.agencyName,
    first_name: a.firstName, last_name: a.lastName, full_name: `${a.firstName || ''} ${a.lastName || ''}`.trim(),
    is_active: safeBool(a.activeFlg), is_certified: safeBool(a.certifiedFlg ?? true), person_type_lk: a.personTypeLk,
    created_at: parsePCMSDate(a.createDate), updated_at: parsePCMSDate(a.lastChangeDate),
    record_changed_at: parsePCMSDate(a.recordChangeDate), agent_json: JSON.stringify(a), ...prov
  };
}

function transformDepthChart(dc: any, prov: any) {
  return {
    team_id: safeNum(dc.teamId), person_id: safeNum(dc.playerId ?? dc.personId),
    salary_year: safeNum(dc.salaryYear ?? dc.season), chart_type_lk: dc.chartTypeLk ?? 'PRIMARY',
    position_lk: dc.positionLk, depth_rank: safeNum(dc.depthRank ?? dc.rank), position_2_lk: dc.position2Lk,
    role_lk: dc.roleLk, roster_status_lk: dc.rosterStatusLk, is_starter: safeBool(dc.starterFlg),
    notes: dc.notes, availability_status_lk: dc.availabilityStatusLk, injury_description: dc.injuryDescription,
    estimated_return_date: dc.estimatedReturnDate, updated_by_user_id: safeNum(dc.lastChangeUser),
    source_record_id: dc.depthChartId?.toString(), ...prov
  };
}

function transformInjuryReport(ir: any, prov: any) {
  return {
    person_id: safeNum(ir.playerId ?? ir.personId), team_id: safeNum(ir.teamId), report_date: ir.reportDate,
    salary_year: safeNum(ir.salaryYear ?? ir.season), availability_status_lk: ir.availabilityStatusLk,
    participation_lk: ir.participationLk, is_active_roster: safeBool(ir.activeRosterFlg),
    injury_description: ir.injuryDescription, reason: ir.reason, body_region_lk: ir.bodyRegionLk,
    body_part_lk: ir.bodyPartLk, laterality_lk: ir.lateralityLk, injury_type_lk: ir.injuryTypeLk,
    is_covid_cardiac_clearance: safeBool(ir.covidCardiacClearanceFlg),
    is_health_safety_protocol: safeBool(ir.healthSafetyProtocolFlg),
    ps_games_missed_count: safeNum(ir.psGamesMissedCount), rs_games_missed_count: safeNum(ir.rsGamesMissedCount),
    po_games_missed_count: safeNum(ir.poGamesMissedCount), notes: ir.notes,
    estimated_return_date: ir.estimatedReturnDate, author_id: safeNum(ir.authorId),
    created_at: parsePCMSDate(ir.createDate), updated_at: parsePCMSDate(ir.lastChangeDate), ...prov
  };
}

function transformMedicalIntel(mi: any, prov: any) {
  return {
    person_id: safeNum(mi.playerId ?? mi.personId), draft_year: safeNum(mi.draftYear),
    is_medical_flag: safeBool(mi.medicalFlag), is_intel_flag: safeBool(mi.intelFlag),
    red_flag_notes: mi.redFlagNotes, medical_history: mi.medicalHistory,
    medical_history_finalized_at: parsePCMSDate(mi.medicalHistoryFinalizedDate),
    medical_history_finalized_by_id: safeNum(mi.medicalHistoryFinalizedBy),
    internal_assessment: mi.internalAssessment, internal_assessment_risk_lk: mi.internalAssessmentRiskLk,
    internal_assessment_finalized_at: parsePCMSDate(mi.internalAssessmentFinalizedDate),
    internal_assessment_finalized_by_id: safeNum(mi.internalAssessmentFinalizedBy),
    orthopedic_exam: mi.orthopedicExam, orthopedic_exam_risk_lk: mi.orthopedicExamRiskLk,
    orthopedic_exam_finalized_at: parsePCMSDate(mi.orthopedicExamFinalizedDate),
    orthopedic_exam_finalized_by_id: safeNum(mi.orthopedicExamFinalizedBy),
    movement_performance: mi.movementPerformance,
    movement_performance_finalized_at: parsePCMSDate(mi.movementPerformanceFinalizedDate),
    movement_performance_finalized_by_id: safeNum(mi.movementPerformanceFinalizedBy),
    scouting_review: mi.scoutingReview, vaccination_status: mi.vaccinationStatus,
    covid_history_json: mi.covidHistory ? JSON.stringify(mi.covidHistory) : null,
    intel_concerns_count: safeNum(mi.intelConcernsCount), medical_concerns_count: safeNum(mi.medicalConcernsCount),
    imaging_requests_json: mi.imagingRequests ? JSON.stringify(mi.imagingRequests) : null,
    intel_reports_json: mi.intelReports ? JSON.stringify(mi.intelReports) : null,
    created_at: parsePCMSDate(mi.createDate), updated_at: parsePCMSDate(mi.lastChangeDate), ...prov
  };
}

function transformScoutingReport(sr: any, prov: any) {
  return {
    scout_id: sr.scoutId?.toString(), scout_name: sr.scoutName, player_id: safeNum(sr.playerId),
    team_id: safeNum(sr.teamId), game_id: sr.gameId?.toString(), event_id: sr.eventId?.toString(),
    league_lk: sr.leagueLk, report_type: sr.reportType, vertical: sr.vertical, rubric_type: sr.rubricType,
    evaluation_date: sr.evaluationDate, overall_grade: safeNum(sr.overallGrade), scout_rank: safeNum(sr.scoutRank),
    scouting_notes: sr.scoutingNotes, strengths: sr.strengths, weaknesses: sr.weaknesses,
    projected_role: sr.projectedRole, comparison_player_id: safeNum(sr.comparisonPlayerId),
    comparison_notes: sr.comparisonNotes, is_draft: safeBool(sr.draftFlg), is_final: safeBool(sr.finalFlg ?? true),
    grades_json: sr.grades ? JSON.stringify(sr.grades) : null, criteria_json: sr.criteria ? JSON.stringify(sr.criteria) : null,
    fields_json: sr.fields ? JSON.stringify(sr.fields) : null, source_system: sr.sourceSystem,
    scouting_report_id: sr.scoutingReportId?.toString(), created_at: parsePCMSDate(sr.createDate),
    updated_at: parsePCMSDate(sr.lastChangeDate), submitted_at: parsePCMSDate(sr.submittedDate), ...prov
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
  const provenance = { source_drop_file: row.s3_key, parser_version: PARSER_VERSION, ingested_at: new Date() };

  const targets = [
    { tag: 'lkAgency', table: 'agencies', transform: transformAgency, pk: ['agency_id'] },
    { tag: 'lkAgent', table: 'agents', transform: transformAgent, pk: ['agent_id'] },
    { tag: 'depthChart', table: 'depth_charts', transform: transformDepthChart, pk: ['team_id', 'salary_year', 'chart_type_lk', 'person_id', 'position_lk'] },
    { tag: 'injuryReport', table: 'injury_reports', transform: transformInjuryReport, pk: ['person_id', 'team_id', 'report_date', 'salary_year'] },
    { tag: 'medicalIntel', table: 'medical_intel', transform: transformMedicalIntel, pk: ['person_id', 'draft_year'] },
    { tag: 'scoutingReport', table: 'scouting_reports', transform: transformScoutingReport, pk: ['scouting_report_id'] }
  ];

  for (const xmlFile of xmlFiles) {
    const filePath = `${extractDir}/${xmlFile}`;
    console.log(`Processing ${xmlFile}...`);

    for (const target of targets) {
      const batch: any[] = [];
      const rawMap = new Map<string, any>();

      const streamParser = new PCMSStreamParser(target.tag, async (entity, rawXml) => {
        const transformed = target.transform(entity, { ...provenance, source_hash: hash(rawXml) });
        if (transformed) {
          batch.push(transformed);
          rawMap.set(target.pk.map(f => String(transformed[f])).join(':'), entity);
        }

        if (batch.length >= 500) {
          if (!dry_run) {
            const res = await upsertBatch(sql, 'pcms', target.table, batch, target.pk);
            await auditUpsert(row.lineage_id, res, target.pk, rawMap);
            summary.tables.push(res);
          } else {
            summary.tables.push({ table: `pcms.${target.table}`, attempted: batch.length, success: true });
          }
          batch.length = 0;
          rawMap.clear();
        }
      });

      const stream = createReadStream(filePath);
      for await (const chunk of stream) await streamParser.parseChunk(chunk);

      if (batch.length > 0) {
        if (!dry_run) {
          const res = await upsertBatch(sql, 'pcms', target.table, batch, target.pk);
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
