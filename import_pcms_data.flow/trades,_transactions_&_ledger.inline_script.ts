/**
 * Trades / Transactions / Ledger Import
 *
 * Reads pre-parsed JSON from the shared extract dir (created by lineage step),
 * then upserts into:
 * - pcms.trades
 * - pcms.trade_teams
 * - pcms.trade_team_details
 * - pcms.trade_groups
 * - pcms.transactions
 * - pcms.ledger_entries
 * - pcms.transaction_waiver_amounts
 *
 * Sources:
 * - *_trade.json           → data["xml-extract"]["trade-extract"]["trade"]
 * - *_transaction.json     → data["xml-extract"]["transaction-extract"]["transaction"]
 * - *_ledger.json          → data["xml-extract"]["ledger-extract"]["transactionLedgerEntry"]
 * - *_transactions-waiver-amounts.json → data["xml-extract"]["twa-extract"]["transactionWaiverAmount"]
 */
import { SQL } from "bun";
import { readdir } from "node:fs/promises";

const sql = new SQL({ url: Bun.env.POSTGRES_URL!, prepare: false });
const PARSER_VERSION = "2.1.0";
const SHARED_DIR = "./shared/pcms";

// ─────────────────────────────────────────────────────────────────────────────
// Types
// ─────────────────────────────────────────────────────────────────────────────

interface LineageContext {
  lineage_id: number;
  s3_key: string;
  source_hash: string;
}

