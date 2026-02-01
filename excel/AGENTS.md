# AGENTS.md — `excel/`

This folder is for the **next-generation Sean-style Excel cap workbook** build.

The goal is a **single, self-contained `.xlsx` workbook** (portable/offline) generated from Postgres (`pcms.*`).

**Design choice (important):** the workbook is a **build artifact generated from code** (Python + XlsxWriter). We do **not** rely on a hand-authored Excel template as a source of truth.

## Canonical design reference

Start with the Blueprints:

- `reference/blueprints/README.md`
- `reference/blueprints/mental-models-and-design-principles.md`
- `reference/blueprints/excel-cap-book-blueprint.md`
- `reference/blueprints/excel-workbook-data-refresh-blueprint.md`
- `reference/blueprints/excel-workbook-data-contract.md`

## Key constraints (non-negotiable)

- **Trust is the product:** headline totals must reconcile to the authoritative counting ledger (`pcms.team_budget_snapshots` → `pcms.team_salary_warehouse`).
- **No external workbook links:** avoid Sean-style `[2]...` cross-workbook refs.
- **No live DB dependency inside Excel by default:** the workbook should open and function offline.
- **Explicit policies:** any generated/fill rows must be visible + toggleable.
- **Explainability:** every headline number needs a contributing-rows drilldown path.

---

## Excel version requirement

**This workbook requires Microsoft Excel 365 or Excel 2021 (or later).**

The workbook uses modern Excel features including:
- **Dynamic arrays**: `FILTER`, `SORTBY`, `UNIQUE`, `TAKE`, `CHOOSECOLS`
- **XLOOKUP**: replaces legacy `INDEX/MATCH` patterns

These features are **not available** in:
- Excel 2019 or earlier
- Excel Online (limited support)
- Google Sheets

If you open the workbook in an unsupported version, formulas may show `#NAME?` errors or fail to spill correctly.

---

## XlsxWriter formula basics

XlsxWriter does not calculate formulas — it writes them to the file and Excel computes on open.

### Choosing the right write method

| Method | Use for | Example |
|--------|---------|---------|
| `write_formula()` | Single-cell formulas | `=SUM(A1:A10)`, `=VLOOKUP(...)` |
| `write_dynamic_array_formula()` | Formulas that spill (return arrays) | `=FILTER(...)`, `=UNIQUE(...)`, `=SORT(...)` |
| `write_array_formula()` | Legacy CSE arrays (Ctrl+Shift+Enter) | Rarely needed with Excel 365 |

**Rule of thumb:** If the formula uses `FILTER`, `UNIQUE`, `SORT`, `SORTBY`, `SEQUENCE`, `RANDARRAY`, or similar dynamic array functions, use `write_dynamic_array_formula()`.

### Spill range references (`#` operator)

Excel uses `F2#` to reference a spill range. XlsxWriter requires `ANCHORARRAY()` instead:

```python
# Excel UI shows: =COUNTA(F2#)
# XlsxWriter needs:
worksheet.write_formula("J2", "=COUNTA(ANCHORARRAY(F2))")
```

### Locale rules (non-negotiable)

Excel stores formulas in US English format regardless of user locale:

```python
# ✅ CORRECT - English function names, comma separators
worksheet.write_formula("A1", "=SUM(1, 2, 3)")

# ❌ WRONG - localized function name
worksheet.write_formula("A1", "=SOMME(1, 2, 3)")

# ❌ WRONG - semicolon separators (European locale)
worksheet.write_formula("A1", "=SUM(1; 2; 3)")
```

### Future functions (`_xlfn.` prefix)

Functions added after Excel 2010 require an `_xlfn.` prefix in the file format. Enable automatic prefixing:

```python
workbook = xlsxwriter.Workbook("output.xlsx", {"use_future_functions": True})
```

With this option, you can write `=XLOOKUP(...)` and XlsxWriter converts it to `=_xlfn._xlws.XLOOKUP(...)`.

### Debugging formula errors

If formulas show `#NAME?` or trigger repair dialogs:

1. Paste the formula into Excel directly to validate syntax
2. Check function names are English
3. Check separators are commas (not semicolons)
4. Check `_xlfn.` / `_xlpm.` prefixes for newer functions
5. If Excel shows unexpected `@` symbols, you probably need `write_dynamic_array_formula()`

