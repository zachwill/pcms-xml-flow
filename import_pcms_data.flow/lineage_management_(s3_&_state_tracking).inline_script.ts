import { SQL } from "bun";
import { $ } from "bun";
import { XMLParser } from "fast-xml-parser";
import { mkdir, readdir, rm } from "node:fs/promises";
import * as wmill from "windmill-client";
import type { S3Object } from "windmill-client";

const sql = new SQL({ url: Bun.env.POSTGRES_URL!, prepare: false });
const PARSER_VERSION = "3.0.0"; // Bumped for clean JSON output
const DEFAULT_S3_KEY = "pcms/nba_pcms_full_extract.zip";
const SHARED_DIR = "./shared/pcms";

// ─────────────────────────────────────────────────────────────────────────────
// Clean function - transforms messy XML-parsed JSON into clean, usable data
// ─────────────────────────────────────────────────────────────────────────────

function clean(obj: unknown): unknown {
  if (obj === null || obj === undefined) return null;
  if (Array.isArray(obj)) return obj.map(clean);
  if (typeof obj !== "object") return obj;

  // Handle xsi:nil objects → null
  if ("@_xsi:nil" in (obj as Record<string, unknown>)) return null;

  const result: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(obj as Record<string, unknown>)) {
    // Skip XML metadata attributes
    if (k.startsWith("@_") || k.startsWith("?")) continue;
    // camelCase → snake_case
    const snakeKey = k.replace(/([A-Z])/g, "_$1").toLowerCase().replace(/^_/, "");
    result[snakeKey] = clean(v);
  }
  return result;
}

// ─────────────────────────────────────────────────────────────────────────────
// XML Parser
// ─────────────────────────────────────────────────────────────────────────────

const xmlParser = new XMLParser({
  ignoreAttributes: false,
  attributeNamePrefix: "@_",
  allowBooleanAttributes: true,
  parseTagValue: true,
  trimValues: true,
  isArray: (name) =>
    [
      // Main entities
      "player", "contract", "version", "salary", "bonus", "trade", "transaction",
      "teamException", "teamExceptionDetail", "draftPick", "twoWayDailyStatus",
      "paymentSchedule", "paymentScheduleDetail", "bonusCriteria",
      "contractProtection", "contractProtectionCondition", "playerServiceYear",
      "protectionType", "teamBudget", "budgetLineItem", "transactionLedgerEntry",
      "waiverPriority", "rookieScaleAmount", "yearlySystemValue",
      "nonContractAmount", "capProjection", "taxRate", "taxTeam", "teamTransaction",
      "yearlySalaryScale", "transactionWaiverAmount",
      // Lookups - inner arrays
      "lkAgency", "lkWApronLevel", "lkBudgetGroup", "lkContractBonusType",
      "lkContractPaymentType", "lkContractType", "lkCriterium", "lkCriteriaOperator",
      "lkDlgExperienceLevel", "lkDlgSalaryLevel", "lkDraftPickConditional",
      "lkEarnedType", "lkExceptionAction", "lkExceptionType", "lkExclusivityStatuses",
      "lkFreeAgentDesignation", "lkFreeAgentStatus", "lkLeague", "lkMaxContract",
      "lkMinContract", "lkModifier", "lkOptionDecision", "lkOption",
      "lkPaymentScheduleType", "lkPersonType", "lkPlayerConsent", "lkPlayerStatus",
      "lkPosition", "lkProtectionCoverage", "lkProtectionType", "lkRecordStatus",
      "lkSalaryOverrideReason", "lkSeasonType", "lkSignedMethod",
      "lkSubjectToApronReason", "lkTradeEntry", "lkTradeRestriction",
      "lkTransactionDescription", "lkTransactionType", "lkTwoWayDailyStatus",
      "lkWithinDay", "lkSchool", "lkTeam",
    ].includes(name),
});

// ─────────────────────────────────────────────────────────────────────────────
// Extraction mappings: XML filename key → clean output
// ─────────────────────────────────────────────────────────────────────────────

interface ExtractConfig {
  outputFile: string;
  extract: (data: any) => unknown;
}

