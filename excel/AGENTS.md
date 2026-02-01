# AGENTS.md — `excel/`

Code-generated Excel workbook for NBA salary cap analysts.

---

## Current status

**DATA_ sheets:** ✅ Solid. Authoritative datasets embedded as Excel Tables.

**UI sheets:** 🚧 Rebuilding from scratch. First target: **PLAYGROUND** sheet.

---

## Next step: Build the PLAYGROUND sheet

Sean's "Playground" is the core working surface — a dense, reactive view where analysts:
- See team roster + cap position
- Model changes (trades, signings, waives) inline
- See deltas immediately without navigating

We're rebuilding this with:
- Modern Excel (dynamic arrays, XLOOKUP, LET, LAMBDA)
- Proper formatting (Aptos Narrow, alignment, subtle borders)
- Yellow input cells, reactive conditional formatting
- Code-generated consistency

See `reference/blueprints/excel-cap-book-blueprint.md` for design principles.

---

## Key references

| Doc | Purpose |
|-----|---------|
| `excel/XLSXWRITER.md` | XlsxWriter patterns, formula gotchas, recipes |
| `reference/blueprints/excel-cap-book-blueprint.md` | Design vision + principles |
| `reference/blueprints/mental-models-and-design-principles.md` | Foundational thinking |
| `reference/blueprints/data-contract.md` | DATA_ sheet specifications |
| `excel/UI.md` | **Authoritative** PLAYGROUND UI spec (do not shortcut) |
| `reference/blueprints/specs/playground.md` | Legacy notes (defer to `excel/UI.md`) |

---

## Architecture

```
excel/
├── AGENTS.md                    # This file
├── XLSXWRITER.md                # XlsxWriter patterns + recipes
├── export_capbook.py            # CLI entrypoint
└── capbook/
    ├── build.py                 # Orchestration
    ├── db.py                    # Database connection
    ├── extract.py               # Dataset extraction (solid ✅)
    ├── xlsx.py                  # XlsxWriter helpers + formats
    └── sheets/
        ├── __init__.py
        └── meta.py              # META sheet
```

UI sheets will be added to `excel/capbook/sheets/` as we build them.

---

## CLI usage

```bash
# Build workbook
uv run excel/export_capbook.py \
  --out shared/capbook.xlsx \
  --base-year 2025 \
  --as-of today

# Skip SQL assertions (faster iteration)
uv run excel/export_capbook.py \
  --out shared/capbook.xlsx \
  --base-year 2025 \
  --as-of today \
  --skip-assertions
```

Requires `POSTGRES_URL` environment variable.

---

## DATA_ sheets (solid ✅)

Embedded datasets from Postgres. Hidden + locked in final workbook.

| Sheet | Table | Source | Purpose |
|-------|-------|--------|---------|
| DATA_system_values | tbl_system_values | pcms.league_system_values | Cap/tax/apron thresholds |
| DATA_tax_rates | tbl_tax_rates | pcms.league_tax_rates | Luxury tax brackets |
| DATA_rookie_scale | tbl_rookie_scale | pcms.rookie_scale_amounts | Rookie scale by pick |
| DATA_minimum_scale | tbl_minimum_scale | pcms.league_salary_scales | Min salary by YOS |
| DATA_team_salary_warehouse | tbl_team_salary_warehouse | pcms.team_salary_warehouse | **Authoritative team totals** |
| DATA_salary_book_warehouse | tbl_salary_book_warehouse | pcms.salary_book_warehouse | Wide salary book |
| DATA_salary_book_yearly | tbl_salary_book_yearly | pcms.salary_book_yearly | Tall salary book |
| DATA_cap_holds_warehouse | tbl_cap_holds_warehouse | pcms.cap_holds_warehouse | Cap holds/rights |
| DATA_dead_money_warehouse | tbl_dead_money_warehouse | pcms.dead_money_warehouse | Dead money |
| DATA_exceptions_warehouse | tbl_exceptions_warehouse | pcms.exceptions_warehouse | Exception inventory |
| DATA_draft_picks_warehouse | tbl_draft_picks_warehouse | pcms.draft_picks_warehouse | Draft picks |

Extractors in `excel/capbook/extract.py`. All filter to 6-year horizon (base_year through base_year + 5).

---

## Constraints (non-negotiable)

- **Trust:** Totals reconcile to authoritative warehouse
- **Offline:** No live DB dependency — workbook works offline
- **Explicit:** Generated/assumption rows are visible and labeled
- **Modern Excel:** Requires Excel 365 / 2021+ (dynamic arrays, XLOOKUP)

---

## Formatting conventions

- **Input cells:** Light yellow background (`#FFFFC0` or similar)
- **Typography:** Aptos Narrow for data, consistent sizes
- **Alignment:** Numbers right, text left, decimals aligned
- **Borders:** Subtle section dividers, not heavy gridlines
- **Conditional formatting:** Reactive feedback (over cap → red, etc.)

See `XLSXWRITER.md` for implementation patterns.