---

## ⚠️ CRITICAL: LET and LAMBDA require `_xlpm.` prefix on variable names

**LET and LAMBDA variable/parameter names must be prefixed with `_xlpm.`**

XlsxWriter generates `_xlfn.LET` / `_xlfn.LAMBDA`, but the variable names also need the `_xlpm.` prefix or Mac Excel will trigger a repair dialog.

### Correct usage

```python
# ✅ CORRECT - variable names have _xlpm. prefix
worksheet.write_formula("A1", "=LET(_xlpm.x,B1,_xlpm.y,C1,_xlpm.x+_xlpm.y)")

# ❌ WRONG - will cause repair dialog on Mac Excel
worksheet.write_formula("A1", "=LET(x,B1,y,C1,x+y)")
```

### Pattern for converting existing formulas

| Before | After |
|--------|-------|
| `=LET(a,A1,b,B1,a+b)` | `=LET(_xlpm.a,A1,_xlpm.b,B1,_xlpm.a+_xlpm.b)` |
| `=LET(mask,condition,SUM(FILTER(col,mask)))` | `=LET(_xlpm.mask,condition,SUM(FILTER(col,_xlpm.mask)))` |
| `=LAMBDA(x,x*2)(5)` | `=LAMBDA(_xlpm.x,_xlpm.x*2)(5)` |

### What works without special handling

These functions work correctly with just `use_future_functions: True`:
- `FILTER`, `SORT`, `SORTBY`, `UNIQUE`, `TAKE`, `DROP` (use `_xlfn._xlws.` prefix)
- `XLOOKUP`, `XMATCH` (use `_xlfn._xlws.` prefix)  
- `CHOOSE`, `IF`, `IFS`, `IFERROR`, `IFNA` (no special prefix needed)
- `SUMIFS`, `COUNTIFS`, `SUMPRODUCT` (no special prefix needed)

### Conditional formatting limitations

**Avoid table references in conditional formatting formulas.** 

CF formulas like `=SUM(tbl_data[column])>0` cause Excel repair dialogs. Use cell references instead, or reference a helper cell that contains the table calculation.

### See also

For detailed tracking of formula fixes, see `.ralph/EXCEL.md`.

---

## CLI usage

The main entrypoint is `excel/export_capbook.py`.

```bash
# Build a workbook snapshot into shared/
uv run excel/export_capbook.py \
  --out shared/capbook.xlsx \
  --base-year 2025 \
  --as-of 2026-01-31

# Use 'today' as the as-of date
uv run excel/export_capbook.py \
  --out shared/capbook.xlsx \
  --base-year 2025 \
  --as-of today

# Skip SQL assertions (for debugging/testing)
uv run excel/export_capbook.py \
  --out shared/capbook.xlsx \
  --base-year 2025 \
  --as-of today \
  --skip-assertions

# Full help
uv run excel/export_capbook.py --help
```

### Required environment

- `POSTGRES_URL` — connection string for the Postgres database with `pcms.*` schema

### Output

- A single `.xlsx` file at the specified `--out` path
- Includes UI sheets + hidden `DATA_*` sheets with embedded Excel Tables
- `META` sheet records refresh timestamp, base year, as-of date, git SHA, validation status

---

## Datasets (DATA_* sheets)

The workbook embeds these datasets from Postgres, per the data contract (`reference/blueprints/excel-workbook-data-contract.md`).

**Data Contract Version:** `v2-2026-01-31`

