#!/usr/bin/env bun
/**
 * Parse all XML files in .shared/ to JSON for local development.
 * 
 * Usage:
 *   bun run scripts/parse-xml-to-json.ts
 *   bun run scripts/parse-xml-to-json.ts --dir ./path/to/extracted
 */
import { XMLParser } from "fast-xml-parser";
import { readdir } from "node:fs/promises";
import { parseArgs } from "util";

const SHARED_DIR = "./.shared/pcms";

// XML Parser configuration matching lineage script
const xmlParser = new XMLParser({
  ignoreAttributes: false,
  attributeNamePrefix: "@_",
  allowBooleanAttributes: true,
  parseTagValue: true,
  trimValues: true,
  // Handle xsi:nil="true" and empty tags as null
  tagValueProcessor: (_name, val) => (val === "" ? null : val),
  attributeValueProcessor: (name, val) =>
    name === "xsi:nil" && val === "true" ? null : val,
  // Ensure these are always arrays even if single element
  isArray: (name) =>
    [
      "player",
      "lkTeam",
      "contract",
      "version",
      "salary",
      "bonus",
      "trade",
      "transaction",
      "teamException",
      "teamExceptionDetail",
      "draftPick",
      "twoWayDailyStatus",
      "paymentSchedule",
      "paymentScheduleDetail",
      "bonusCriteria",
      "contractProtection",
      "contractProtectionCondition",
      "playerServiceYear",
      "protectionType",
      "lookup",
      "lookupValue",
      "teamBudget",
      "budgetLineItem",
      "ledgerEntry",
      "waiverPriority",
      "rookieScaleAmount",
      "systemValue",
      "ncaValue",
    ].includes(name),
});

async function main() {
  const { values } = parseArgs({
    args: Bun.argv.slice(2),
    options: {
      dir: { type: "string", short: "d", default: SHARED_DIR },
      verbose: { type: "boolean", short: "v", default: false },
    },
  });

  const baseDir = values.dir!;
  const verbose = values.verbose!;

  // Find the extracted directory (e.g., nba_pcms_full_extract)
  const entries = await readdir(baseDir, { withFileTypes: true });
  const extractedDir = entries.find((e) => e.isDirectory());
  const workDir = extractedDir ? `${baseDir}/${extractedDir.name}` : baseDir;

  console.log(`📂 Working directory: ${workDir}`);

  // List XML files
  const allFiles = await readdir(workDir);
  const xmlFiles = allFiles.filter((f) => f.endsWith(".xml"));

  console.log(`📄 Found ${xmlFiles.length} XML files\n`);

  const results: { file: string; success: boolean; error?: string; size?: number }[] = [];

  for (const xmlFile of xmlFiles) {
    const xmlPath = `${workDir}/${xmlFile}`;
    const jsonFile = xmlFile.replace(".xml", ".json");
    const jsonPath = `${workDir}/${jsonFile}`;

    process.stdout.write(`  Parsing ${xmlFile}...`);

    try {
      const xmlContent = await Bun.file(xmlPath).text();
      const parsed = xmlParser.parse(xmlContent);
      const jsonContent = JSON.stringify(parsed, null, 2);
      await Bun.write(jsonPath, jsonContent);

      const size = jsonContent.length;
      results.push({ file: jsonFile, success: true, size });
      console.log(` ✅ (${formatBytes(size)})`);

      if (verbose) {
        // Show top-level keys and array counts
        const keys = Object.keys(parsed);
        for (const key of keys) {
          const val = parsed[key];
          if (typeof val === "object" && val !== null) {
            const subKeys = Object.keys(val);
            for (const sk of subKeys) {
              if (Array.isArray(val[sk])) {
                console.log(`       └─ ${key}.${sk}: ${val[sk].length} items`);
              }
            }
          }
        }
      }
    } catch (err: any) {
      results.push({ file: jsonFile, success: false, error: err.message });
      console.log(` ❌ ${err.message}`);
    }
  }

  // Summary
  const success = results.filter((r) => r.success).length;
  const failed = results.filter((r) => !r.success).length;
  const totalSize = results.reduce((sum, r) => sum + (r.size || 0), 0);

  console.log(`\n✨ Done: ${success} succeeded, ${failed} failed`);
  console.log(`📊 Total JSON size: ${formatBytes(totalSize)}`);

  // Show JSON file list for reference
  console.log(`\n📋 JSON files created:`);
  for (const r of results.filter((r) => r.success)) {
    console.log(`   ${r.file}`);
  }
}

function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
}

main().catch(console.error);