interface UpsertResult {
  table: string;
  attempted: number;
  success: boolean;
  error?: string;
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers (inline)
// ─────────────────────────────────────────────────────────────────────────────

function hash(data: string): string {
  return new Bun.CryptoHasher("sha256").update(data).digest("hex");
}

function nilSafe(val: unknown): unknown {
  if (val && typeof val === "object" && "@_xsi:nil" in val) return null;
  return val;
}

function unwrapSingleArray(val: unknown): unknown {
  const v = nilSafe(val);
  if (Array.isArray(v) && v.length === 1) return nilSafe(v[0]);
  return v;
}

function safeNum(val: unknown): number | null {
  const v = unwrapSingleArray(val);
  if (v === null || v === undefined || v === "") return null;
  if (typeof v === "object") return null;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

function safeVersionNum(val: unknown): number | null {
  const n = safeNum(val);
  if (n === null) return null;
  if (Number.isInteger(n)) return n;
  return Math.round(n * 100);
}

function safeStr(val: unknown): string | null {
  const v = unwrapSingleArray(val);
  if (v === null || v === undefined || v === "") return null;
  if (typeof v === "object") return null;
  return String(v);
}

function safeBool(val: unknown): boolean | null {
  const v = unwrapSingleArray(val);
  if (v === null || v === undefined) return null;
  if (typeof v === "boolean") return v;
  if (v === 1 || v === "1" || v === "Y" || v === "true" || v === true) return true;
  if (v === 0 || v === "0" || v === "N" || v === "false" || v === false) return false;
  return null;
}

function safeBigInt(val: unknown): string | null {
  const v = unwrapSingleArray(val);
  if (v === null || v === undefined || v === "") return null;
  if (typeof v === "object") return null;
  try {
    return BigInt(Math.round(Number(v))).toString();
  } catch {
    return null;
  }
}

function asArray<T = any>(val: unknown): T[] {
  const v = nilSafe(val);
  if (v === null || v === undefined) return [];
  return Array.isArray(v) ? (v as T[]) : ([v] as T[]);
}

async function getLineageContext(extractDir: string): Promise<LineageContext> {
  const lineageFile = `${extractDir}/lineage.json`;
  const file = Bun.file(lineageFile);
  if (await file.exists()) return await file.json();
  throw new Error(`Lineage file not found: ${lineageFile}`);
}

async function upsertBatch<T extends Record<string, unknown>>(
  schema: string,
  table: string,
  rows: T[],
  conflictColumns: string[]
): Promise<UpsertResult> {
  const fullTable = `${schema}.${table}`;
  if (rows.length === 0) {
    return { table: fullTable, attempted: 0, success: true };
  }

  try {
    const allColumns = Object.keys(rows[0]);
    const updateColumns = allColumns.filter((col) => !conflictColumns.includes(col));
    const setClauses = updateColumns.map((col) => `${col} = EXCLUDED.${col}`).join(", ");
    const conflictTarget = conflictColumns.join(", ");

    const query = `
      INSERT INTO ${fullTable} (${allColumns.join(", ")})
      SELECT * FROM jsonb_populate_recordset(null::${fullTable}, $1::jsonb)
      ON CONFLICT (${conflictTarget}) DO UPDATE SET ${setClauses}
      WHERE ${fullTable}.source_hash IS DISTINCT FROM EXCLUDED.source_hash
    `;

    await sql.unsafe(query, [JSON.stringify(rows)]);
    return { table: fullTable, attempted: rows.length, success: true };
  } catch (error) {
    const msg = error instanceof Error ? error.message : String(error);
    return { table: fullTable, attempted: rows.length, success: false, error: msg };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Transformers
// ─────────────────────────────────────────────────────────────────────────────

function transformTrade(t: any, prov: any) {
  return {
    trade_id: safeNum(t.tradeId),
    trade_date: safeStr(t.tradeDate),
    trade_finalized_date: safeStr(t.tradeFinalizedDate),
    league_lk: safeStr(t.leagueLk),
    record_status_lk: safeStr(t.recordStatusLk),
    trade_comments: safeStr(t.tradeComments),
    created_at: safeStr(t.createDate),
    updated_at: safeStr(t.lastChangeDate),
    record_changed_at: safeStr(t.recordChangeDate),
    ...prov,
  };
}

function transformTradeTeam(tt: any, tradeId: number, prov: any) {
  const teamId = safeNum(tt.teamId);
  return {
    trade_team_id: teamId ? `${tradeId}_${teamId}` : null,
    trade_id: tradeId,
    team_id: teamId,
    team_salary_change: safeBigInt(tt.teamSalaryChange),
    total_cash_received: safeBigInt(tt.totalCashReceived),
    total_cash_sent: safeBigInt(tt.totalCashSent),
    seqno: safeNum(tt.seqno),
    ...prov,
  };
}

function transformTradeTeamDetail(ttd: any, tradeId: number, teamId: number, prov: any) {
  const seqno = safeNum(ttd.seqno);
  return {
    trade_team_detail_id: seqno !== null ? `${tradeId}_${teamId}_${seqno}` : null,
    trade_id: tradeId,
    team_id: teamId,
    seqno,
    group_number: safeNum(ttd.groupNumber),
    player_id: safeNum(ttd.playerId),
    contract_id: safeNum(ttd.contractId),
    version_number: safeVersionNum(ttd.versionNumber),
    post_version_number: safeVersionNum(ttd.postVersionNumber),
    is_sent: safeBool(ttd.sentFlg),
    is_sign_and_trade: safeBool(ttd.signAndTradeFlg),
    mts_value_override: safeBigInt(ttd.mtsValueOverride),
    is_trade_bonus: safeBool(ttd.tradeBonusFlg),
    is_no_trade: safeBool(ttd.noTradeFlg),
    is_player_consent: safeBool(ttd.playerConsentFlg),
    is_poison_pill: safeBool(ttd.poisonPillFlg),
    is_incentive_bonus: safeBool(ttd.incentiveBonusFlg),
    cash_amount: safeBigInt(ttd.cashAmount),
    trade_entry_lk: safeStr(ttd.tradeEntryLk),
    free_agent_designation_lk: safeStr(ttd.freeAgentDesignationLk),
    base_year_amount: safeBigInt(ttd.baseYearAmount),
    is_base_year: safeBool(ttd.baseYearFlg),
    draft_pick_year: safeNum(ttd.draftPickYear),
    draft_pick_round: safeNum(ttd.draftPickRound),
    is_draft_pick_future: safeBool(ttd.draftPickFutureFlg),
    is_draft_pick_swap: safeBool(ttd.draftPickSwapFlg),
    draft_pick_conditional_lk: safeStr(ttd.draftPickConditionalLk),
    is_draft_year_plus_two: safeBool(ttd.draftYearPlusTwoFlg),
    ...prov,
  };
}

function transformTradeGroup(tg: any, tradeId: number, teamIdFallback: number, prov: any) {
  const teamId = safeNum(tg.teamId) ?? teamIdFallback;
  const groupNumber = safeNum(tg.tradeGroupNumber);
  return {
    trade_group_id: groupNumber !== null ? `${tradeId}_${teamId}_${groupNumber}` : null,
    trade_id: tradeId,
    team_id: teamId,
    trade_group_number: groupNumber,
    trade_group_comments: safeStr(tg.tradeGroupComments),
    acquired_team_exception_id: safeNum(tg.acquiredTeamExceptionId),
    generated_team_exception_id: safeNum(tg.generatedTeamExceptionId),
    signed_method_lk: safeStr(tg.signedMethodLk),
    ...prov,
  };
}

function transformTransaction(t: any, prov: any) {
  return {
    transaction_id: safeNum(t.transactionId),
    player_id: safeNum(t.playerId),
    from_team_id: safeNum(t.fromTeamId),
    to_team_id: safeNum(t.toTeamId),
    transaction_date: safeStr(t.transactionDate),
    trade_finalized_date: safeStr(t.tradeFinalizedDate),
    trade_id: safeNum(t.tradeId),
    transaction_type_lk: safeStr(t.transactionTypeLk),
    transaction_description_lk: safeStr(t.transactionDescriptionLk),
    record_status_lk: safeStr(t.recordStatusLk),
    league_lk: safeStr(t.leagueLk),
    seqno: safeNum(t.seqno),
    is_in_season: safeBool(t.inSeasonFlg),
    contract_id: safeNum(t.contractId),
    original_contract_id: safeNum(t.originalContractId),
    version_number: safeVersionNum(t.versionNumber),
    contract_type_lk: safeStr(t.contractTypeLk),
    min_contract_lk: safeStr(t.minContractLk),
    signed_method_lk: safeStr(t.signedMethodLk),
    team_exception_id: safeNum(t.teamExceptionId),
    rights_team_id: safeNum(t.rightsTeamId),
    waiver_clear_date: safeStr(t.waiverClearDate),
    is_clear_player_rights: safeBool(t.clearPlayerRightsFlg),
    free_agent_status_lk: safeStr(t.freeAgentStatusLk),
    free_agent_designation_lk: safeStr(t.freeAgentDesignationLk),
    from_player_status_lk: safeStr(t.fromPlayerStatusLk),
    to_player_status_lk: safeStr(t.toPlayerStatusLk),
    option_year: safeNum(t.optionYear),
    adjustment_amount: safeBigInt(t.adjustmentAmount),
    bonus_true_up_amount: safeBigInt(t.bonusTrueUpAmount),
    draft_amount: safeBigInt(t.draftAmount),
    draft_pick: safeNum(t.draftPick),
    draft_round: safeNum(t.draftRound),
    draft_year: safeNum(t.draftYear),
    free_agent_amount: safeBigInt(t.freeAgentAmount),
    qoe_amount: safeBigInt(t.qoeAmount),
    tender_amount: safeBigInt(t.tenderAmount),
    is_divorce: safeBool(t.divorceFlg),
    effective_salary_year: safeNum((t as any).effectiveSeason),
    is_initially_convertible_exception: safeBool(t.initiallyConvertibleExceptionFlg),
    is_sign_and_trade: safeBool(t.signAndTradeFlg),
    sign_and_trade_team_id: safeNum(t.signAndTradeTeamId),
    sign_and_trade_link_transaction_id: safeNum(t.signAndTradeLinkTransactionId),
    dlg_contract_id: safeNum(t.dlgContractId),
    dlg_experience_level_lk: safeStr(t.dlgExperienceLevelLk),
    dlg_salary_level_lk: safeStr(t.dlgSalaryLevelLk),
    comments: safeStr(t.comments),
    created_at: safeStr(t.createDate),
    updated_at: safeStr(t.lastChangeDate),
    record_changed_at: safeStr(t.recordChangeDate),
    ...prov,
  };
}

function transformLedgerEntry(le: any, prov: any) {
  return {
    transaction_ledger_entry_id: safeNum(le.transactionLedgerEntryId),
    transaction_id: safeNum(le.transactionId),
    team_id: safeNum(le.teamId),
    player_id: safeNum(le.playerId),
    contract_id: safeNum(le.contractId),
    dlg_contract_id: safeNum(le.dlgContractId),
    salary_year: safeNum(le.salaryYear),
    ledger_date: safeStr(le.ledgerDate),
    league_lk: safeStr(le.leagueLk),
    transaction_type_lk: safeStr(le.transactionTypeLk),
    transaction_description_lk: safeStr(le.transactionDescriptionLk),
    version_number: safeVersionNum(le.versionNumber),
    seqno: safeNum(le.seqno),
    sub_seqno: safeNum(le.subSeqno),
    team_ledger_seqno: safeNum(le.teamLedgerSeqno),
    is_leaving_team: safeBool(le.leavingTeamFlg),
    has_no_budget_impact: safeBool(le.noBudgetImpactFlg),
    mts_amount: safeBigInt(le.mtsAmount),
    mts_change: safeBigInt(le.mtsChange),
    mts_value: safeBigInt(le.mtsValue),
    cap_amount: safeBigInt(le.capAmount),
    cap_change: safeBigInt(le.capChange),
    cap_value: safeBigInt(le.capValue),
    tax_amount: safeBigInt(le.taxAmount),
    tax_change: safeBigInt(le.taxChange),
    tax_value: safeBigInt(le.taxValue),
    apron_amount: safeBigInt(le.apronAmount),
    apron_change: safeBigInt(le.apronChange),
    apron_value: safeBigInt(le.apronValue),
    trade_bonus_amount: safeBigInt(le.tradeBonusAmount),
    ...prov,
  };
}

function transformWaiverAmount(wa: any, prov: any) {
  return {
    transaction_waiver_amount_id: safeNum(wa.transactionWaiverAmountId),
    transaction_id: safeNum(wa.transactionId),
    player_id: safeNum(wa.playerId),
    team_id: safeNum(wa.teamId),
    contract_id: safeNum(wa.contractId),
    salary_year: safeNum(wa.salaryYear),
    version_number: safeVersionNum(wa.versionNumber),
    waive_date: safeStr(wa.waiveDate),
    cap_value: safeBigInt(wa.capValue),
    cap_change_value: safeBigInt(wa.capChangeValue),
    is_cap_calculated: safeBool(wa.capCalculated),
    tax_value: safeBigInt(wa.taxValue),
    tax_change_value: safeBigInt(wa.taxChangeValue),
    is_tax_calculated: safeBool(wa.taxCalculated),
    apron_value: safeBigInt(wa.apronValue),
    apron_change_value: safeBigInt(wa.apronChangeValue),
    is_apron_calculated: safeBool(wa.apronCalculated),
    mts_value: safeBigInt(wa.mtsValue),
    mts_change_value: safeBigInt(wa.mtsChangeValue),
    two_way_salary: safeBigInt(wa.twoWaySalary),
    two_way_nba_salary: safeBigInt(wa.twoWayNbaSalary),
    two_way_dlg_salary: safeBigInt(wa.twoWayDlgSalary),
    option_decision_lk: safeStr(wa.optionDecisionLk),
    wnba_contract_id: safeNum(wa.wnbaContractId),
    wnba_version_number: safeVersionNum(wa.wnbaVersionNumber),
    ...prov,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Main
// ─────────────────────────────────────────────────────────────────────────────

export async function main(
  dry_run = false,
  lineage_id?: number,
  s3_key?: string,
  extract_dir: string = SHARED_DIR
) {
  const startedAt = new Date().toISOString();
  const tables: UpsertResult[] = [];
  const errors: string[] = [];

  try {
    // Find the actual extract directory
    const entries = await readdir(extract_dir, { withFileTypes: true });
    const subDir = entries.find((e) => e.isDirectory());
    const baseDir = subDir ? `${extract_dir}/${subDir.name}` : extract_dir;

    // Get lineage context
    const ctx = await getLineageContext(baseDir);
    const effectiveLineageId = lineage_id ?? ctx.lineage_id;
    const effectiveS3Key = s3_key ?? ctx.s3_key;
    void effectiveLineageId; // lineage_id is not stored on these tables, but available for debugging

    // Locate JSON files
    const allFiles = await readdir(baseDir);

    const tradeJsonFile = allFiles.find((f) => f.includes("trade") && f.endsWith(".json"));
    const transactionJsonFile = allFiles.find(
      (f) => f.includes("transaction") && f.endsWith(".json") && !f.includes("waiver")
    );
    const ledgerJsonFile = allFiles.find((f) => f.includes("ledger") && f.endsWith(".json"));
    const twaJsonFile = allFiles.find(
      (f) => f.includes("transactions-waiver-amounts") && f.endsWith(".json")
    );

    if (!tradeJsonFile) throw new Error(`No trade JSON file found in ${baseDir}`);
    if (!transactionJsonFile) throw new Error(`No transaction JSON file found in ${baseDir}`);
    if (!ledgerJsonFile) throw new Error(`No ledger JSON file found in ${baseDir}`);
    if (!twaJsonFile) throw new Error(`No transactions-waiver-amounts JSON file found in ${baseDir}`);

    const provenanceBase = {
      source_drop_file: effectiveS3Key,
      parser_version: PARSER_VERSION,
      ingested_at: new Date(),
    };

    // ─────────────────────────────────────────────────────────────────────────
    // Trades
    // ─────────────────────────────────────────────────────────────────────────

    console.log(`Reading ${tradeJsonFile}...`);
    const tradeData = await Bun.file(`${baseDir}/${tradeJsonFile}`).json();
    const trades: any[] = asArray(tradeData?.["xml-extract"]?.["trade-extract"]?.trade);
    console.log(`Found ${trades.length} trades`);

    const tradeRows: any[] = [];
    const tradeTeamRows: any[] = [];
    const tradeTeamDetailRows: any[] = [];
    const tradeGroupRows: any[] = [];

    for (const t of trades) {
      const tradeId = safeNum(t?.tradeId);
      if (!tradeId) continue;

      const tradeProv = { ...provenanceBase, source_hash: hash(JSON.stringify(t)) };
      tradeRows.push(transformTrade(t, tradeProv));

      const tradeTeams = asArray(t?.tradeTeams?.tradeTeam);
      for (const tt of tradeTeams) {
        const teamId = safeNum(tt?.teamId);
        if (!teamId) continue;

        const ttProv = { ...provenanceBase, source_hash: hash(JSON.stringify({ tradeId, ...tt })) };
        const tradeTeamRow = transformTradeTeam(tt, tradeId, ttProv);
        if (tradeTeamRow.trade_team_id) tradeTeamRows.push(tradeTeamRow);

        const details = asArray(tt?.tradeTeamDetails?.tradeTeamDetail);
        for (const ttd of details) {
          const seqno = safeNum(ttd?.seqno);
          if (seqno === null) continue;

          const ttdProv = {
            ...provenanceBase,
            source_hash: hash(JSON.stringify({ tradeId, teamId, ...ttd })),
          };
          const detailRow = transformTradeTeamDetail(ttd, tradeId, teamId, ttdProv);
          if (detailRow.trade_team_detail_id) tradeTeamDetailRows.push(detailRow);
        }

        // In current extracts, trade groups are nested under tradeTeam.
        const groupsFromTeam = asArray(tt?.tradeGroups?.tradeGroup);
        const groupsFromTrade = asArray(t?.tradeGroups?.tradeGroup);
        const groups = groupsFromTeam.length > 0 ? groupsFromTeam : groupsFromTrade;

        for (const tg of groups) {
          const groupNumber = safeNum(tg?.tradeGroupNumber);
          if (groupNumber === null) continue;

          const tgProv = {
            ...provenanceBase,
            source_hash: hash(JSON.stringify({ tradeId, teamId, ...tg })),
          };
          const groupRow = transformTradeGroup(tg, tradeId, teamId, tgProv);
          if (groupRow.trade_group_id) tradeGroupRows.push(groupRow);
        }
      }
    }

    console.log(
      `Prepared rows: trades=${tradeRows.length}, trade_teams=${tradeTeamRows.length}, trade_team_details=${tradeTeamDetailRows.length}, trade_groups=${tradeGroupRows.length}`
    );

    // ─────────────────────────────────────────────────────────────────────────
    // Transactions
    // ─────────────────────────────────────────────────────────────────────────

    console.log(`Reading ${transactionJsonFile}...`);
    const transactionData = await Bun.file(`${baseDir}/${transactionJsonFile}`).json();
    const transactions: any[] = asArray(
      transactionData?.["xml-extract"]?.["transaction-extract"]?.transaction
    );
    console.log(`Found ${transactions.length} transactions`);

    // ─────────────────────────────────────────────────────────────────────────
    // Ledger
    // ─────────────────────────────────────────────────────────────────────────

    console.log(`Reading ${ledgerJsonFile}...`);
    const ledgerData = await Bun.file(`${baseDir}/${ledgerJsonFile}`).json();
    const ledgerEntries: any[] = asArray(
      ledgerData?.["xml-extract"]?.["ledger-extract"]?.transactionLedgerEntry
    );
    console.log(`Found ${ledgerEntries.length} ledger entries`);

    // ─────────────────────────────────────────────────────────────────────────
    // Transaction waiver amounts
    // ─────────────────────────────────────────────────────────────────────────

    console.log(`Reading ${twaJsonFile}...`);
    const twaData = await Bun.file(`${baseDir}/${twaJsonFile}`).json();
    const waiverAmounts: any[] = asArray(twaData?.["xml-extract"]?.["twa-extract"]?.transactionWaiverAmount);
    console.log(`Found ${waiverAmounts.length} transaction waiver amounts`);

    const BATCH_SIZE = 500;

    // Upsert trades
    for (let i = 0; i < tradeRows.length; i += BATCH_SIZE) {
      const batch = tradeRows.slice(i, i + BATCH_SIZE);
      if (!dry_run) {
        const result = await upsertBatch("pcms", "trades", batch, ["trade_id"]);
        tables.push(result);
        if (!result.success) errors.push(result.error!);
      } else {
        tables.push({ table: "pcms.trades", attempted: batch.length, success: true });
      }
    }

    // Upsert trade teams
    for (let i = 0; i < tradeTeamRows.length; i += BATCH_SIZE) {
      const batch = tradeTeamRows.slice(i, i + BATCH_SIZE);
      if (!dry_run) {
        const result = await upsertBatch("pcms", "trade_teams", batch, ["trade_team_id"]);
        tables.push(result);
        if (!result.success) errors.push(result.error!);
      } else {
        tables.push({ table: "pcms.trade_teams", attempted: batch.length, success: true });
      }
    }

    // Upsert trade team details
    for (let i = 0; i < tradeTeamDetailRows.length; i += BATCH_SIZE) {
      const batch = tradeTeamDetailRows.slice(i, i + BATCH_SIZE);
      if (!dry_run) {
        const result = await upsertBatch("pcms", "trade_team_details", batch, [
          "trade_team_detail_id",
        ]);
        tables.push(result);
        if (!result.success) errors.push(result.error!);
      } else {
        tables.push({ table: "pcms.trade_team_details", attempted: batch.length, success: true });
      }
    }

    // Upsert trade groups
    for (let i = 0; i < tradeGroupRows.length; i += BATCH_SIZE) {
      const batch = tradeGroupRows.slice(i, i + BATCH_SIZE);
      if (!dry_run) {
        const result = await upsertBatch("pcms", "trade_groups", batch, ["trade_group_id"]);
        tables.push(result);
        if (!result.success) errors.push(result.error!);
      } else {
        tables.push({ table: "pcms.trade_groups", attempted: batch.length, success: true });
      }
    }

    // Upsert transactions (transform in batches to keep memory bounded)
    for (let i = 0; i < transactions.length; i += BATCH_SIZE) {
      const batch = transactions.slice(i, i + BATCH_SIZE);
      const rows = batch
        .map((t) => {
          const txId = safeNum(t?.transactionId);
          if (!txId) return null;
          return transformTransaction(t, {
            ...provenanceBase,
            source_hash: hash(JSON.stringify(t)),
          });
        })
        .filter(Boolean) as Record<string, unknown>[];

      if (rows.length === 0) continue;

      if (!dry_run) {
        const result = await upsertBatch("pcms", "transactions", rows, ["transaction_id"]);
        tables.push(result);
        if (!result.success) errors.push(result.error!);
      } else {
        tables.push({ table: "pcms.transactions", attempted: rows.length, success: true });
      }
    }

    // Upsert ledger entries
    for (let i = 0; i < ledgerEntries.length; i += BATCH_SIZE) {
      const batch = ledgerEntries.slice(i, i + BATCH_SIZE);
      const rows = batch
        .map((le) => {
          const leId = safeNum(le?.transactionLedgerEntryId);
          if (leId === null) return null;
          return transformLedgerEntry(le, {
            ...provenanceBase,
            source_hash: hash(JSON.stringify(le)),
          });
        })
        .filter(Boolean) as Record<string, unknown>[];

      if (rows.length === 0) continue;

      if (!dry_run) {
        const result = await upsertBatch("pcms", "ledger_entries", rows, ["transaction_ledger_entry_id"]);
        tables.push(result);
        if (!result.success) errors.push(result.error!);
      } else {
        tables.push({ table: "pcms.ledger_entries", attempted: rows.length, success: true });
      }
    }

    // Upsert waiver amounts
    for (let i = 0; i < waiverAmounts.length; i += BATCH_SIZE) {
      const batch = waiverAmounts.slice(i, i + BATCH_SIZE);
      const rows = batch
        .map((wa) => {
          const waId = safeNum(wa?.transactionWaiverAmountId);
          if (!waId) return null;
          return transformWaiverAmount(wa, {
            ...provenanceBase,
            source_hash: hash(JSON.stringify(wa)),
          });
        })
        .filter(Boolean) as Record<string, unknown>[];

      if (rows.length === 0) continue;

      if (!dry_run) {
        const result = await upsertBatch("pcms", "transaction_waiver_amounts", rows, [
          "transaction_waiver_amount_id",
        ]);
        tables.push(result);
        if (!result.success) errors.push(result.error!);
      } else {
        tables.push({ table: "pcms.transaction_waiver_amounts", attempted: rows.length, success: true });
      }
    }

    return {
      dry_run,
      started_at: startedAt,
      finished_at: new Date().toISOString(),
      tables,
      errors,
    };
  } catch (e: any) {
    errors.push(e?.message ?? String(e));
    return {
      dry_run,
      started_at: startedAt,
      finished_at: new Date().toISOString(),
      tables,
      errors,
    };
  }
}