| Excel Sheet | Excel Table | Postgres Source | Purpose |
|---|---|---|---|
| `DATA_system_values` | `tbl_system_values` | `pcms.league_system_values` | Cap/tax/apron thresholds, exception amounts, salary limits |
| `DATA_tax_rates` | `tbl_tax_rates` | `pcms.league_tax_rates` | Luxury tax brackets (repeater + non-repeater) |
| `DATA_rookie_scale` | `tbl_rookie_scale` | `pcms.rookie_scale_amounts` | Rookie scale by pick number (years 1-4) |
| `DATA_minimum_scale` | `tbl_minimum_scale` | `pcms.league_salary_scales` | Minimum salary by years of service |
| `DATA_team_salary_warehouse` | `tbl_team_salary_warehouse` | `pcms.team_salary_warehouse` | **Authoritative team totals** (cap/tax/apron by bucket) |
| `DATA_salary_book_warehouse` | `tbl_salary_book_warehouse` | `pcms.salary_book_warehouse` | Wide salary book (relative-year columns: `cap_y0..cap_y5`) |
| `DATA_salary_book_yearly` | `tbl_salary_book_yearly` | `pcms.salary_book_yearly` | Tall salary book (one row per player/year) |
| `DATA_cap_holds_warehouse` | `tbl_cap_holds_warehouse` | `pcms.cap_holds_warehouse` | Cap holds/rights that count toward totals |
| `DATA_dead_money_warehouse` | `tbl_dead_money_warehouse` | `pcms.dead_money_warehouse` | Dead money (waived/terminated) that counts |
| `DATA_exceptions_warehouse` | `tbl_exceptions_warehouse` | `pcms.exceptions_warehouse` | TPE/MLE/BAE exception inventory |
| `DATA_draft_picks_warehouse` | `tbl_draft_picks_warehouse` | `pcms.draft_picks_warehouse` | Draft pick ownership + encumbrances |

### Dataset extraction logic

Each dataset has a dedicated extractor in `excel/capbook/extract.py`:
- `extract_system_values(base_year, league)`
- `extract_tax_rates(base_year, league)`
- `extract_rookie_scale(base_year, league)`
- `extract_minimum_scale(base_year, league)`
- `extract_team_salary_warehouse(base_year)`
- `extract_salary_book_warehouse(base_year, league)`
- `extract_salary_book_yearly(base_year, league)`
- `extract_cap_holds_warehouse(base_year)`
- `extract_dead_money_warehouse(base_year)`
- `extract_exceptions_warehouse(base_year)`
- `extract_draft_picks_warehouse(base_year)`

All extractors filter to `base_year` through `base_year + 5` (6-year horizon).

---

## UI sheets

The workbook includes these UI sheets (per `excel-cap-book-blueprint.md`):

| Sheet | Purpose |
|---|---|
| `HOME` | Workbook summary + navigation links |
| `META` | Build metadata (timestamp, git SHA, validation status) |
| `TEAM_COCKPIT` | Primary flight display: key readouts + alerts + quick drivers + plan comparison |
| `ROSTER_GRID` | Full roster/ledger view with reconciliation + EXISTS_ONLY section |
| `BUDGET_LEDGER` | Authoritative totals + plan deltas (journal + subsystem outputs) |
| `PLAN_MANAGER` | Scenario/plan definitions |
| `PLAN_JOURNAL` | Ordered action journal for scenario modeling + running-state panel |
| `TRADE_MACHINE` | Lane-based trade iteration (A/B/C/D) |
| `SIGNINGS_AND_EXCEPTIONS` | Signing inputs + exception inventory (live from DATA_exceptions_warehouse) |
| `WAIVE_BUYOUT_STRETCH` | Dead money modeling inputs |
| `ASSETS` | Exception/TPE + draft pick inventory |
| `AUDIT_AND_RECONCILE` | Totals reconciliation + assumptions display |
| `RULES_REFERENCE` | Quick reference tables (tax rates, minimums, rookie scale, matching tiers) |

### TEAM_COCKPIT features

The `TEAM_COCKPIT` sheet includes:

1. **Command Bar** (editable) — the workbook's operating context:
   - Context selectors: Team, Year, As-Of, Mode
   - Policy toggles: RosterFillTarget, RosterFillType, ShowExistsOnlyRows
   - Plan selectors: ActivePlan, ComparePlanA/B/C/D

2. **Validation Banner** — shows PASS/FAIL status from META

3. **Alert Stack** — formula-driven alerts:
   - Validation failed warning
   - Reconciliation delta (mode-aware)
   - Roster fill active notification
   - EXISTS_ONLY section info

4. **Primary Readouts** — key cap metrics from tbl_team_salary_warehouse:
   - Cap/Tax/Apron positions
   - Roster count + two-way count
   - Repeater status, Cap/Tax totals
   - Two-way informational readouts

