import { SQL } from "bun";
import {
  hash,
  upsertBatch,
  createSummary,
  finalizeSummary,
  safeNum,
  safeBigInt,
  safeBool,
  UpsertResult,
  PCMSStreamParser,
  resolvePCMSLineageContext
} from "/f/ralph/utils.ts";
import { readdirSync, createReadStream } from "fs";

const sql = new SQL({ url: Bun.env.POSTGRES_URL!, prepare: false });
const PARSER_VERSION = "2.0.0";
const SHARED_DIR = "./shared/pcms";

async function auditUpsert(lineageId: number, result: UpsertResult, pkField: string, originalDataMap: Map<string, any>) {
  if (!result.success || !result.rows || result.rows.length === 0) return;
  const audits = result.rows.map((row) => ({
    lineage_id: lineageId,
    table_name: result.table.split('.').pop(),
    source_record_id: String(row[pkField]),
    record_hash: row.source_hash,
    parser_version: PARSER_VERSION,
    operation_type: 'UPSERT',
    source_data_json: originalDataMap.get(String(row[pkField]))
  }));
  if (audits.length > 0) {
    await sql`INSERT INTO pcms.pcms_lineage_audit ${sql(audits)} ON CONFLICT (table_name, source_record_id, record_hash, parser_version) DO NOTHING`;
  }
}

// --- Transformation Logic ---

function transformTrade(t: any, prov: any) {
  return {
    trade_id: safeNum(t.tradeId), trade_date: t.tradeDate, trade_finalized_date: t.tradeFinalizedDate,
    league_lk: t.leagueLk, record_status_lk: t.recordStatusLk, trade_comments: t.tradeComments,
    created_at: t.createDate, updated_at: t.lastChangeDate, record_changed_at: t.recordChangeDate, ...prov
  };
}

function transformTradeTeam(tt: any, tradeId: number, prov: any) {
  const teamId = safeNum(tt.teamId);
  return {
    trade_team_id: `${tradeId}_${teamId}`, trade_id: tradeId, team_id: teamId,
    team_salary_change: safeBigInt(tt.teamSalaryChange), total_cash_received: safeBigInt(tt.totalCashReceived),
    total_cash_sent: safeBigInt(tt.totalCashSent), seqno: safeNum(tt.seqno), ...prov
  };
}

function transformTradeTeamDetail(ttd: any, tradeId: number, teamId: number, prov: any) {
  const seqno = safeNum(ttd.seqno);
  return {
    trade_team_detail_id: `${tradeId}_${teamId}_${seqno}`, trade_id: tradeId, team_id: teamId, seqno,
    group_number: safeNum(ttd.groupNumber), player_id: safeNum(ttd.playerId), contract_id: safeNum(ttd.contractId),
    version_number: safeNum(ttd.versionNumber), post_version_number: safeNum(ttd.postVersionNumber),
    is_sent: safeBool(ttd.sentFlg), is_sign_and_trade: safeBool(ttd.signAndTradeFlg),
    mts_value_override: safeBigInt(ttd.mtsValueOverride), is_trade_bonus: safeBool(ttd.tradeBonusFlg),
    is_no_trade: safeBool(ttd.noTradeFlg), is_player_consent: safeBool(ttd.playerConsentFlg),
    is_poison_pill: safeBool(ttd.poisonPillFlg), is_incentive_bonus: safeBool(ttd.incentiveBonusFlg),
    cash_amount: safeBigInt(ttd.cashAmount), trade_entry_lk: ttd.tradeEntryLk,
    free_agent_designation_lk: ttd.freeAgentDesignationLk, base_year_amount: safeBigInt(ttd.baseYearAmount),
    is_base_year: safeBool(ttd.baseYearFlg), draft_pick_year: safeNum(ttd.draftPickYear),
    draft_pick_round: safeNum(ttd.draftPickRound), is_draft_pick_future: safeBool(ttd.draftPickFutureFlg),
    is_draft_pick_swap: safeBool(ttd.draftPickSwapFlg), draft_pick_conditional_lk: ttd.draftPickConditionalLk,
    is_draft_year_plus_two: safeBool(ttd.draftYearPlusTwoFlg), ...prov
  };
}

