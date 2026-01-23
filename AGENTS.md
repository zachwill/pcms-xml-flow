# PCMS XML Flow (Windmill) — Agent Handoff

Imports **NBA PCMS XML → Postgres**. **Python only**.

If you are working on **Sean-style tooling** (Salary Book / Team Master / Trade Machine), start with:

- `TODO.md` (roadmap + what we’re building next)
- `SEAN.md` (current state + roadmap; reference specs are directional)
- `SALARY_BOOK.md` (how to interpret contracts/salaries; canonical table)
- `queries/AGENTS.md` (tool/query handoff)
- `SCHEMA.md` (authoritative schema/column names)

---

## Architecture (flow steps)

**Step A**: `pcms_xml_to_json` — S3 ZIP → XML → **clean JSON** in `shared/pcms/nba_pcms_full_extract/`

**Steps B–G**: read JSON → upsert to `pcms.*` tables

Key principle: **clean data once in Step A**. Import scripts should be deterministic: read JSON, normalize lightly, upsert.

---

## Project structure

```
import_pcms_data.flow/
  pcms_xml_to_json.inline_script.py    # A: XML → JSON
  lookups.inline_script.py             # B
  people.inline_script.py              # C
  contracts.inline_script.py           # D
  transactions.inline_script.py        # E
  league_config.inline_script.py       # F
  team_financials.inline_script.py     # G

shared/pcms/nba_pcms_full_extract/     # cleaned JSON outputs
migrations/                            # schema + cache tables/functions
scripts/
  xml-to-json.py                       # local XML→JSON (mirrors Step A)
  test-import.py                       # local runner (dry-run by default)
SCHEMA.md                              # schema reference
```

---

## Running imports locally

Always use `uv run`.

```bash
# dry-run is default (NO DB writes)
uv run scripts/test-import.py transactions --dry-run

# commit to DB
uv run scripts/test-import.py transactions --write

# run everything
uv run scripts/test-import.py all --write
```

---

## Debugging checklist (when data is missing / NULL)

1) **Confirm DB state**
```bash
psql "$POSTGRES_URL" -c "SELECT COUNT(*), COUNT(some_column) FROM pcms.some_table;"
psql "$POSTGRES_URL" -c "SELECT * FROM pcms.some_table LIMIT 3;"
```

2) **Find the script + JSON input**
```bash
grep -n "pcms.some_table" import_pcms_data.flow/*.py
grep -n "\.json" import_pcms_data.flow/some.inline_script.py | head
```

3) **Inspect JSON structure (use jq)**
```bash
jq 'type' shared/pcms/nba_pcms_full_extract/something.json
jq '.[0]' shared/pcms/nba_pcms_full_extract/something.json
jq '.. | .some_field? // empty' shared/pcms/nba_pcms_full_extract/something.json | head
```

4) **Fix pattern**: if the field lives elsewhere, build an enrichment lookup and merge during import.

5) **Re-test**
```bash
rm -rf import_pcms_data.flow/__pycache__
uv run scripts/test-import.py <step> --dry-run
uv run scripts/test-import.py <step> --write
```

---

## Common gotchas

- JSON keys can contain hyphens → use `data["hyphen-key"]`.
- Data may live in a different JSON file/branch → build enrichment lookups.
- Some schema columns may not exist in source → verify in JSON before chasing.
- Pycache can mask changes → `rm -rf import_pcms_data.flow/__pycache__`.
- You probably forgot `--write` → dry-run is default.

### Postgres regex gotcha (important)

When writing `LANGUAGE sql` functions using `$$ ... $$` bodies, **backslashes are literal**.
That means regex escapes like `\s`, `\b`, `\d` should generally be written as **single-backslash**
(`\s`, `\b`, `\d`) *inside the function body*, not double-escaped.

Symptoms when you get this wrong:
- regex `~* '^to\\s+'` appears to work in some ad-hoc contexts, but inside the function all matches fail
- CASE expressions fall through and everything becomes `'OTHER'`
- `regexp_matches()` extraction returns empty arrays unexpectedly

Fix:
- Prefer `~* '^to\s+'` (single backslash) inside `$$`-quoted SQL function bodies.
- Validate patterns with a tiny `SELECT` inside psql before baking into a migration.

---

## Tooling caches: source-of-truth hierarchy (Team Master / Trade tools)

When building Sean-style tooling, distinguish **"what exists"** from **"what counts"**.

### What counts (authoritative cap sheet totals)
- **`pcms.team_budget_snapshots`** is the canonical source for team-year amounts that actually count toward:
  - cap (`cap_amount`)
  - tax (`tax_amount`)
  - apron (`apron_amount`)
  - MTS (`mts_amount`)
- This is the source for `pcms.team_salary_warehouse`.

### Detail tables (often include "phantom" rows)
Some tables represent a superset of possibilities (rights/holds/history) and may include rows that *do not currently count*.

- **`pcms.non_contract_amounts`** (cap holds / rights) can include holds for a team even if the team renounced them or the player signed elsewhere.
  - Example: a player may appear as a cap hold for Team A, while `salary_book_warehouse` shows they signed with Team B.
  - For tool correctness, `pcms.cap_holds_warehouse` is filtered to **only rows that appear in** `team_budget_snapshots` FA buckets.

- **`pcms.transaction_waiver_amounts`** (waiver/dead money detail) should be treated as drilldown detail.
  - For our ingests, `transaction_waiver_amounts.team_code` can be NULL; resolve via `pcms.teams` using `team_id`.

### Warehouse tables (tool-facing caches)
- Player cache: `pcms.salary_book_warehouse`
- Team totals cache: `pcms.team_salary_warehouse`
- Exceptions cache: `pcms.exceptions_warehouse`
- Dead money drilldown: `pcms.dead_money_warehouse`
- Cap holds drilldown: `pcms.cap_holds_warehouse`

Rule of thumb: if you’re showing tool output, prefer a `*_warehouse` table first; if you need detail, join a detail table but scope it to what `team_budget_snapshots` says counts.

---

## Windmill notes

`flow.yaml` uses `same_worker: true`, so all steps share the `./shared/` directory.
