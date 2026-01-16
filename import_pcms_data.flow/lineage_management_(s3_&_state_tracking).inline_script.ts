import { SQL } from "bun";
import { streamS3File, hashStream, createSummary, finalizeSummary, parsePCMSDate } from "/f/ralph/utils.ts";
import { execSync } from "child_process";
import { mkdirSync, existsSync, readdirSync } from "fs";

const sql = new SQL({ url: Bun.env.POSTGRES_URL!, prepare: false });
const PARSER_VERSION = "2.0.0";
const DEFAULT_S3_KEY = "pcms/nba_pcms_full_extract.zip";
const SHARED_DIR = "./shared/pcms";

/**
 * Downloads S3 file and extracts to ./shared/pcms/
 */
async function downloadAndExtract(s3Key: string): Promise<{ fileHash: string; xmlFiles: string[] }> {
  // Clean and create shared directory
  if (existsSync(SHARED_DIR)) {
    execSync(`rm -rf ${SHARED_DIR}`);
  }
  mkdirSync(SHARED_DIR, { recursive: true });

  // Download from S3
  console.log(`Downloading ${s3Key} from S3...`);
  const resp = await streamS3File(s3Key);
  if (!resp.body) {
    throw new Error(`S3 file not found or empty: ${s3Key}`);
  }

  // Write to temp file and compute hash
  const tmpZip = `/tmp/pcms_extract.zip`;
  const chunks: Uint8Array[] = [];
  for await (const chunk of resp.body) {
    chunks.push(chunk);
  }
  const fullBuffer = Buffer.concat(chunks);
  await Bun.write(tmpZip, fullBuffer);

  // Compute hash
  const hasher = new Bun.CryptoHasher("sha256");
  hasher.update(fullBuffer);
  const fileHash = hasher.digest("hex");

  // Extract to shared directory
  console.log(`Extracting to ${SHARED_DIR}...`);
  execSync(`unzip -o ${tmpZip} -d ${SHARED_DIR}`);
  execSync(`rm -f ${tmpZip}`);

  // List extracted XML files
  const xmlFiles = readdirSync(SHARED_DIR).filter(f => f.endsWith('.xml'));
  console.log(`Extracted ${xmlFiles.length} XML files`);

  return { fileHash, xmlFiles };
}

/**
 * Initializes lineage for a file.
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
 * Updates lineage metadata from the XML header.
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
export async function finishLineage(lineageId: number, count: number, status: 'SUCCESS' | 'FAILED', error?: string) {
  await sql`
    UPDATE pcms.pcms_lineage SET
      record_count = ${count},
      ingestion_status = ${status},
      error_log = ${error || null},
      ingested_at = now()
    WHERE lineage_id = ${lineageId}
  `;
}

export async function main(
  dry_run = false,
  s3_key = DEFAULT_S3_KEY
) {
  const summary = createSummary(dry_run);

  try {
    const { fileHash, xmlFiles } = await downloadAndExtract(s3_key);

    if (dry_run) {
      // Persist context even for dry-run so downstream steps can proceed
      // even if Windmill doesn't wire results.a.* as expected.
      await Bun.write(`${SHARED_DIR}/lineage.json`, JSON.stringify({
        lineage_id: 0,
        s3_key,
        source_hash: fileHash,
        parser_version: PARSER_VERSION,
        extracted_at: new Date().toISOString(),
        dry_run: true
      }));

      return {
        ...finalizeSummary(summary),
        s3_key,
        extract_dir: SHARED_DIR,
        xml_files: xmlFiles,
        file_hash: fileHash,
        lineage_id: 0
      };
    }

    const lineageId = await initLineage(s3_key, fileHash);
    summary.tables.push({
      table: "pcms.pcms_lineage",
      attempted: 1,
      success: true
    });

    // Persist lineage context for other scripts on the same worker.
    await Bun.write(`${SHARED_DIR}/lineage.json`, JSON.stringify({
      lineage_id: lineageId,
      s3_key,
      source_hash: fileHash,
      parser_version: PARSER_VERSION,
      extracted_at: new Date().toISOString()
    }));

    return {
      ...finalizeSummary(summary),
      extract_dir: SHARED_DIR,
      xml_files: xmlFiles,
      file_hash: fileHash,
      s3_key,
      lineage_id: lineageId
    };

  } catch (e: any) {
    summary.errors.push(e.message);
    return finalizeSummary(summary);
  }
}
