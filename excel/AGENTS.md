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

## Architecture (code-generated workbook)

We generate the workbook from scratch using Python (XlsxWriter):

- Create all **UI sheets** (cockpit, roster grid, audit, etc.).
- Create hidden/locked **`DATA_*` sheets** as Excel Tables (`tbl_*`) per the data contract.
- Define **named ranges** for cockpit “command bar” inputs (team/year/as-of/mode/etc.).
- Apply **formats**, **data validation** (dropdowns), **conditional formatting** (alerts), and **protection** (safe editing zones).
- Write `META` fields so every workbook is reproducible (timestamp, base-year, as-of date, exporter git sha, validation status).

Implementation should be split across multiple Python files (not one giant script) so autonomous agents can work safely.

## UI conventions (reuse existing decisions from `web/`)

We already made a bunch of high-signal UI decisions in the web Salary Book.

When implementing **Excel UI formatting** (colors, labels, badges, warnings), prefer to *reuse* those conventions instead of inventing new ones.

Good places to look (search these files first):

- `web/src/features/SalaryBook/components/MainCanvas/PlayerRow.tsx`
  - shows `MINIMUM` under salary for min contracts
  - salary cell tinting + tooltips for options/guarantees/trade restrictions

- `web/src/features/SalaryBook/components/MainCanvas/playerRowHelpers.ts`
  - `% of cap` formatting + percentile “block” indicator logic

- `web/src/features/SalaryBook/components/MainCanvas/badges/*`
  - `OptionBadge.tsx` (PO/TO/ETO labels + colors)
  - `GuaranteeBadge.tsx` (GTD/PRT/NG colors)
  - `ConsentBadge.tsx` (Consent badge styling)

- `web/src/features/SalaryBook/components/RightPanel/PlayerDetail/TradeRestrictions.tsx`
  - color semantics for No-Trade / Consent / Trade Kicker / Poison Pill / Pre-consented

If we introduce new UI semantics in Excel, record them back into `reference/blueprints/` so the conventions stay canonical.

## Common env vars

- `POSTGRES_URL` — required to extract from the DB

## Local workflow (target)

```bash
# Build a workbook snapshot into shared/
uv run excel/export_capbook.py \
  --out shared/capbook.xlsx \
  --base-year 2025 \
  --as-of 2026-01-31
```

(Exact filenames/CLI may evolve; keep it consistent with the Blueprints + data contract.)