function transformTradeGroup(tg: any, tradeId: number, prov: any) {
  const teamId = safeNum(tg.teamId);
  const groupNumber = safeNum(tg.tradeGroupNumber);
  return {
    trade_group_id: `${tradeId}_${teamId}_${groupNumber}`, trade_id: tradeId, team_id: teamId,
    trade_group_number: groupNumber, trade_group_comments: tg.tradeGroupComments,
    acquired_team_exception_id: safeNum(tg.acquiredTeamExceptionId),
    generated_team_exception_id: safeNum(tg.generatedTeamExceptionId), signed_method_lk: tg.signedMethodLk, ...prov
  };
}

function transformTransaction(t: any, prov: any) {
  return {
    transaction_id: safeNum(t.transactionId), player_id: safeNum(t.playerId),
    from_team_id: safeNum(t.fromTeamId), to_team_id: safeNum(t.toTeamId),
    transaction_date: t.transactionDate, trade_finalized_date: t.tradeFinalizedDate,
    trade_id: safeNum(t.tradeId), transaction_type_lk: t.transactionTypeLk,
    transaction_description_lk: t.transactionDescriptionLk, record_status_lk: t.recordStatusLk,
    league_lk: t.leagueLk, seqno: safeNum(t.seqno), is_in_season: safeBool(t.inSeasonFlg),
    contract_id: safeNum(t.contractId), original_contract_id: safeNum(t.originalContractId),
    version_number: safeNum(t.versionNumber), contract_type_lk: t.contractTypeLk,
    min_contract_lk: t.minContractLk, signed_method_lk: t.signedMethodLk,
    team_exception_id: safeNum(t.teamExceptionId), rights_team_id: safeNum(t.rightsTeamId),
    waiver_clear_date: t.waiverClearDate, is_clear_player_rights: safeBool(t.clearPlayerRightsFlg),
    free_agent_status_lk: t.freeAgentStatusLk, free_agent_designation_lk: t.freeAgentDesignationLk,
    from_player_status_lk: t.fromPlayerStatusLk, to_player_status_lk: t.toPlayerStatusLk,
    option_year: safeNum(t.optionYear), adjustment_amount: safeBigInt(t.adjustmentAmount),
    bonus_true_up_amount: safeBigInt(t.bonusTrueUpAmount), draft_amount: safeBigInt(t.draftAmount),
    draft_pick: safeNum(t.draftPick), draft_round: safeNum(t.draftRound), draft_year: safeNum(t.draftYear),
    free_agent_amount: safeBigInt(t.freeAgentAmount), qoe_amount: safeBigInt(t.qoeAmount),
    tender_amount: safeBigInt(t.tenderAmount), is_divorce: safeBool(t.divorceFlg),
    effective_salary_year: safeNum(t.effectiveSeason),
    is_initially_convertible_exception: safeBool(t.initiallyConvertibleExceptionFlg),
    is_sign_and_trade: safeBool(t.signAndTradeFlg), sign_and_trade_team_id: safeNum(t.signAndTradeTeamId),
    sign_and_trade_link_transaction_id: safeNum(t.signAndTradeLinkTransactionId),
    dlg_contract_id: safeNum(t.dlgContractId), dlg_experience_level_lk: t.dlgExperienceLevelLk,
    dlg_salary_level_lk: t.dlgSalaryLevelLk, comments: t.comments,
    created_at: t.createDate, updated_at: t.lastChangeDate, record_changed_at: t.recordChangeDate, ...prov
  };
}

