#!/usr/bin/env bun
/**
 * Show the data paths for all JSON files - useful for writing import scripts.
 */
import { readdir } from "node:fs/promises";

const SHARED_DIR = "./.shared";

async function main() {
  const entries = await readdir(SHARED_DIR, { withFileTypes: true });
  const extractedDir = entries.find((e) => e.isDirectory());
  const workDir = extractedDir ? `${SHARED_DIR}/${extractedDir.name}` : SHARED_DIR;

  const allFiles = await readdir(workDir);
  const jsonFiles = allFiles.filter((f) => f.endsWith(".json") && f !== "lineage.json");

  console.log("// JSON Data Paths Reference\n");

  for (const jsonFile of jsonFiles.sort()) {
    const data = await Bun.file(`${workDir}/${jsonFile}`).json();
    const xmlExtract = data["xml-extract"];
    if (!xmlExtract) continue;

    const extractType = xmlExtract.extractType;
    const extractKey = Object.keys(xmlExtract).find(k => k.endsWith("-extract") && k !== "extractType");
    
    if (!extractKey) continue;

    const inner = xmlExtract[extractKey];
    const arrayKeys = Object.keys(inner).filter(k => Array.isArray(inner[k]));
    const objectKeys = Object.keys(inner).filter(k => !Array.isArray(inner[k]) && typeof inner[k] === "object");

    const shortName = jsonFile.replace("nba_pcms_full_extract_", "").replace(".json", "");
    console.log(`// ${shortName} (${extractType})`);
    
    for (const ak of arrayKeys) {
      console.log(`data["xml-extract"]["${extractKey}"]["${ak}"]  // Array[${inner[ak].length}]`);
    }
    
    for (const ok of objectKeys) {
      const subArrays = Object.entries(inner[ok])
        .filter(([_, v]) => Array.isArray(v))
        .map(([k, v]) => `${k}[${(v as any[]).length}]`);
      if (subArrays.length > 0) {
        console.log(`data["xml-extract"]["${extractKey}"]["${ok}"]  // { ${subArrays.join(", ")} }`);
      }
    }
    console.log();
  }
}

main().catch(console.error);
