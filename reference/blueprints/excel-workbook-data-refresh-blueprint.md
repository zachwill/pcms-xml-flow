# Excel Workbook Data Refresh Blueprint (DB → Sheets)

**Updated:** 2026-01-31

This blueprint describes *how* we’d populate a new Sean-style Excel cap workbook from Postgres in a way that is:

- **reproducible** (the workbook knows what snapshot it represents)
- **trustworthy** (totals reconcile to the authoritative ledger)
- **offline-friendly** (no brittle external workbook links)
- **fast** (warehouse-backed extracts, not raw joins)
- **operationally simple** (one command locally; one Windmill step in production)

This is intentionally **mechanics and design**, not code.

---

## 1) Output artifact(s)

### Preferred: single self-contained workbook
A single `.xlsx` (or `.xlsm` if we later want light macros) that includes:

- **UI sheets** (cockpit, roster grid, plan journal, trade machine, etc.)
- **hidden/locked `DATA_*` sheets** containing extracted tables
- a small **`META`** sheet recording:
  - refresh timestamp
  - source salary year range
  - as-of date used
  - data source identifier (DB name, schema version)
  - git commit hash (of exporter)
  - validation status + reconciliation deltas

**Why single-file matters:**
- avoids Sean’s current “external workbook ref” brittleness
- makes the workbook portable to analysts (email/Slack/Drive)
- ensures the cockpit always matches the data snapshot embedded inside

### Optional (future): split “data pack” + “UI workbook”
Two files:
- `capbook_data.xlsx` (tables only)
- `capbook_ui.xlsx` (UI + formulas referencing data pack)

This can speed up refresh (swap data file only), but reintroduces cross-workbook linkage risk.

Given the repo’s trust goals, **single-file is the default**.

---

## 2) Primary constraint: “what counts” must be authoritative

**Rule:** the workbook’s headline totals must come from the authoritative counting ledger.

In our Postgres model that’s:
- `pcms.team_budget_snapshots` (authoritative)
  - exposed tool-facing via `pcms.team_salary_warehouse`

The workbook can still show drilldowns (salary book rows, holds, dead money), but:
- those drilldowns must reconcile to the same bucket totals
- any “exists-only” artifacts must be labeled and must not silently affect totals

---

## 3) Data extraction strategy (what queries we run)

### Guiding principle: pull from warehouses, not raw tables
For Excel refreshes, prefer `pcms.*_warehouse` and stable views/functions.

This keeps refresh:
- fast
- consistent
- aligned to how the UI wants to display information

### Extract sets (minimum viable)
These are the datasets needed to power the blueprint workbook.

#### A) System / CBA constants
- `pcms.league_system_values`
  - cap, tax line, aprons, days_in_season, MLE/BAE, etc.
- `pcms.league_tax_rates`
- `pcms.rookie_scale_amounts`
- `pcms.league_salary_scales` (PCMS minimums; plus derived multi-year mins if needed)

Excel destination:
- `DATA_system_values` (table)
- `DATA_tax_rates` (table)
- `DATA_rookie_scale` (table)
- `DATA_minimum_scale` (table)

#### B) Team totals (the authoritative readouts)
- `pcms.team_salary_warehouse`
  - one row per team/year with cap/tax/apron totals, apron level, repeater flag, roster counts

Excel destination:
- `DATA_team_salary_warehouse`

**Note:** cockpit readouts should be driven from this dataset (or reconcile exactly to it).

#### C) Player salary book (roster rows)
- `pcms.salary_book_warehouse` (wide) for UI grids
- `pcms.salary_book_yearly` (tall) for calculations that are cleaner per-year

Excel destination:
- `DATA_salary_book_warehouse`
- `DATA_salary_book_yearly`

Design choice:
- UI roster grid can use the wide table
- scenario math / aggregations often want tall (player, year) rows

#### D) Holds / rights that count
- `pcms.cap_holds_warehouse` (already scoped to what counts in `team_budget_snapshots` buckets)

Excel destination:
- `DATA_cap_holds_warehouse`

#### E) Dead money that counts
- `pcms.dead_money_warehouse`

Excel destination:
- `DATA_dead_money_warehouse`

#### F) Exceptions / TPE inventory
- `pcms.exceptions_warehouse`

Excel destination:
- `DATA_exceptions_warehouse`

#### G) Draft assets
- `pcms.draft_picks_warehouse` (and/or `pcms.draft_assets_warehouse` depending on UI needs)

Excel destination:
- `DATA_draft_picks_warehouse`

---

## 4) Excel data sheet design (how the tables live in the workbook)

### A) One dataset per `DATA_*` sheet
Each data sheet contains exactly one Excel Table (ListObject).

- Sheet name: `DATA_salary_book_warehouse`
- Table name: `tbl_salary_book_warehouse`

