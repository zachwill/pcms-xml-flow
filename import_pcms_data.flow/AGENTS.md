# AGENTS.md — `import_pcms_data.flow/`

This directory is the **Windmill flow** that imports **NBA PCMS XML → Postgres (`pcms` schema)**.

If you're debugging a PCMS import issue, you’ll usually bounce between:
- `import_pcms_data.flow/` (the Windmill scripts)
- `scripts/` (local runners)
- `migrations/` (tables/functions/warehouses)
- `queries/` (assertion-style SQL tests)

---

## Flow overview (`flow.yaml`)

All steps are `rawscript` Python inline scripts.

### A) `pcms_xml_to_json.inline_script.py`
- Downloads an S3 ZIP (via `wmill.load_s3_file()`)
- Extracts XML into `./shared/pcms/`
- Parses XML → **clean JSON** (snake_case keys, `xsi:nil` → `null`)
- Writes JSON alongside the extracted XML directory (usually `./shared/pcms/nba_pcms_full_extract/`)

### B–G) JSON → upsert `pcms.*`
These steps should be **deterministic**:
- read clean JSON
- minimal normalization
- `INSERT ... ON CONFLICT ...` upserts

Files (typical):
- `lookups.json`
- `players.json`
- `contracts.json`
- `transactions.json`
- `trades.json`
- `ledger.json`
- `team_exceptions.json`
- `team_budgets.json`
- `non_contract_amounts.json`
- `transaction_waiver_amounts.json`
- `yearly_system_values.json`
- `rookie_scale_amounts.json`
- `yearly_salary_scales.json`
- `tax_rates.json`, `tax_teams.json`
- `cap_projections.json`
- `two_way.json`, `two_way_utility.json`

### H) `refresh_caches.inline_script.py`
Runs after base table imports and calls the DB refresh functions:
- `pcms.refresh_salary_book_warehouse()`
- `pcms.refresh_team_salary_warehouse()`
- `pcms.refresh_exceptions_warehouse()`
- `pcms.refresh_dead_money_warehouse()`
- `pcms.refresh_cap_holds_warehouse()`
- `pcms.refresh_player_rights_warehouse()`
- `pcms.refresh_draft_pick_trade_claims_warehouse()`
- `pcms.refresh_draft_picks_warehouse()`
- `pcms.refresh_draft_assets_warehouse()`

### I) `export_capbook.inline_script.py`
Runs after warehouses are refreshed:
- Builds a self-contained Excel cap workbook (`./shared/capbook.xlsx`)
- Uses `base_year` from flow input (default: current year)
- Uses today's date as `as_of`
- Validates against the data contract
- See `excel/AGENTS.md` for workbook details

**Windmill note:** `flow.yaml` sets `same_worker: true`, so `./shared/` is shared across steps.

---

## Core project principle (important)

**Clean data once in Step A.**

If you find yourself writing “XML weirdness” handling in steps B–G, that’s usually a sign the fix belongs in:
- Step A (preferred) or
- a deterministic enrichment lookup (read JSON A + JSON B → merge)

---

## Running locally (PCMS)

### 1) Ensure you have a local extract
The local runner (`scripts/test-import.py`) expects clean JSON in:
- `shared/pcms/nba_pcms_full_extract/`

If you have the raw XML files locally, generate JSON with:

```bash
uv run scripts/xml-to-json.py \
  --xml-dir shared/pcms/nba_pcms_full_extract_xml \
  --out-dir shared/pcms/nba_pcms_full_extract
```

(See also `shared/AGENTS.md` for scratch directory notes.)

### 2) Run a step
```bash
# default is dry-run (no DB writes)
uv run scripts/test-import.py lookups

# commit to DB
uv run scripts/test-import.py contracts --write

# run everything
uv run scripts/test-import.py all --write
```

---

## Debugging checklist (missing / NULL data)

1) **Confirm DB state**
```bash
psql "$POSTGRES_URL" -c "SELECT COUNT(*), COUNT(some_column) FROM pcms.some_table;"
psql "$POSTGRES_URL" -c "SELECT * FROM pcms.some_table LIMIT 3;"
```

2) **Find the importer + its JSON inputs**
```bash
rg -n "pcms\.some_table" import_pcms_data.flow/*.py
rg -n "\.json" import_pcms_data.flow/some.inline_script.py
```

3) **Inspect JSON structure**
```bash
jq 'type' shared/pcms/nba_pcms_full_extract/something.json
jq '.[0]' shared/pcms/nba_pcms_full_extract/something.json
jq '.. | .some_field? // empty' shared/pcms/nba_pcms_full_extract/something.json | head
```

4) **Fix pattern**
- If the field is present in JSON → importer bug
- If the field is missing in JSON → Step A bug OR you’re looking in the wrong JSON file

5) **Clear pycache when changes “don’t take”**
```bash
rm -rf import_pcms_data.flow/__pycache__
```

---

## Gotchas

- JSON keys can contain hyphens → use `data["hyphen-key"]`.
- `extract_dir` is often passed as `./shared/pcms` and the scripts call `find_extract_dir()` to pick the first nested folder.
- Step A **deletes** `./shared/pcms/` before extracting.
- Some detail tables can have missing team codes (e.g., waiver amounts); resolve via `team_id → pcms.teams` when needed.
