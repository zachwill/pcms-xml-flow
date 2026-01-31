# AGENTS.md — `reference/warehouse/`

**Updated: 2026-01-30**

This folder contains Sean's **current Excel workbook** exported as JSON. These are the newest analyst sheets — use these as the primary reference for understanding how a salary-cap analyst models contracts, trades, and team financials.

> The older `reference/sean/` folder contains a previous version of these sheets. Prefer this folder for current mental models.

---

## File Format

Each JSON file represents an Excel worksheet. Structure:

- **Row numbers** as top-level keys (strings: `"1"`, `"2"`, …)
- Each row is an object mapping **columns** (`"A"`, `"B"`, … `"AA"`, …) to:
  - Literal values (strings/numbers)
  - Excel formulas (strings starting with `=`)

Example from `dynamic_contracts.json`:

```json
"10": {
  "A": "99966",
  "B": "1",
  "C": "1630700",
  "D": "Dyson",
  "E": "Daniels",
  "G": "ATL",
  "K": "25000000",
  "P": "=IFERROR(IF(OR(N10=\"Player Opt\", ...)...)"
}
```

---

## File Inventory

### Core Data Warehouses

| File | Size | Purpose |
|------|------|---------|
| `y.json` | 1.5MB | **Y Warehouse** — multi-year salary matrix per player (2025+ base year). Primary source for Salary Book / Playground. |
| `dynamic_contracts.json` | 5.3MB | Detailed contract rows with salaries (cap/tax/apron), options, protections, trade bonus calcs. Feeds the pivoted views. |
| `contract_protections.json` | 580KB | Guarantee/protection lookup by contract + year. |

### System / CBA Constants

| File | Size | Purpose |
|------|------|---------|
| `system_values.json` | 14KB | CBA constants by season: salary cap, tax level, apron 1, apron 2, minimum level, tax brackets. Compare to `pcms.league_system_values`. |
| `minimum_salary_scale.json` | 31KB | Minimum salary by years of service. |
| `rookie_scale_amounts.json` | 271KB | Rookie scale salary lookup by pick + year. |

### Team-Level Views

| File | Size | Purpose |
|------|------|---------|
| `team.json` | 106KB | Team roster view with contract calculator blocks. |
| `team_summary.json` | 46KB | Team salary totals dashboard (current salaries vs cap/tax/apron). |
| `finance.json` | 90KB | Team financial data. |
| `ga.json` | 136KB | G-League affiliate / two-way data. |

### Playground / Salary Book

| File | Size | Purpose |
|------|------|---------|
| `playground.json` | 98KB | Interactive team Salary Book view (pick team → see roster by year). |
| `por.json` | 98KB | Portland-specific Playground snapshot (exact duplicate of `playground.json` with team selector set to POR). |
| `2025.json` | 132KB | 2025 season snapshot. |

### Trade Tooling

| File | Size | Purpose |
|------|------|---------|
| `machine.json` | 72KB | Trade Machine logic — incoming/outgoing salary rules, exception usage. |
| `exceptions.json` | 18KB | Active trade exceptions by team. |
| `trade_bonus_amounts.json` | 40KB | Trade bonus / kicker calculations. |

### Draft Picks

| File | Size | Purpose |
|------|------|---------|
| `draft_picks.json` | 377KB | Draft pick ownership/trades. |
| `pick_database.json` | 126KB | Pick reference database. |

### Contract Calculators / Projections

| File | Size | Purpose |
|------|------|---------|
| `the_matrix.json` | 158KB | Multi-team trade scenario calculator (salary matching + apron constraints). |
| `high_low.json` | 1.2MB | High/low salary projections per contract. |
| `tax_array.json` | 71KB | Luxury tax bracket calculations. |

### Buyout / Waiver Tools

| File | Size | Purpose |
|------|------|---------|
| `buyout_calculator.json` | 2.5KB | Buyout scenario calculator. |
| `kuzma_buyout.json` | 3.2KB | Specific buyout example (Kyle Kuzma). |
| `set-off.json` | 3.2KB | Waiver set-off calculations. |

### Misc

| File | Size | Purpose |
|------|------|---------|
| `cover.json` | 78B | Cover sheet metadata. |

---

## Key Relationships

The Excel workbook has cross-sheet dependencies. Key patterns:

1. **`dynamic_contracts.json`** is the raw data layer — contract rows with all year/salary permutations.

2. **`y.json`** is a pivoted view — one row per player with columns for each year's salary. Other sheets `VLOOKUP` / `INDEX/MATCH` into Y.

3. **`system_values.json`** provides CBA constants that formulas reference (e.g., `='System Values'!G8` for salary cap).

4. **`contract_protections.json`** is a lookup table joined by contract ID + year.

5. **`playground.json`** / **`team.json`** are presentation layers that filter/sort the warehouse data by team.

6. Some presentation sheets are **cloned snapshots** of others (e.g., `por.json` is an exact copy of `playground.json`).

---

## Mapping to Our PCMS Tables

| Sean Concept | Warehouse File | Our Table(s) |
|--------------|----------------|--------------|
| Player salaries by year | `y.json`, `dynamic_contracts.json` | `pcms.salary_book_warehouse`, `pcms.contract_amounts` |
| CBA constants | `system_values.json` | `pcms.league_system_values` |
| Trade exceptions | `exceptions.json` | `pcms.exceptions_warehouse`, `pcms.team_exceptions` |
| Team totals | `team_summary.json` | `pcms.team_salary_warehouse`, `pcms.team_budget_snapshots` |
| Contract protections | `contract_protections.json` | `pcms.contract_amounts` (guarantee fields) |
| Rookie scale | `rookie_scale_amounts.json` | `pcms.rookie_scale_amounts` |
| Minimum salary scale (by YOS) | `minimum_salary_scale.json` | `pcms.league_salary_scales` (minimum_salary_amount by YOS/year) |
| Luxury tax brackets / rates | `tax_array.json` | `pcms.league_tax_rates` (rates + base charges) + `pcms.tax_team_status` (repeater flag) |
| Draft picks | `draft_picks.json`, `pick_database.json` | `pcms.draft_picks` / `pcms.draft_picks_warehouse` |

---

## Differences from Old `reference/sean/`

The old `reference/sean/*.txt` files were from an **earlier version** of the workbook:
- Base year was 2024-25 (X) / 2025-26 (Y)
- Some columns have shifted

This folder (`reference/warehouse/`) is the **current 2025-26 season** version. Prefer this for:
- Understanding current analyst mental models
- Validating our warehouse outputs
- Identifying gaps in our tooling

---

## Usage Tips

### Quick inspection with jq

```bash
# See a specific row
jq '."10"' reference/warehouse/y.json

# Find all keys (row numbers)
jq 'keys | length' reference/warehouse/y.json

# Search for a player name
jq 'to_entries[] | select(.value.B == "James, LeBron")' reference/warehouse/y.json
```

### Finding formula patterns

```bash
# See what formulas reference System Values
grep -o "System Values[^\"]*" reference/warehouse/team_summary.json | sort -u

# Find VLOOKUP patterns
grep -o "VLOOKUP[^)]*)" reference/warehouse/machine.json | head -10
```

---

## Caveats

- These are **Excel exports**, not clean datasets. Expect formulas, not just values.
- Some rows are **scenario/hypothetical** entries (e.g., "Player Max Extension" placeholders).
- Column meanings must be inferred from headers (usually row 1-3) and formula context.
- This is a **snapshot** — it reflects Sean's workbook at export time, not live PCMS data.