const EXTRACT_MAP: Record<string, ExtractConfig> = {
  "player": {
    outputFile: "players.json",
    extract: (d) => d["xml-extract"]["player-extract"]["player"],
  },
  "contract": {
    outputFile: "contracts.json",
    extract: (d) => d["xml-extract"]["contract-extract"]["contract"],
  },
  "transaction": {
    outputFile: "transactions.json",
    extract: (d) => d["xml-extract"]["transaction-extract"]["transaction"],
  },
  "ledger": {
    outputFile: "ledger.json",
    extract: (d) => d["xml-extract"]["ledger-extract"]["transactionLedgerEntry"],
  },
  "trade": {
    outputFile: "trades.json",
    extract: (d) => d["xml-extract"]["trade-extract"]["trade"],
  },
  "dp-extract": {
    outputFile: "draft_picks.json",
    extract: (d) => d["xml-extract"]["dp-extract"]["draftPick"],
  },
  "team-exception": {
    outputFile: "team_exceptions.json",
    extract: (d) => d["xml-extract"]["team-exception-extract"]["exceptionTeams"],
  },
  "team-budget": {
    outputFile: "team_budgets.json",
    extract: (d) => ({
      budget_teams: d["xml-extract"]["team-budget-extract"]["budgetTeams"],
      tax_teams: d["xml-extract"]["team-budget-extract"]["taxTeams"],
    }),
  },
  "lookup": {
    outputFile: "lookups.json",
    extract: (d) => d["xml-extract"]["lookups-extract"],
  },
  "cap-projections": {
    outputFile: "cap_projections.json",
    extract: (d) => d["xml-extract"]["cap-projections-extract"]["capProjection"],
  },
  "yearly-system-values": {
    outputFile: "yearly_system_values.json",
    extract: (d) => d["xml-extract"]["yearly-system-values-extract"]["yearlySystemValue"],
  },
  "nca-extract": {
    outputFile: "non_contract_amounts.json",
    extract: (d) => d["xml-extract"]["nca-extract"]["nonContractAmount"],
  },
  "rookie-scale-amounts": {
    outputFile: "rookie_scale_amounts.json",
    extract: (d) => d["xml-extract"]["rookie-scale-amounts-extract"]["rookieScaleAmount"],
  },
  "team-tr-extract": {
    outputFile: "team_transactions.json",
    extract: (d) => d["xml-extract"]["tt-extract"]["teamTransaction"],
  },
  "tax-rates-extract": {
    outputFile: "tax_rates.json",
    extract: (d) => d["xml-extract"]["tax-rates-extract"]["taxRate"],
  },
  "tax-teams-extract": {
    outputFile: "tax_teams.json",
    extract: (d) => d["xml-extract"]["tax-teams-extract"]["taxTeam"],
  },
  "transactions-waiver-amounts": {
    outputFile: "transaction_waiver_amounts.json",
    extract: (d) => d["xml-extract"]["twa-extract"]["transactionWaiverAmount"],
  },
  "yearly-salary-scales-extract": {
    outputFile: "yearly_salary_scales.json",
    extract: (d) => d["xml-extract"]["yearly-salary-scales-extract"]["yearlySalaryScale"],
  },
  "dps": {
    outputFile: "draft_pick_summaries.json",
    extract: (d) => d["xml-extract"]["dps-extract"]["draft-pick-summary"],
  },
  "two-way": {
    outputFile: "two_way.json",
    extract: (d) => ({
      daily_statuses: d["xml-extract"]["two-way-extract"]["daily-statuses"],
      player_day_counts: d["xml-extract"]["two-way-extract"]["player-day-counts"],
      two_way_seasons: d["xml-extract"]["two-way-extract"]["two-way-seasons"],
    }),
  },
  "two-way-utility-extract": {
    outputFile: "two_way_utility.json",
    extract: (d) => d["xml-extract"]["two-way-utility-extract"],
  },
  "waiver-priority-extract": {
    outputFile: "waiver_priority.json",
    extract: (d) => d["xml-extract"]["waiver-priority-extract"],
  },
};

// ─────────────────────────────────────────────────────────────────────────────
// S3 Download, Extract, Parse to Clean JSON
// ─────────────────────────────────────────────────────────────────────────────