5. **Minimum Contracts** — count + total for min-contract players
   - Uses Excel 365 dynamic arrays: `FILTER + SUM/ROWS`
   - Count uses `ROWS(FILTER(...))` instead of legacy COUNTIFS
   - Total uses `SUM(FILTER(...))` instead of legacy SUMPRODUCT

6. **Plan Comparison Panel** — shows ComparePlan A/B/C/D deltas:
   - Uses Excel 365 dynamic arrays: `XLOOKUP + FILTER + SUM/ROWS`
   - Resolves plan_name → plan_id via `XLOOKUP` (replaces INDEX/MATCH)
   - Delta uses `SUM(FILTER(...))` instead of legacy SUMPRODUCT
   - Action count uses `ROWS(FILTER(...))` instead of legacy SUMPRODUCT
   - Filter rules: `(plan_id = resolved OR "") AND (salary_year = SelectedYear OR "") AND enabled = "Yes"`
   - Warns if compare plan is blank or equals Baseline
   - Links to PLAN_JOURNAL for details
   - Positive deltas (cost increase) in red, negative (savings) in green

7. **Quick Drivers Panel** (right side) — top cap hits, dead money, holds
   - Uses Excel 365 dynamic arrays: `FILTER + SORTBY + TAKE`
   - Single spilling formula per column (replaces per-row AGGREGATE/MATCH)
   - Mode-aware sorting (respects SelectedMode: Cap/Tax/Apron)

### ROSTER_GRID sections

The `ROSTER_GRID` sheet includes these sections:

1. **ROSTER (Active Contracts)** — bucket = ROST, Ct$=Y, CtR=Y
2. **TWO-WAY CONTRACTS** — bucket = 2WAY, Ct$=Y, CtR=N
3. **CAP HOLDS (Free Agent Rights)** — bucket = FA, Ct$=Y, CtR=N
4. **DEAD MONEY (Terminated Contracts)** — bucket = TERM, Ct$=Y, CtR=N
5. **GENERATED (Roster Fill Slots)** — bucket = GEN, Ct$=Y, CtR=Y
   - Generated when `RosterFillTarget` is 12, 14, or 15 (0 = off)
   - Fill amounts from `RosterFillType`: "Rookie Min" / "Vet Min" / "Cheapest"
   - Displays as "Fill Slot #N (type)" rows with gold/amber styling
   - Policy assumptions — included in totals but NOT in reconciliation checks
6. **EXISTS_ONLY (Future-Year Contracts)** — bucket = EXISTS, Ct$=N, CtR=N
   - Shows players with $0 in SelectedYear but non-zero in future years
   - Controlled by `ShowExistsOnlyRows` toggle ("Yes" to show, "No" to hide)
   - For analyst reference only — excluded from totals
7. **RECONCILIATION** — proves grid sums match warehouse totals

### BUDGET_LEDGER features

The `BUDGET_LEDGER` sheet includes:

1. **Snapshot Totals** — authoritative totals from `tbl_team_salary_warehouse`:
   - Cap/Tax/Apron totals by bucket (ROST, FA, TERM, 2WAY)
   - System thresholds for context (Cap, Tax Level, Aprons)

2. **Plan Deltas** — aggregated from two sources:
   - **Journal Entries (`tbl_plan_journal`)**: manual actions by action type
   - **Subsystem Outputs (`tbl_subsystem_outputs`)**: auto-linked from Trade lanes A-D, Signings, Waive/Buyout
   - Both filtered by `ActivePlanId + SelectedYear`
   - Combined into **PLAN DELTA TOTAL**
   - Info banner shows when subsystem outputs are included

3. **Policy Deltas** — generated assumptions:
   - Fill rows (when RosterFillTarget > 0)
   - Amber styling indicates policy assumptions vs authoritative data

4. **Derived Totals** — `Snapshot + Plan + Policy = Derived`:
   - Room/Over analysis for Cap, Tax, Apron 1, Apron 2
   - Positive room = green, negative = red

5. **Verification** — confirms formulas are consistent with warehouse

### PLAN_JOURNAL features

The `PLAN_JOURNAL` sheet includes:

1. **Journal Table (`tbl_plan_journal`)** — ordered action journal with columns:
   - step, plan_id, enabled, salary_year, effective_date, action_type
   - target_player, target_team, notes
   - delta_cap, delta_tax, delta_apron (delta columns)
   - validation, source

2. **Running-State Panel** — positioned to the right of the journal table:
   - **Plan Summary Box**: Active Plan name, Selected Year, Enabled action count
   - **Total Deltas**: Aggregate cap/tax/apron deltas for ActivePlan + SelectedYear
   - Formulas use `FILTER` (dynamic arrays) to filter by `ActivePlanId + SelectedYear + enabled` (with blank salary_year treated as SelectedYear)

3. **Cumulative Running Totals** — step-by-step running totals aligned with journal rows:
   - Each row shows cumulative Δ Cap, Δ Tax, Δ Apron up to that step
   - Only includes rows matching ActivePlan + SelectedYear context

4. **Conditional Formatting** — grays out journal rows not matching current context:
   - Rows with plan_id ≠ ActivePlanId (unless blank)
   - Rows with salary_year ≠ SelectedYear (unless blank)
   - Helps analysts focus on the currently-active plan/year

5. **Subsystem Outputs Table (`tbl_subsystem_outputs`)** — aggregates deltas from subsystem sheets:
   - Fixed rows for: Trade Lane A, B, C, D, Signings, Waive/Buyout
   - **Columns**:
     - `include_in_plan`: Yes/No toggle to include in plan calculations
     - `plan_id`: defaults to ActivePlanId (formula)
     - `salary_year`: defaults to SelectedYear (formula)
     - `delta_cap`, `delta_tax`, `delta_apron`: linked to subsystem outputs
     - `source`: fixed label per row
     - `notes`: freeform input
   - **Trade lanes**: manual delta entry (copy from TRADE_MACHINE Journal Output)
   - **Signings/Waive**: auto-linked via SUBTOTAL formulas from input tables
   - **Included Totals**: shows sum of deltas where include_in_plan="Yes"
   - ⚠️ **WARNING**: Do NOT also copy these into tbl_plan_journal (double-counting!)
   - BUDGET_LEDGER sums from both tbl_plan_journal AND tbl_subsystem_outputs

### SIGNINGS_AND_EXCEPTIONS features

The `SIGNINGS_AND_EXCEPTIONS` sheet includes:

1. **Signings Input Table (`tbl_signings_input`)** — prospective signing entries:
   - player_name, signing_type, exception_used, years
   - year_1_salary through year_4_salary (amounts per contract year)
   - notes
   - **Formula-driven delta columns**: delta_cap, delta_tax, delta_apron
     - Automatically computed based on SelectedYear
     - year_1_salary = MetaBaseYear, year_2 = MetaBaseYear+1, etc.
     - Formula: `IFERROR(CHOOSE(SelectedYear-MetaBaseYear+1, year_1, year_2, year_3, year_4), 0)`

2. **Journal Output Block** — aggregated deltas for publishing to PLAN_JOURNAL:
   - Selected Year context (from command bar)
   - Signing count (non-blank rows)
   - Total Δ Cap, Δ Tax, Δ Apron for SelectedYear
   - Source label: "Signings (SIGNINGS_AND_EXCEPTIONS)"
   - Manual publish instructions (copy into PLAN_JOURNAL)

3. **Exception Inventory** — live FILTER from tbl_exceptions_warehouse:
   - Filtered by SelectedTeam
   - Shows salary_year, exception_type_name, original/remaining amounts, dates, status
   - Used for exception_used validation in signings table

4. **Exception Used Dropdown** — dynamic validation list for exception_used column:
   - Helper spill range creates labels from tbl_exceptions_warehouse for SelectedTeam
   - Filters to active (non-expired) exceptions only
   - Label format: "exception_type_name ($remaining)" or "TPE: player_name ($remaining)"
   - Named range `ExceptionUsedList` references the spill range
   - Data validation uses warning mode (allows non-list values with warning)

5. **Signing Type Validation** — dropdown with values:
   - Cap Room, MLE (Full), MLE (Taxpayer), MLE (Room), BAE, Minimum, TPE, Other

6. **Hard-Cap Trigger Notes** — inline reference for which signings trigger hard cap