function transformLedgerEntry(le: any, prov: any) {
  return {
    transaction_ledger_entry_id: safeNum(le.transactionLedgerEntryId), transaction_id: safeNum(le.transactionId),
    team_id: safeNum(le.teamId), player_id: safeNum(le.playerId), contract_id: safeNum(le.contractId),
    dlg_contract_id: safeNum(le.dlgContractId), salary_year: safeNum(le.salaryYear), ledger_date: le.ledgerDate,
    league_lk: le.leagueLk, transaction_type_lk: le.transactionTypeLk,
    transaction_description_lk: le.transactionDescriptionLk, version_number: safeNum(le.versionNumber),
    seqno: safeNum(le.seqno), sub_seqno: safeNum(le.subSeqno), team_ledger_seqno: safeNum(le.teamLedgerSeqno),
    is_leaving_team: safeBool(le.leavingTeamFlg), has_no_budget_impact: safeBool(le.noBudgetImpactFlg),
    mts_amount: safeBigInt(le.mtsAmount), mts_change: safeBigInt(le.mtsChange), mts_value: safeBigInt(le.mtsValue),
    cap_amount: safeBigInt(le.capAmount), cap_change: safeBigInt(le.capChange), cap_value: safeBigInt(le.capValue),
    tax_amount: safeBigInt(le.taxAmount), tax_change: safeBigInt(le.taxChange), tax_value: safeBigInt(le.taxValue),
    apron_amount: safeBigInt(le.apronAmount), apron_change: safeBigInt(le.apronChange), apron_value: safeBigInt(le.apronValue),
    trade_bonus_amount: safeBigInt(le.tradeBonusAmount), ...prov
  };
}

