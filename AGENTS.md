# AGENTS.md - PCMS XML Flow

## Project Context

This is a Windmill flow that imports NBA PCMS XML data into PostgreSQL. The flow runs on Bun runtime.

## Key Files

- `import_pcms_data.flow/flow.yaml` - Flow definition (steps A-L run sequentially)
- `import_pcms_data.flow/*.inline_script.ts` - Individual step implementations
- `new_pcms_schema.flow/*.pg.sql` - PostgreSQL schema definitions
- `utils.ts` - Shared utilities (imported as `f/ralph/utils.ts` on Windmill)
- `.shared/` - Shared directory for passing files between flow steps
- `docs/bun-*.md` - Bun best practices (READ THESE)

## Architecture

1. **Step A (lineage)**: Downloads ZIP from S3, extracts XML, parses ALL XML to JSON, saves to `.shared/`
2. **Steps B-K**: Read JSON from `.shared/`, transform, upsert to Postgres
3. **Step L (finalize)**: Updates lineage status to SUCCESS/FAILED

## Bun Best Practices (MUST FOLLOW)

### File I/O (see docs/bun-io.md)
```typescript
// ✅ DO: Use Bun.file() and Bun.write()
const data = await Bun.file("./path/file.json").json();
await Bun.write("./out/data.json", JSON.stringify(obj));

// ❌ DON'T: Use fs.readFileSync/writeFileSync
```

### Shell Commands (see docs/bun-shell.md)
```typescript
// ✅ DO: Use Bun shell $``
import { $ } from "bun";
await $`unzip -o ${zipPath} -d ${outDir}`;

// ❌ DON'T: Use execSync from child_process
```

### Directory Operations
```typescript
// Use node:fs/promises for directories (Bun-compatible)
import { mkdir, readdir, rm } from "node:fs/promises";
await mkdir("./out", { recursive: true });
const files = await readdir("./out");
```

## XML Parsing Strategy

The lineage script should:
1. Parse each XML file with `fast-xml-parser`
2. Save the JSON equivalent to `.shared/` (e.g., `player.xml` → `player.json`)
3. Downstream scripts read JSON directly - NO XML re-parsing

```typescript
import { XMLParser } from "fast-xml-parser";

const parser = new XMLParser({
  ignoreAttributes: false,
  attributeNamePrefix: "@_",
  // Handle xsi:nil="true" as null
  tagValueProcessor: (name, val) => val === "" ? null : val,
});

const xml = await Bun.file("./data.xml").text();
const json = parser.parse(xml);
await Bun.write("./data.json", JSON.stringify(json));
```

## Database Patterns

```typescript
import { SQL } from "bun";

const sql = new SQL({ url: Bun.env.POSTGRES_URL!, prepare: false });

// Upsert with conflict handling
await sql`
  INSERT INTO pcms.people ${sql(rows)}
  ON CONFLICT (person_id) DO UPDATE SET
    first_name = EXCLUDED.first_name,
    updated_at = EXCLUDED.updated_at
`;
```

## Common Pitfalls

1. **Don't use execSync** - Use `$` from Bun shell
2. **Don't use fs.readFileSync** - Use `Bun.file().text()` or `.json()`
3. **Don't re-parse XML in each step** - Parse once in lineage, read JSON after
4. **Don't forget hash-based dedup** - Use `source_hash` column for change detection
5. **Windmill paths** - Utils imported as `f/ralph/utils.ts` on Windmill, local path differs

## Schema Reference

See `new_pcms_schema.flow/*.pg.sql` for table definitions. Key tables:
- `pcms.pcms_lineage` - Import run tracking
- `pcms.people` - Players/coaches (PK: person_id)
- `pcms.contracts` - Contracts (PK: contract_id)
- `pcms.salaries` - Salary details (PK: contract_id + version_number + salary_year)

## Testing Locally

```bash
# Set required env vars
export POSTGRES_URL="postgres://user:pass@host:5432/db"

# Run a specific step
bun run import_pcms_data.flow/lineage_management_*.ts

# Or with dry_run
bun -e "import { main } from './import_pcms_data.flow/lineage_management_(s3_&_state_tracking).inline_script.ts'; main(true)"
```
