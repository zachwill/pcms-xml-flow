# Tax Array Spec

**Source:** `reference/warehouse/tax_array.json`  
**Rows:** 150

---

## 1. Purpose

`Tax Array` is a **lookup table for luxury tax calculation**. It provides the progressive bracket thresholds and marginal rates that determine how much a team pays in luxury tax based on how far they exceed the tax level.

The NBA luxury tax is **tiered/progressive**: each increment above the tax level is taxed at a higher marginal rate, similar to income tax brackets.

The sheet has two parallel arrays:
- **Tax Array** (cols E–I): standard "first-time" taxpayer rates
- **Repeat Tax Array** (cols K–O): higher rates for repeat offenders

---

## 2. Key Inputs / Controls

### GrowthRate / TaxBracket lookup (cols A–C, rows 4–10)

Defines the **tax bracket increment** per season. This controls how much salary fits in each bracket tier.

| Col | Header | Example (row 4) |
|-----|--------|-----------------|
| A   | Season | `2024` |
| B   | Tax Bracket | `5168000` (2024 bracket width) |
| C   | Growth % | `=INDEX(GrowthRate[Growth %], MATCH(TaxBracket[[#This Row],[Season]], GrowthRate[Season], 0))` |

Key rows:
- **Row 4** (2024): Tax Bracket = `$5,168,000` (hardcoded)
- **Row 5** (2025): `='System Values'!L8` → `$5,685,000`
- **Row 6** (2026): `='System Values'!L9` → `$6,102,000`
- **Row 7+** (2027+): `=B6*TaxBracket[[#This Row],[Growth %]]` (projected)

---

## 3. Key Outputs

### Tax Array (cols E–I)

Standard taxpayer rate lookup. 21 rows per season, starting row 4.

| Col | Header | Example (row 4) |
|-----|--------|-----------------|
| E   | Season | `2024` |
| F   | Index | `1` (bracket number 1–21) |
| G   | Tax Bracket | cumulative threshold in $ |
| H   | Tax Rate | marginal rate multiplier |
| I   | Increment | rate increment from prior bracket |

**2024 first-time rates (rows 4–24)**:
- Bracket 1 ($0–$5.17M over tax): `H = 1.5` (pay $1.50 per $1 over)
- Bracket 2 ($5.17M–$10.34M over): `H = 1.75` (pay $1.75 per $1 in this tier)
- Bracket 3 ($10.34M–$15.51M over): `H = 2.5`
- ...continues, +0.5 per tier after tier 5

### Repeat Tax Array (cols K–O)

Repeat offender rate lookup. Same structure, higher rates (starts at 2.5x instead of 1.5x).

| Col | Header | Example (row 4) |
|-----|--------|-----------------|
| K   | Season | `2024` |
| L   | Index | `1` |
| M   | Tax Bracket | cumulative threshold (same as col G) |
| N   | Tax Rate | `2.5` (1.0 higher than first-time) |
| O   | Increment | `2.5` |

---

## 4. Layout / Zones

```
Row 1:  Headers ("Growth Rate", "Tax Array", "Repeat Tax Array")
Row 3:  Column headers (Season, Tax Bracket, Growth %, etc.)
Rows 4–10:  TaxBracket lookup (cols A–C) — 7 seasons (2024–2030)
Rows 4–24:  2024 tax brackets (21 rows, cols E–I and K–O)
Rows 25–45: 2025 tax brackets
Rows 46–66: 2026 tax brackets
...
Rows 130–150: 2030 tax brackets
```

Each season block = 21 rows (bracket indices 1–21).

---

## 5. Cross-Sheet Dependencies

### This sheet references:

| Sheet | Cells | Purpose |
|-------|-------|---------|
| `System Values` | `L8`, `L9` | Tax bracket increment for 2025, 2026 |
| `GrowthRate` (internal table) | via INDEX/MATCH | Growth rate for projected seasons |

### Sheets that reference this sheet:

| Sheet | Usage |
|-------|-------|
| `2025.json` | SUMPRODUCT formula to calculate total tax owed |
| `finance.json` | SUMPRODUCT formula for team finance tax calc |
| `ga.json` | SUMPRODUCT for G-League affiliate tax |
| `playground.json` | SUMPRODUCT for Salary Book tax calc |

---

## 6. Key Formulas / Logic Patterns

### Tax bracket cumulative threshold (col G)

```
Row 5 (Index 2):
G5 = INDEX(TaxBracket[Tax Bracket], MATCH(Table2[[#This Row],[Season]], TaxBracket[Season]))

Row 6+ (Index 3+):
G6 = G5 + INDEX(TaxBracket[Tax Bracket], MATCH(Table2[[#This Row],[Season]], TaxBracket[Season]))
```

Logic: each bracket threshold is the previous threshold + one bracket increment.

### Tax calculation SUMPRODUCT (from consuming sheets)

```excel
=IF(
  $J$1="Yes",                                           -- is repeat taxpayer?
  SUMPRODUCT(
    (E53>'Tax Array'!$M$4:$M$200) *                     -- taxable amount > threshold
    ('Tax Array'!$K$4:$K$200=$E$3) *                    -- season matches
    (E53 - 'Tax Array'!$M$4:$M$200) *                   -- amount over this bracket
    ('Tax Array'!$O$4:$O$200)                           -- marginal increment rate
  ),
  SUMPRODUCT(
    (E53>'Tax Array'!$G$4:$G$200) *                     -- standard taxpayer version
    ('Tax Array'!$E$4:$E$200=$E$3) *
    (E53 - 'Tax Array'!$G$4:$G$200) *
    ('Tax Array'!$I$4:$I$200)
  )
)
```

This sums `(amount_over_bracket) * (marginal_increment)` across all applicable brackets, producing the total tax owed.

---

## 7. Mapping to Our Postgres Model

| Sean Concept | Postgres Equivalent | Notes |
|--------------|---------------------|-------|
| Progressive tax brackets + rates | `pcms.league_tax_rates` | PCMS already provides tax brackets per `(league_lk, salary_year)` with `lower_limit`, `upper_limit`, per-tier rates, and precomputed `base_charge_*` values. |
| Repeat taxpayer flag | `pcms.tax_team_status.is_repeater_taxpayer` (and surfaced in `pcms.team_salary_warehouse`) | Sean hard-codes repeaters in some sheets; we can source this from PCMS. |
| Tax level threshold | `pcms.league_system_values.luxury_tax_amount` (naming varies) | Needed to convert “team tax salary” → “amount over tax line”. |

### How this maps to Sean’s SUMPRODUCT

Sean’s SUMPRODUCT effectively computes a piecewise function over the “amount over the tax line”.

In PCMS terms you can compute luxury tax as:

1. `over_tax = GREATEST(0, team_tax_salary - luxury_tax_amount)`
2. Find the bracket row in `pcms.league_tax_rates` where `over_tax` falls (`lower_limit <= over_tax < upper_limit`)
3. `tax_owed = base_charge_(repeater/non) + (over_tax - lower_limit) * tax_rate_(repeater/non)`

This is more efficient (and less error-prone) than reproducing the bracket array + SUMPRODUCT trick.

---

## 8. Open Questions / TODO

- [ ] Confirm `pcms.league_tax_rates.lower_limit/upper_limit` are defined in terms of **amount over the tax line** (vs absolute payroll).
- [ ] Add a small SQL helper function (or view) for tool parity, e.g. `pcms.fn_luxury_tax_amount(salary_year, team_tax_salary, is_repeater)`.
- [ ] Reconcile workbook “Tax Bracket” increment (`System Values` col L) vs PCMS bracket definitions (should match when converting to `league_tax_rates`).
- [ ] Confirm repeat taxpayer definition used by PCMS matches Sean’s workbook assumptions.
