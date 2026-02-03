# AGENTS.md — `excel/`

Code-generated Excel workbook for NBA salary cap analysis.

---

## Architecture

```
excel/
├── AGENTS.md                    # This file
├── XLSXWRITER.md                # XlsxWriter patterns + gotchas (READ THIS)
├── export_capbook.py            # CLI entrypoint
└── capbook/
    ├── build.py                 # Orchestration
    ├── db.py                    # Database helpers
    ├── extract.py               # Dataset extraction
    ├── xlsx.py                  # XlsxWriter helpers + shared formats
    └── sheets/
        ├── meta.py              # META sheet (base year, as-of date)
        └── playground/
            ├── writer/          # PLAYGROUND writer package (setup/calc/inputs/roster/totals)
            ├── formulas.py      # Formula builders (LET/LAMBDA/etc)
            ├── formats.py       # Cell formats
            └── layout.py        # Grid constants (rows, columns)
```

---

## CLI

```bash
# Build workbook (defaults: out=shared/capbook.xlsx, base-year=2025, as-of=today)
uv run excel/export_capbook.py

# Override output
uv run excel/export_capbook.py --out shared/capbook.xlsx

# Override snapshot parameters
uv run excel/export_capbook.py --base-year 2025 --as-of 2026-02-01

# Skip SQL assertions (faster iteration)
uv run excel/export_capbook.py --skip-assertions
```

Requires `POSTGRES_URL` environment variable.

---

## DATA_ Sheets

Embedded datasets from Postgres, hidden in final workbook:

| Sheet | Table Name | Purpose |
|-------|------------|---------|
| DATA_system_values | `tbl_system_values` | Cap/tax/apron thresholds |
| DATA_team_salary_warehouse | `tbl_team_salary_warehouse` | **Authoritative team totals** |
| DATA_salary_book_yearly | `tbl_salary_book_yearly` | Player salaries (tall format) |
| DATA_salary_book_warehouse | `tbl_salary_book_warehouse` | Player salaries (wide format) |
| DATA_minimum_scale | `tbl_minimum_scale` | Min salary by YOS |
| DATA_tax_rates | `tbl_tax_rates` | Luxury tax brackets |
| DATA_exceptions_warehouse | `tbl_exceptions_warehouse` | Exception inventory |
| DATA_draft_picks_warehouse | `tbl_draft_picks_warehouse` | Draft picks |
| DATA_dead_money_warehouse | `tbl_dead_money_warehouse` | Dead money |
| DATA_cap_holds_warehouse | `tbl_cap_holds_warehouse` | Cap holds |

All filter to 6-year horizon (base_year through base_year + 5).

---

## PLAYGROUND Sheet Structure

### Frozen Regions
- **Rows 1-3:** Team context, KPI bar, column headers
- **Columns A-C:** Input rail (scenario inputs)

### Key Patterns

**Scenario calculations live in hidden CALC sheet:**
```python
calc_ws.write_formula("A1", "=LET(...complex scenario formula...)")
wb.define_name("ScnCapTotal0", "=CALC!$A$1")
```

**Spill formatting uses column formats:**
```python
ws.set_column(COL_PLAYER, COL_PLAYER, 20, fmts["player"])
ws.write_dynamic_array_formula("D4", "=RosterNames")
```

**Complex formulas use the builder in formulas.py:**
```python
def scenario_team_total(*, year_expr: str, year_offset: int) -> str:
    # Returns formula with proper _xlpm. prefixes and balanced parens
```

---

## Formula Conventions

All formulas follow patterns in `XLSXWRITER.md`. Key rules:

1. **Always enable `use_future_functions`** on workbook creation
2. **LAMBDA params use `_xlpm.` prefix** (e.g., `_xlpm.x`)
3. **Spill refs use `ANCHORARRAY()`** not `F2#`
4. **Comment closing parens** in complex nested formulas
5. **Set column formats** for spill columns (anchor format doesn't propagate)

---

## Key Named Ranges

| Name | Purpose |
|------|---------|
| `SelectedTeam` | Team selector input |
| `TradeOutNames` / `TradeInNames` | Trade scenario inputs |
| `WaivedNames` / `StretchNames` | Waive/stretch inputs |
| `SignNames` / `SignSalaries` | Signing inputs |
| `FillMode` | Fill preset mode: `IMMEDIATE`, `TRADE (+14)`, `CUSTOM` |
| `FillEventDate` / `FillDelayDays` | Roster-fill pricing date + delay window (Matrix-style +14 supported) |
| `FillTo12MinType` / `FillTo14MinType` | Roster-fill basis selection (rookie vs vet minimum assumptions) |
| `MetaBaseYear` / `MetaAsOfDate` | From META sheet |
| `ScnCapTotal{0-3}` | Scenario-adjusted cap totals by year offset |
| `ScnRosterCount{0-3}` | Scenario-adjusted roster counts |
| `ScnFill12Amount{0-3}` / `ScnFill14Amount{0-3}` | Roster fill amounts (to 12 / to 14) |

---

## Progress Tracking

See `.ralph/EXCEL.md` for current state and remaining work.

---

## Constraints

- **Offline:** No live DB—workbook works offline with embedded DATA_ sheets
- **Trust:** Totals must reconcile to `tbl_team_salary_warehouse`
- **Modern Excel:** Requires Excel 365/2021+ (dynamic arrays, XLOOKUP)