function transformWaiverAmount(wa: any, prov: any) {
  return {
    transaction_waiver_amount_id: safeNum(wa.transactionWaiverAmountId), transaction_id: safeNum(wa.transactionId),
    player_id: safeNum(wa.playerId), team_id: safeNum(wa.teamId), contract_id: safeNum(wa.contractId),
    salary_year: safeNum(wa.salaryYear), version_number: safeNum(wa.versionNumber), waive_date: wa.waiveDate,
    cap_value: safeBigInt(wa.capValue), cap_change_value: safeBigInt(wa.capChangeValue), is_cap_calculated: safeBool(wa.capCalculated),
    tax_value: safeBigInt(wa.taxValue), tax_change_value: safeBigInt(wa.taxChangeValue), is_tax_calculated: safeBool(wa.taxCalculated),
    apron_value: safeBigInt(wa.apronValue), apron_change_value: safeBigInt(wa.apronChangeValue), is_apron_calculated: safeBool(wa.apronCalculated),
    mts_value: safeBigInt(wa.mtsValue), mts_change_value: safeBigInt(wa.mtsChangeValue),
    two_way_salary: safeBigInt(wa.twoWaySalary), two_way_nba_salary: safeBigInt(wa.twoWayNbaSalary),
    two_way_dlg_salary: safeBigInt(wa.twoWayDlgSalary), option_decision_lk: wa.optionDecisionLk,
    wnba_contract_id: safeNum(wa.wnbaContractId), wnba_version_number: wa.wnbaVersionNumber, ...prov
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
  const allFiles = readdirSync(extractDir).filter(f => f.endsWith('.xml'));
  const provenance = { source_drop_file: row.s3_key, parser_version: PARSER_VERSION, ingested_at: new Date() };

  const handlers = [
    { pattern: /extract_trade\.xml/, tag: 'trade', tables: ['trades', 'trade_teams', 'trade_team_details', 'trade_groups'], pk: 'trade_id' },
    { pattern: /extract_transaction\.xml/, tag: 'transaction', tables: ['transactions'], pk: 'transaction_id' },
    { pattern: /extract_ledger\.xml/, tag: 'transactionLedgerEntry', tables: ['ledger_entries'], pk: 'transaction_ledger_entry_id' },
    { pattern: /extract_transactions-waiver-amounts\.xml/, tag: 'transactionWaiverAmount', tables: ['transaction_waiver_amounts'], pk: 'transaction_waiver_amount_id' }
  ];

  for (const h of handlers) {
    const xmlFile = allFiles.find(f => h.pattern.test(f));
    if (!xmlFile) continue;

    const filePath = `${extractDir}/${xmlFile}`;
    console.log(`Processing ${xmlFile}...`);

    const batches: Record<string, any[]> = Object.fromEntries(h.tables.map(t => [t, []]));
    const rawMap = new Map<string, any>();

    async function flush() {
      if (!dry_run) {
        for (const table of h.tables) {
          if (batches[table].length === 0) continue;
          const pks = table === 'trade_teams' ? ['trade_team_id'] : table === 'trade_team_details' ? ['trade_team_detail_id'] : table === 'trade_groups' ? ['trade_group_id'] : [h.pk];
          const res = await upsertBatch(sql, 'pcms', table, batches[table], pks);
          if (table === h.tables[0]) await auditUpsert(row.lineage_id, res, h.pk, rawMap);
          summary.tables.push(res);
          batches[table].length = 0;
        }
        rawMap.clear();
      } else {
        for (const table of h.tables) {
          summary.tables.push({ table: `pcms.${table}`, attempted: batches[table].length, success: true });
          batches[table].length = 0;
        }
      }
    }

    const streamParser = new PCMSStreamParser(h.tag, async (entity, rawXml) => {
      const prov = { ...provenance, source_hash: hash(rawXml) };

      if (h.tag === 'trade') {
        const tradeId = safeNum(entity.tradeId);
        if (!tradeId) return;
        batches['trades'].push(transformTrade(entity, prov));
        rawMap.set(String(tradeId), entity);
        if (entity.tradeTeams?.tradeTeam) {
          const teams = Array.isArray(entity.tradeTeams.tradeTeam) ? entity.tradeTeams.tradeTeam : [entity.tradeTeams.tradeTeam];
          for (const tt of teams) {
            const teamId = safeNum(tt.teamId);
            batches['trade_teams'].push(transformTradeTeam(tt, tradeId, prov));
            if (tt.tradeTeamDetails?.tradeTeamDetail) {
              const details = Array.isArray(tt.tradeTeamDetails.tradeTeamDetail) ? tt.tradeTeamDetails.tradeTeamDetail : [tt.tradeTeamDetails.tradeTeamDetail];
              for (const ttd of details) batches['trade_team_details'].push(transformTradeTeamDetail(ttd, tradeId, teamId!, prov));
            }
          }
        }
        if (entity.tradeGroups?.tradeGroup) {
          const groups = Array.isArray(entity.tradeGroups.tradeGroup) ? entity.tradeGroups.tradeGroup : [entity.tradeGroups.tradeGroup];
          for (const tg of groups) batches['trade_groups'].push(transformTradeGroup(tg, tradeId, prov));
        }
      } else if (h.tag === 'transaction') {
        const t = transformTransaction(entity, prov);
        batches['transactions'].push(t);
        rawMap.set(String(t.transaction_id), entity);
      } else if (h.tag === 'transactionLedgerEntry') {
        const le = transformLedgerEntry(entity, prov);
        batches['ledger_entries'].push(le);
        rawMap.set(String(le.transaction_ledger_entry_id), entity);
      } else if (h.tag === 'transactionWaiverAmount') {
        const wa = transformWaiverAmount(entity, prov);
        batches['transaction_waiver_amounts'].push(wa);
        rawMap.set(String(wa.transaction_waiver_amount_id), entity);
      }

      if (batches[h.tables[0]].length >= 100) await flush();
    });

    const stream = createReadStream(filePath);
    for await (const chunk of stream) await streamParser.parseChunk(chunk);
    await flush();
  }

  return finalizeSummary(summary);
}
