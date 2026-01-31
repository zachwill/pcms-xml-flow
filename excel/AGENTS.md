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
| `TEAM_COCKPIT` | Primary flight display: key readouts + alerts + quick drivers |
| `ROSTER_GRID` | Full roster/ledger view with reconciliation + EXISTS_ONLY section |
| `BUDGET_LEDGER` | Authoritative totals + plan deltas |
| `PLAN_MANAGER` | Scenario/plan definitions |
| `PLAN_JOURNAL` | Ordered action journal for scenario modeling |
| `TRADE_MACHINE` | Lane-based trade iteration (A/B/C/D) |
| `SIGNINGS_AND_EXCEPTIONS` | Signing inputs + exception tracking |
| `WAIVE_BUYOUT_STRETCH` | Dead money modeling inputs |
| `ASSETS` | Exception/TPE + draft pick inventory |
| `AUDIT_AND_RECONCILE` | Totals reconciliation + assumptions display |
| `RULES_REFERENCE` | Quick reference tables (tax rates, minimums, rookie scale, matching tiers) |

### ROSTER_GRID sections

The `ROSTER_GRID` sheet includes these sections:

1. **ROSTER (Active Contracts)** — bucket = ROST, Ct$=Y, CtR=Y
2. **TWO-WAY CONTRACTS** — bucket = 2WAY, Ct$=Y, CtR=N
3. **CAP HOLDS (Free Agent Rights)** — bucket = FA, Ct$=Y, CtR=N
4. **DEAD MONEY (Terminated Contracts)** — bucket = TERM, Ct$=Y, CtR=N
5. **EXISTS_ONLY (Future-Year Contracts)** — bucket = EXISTS, Ct$=N, CtR=N
   - Shows players with $0 in SelectedYear but non-zero in future years
   - Controlled by `ShowExistsOnlyRows` toggle ("Yes" to show, "No" to hide)
   - For analyst reference only — excluded from totals
6. **RECONCILIATION** — proves grid sums match warehouse totals

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
        └── ui_stubs.py        # HOME + stub writers
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
