import { SQL } from "bun";
import { $ } from "bun";
import { XMLParser } from "fast-xml-parser";
import { mkdir, readdir, rm } from "node:fs/promises";
import * as wmill from "windmill-client";
import type { S3Object } from "windmill-client";

const sql = new SQL({ url: Bun.env.POSTGRES_URL!, prepare: false });
const PARSER_VERSION = "2.1.0";
const DEFAULT_S3_KEY = "pcms/nba_pcms_full_extract.zip";
const SHARED_DIR = "./shared/pcms";

// XML Parser configuration for PCMS files
const xmlParser = new XMLParser({
  ignoreAttributes: false,
  attributeNamePrefix: "@_",
  allowBooleanAttributes: true,
  parseTagValue: true,
  trimValues: true,
  // Handle xsi:nil="true" and empty tags as null
  tagValueProcessor: (_name, val) => (val === "" ? null : val),
  attributeValueProcessor: (name, val) => (name === "xsi:nil" && val === "true" ? null : val),
  // Ensure these are always arrays even if single element
  isArray: (name) => [
    "player", "lkTeam", "contract", "version", "salary", "bonus",
    "trade", "transaction", "teamException", "teamExceptionDetail",
    "draftPick", "twoWayDailyStatus", "paymentSchedule", "paymentScheduleDetail",
    "bonusCriteria", "contractProtection", "contractProtectionCondition",
    "playerServiceYear", "protectionType"
  ].includes(name),
});

/**
 * Downloads S3 file, extracts ZIP, and parses all XML to JSON.
 */
async function downloadExtractAndParse(s3Key: string): Promise<{
  fileHash: string;
  xmlFiles: string[];
  jsonFiles: string[];
}> {
  // Clean and create shared directory
  try {
    await rm(SHARED_DIR, { recursive: true, force: true });
  } catch { /* ignore if doesn't exist */ }
  await mkdir(SHARED_DIR, { recursive: true });

  // Download from S3
  console.log(`Downloading ${s3Key} from S3...`);
  const s3obj: S3Object = { s3: s3Key };
  const response = await wmill.loadS3File(s3obj);
  const buffer = new Uint8Array(await response.arrayBuffer());

  // Write to temp file
  const tmpZip = `${SHARED_DIR}/extract.zip`;
  await Bun.write(tmpZip, buffer);

  // Compute hash
  const fileHash = new Bun.CryptoHasher("sha256").update(buffer).digest("hex");
  console.log(`File hash: ${fileHash}`);

  // Extract using Bun shell
  console.log(`Extracting to ${SHARED_DIR}...`);
  await $`unzip -o ${tmpZip} -d ${SHARED_DIR}`.quiet();
  await rm(tmpZip);

  // Find the extracted directory (usually named like nba_pcms_full_extract)
  const entries = await readdir(SHARED_DIR, { withFileTypes: true });
  const extractedDir = entries.find(e => e.isDirectory());
  const baseDir = extractedDir ? `${SHARED_DIR}/${extractedDir.name}` : SHARED_DIR;

  // List XML files
  const allFiles = await readdir(baseDir);
  const xmlFiles = allFiles.filter(f => f.endsWith(".xml"));
  console.log(`Found ${xmlFiles.length} XML files`);

  // Parse each XML file to JSON
  const jsonFiles: string[] = [];
  for (const xmlFile of xmlFiles) {
    const xmlPath = `${baseDir}/${xmlFile}`;
    const jsonFile = xmlFile.replace(".xml", ".json");
    const jsonPath = `${baseDir}/${jsonFile}`;

    console.log(`Parsing ${xmlFile}...`);
    try {
      const xmlContent = await Bun.file(xmlPath).text();
      const parsed = xmlParser.parse(xmlContent);
      await Bun.write(jsonPath, JSON.stringify(parsed));
      jsonFiles.push(jsonFile);
    } catch (err) {
      console.error(`Failed to parse ${xmlFile}: ${err}`);
    }
  }

  console.log(`Parsed ${jsonFiles.length} files to JSON`);
  return { fileHash, xmlFiles, jsonFiles };
}