### TRADE_MACHINE features

The `TRADE_MACHINE` sheet includes:

1. **Lane Layout** — 4 parallel lanes (A/B/C/D) for side-by-side trade comparison:
   - Each lane is independent with its own team selector
   - Color-coded headers: Blue (A), Purple (B), Green (C), Orange (D)

2. **Team Selector** — dropdown validated from warehouse:
   - Dynamic list from `tbl_team_salary_warehouse[team_code]` filtered by SelectedYear
   - Named range `TradeTeamList` (UNIQUE + SORT formula) for validation source
   - Named range `TradeLane{A|B|C|D}Team` for each lane's selected team

3. **Lane Status Summary** — shows team's cap position for SelectedYear:
   - **Cap/Tax/Apron Totals**: pulled from `tbl_team_salary_warehouse` via SUMIFS
   - **Room (Tax)**: room under tax level
   - **Room (Apron 1)**: room under first apron
   - **Is Taxpayer**: Yes/No based on `is_taxpayer` flag
   - **Repeater**: Yes/No based on `is_repeater_taxpayer` flag
   - **Apron Level**: lookup value from `apron_level_lk` (e.g., "BELOW_TAX", "FIRST_APRON")

4. **Outgoing/Incoming Slots** — 5 player slots per side:
   - Player name (manual text input)
   - Salary (manual money input)
   - SUM formula for Total Out / Total In

5. **Trade Matching Outputs** — formula-driven legality checks:
   - **Net Delta**: formula `Total In - Total Out`
   - **Max Incoming**: calculated using CBA salary matching rules:
     - For below-tax teams: `MAX(MIN(out×2+$250K, out+TPE_allowance), out×1.25+$250K)`
     - For first apron or above: `out + $100K` (no aggregation allowed)
     - TPE_allowance looked up from `tbl_system_values` for SelectedYear
   - **Legal?**: check `Total In <= Max Incoming` with ✓ LEGAL / ✗ OVER LIMIT status
   - **Matching Rule**: shows which tier applies (Low: 200%+$250K / Mid: 100%+TPE / High: 125%+$250K / Apron: 100%+$100K)
   - Conditional formatting: green for legal, red for over limit

6. **Journal Output Block** (per lane) — for publishing to PLAN_JOURNAL:
   - **Δ Cap / Δ Tax / Δ Apron**: net delta (Total In - Total Out) for SelectedYear
   - **Source**: label identifying the lane (e.g., "Trade Lane A")
   - Brief publish instructions with link to detailed instructions below

7. **Salary Matching Reference** — inline table with matching tiers:
   - Tier breakpoints derived from TPE_dollar_allowance (~$8M low, ~$33M high for 2025)
   - Formulas for each tier (200%+$250K, 100%+TPE, 125%+$250K)
   - Apron gate notes: first apron teams cannot aggregate players

8. **Journal Publish Instructions** — detailed workflow for copying trade deltas to PLAN_JOURNAL:
   - Step-by-step instructions for adding trade rows to journal
   - Notes about multi-team trades requiring one row per team

### WAIVE_BUYOUT_STRETCH features

The `WAIVE_BUYOUT_STRETCH` sheet includes:

1. **Waive/Buyout Input Table (`tbl_waive_input`)** — dead money scenario entries:
   - player_name, waive_date, years_remaining (input columns)
   - remaining_gtd, giveback (input amounts)
   - stretch (Yes/No toggle)
   - **Formula-driven computed columns**:
     - `net_owed = remaining_gtd - giveback`
     - `dead_year_1/2/3`: distribution based on stretch toggle
       - If stretch="No": all net_owed goes to dead_year_1
       - If stretch="Yes": divided across (2 × years_remaining + 1) years
     - `delta_cap`, `delta_tax`, `delta_apron`: picks dead_year matching SelectedYear
       - dead_year_1 = MetaBaseYear, dead_year_2 = MetaBaseYear+1, etc.
   - notes (freeform input)

2. **Journal Output Block** — aggregated deltas for publishing to PLAN_JOURNAL:
   - Selected Year context (from command bar)
   - Waive count (non-blank rows)
   - Total Δ Cap, Δ Tax, Δ Apron for SelectedYear
   - Source label: "Waive/Buyout (WAIVE_BUYOUT_STRETCH)"
   - Manual publish instructions (copy into PLAN_JOURNAL)