async function downloadExtractAndParse(s3Key: string): Promise<{
  fileHash: string;
  extractDir: string;
  jsonFiles: string[];
}> {
  // Clean and create shared directory
  try {
    await rm(SHARED_DIR, { recursive: true, force: true });
  } catch { /* ignore */ }
  await mkdir(SHARED_DIR, { recursive: true });

  // Download from S3
  console.log(`Downloading ${s3Key} from S3...`);
  const s3obj: S3Object = { s3: s3Key };
  const buffer = await wmill.loadS3File(s3obj);
  if (!buffer) throw new Error(`Failed to download ${s3Key} from S3`);

  // Write to temp file
  const tmpZip = `${SHARED_DIR}/extract.zip`;
  await Bun.write(tmpZip, buffer);

  // Compute hash
  const fileHash = new Bun.CryptoHasher("sha256").update(buffer).digest("hex");
  console.log(`File hash: ${fileHash}`);

  // Extract
  console.log(`Extracting to ${SHARED_DIR}...`);
  await $`unzip -o ${tmpZip} -d ${SHARED_DIR}`.quiet();
  await rm(tmpZip);

  // Find extracted directory
  const entries = await readdir(SHARED_DIR, { withFileTypes: true });
  const extractedDir = entries.find(e => e.isDirectory());
  const extractDir = extractedDir ? `${SHARED_DIR}/${extractedDir.name}` : SHARED_DIR;

  // List XML files
  const allFiles = await readdir(extractDir);
  const xmlFiles = allFiles.filter(f => f.endsWith(".xml"));
  console.log(`Found ${xmlFiles.length} XML files`);

  // Parse each XML → clean JSON
  const jsonFiles: string[] = [];
  for (const xmlFile of xmlFiles) {
    // Extract key from filename like "nba_pcms_full_extract_player.xml" → "player"
    const key = xmlFile.replace(/^nba_pcms_full_extract_/, "").replace(".xml", "");
    const config = EXTRACT_MAP[key];

    if (!config) {
      console.log(`  ⏭️  ${xmlFile} - no mapping`);
      continue;
    }

    console.log(`  ${key} → ${config.outputFile}...`);
    try {
      const xmlContent = await Bun.file(`${extractDir}/${xmlFile}`).text();
      const parsed = xmlParser.parse(xmlContent);
      const rawData = config.extract(parsed);
      const cleanData = clean(rawData);
      await Bun.write(`${extractDir}/${config.outputFile}`, JSON.stringify(cleanData));
      jsonFiles.push(config.outputFile);
    } catch (err) {
      console.error(`  ❌ Failed: ${err}`);
    }
  }

  console.log(`Parsed ${jsonFiles.length} clean JSON files`);
  return { fileHash, extractDir, jsonFiles };
}

// ─────────────────────────────────────────────────────────────────────────────
// Database
// ─────────────────────────────────────────────────────────────────────────────

async function initLineage(key: string, fileHash: string): Promise<number> {
  const result = await sql`
    INSERT INTO pcms.pcms_lineage (
      drop_filename,
      source_hash,
      parser_version,
      s3_key,
      ingestion_status,
      ingested_at
    ) VALUES (
      ${key.split("/").pop()},
      ${fileHash},
      ${PARSER_VERSION},
      ${key},
      'PROCESSING',
      now()
    )
    ON CONFLICT (source_hash) DO UPDATE SET
      ingestion_status = 'PROCESSING',
      ingested_at = now()
    RETURNING lineage_id
  `;
  return result[0].lineage_id;
}

// ─────────────────────────────────────────────────────────────────────────────
// Main
// ─────────────────────────────────────────────────────────────────────────────

export async function main(dry_run = false, s3_key = DEFAULT_S3_KEY) {
  const startedAt = new Date().toISOString();
  const errors: string[] = [];

  try {
    const { fileHash, extractDir, jsonFiles } = await downloadExtractAndParse(s3_key);

    const lineageId = dry_run ? 0 : await initLineage(s3_key, fileHash);

    // Write lineage context for downstream steps
    await Bun.write(
      `${extractDir}/lineage.json`,
      JSON.stringify({
        lineage_id: lineageId,
        s3_key,
        source_hash: fileHash,
        parser_version: PARSER_VERSION,
        extracted_at: new Date().toISOString(),
        dry_run,
      })
    );

    return {
      dry_run,
      started_at: startedAt,
      finished_at: new Date().toISOString(),
      s3_key,
      extract_dir: extractDir,
      json_files: jsonFiles,
      file_hash: fileHash,
      lineage_id: lineageId,
      tables: [{ table: "pcms.pcms_lineage", attempted: dry_run ? 0 : 1, success: true }],
      errors: [],
    };
  } catch (e: any) {
    errors.push(e.message);
    return {
      dry_run,
      started_at: startedAt,
      finished_at: new Date().toISOString(),
      s3_key,
      extract_dir: SHARED_DIR,
      json_files: [],
      file_hash: "",
      lineage_id: 0,
      tables: [],
      errors,
    };
  }
}
