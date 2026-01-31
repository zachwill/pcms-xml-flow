# System Values Spec

**Source:** `reference/warehouse/system_values.json`  
**Rows:** 29

---

## 1. Purpose

`System Values` is the workbook’s **CBA constants table**. It provides (by season):

- Salary cap, tax level, apron 1, apron 2
- Minimum team salary (90% floor)
- Tax bracket increment (used by `tax_array.json`)
- Cash limits / int’l buyout limits
- Exception amounts (MLE/BAE, etc.)
- Maximum salary amounts (25% / 30% / 35% of cap)

Nearly every presentation/tool sheet uses these values via either:

- direct cell references like `='System Values'!G8`, or
- structured table references like `SystemValues[[#All],[Salary Cap]]`.

---

## 2. Key Inputs / Controls

This sheet is mostly constants, but it has one explicit modeling input block:

### GrowthRate table (cols A–B)

Rows 4–11 define “Growth %” by season for projecting future caps.

Example:
- `B6` (season 2026 growth): `=G9/G8` (infers growth from the 2028 vs 2027 cap in the other table)
- Rows 10+ use `INDEX(GrowthRate[Growth %], MATCH(...))` to project forward.

In practice, analysts can change:
- `Growth %` (col B) to change future projections.

---

## 3. Key Outputs

The sheet has two main logical tables:

### A) SystemValues table (rows 3–14, cols D–N)
Headers (row 3):
- `Season`, `Avg. Salary`, `Est. Avg. Salary`, `Salary Cap`, `Tax Level`, `Apron 1`, `Apron 2`, `Minimum Level`, `Tax Bracket`, `Cash Limit`, `Int'l Payment`

Example constant row:
- 2028 row (`Season=2025` in the right-hand table at row 8):
  - `G8 = 154647000` (cap)
  - `H8 = 187895000` (tax)
  - `I8 = 195945000` (apron 1)
  - `J8 = 207824000` (apron 2)
  - `K8 = SystemValues[[#This Row],[Salary Cap]]*0.9` (minimum team salary = 90% of cap)

Projected rows (2030+):
- `G10 = INDEX(GrowthRate[Growth %], MATCH(SystemValues[[#This Row],[Season]], GrowthRate[Season], 0))*G9`

### B) Maximums table (rows 18–29, cols D–N)
Header row 18 includes:
- Exceptions: `BAE`, `MLE`, `TP-MLE`, `R-MLE`, `TPE Allowance`
- Maximum salary thresholds: `25%`, `30%`, `35%`
- Two-way amounts: `2W Salary`, `Max 2W`

Example:
- Row 23 (Season 2025):
  - `I23 = 8527000` (TPE allowance; appears directly in trade-math formulas)
  - `J23 = 38661750` (25% max)
  - `K23 = 46394100` (30% max)
  - `L23 = 54126450` (35% max)

---

## 4. Layout / Zones

- Row 1: Titles (`Master Growth Rate`, `System Values`)
- Rows 3–14:
  - Left: GrowthRate stub (A–B)
  - Right: SystemValues table (D–N)
- Rows 16–29:
  - Maximums + Exceptions table (D–N)

---

## 5. Cross-Sheet Dependencies

### System Values is referenced by:

Direct cell refs:
- `team_summary.json`: `='System Values'!G8` / `H8` / `I8` / `J8` (cap/tax/aprons)
- `tax_array.json`: references `='System Values'!L8`, `L9`, etc. (tax bracket increments)

Structured table refs (`SystemValues[...]`):
- `playground.json`, `team.json`, `finance.json`, `2025.json`, `the_matrix.json`, `high_low.json` (caps and thresholds per year)

Maximums table refs:
- `trade_bonus_amounts.json` uses `Maximums[[#Data],[25%]]` etc. for the trade-kicker max constraint.

### System Values references:

- It self-references its named tables (`SystemValues`, `GrowthRate`, `Maximums`) via structured references.
- No external sheet references were observed in `system_values.json`.

---

## 6. Key Formulas / Logic Patterns

### Minimum team salary (90% floor)
- `K8`: `=SystemValues[[#This Row],[Salary Cap]]*0.9`

### Projecting future years using GrowthRate
- `G10`: `=INDEX(GrowthRate[Growth %], MATCH(SystemValues[[#This Row],[Season]], GrowthRate[Season], 0))*G9`

### TPE allowance constant (drives trade-math tier)
- `I23` (2025): `8527000`

---

## 7. Mapping to Postgres

Primary mapping:

| Sean concept | Source | Our table | Notes |
|---|---|---|---|
| Cap/tax/apron thresholds by year | `SystemValues` table | `pcms.league_system_values` | `salary_cap_amount`, `luxury_tax_amount`, `apron_1_amount`, `apron_2_amount`, etc. |
| Minimum team salary (90% floor) | `Minimum Level` | `pcms.league_system_values.minimum_team_salary_amount` | Already present in our schema (used by team salary warehouse). |
| Max salaries (25/30/35%) | `Maximums` table | `pcms.league_system_values` | Our `league_system_values` stores max amounts (used in trade-kicker logic). |

Notes:
- The workbook’s `TPE Allowance` is the same constant we hardcode/parameterize in trade-matching logic (`fn_tpe_trade_math`).

---

## 8. Open Questions / TODO

- [ ] Confirm column-by-column naming alignment between `SystemValues`/`Maximums` and our `pcms.league_system_values` fields (some repos use different names like `salary_cap_amount` vs `salary_cap`).
- [ ] The sheet includes `Cash Limit` and `Int'l Payment`; we currently don’t surface these in tool-facing caches.
- [ ] Decide whether to keep trade constants hard-coded in SQL functions or always source from `pcms.league_system_values`.