3. **Data Validation**:
   - Stretch toggle: Yes/No dropdown
   - Years remaining: integer 1-5 validation

4. **Stretch Provision Reference** — inline notes:
   - Formula: spread over (2 × years remaining + 1) seasons
   - Election window timing
   - Set-off rules when player signs elsewhere

5. **Formula Reference** — documents the computed column logic

---

## Architecture (code-generated workbook)

We generate the workbook from scratch using Python (XlsxWriter):

- Create all **UI sheets** (cockpit, roster grid, audit, etc.).
- Create hidden/locked **`DATA_*` sheets** as Excel Tables (`tbl_*`) per the data contract.
- Define **named ranges** for cockpit "command bar" inputs (team/year/as-of/mode/etc.).
- Apply **formats**, **data validation** (dropdowns), **conditional formatting** (alerts), and **protection** (safe editing zones).
- Write `META` fields so every workbook is reproducible (timestamp, base-year, as-of date, exporter git sha, validation status).

Implementation is split across multiple Python files:

```
excel/
├── export_capbook.py          # CLI entrypoint
└── capbook/
    ├── build.py               # Orchestration + sheet creation
    ├── db.py                  # Database connection + SQL assertions
    ├── extract.py             # Dataset extraction functions
    ├── reconcile.py           # Reconciliation logic
    ├── xlsx.py                # XlsxWriter helpers + format definitions
    └── sheets/
        ├── __init__.py
        ├── command_bar.py     # Shared command bar helper
        ├── cockpit.py         # TEAM_COCKPIT implementation
        ├── roster_grid.py     # ROSTER_GRID implementation
        ├── budget_ledger.py   # BUDGET_LEDGER implementation
        ├── plan.py            # PLAN_MANAGER + PLAN_JOURNAL
        ├── subsystems.py      # TRADE_MACHINE, SIGNINGS, WAIVE, ASSETS
        ├── audit.py           # AUDIT_AND_RECONCILE implementation
        ├── rules_reference.py # RULES_REFERENCE implementation
        ├── meta.py            # META sheet + named ranges
        ├── home.py            # HOME landing page implementation
        └── ui_stubs.py        # Stub writers for incomplete sheets
```

---

---

## UI conventions (reuse existing decisions from `web/`)

We already made a bunch of high-signal UI decisions in the web Salary Book.

When implementing **Excel UI formatting** (colors, labels, badges, warnings), prefer to *reuse* those conventions instead of inventing new ones.

Good places to look (search these files first):

- `web/src/features/SalaryBook/components/MainCanvas/PlayerRow.tsx`
  - shows `MINIMUM` under salary for min contracts
  - salary cell tinting + tooltips for options/guarantees/trade restrictions

- `web/src/features/SalaryBook/components/MainCanvas/playerRowHelpers.ts`
  - `% of cap` formatting + percentile "block" indicator logic

- `web/src/features/SalaryBook/components/MainCanvas/badges/*`
  - `OptionBadge.tsx` (PO/TO/ETO labels + colors)
  - `GuaranteeBadge.tsx` (GTD/PRT/NG colors)
  - `ConsentBadge.tsx` (Consent badge styling)

- `web/src/features/SalaryBook/components/RightPanel/PlayerDetail/TradeRestrictions.tsx`
  - color semantics for No-Trade / Consent / Trade Kicker / Poison Pill / Pre-consented

If we introduce new UI semantics in Excel, record them back into `reference/blueprints/` so the conventions stay canonical.

---

## Validation + reconciliation

The build process includes:

1. **SQL assertions** — runs `queries/sql/run_all.sql` before export (unless `--skip-assertions`)
2. **Reconciliation checks** — verifies `team_salary_warehouse` totals match bucket sums
3. **Fail-forward behavior** — on any failure, we still emit a workbook with `META.validation_status = FAILED`

The `AUDIT_AND_RECONCILE` sheet surfaces reconciliation deltas and policy assumptions.

---

## Common env vars

- `POSTGRES_URL` — required to extract from the DB
