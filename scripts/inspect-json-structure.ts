#!/usr/bin/env bun
/**
 * Inspect the structure of parsed JSON files.
 * Shows top-level keys, array counts, and sample records.
 * 
 * Usage:
 *   bun run scripts/inspect-json-structure.ts                    # all files
 *   bun run scripts/inspect-json-structure.ts player             # files matching "player"
 *   bun run scripts/inspect-json-structure.ts contract --sample  # show sample record
 */
import { readdir } from "node:fs/promises";
import { parseArgs } from "util";

const SHARED_DIR = "./.shared";

async function main() {
  const { values, positionals } = parseArgs({
    args: Bun.argv.slice(2),
    options: {
      dir: { type: "string", short: "d", default: SHARED_DIR },
      sample: { type: "boolean", short: "s", default: false },
      depth: { type: "string", default: "3" },
    },
    allowPositionals: true,
  });

  const baseDir = values.dir!;
  const showSample = values.sample!;
  const maxDepth = parseInt(values.depth!, 10);
  const filter = positionals[0]?.toLowerCase();

  // Find the extracted directory
  const entries = await readdir(baseDir, { withFileTypes: true });
  const extractedDir = entries.find((e) => e.isDirectory());
  const workDir = extractedDir ? `${baseDir}/${extractedDir.name}` : baseDir;

  // List JSON files
  const allFiles = await readdir(workDir);
  let jsonFiles = allFiles.filter((f) => f.endsWith(".json") && f !== "lineage.json");

  if (filter) {
    jsonFiles = jsonFiles.filter((f) => f.toLowerCase().includes(filter));
  }

  if (jsonFiles.length === 0) {
    console.log(`No JSON files found${filter ? ` matching "${filter}"` : ""}`);
    return;
  }

  for (const jsonFile of jsonFiles) {
    console.log(`\n${"═".repeat(80)}`);
    console.log(`📄 ${jsonFile}`);
    console.log(`${"═".repeat(80)}`);

    const jsonPath = `${workDir}/${jsonFile}`;
    const file = Bun.file(jsonPath);
    const size = file.size;
    console.log(`   Size: ${formatBytes(size)}`);

    try {
      const data = await file.json();
      console.log(`\n   Structure:`);
      printStructure(data, "   ", 0, maxDepth);

      if (showSample) {
        console.log(`\n   Sample record:`);
        const sample = findSampleRecord(data);
        if (sample) {
          console.log(JSON.stringify(sample, null, 2).split("\n").map(l => `   ${l}`).join("\n"));
        } else {
          console.log("   (no array data found)");
        }
      }
    } catch (err: any) {
      console.log(`   ❌ Error: ${err.message}`);
    }
  }
}

function printStructure(obj: any, indent: string, depth: number, maxDepth: number) {
  if (depth >= maxDepth) {
    console.log(`${indent}...`);
    return;
  }

  if (obj === null || obj === undefined) {
    console.log(`${indent}null`);
    return;
  }

  if (Array.isArray(obj)) {
    console.log(`${indent}Array[${obj.length}]`);
    if (obj.length > 0 && depth < maxDepth - 1) {
      console.log(`${indent}  └─ item:`);
      printStructure(obj[0], indent + "     ", depth + 1, maxDepth);
    }
    return;
  }

  if (typeof obj === "object") {
    const keys = Object.keys(obj);
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i];
      const val = obj[key];
      const isLast = i === keys.length - 1;
      const prefix = isLast ? "└─" : "├─";

      if (Array.isArray(val)) {
        console.log(`${indent}${prefix} ${key}: Array[${val.length}]`);
        if (val.length > 0 && depth < maxDepth - 1) {
          const newIndent = indent + (isLast ? "   " : "│  ");
          printStructure(val[0], newIndent + "   ", depth + 1, maxDepth);
        }
      } else if (typeof val === "object" && val !== null) {
        const subKeys = Object.keys(val).slice(0, 5);
        const preview = subKeys.join(", ") + (Object.keys(val).length > 5 ? ", ..." : "");
        console.log(`${indent}${prefix} ${key}: { ${preview} }`);
        if (depth < maxDepth - 1) {
          const newIndent = indent + (isLast ? "   " : "│  ");
          printStructure(val, newIndent, depth + 1, maxDepth);
        }
      } else {
        const typeStr = val === null ? "null" : typeof val;
        const preview = typeof val === "string" && val.length > 30 
          ? `"${val.slice(0, 30)}..."` 
          : JSON.stringify(val);
        console.log(`${indent}${prefix} ${key}: ${typeStr} = ${preview}`);
      }
    }
    return;
  }

  console.log(`${indent}${typeof obj}: ${JSON.stringify(obj)}`);
}

function findSampleRecord(obj: any, depth = 0): any {
  if (depth > 5) return null;
  if (Array.isArray(obj) && obj.length > 0) {
    return obj[0];
  }
  if (typeof obj === "object" && obj !== null) {
    for (const key of Object.keys(obj)) {
      const found = findSampleRecord(obj[key], depth + 1);
      if (found) return found;
    }
  }
  return null;
}

function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
}

main().catch(console.error);