/**
 * Safe date parser for PCMS dates.
 */
function parsePCMSDate(val: string | null | undefined): string | null {
  if (!val || val === "0001-01-01" || val === "") return null;
  if (!isNaN(Date.parse(String(val)))) return String(val);
  return null;
}

/**
 * Initializes lineage record for this import.
 */
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

/**
 * Updates lineage metadata from XML headers.
 */
export async function updateLineageMetadata(lineageId: number, metadata: {
  extractType?: string;
  extractVersion?: string;
  asofDate?: string;
  runDate?: string;
}) {
  await sql`
    UPDATE pcms.pcms_lineage SET
      source_extract_type = ${metadata.extractType || null},
      source_extract_version = ${metadata.extractVersion || null},
      as_of_date = ${parsePCMSDate(metadata.asofDate)},
      run_date = ${parsePCMSDate(metadata.runDate)}
    WHERE lineage_id = ${lineageId}
  `;
}

/**
 * Marks lineage as finished.
 */
export async function finishLineage(
  lineageId: number,
  count: number,
  status: "SUCCESS" | "FAILED",
  error?: string
) {
  await sql`
    UPDATE pcms.pcms_lineage SET
      record_count = ${count},
      ingestion_status = ${status},
      error_log = ${error || null},
      ingested_at = now()
    WHERE lineage_id = ${lineageId}
  `;
}

// ─────────────────────────────────────────────────────────────────────────────
// Main
// ─────────────────────────────────────────────────────────────────────────────

export async function main(dry_run = false, s3_key = DEFAULT_S3_KEY) {
  const startedAt = new Date().toISOString();
  const errors: string[] = [];

  try {
    const { fileHash, xmlFiles, jsonFiles } = await downloadExtractAndParse(s3_key);

    // Find the extracted directory path
    const entries = await readdir(SHARED_DIR, { withFileTypes: true });
    const extractedDir = entries.find(e => e.isDirectory());
    const extractDir = extractedDir ? `${SHARED_DIR}/${extractedDir.name}` : SHARED_DIR;

    if (dry_run) {
      // Write lineage context for downstream steps
      await Bun.write(
        `${extractDir}/lineage.json`,
        JSON.stringify({
          lineage_id: 0,
          s3_key,
          source_hash: fileHash,
          parser_version: PARSER_VERSION,
          extracted_at: new Date().toISOString(),
          dry_run: true,
        })
      );

      return {
        dry_run: true,
        started_at: startedAt,
        finished_at: new Date().toISOString(),
        s3_key,
        extract_dir: extractDir,
        xml_files: xmlFiles,
        json_files: jsonFiles,
        file_hash: fileHash,
        lineage_id: 0,
        tables: [{ table: "pcms.pcms_lineage", attempted: 0, success: true }],
        errors: [],
      };
    }

    // Create lineage record
    const lineageId = await initLineage(s3_key, fileHash);

    // Write lineage context for downstream steps
    await Bun.write(
      `${extractDir}/lineage.json`,
      JSON.stringify({
        lineage_id: lineageId,
        s3_key,
        source_hash: fileHash,
        parser_version: PARSER_VERSION,
        extracted_at: new Date().toISOString(),
      })
    );

    return {
      dry_run: false,
      started_at: startedAt,
      finished_at: new Date().toISOString(),
      s3_key,
      extract_dir: extractDir,
      xml_files: xmlFiles,
      json_files: jsonFiles,
      file_hash: fileHash,
      lineage_id: lineageId,
      tables: [{ table: "pcms.pcms_lineage", attempted: 1, success: true }],
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
      xml_files: [],
      json_files: [],
      file_hash: "",
      lineage_id: 0,
      tables: [],
      errors,
    };
  }
}