This makes formulas predictable and prevents “mystery named ranges.”

### B) Stable keys everywhere
Every dataset should include stable identifiers:
- `player_id`
- `team_code`
- `salary_year`
- `contract_id` / `version_number` (when relevant)
- `team_exception_id` (exceptions)

UI and scenario inputs should reference IDs (not player names) to avoid collisions.

### C) Columns are explicit, not inferred
For each extracted table we define:
- required columns
- types (int/text/date)
- nullability expectations

The exporter is responsible for producing those columns consistently.

### D) Hidden + protected
`DATA_*` sheets should be:
- hidden
- protected

Analysts should not edit them manually.

---

## 5) The refresh process (what happens when we “build the workbook”)

### Step 0 — Preconditions
- PCMS import completed
- warehouse refresh functions executed (already done in Windmill flow step H)

### Step 1 — Run validations (fail fast)
Before generating the workbook, run:

- SQL assertion suite:
  - `psql "$POSTGRES_URL" -v ON_ERROR_STOP=1 -f queries/sql/run_all.sql`

- Optional: export-time reconciliation checks
  - e.g. for each team/year, verify:
    - `team_salary_warehouse.cap_total` equals sum of drilldowns that should count

If validations fail:
- do not produce a “clean” workbook
- either fail the job, or produce a workbook with a loud `META.validation_status = FAILED` plus deltas

### Step 2 — Extract datasets
Run fixed queries (or call stable SQL views/functions) to fetch all datasets into memory.

Key design choice:
- **Do not** embed ad-hoc SQL in the Excel workbook.
- The exporter owns the SQL so the workbook stays portable.

### Step 3 — Generate the workbook (code-first)
Generate the workbook from scratch (Python + XlsxWriter) so it is deterministic and reproducible.

Generator responsibilities:
- create all UI sheets + `DATA_*` sheets
- write Excel Tables (`tbl_*`) for each dataset (stable table names)
- define named ranges for cockpit “command bar” inputs (team/year/as-of/mode/etc.)
- apply formats, data validation, conditional formatting, and protection rules
- write `META` fields (`refreshed_at`, `base_year`, `as_of_date`, exporter git sha, validation status)

Behavior:
- treat the workbook as a build artifact; do not rely on manual Excel edits as a source of truth

### Step 4 — Save artifact + distribution
- Save to a known path (`shared/` locally; Windmill workspace in prod)
- Optional distribution:
  - upload to S3/Drive
  - post a Slack link

---

## 6) Two execution modes (same logic, different runner)

### A) Local developer / analyst build (uv)
Target:
- reproducible local workbook builds

Conceptual CLI (example):
- `uv run excel/export_capbook.py --out shared/capbook.xlsx --base-year 2025 --as-of 2026-01-31`

Inputs:
- `POSTGRES_URL`

Outputs:
- `shared/capbook.xlsx`

### B) Windmill flow step
Target:
- automatically produce a new workbook after every PCMS refresh

Flow shape:
1. Import PCMS XML
2. Refresh warehouses (existing step)
3. **Build Excel cap workbook** (new step)
4. Publish artifact (Slack/Drive)

Same environment variables:
- `POSTGRES_URL`

---

## 7) Where “as-of date” lives

We need to decide whether the as-of date is:

1) **purely an Excel UI parameter** used for proration math inside formulas
2) **part of the extract**, where date-sensitive primitives are precomputed in SQL

Recommended hybrid:
- keep baseline datasets mostly date-agnostic (warehouses are year-based)
- precompute only the places where date logic is subtle or rule-heavy (buyout primitives, days remaining)

The `META` sheet must always record the as-of date so scenarios are reproducible.

---

## 8) Data health + audit integration

The workbook must make it hard to ship incorrect numbers.

### Minimum:
- `META.validation_status` (PASS/FAIL)
- `META.reconciliation_delta_cap/tax/apron` (0 if clean)
- a visible alert in `TEAM_COCKPIT` if status is not PASS

### Better:
- an `AUDIT_AND_RECONCILE` sheet that surfaces:
  - which dataset mismatch caused delta
  - which rows contributed

---

## 9) Practical constraints / gotchas

- Excel performance: prefer tables + XLOOKUP/INDEX over volatile OFFSET/INDIRECT.
- Row limits: we’re safe for NBA datasets, but avoid dumping raw salary history if not needed.
- Names are not keys: always include IDs.
- Avoid cross-workbook links and live DB connections as the default.
- Protect inputs vs outputs to prevent accidental formula damage.

---

## 10) Follow-on blueprint (optional but likely)

Once we agree on refresh mechanics, the next blueprint should define a *data contract*:

- For each `tbl_*`:
  - required columns
  - types
  - example rows
  - which UI sheets depend on it
  - reconciliation expectations

That becomes the durable interface between DB and workbook.
