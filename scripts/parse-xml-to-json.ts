#!/usr/bin/env bun
/**
 * Parse XML to CLEAN JSON.
 * 
 * Output: Flat, clean JSON files with:
 *   - snake_case keys (match DB columns)
 *   - null instead of { "@_xsi:nil": "true" }
 *   - No XML wrapper nesting
 * 
 * Usage:
 *   bun run scripts/parse-xml-to-json.ts
 */
import { XMLParser } from "fast-xml-parser";
import { readdir, mkdir } from "node:fs/promises";

const XML_DIR = "./.shared/nba_pcms_full_extract_xml";
const OUT_DIR = "./.shared/nba_pcms_full_extract";

// ─────────────────────────────────────────────────────────────────────────────
// Clean function - the key to everything
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
// Extraction mappings: source key → output config
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
};

// ─────────────────────────────────────────────────────────────────────────────
// Main
// ─────────────────────────────────────────────────────────────────────────────

async function main() {
  console.log(`📂 XML source: ${XML_DIR}`);
  console.log(`📂 Output dir: ${OUT_DIR}\n`);

  await mkdir(OUT_DIR, { recursive: true });

  const allFiles = await readdir(XML_DIR);
  const xmlFiles = allFiles.filter((f) => f.endsWith(".xml"));

  console.log(`📄 Found ${xmlFiles.length} XML files\n`);

  let totalSize = 0;

  for (const xmlFile of xmlFiles) {
    // Extract the key from filename like "nba_pcms_full_extract_player.xml" → "player"
    const key = xmlFile.replace("nba_pcms_full_extract_", "").replace(".xml", "");

    const config = EXTRACT_MAP[key];
    if (!config) {
      console.log(`  ⏭️  ${xmlFile} - no mapping (${key})`);
      continue;
    }

    process.stdout.write(`  ${key} → ${config.outputFile}...`);

    try {
      // Parse XML
      const xmlContent = await Bun.file(`${XML_DIR}/${xmlFile}`).text();
      const parsed = xmlParser.parse(xmlContent);

      // Extract the relevant data
      const rawData = config.extract(parsed);

      // Clean it
      const cleanData = clean(rawData);

      // Write clean JSON
      const outputPath = `${OUT_DIR}/${config.outputFile}`;
      const jsonContent = JSON.stringify(cleanData, null, 2);
      await Bun.write(outputPath, jsonContent);

      const size = jsonContent.length;
      totalSize += size;

      const count = Array.isArray(cleanData) 
        ? cleanData.length 
        : (cleanData && typeof cleanData === 'object' ? Object.keys(cleanData).length : 0);
      console.log(` ✅ ${count} items (${formatBytes(size)})`);
    } catch (err: any) {
      console.log(` ❌ ${err.message}`);
    }
  }

  console.log(`\n✨ Done! Total: ${formatBytes(totalSize)}`);
}

function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
}

main().catch(console.error);
