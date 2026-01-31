# Sean Workbook — Index & Dependency Map

**Generated:** 2026-01-31  
**Source:** `reference/warehouse/*.json` (current Excel export)

---

## Workbook Overview

Sean's workbook is the canonical analyst reference for NBA salary cap modeling. It contains:

- **Data warehouses** — raw contract/salary data in structured formats
- **System constants** — CBA parameters (cap, tax, apron) by year
- **Presentation views** — team rosters, salary books, dashboards
- **Trade tools** — trade machine, exceptions, salary matching logic
- **Calculators** — extensions, buyouts, rookie scale, projections

---

## Sheet Inventory

| Sheet | File | Purpose | Spec |
|-------|------|---------|------|
| Cover | `cover.json` | Title page with date stamp | [cover.md](cover.md) |
| **Y Warehouse** | `y.json` | Multi-year salary matrix (1 row/player) | [y.md](y.md) |
| Dynamic Contracts | `dynamic_contracts.json` | Detailed contract rows with all year/salary permutations | [dynamic_contracts.md](dynamic_contracts.md) |
| Contract Protections | `contract_protections.json` | Guarantee/protection lookup by contract+year | [contract_protections.md](contract_protections.md) |
| System Values | `system_values.json` | CBA constants: cap, tax, aprons, mins by season | [system_values.md](system_values.md) |
| Minimum Salary Scale | `minimum_salary_scale.json` | Minimum salary by years of service | [minimum_salary_scale.md](minimum_salary_scale.md) |
| Rookie Scale Amounts | `rookie_scale_amounts.json` | Rookie scale salary by pick + year | [rookie_scale_amounts.md](rookie_scale_amounts.md) |
| Playground | `playground.json` | Interactive team salary book view | [playground.md](playground.md) |
| POR | `por.json` | Portland-specific playground snapshot | [por.md](por.md) |
| 2025 | `2025.json` | 2025 season snapshot view | [2025.md](2025.md) |
| Team | `team.json` | Team roster with contract calculator blocks | [team.md](team.md) |
| Team Summary | `team_summary.json` | Team salary totals dashboard (vs cap/tax/apron) | [team_summary.md](team_summary.md) |
| Finance | `finance.json` | Team financial data | [finance.md](finance.md) |
| GA | `ga.json` | G-League affiliate / two-way data | [ga.md](ga.md) |
| Machine | `machine.json` | Trade machine logic | [machine.md](machine.md) |
| Exceptions | `exceptions.json` | Active trade exceptions by team | [exceptions.md](exceptions.md) |
| Trade Bonus Amounts | `trade_bonus_amounts.json` | Trade bonus / kicker calculations | [trade_bonus_amounts.md](trade_bonus_amounts.md) |
| Draft Picks | `draft_picks.json` | Draft pick ownership/trades | [draft_picks.md](draft_picks.md) |
| Pick Database | `pick_database.json` | Pick reference database | [pick_database.md](pick_database.md) |
| The Matrix | `the_matrix.json` | Contract extension calculator | [the_matrix.md](the_matrix.md) |
| High Low | `high_low.json` | High/low salary projections | [high_low.md](high_low.md) |
| Tax Array | `tax_array.json` | Luxury tax bracket calculations | [tax_array.md](tax_array.md) |
| Buyout Calculator | `buyout_calculator.json` | Buyout scenario calculator | [buyout_calculator.md](buyout_calculator.md) |
| Kuzma Buyout | `kuzma_buyout.json` | Specific buyout example | [kuzma_buyout.md](kuzma_buyout.md) |
| Set-Off | `set-off.json` | Waiver set-off calculations | [set-off.md](set-off.md) |

---

## Dependency Graph

The workbook has a layered architecture:

```
┌─────────────────────────────────────────────────────────────────┐
│                     PRESENTATION LAYER                          │
│  playground, por, 2025, team, team_summary, finance, ga         │
│  machine, the_matrix, buyout_calculator, kuzma_buyout           │
└─────────────────────────────────┬───────────────────────────────┘
                                  │
                    ┌─────────────▼─────────────┐
                    │     Y WAREHOUSE (Y)       │  ◄── Central hub
                    │   1 row per player        │
                    │   Cols: cap/tax/apron     │
                    │   by year (2025-2031)     │
                    └─────────────┬─────────────┘
                                  │
           ┌──────────────────────┼──────────────────────┐
           │                      │                      │
           ▼                      ▼                      ▼
┌──────────────────┐   ┌──────────────────┐   ┌──────────────────┐
│ dynamic_contracts│   │ trade_bonus_amts │   │   exceptions     │
│ (detail rows)    │   │ (kicker lookup)  │   │ (TPE list)       │
└────────┬─────────┘   └──────────────────┘   └──────────────────┘
         │
         ▼
┌──────────────────┐
│contract_protections│
│ (guarantee lookup) │
└──────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                     CONSTANTS LAYER                             │
│  system_values, minimum_salary_scale, rookie_scale_amounts      │
│  tax_array                                                      │
└─────────────────────────────────────────────────────────────────┘
```

### Sheets that reference Y (central warehouse)

| Sheet | Reference Count |
|-------|-----------------|
| high_low.json | 11,702 |
| the_matrix.json | 1,496 |
| ga.json | 1,117 |
| 2025.json | 1,111 |
| dynamic_contracts.json | 1,004 |
| team.json | 825 |
| por.json | 756 |
| playground.json | 756 |
| finance.json | 674 |
| team_summary.json | 420 |
| machine.json | 283 |
| buyout_calculator.json | 12 |
| kuzma_buyout.json | 6 |

### Other cross-sheet references

| From | To | Purpose |
|------|----|---------|
| y.json | Trade Bonus Amounts | Trade kicker lookup |
| dynamic_contracts.json | Contract Protections | Guarantee/protection lookup |
| team_summary.json | System Values | Cap/tax/apron constants |
| tax_array.json | System Values | Tax bracket thresholds |
| the_matrix.json | Exceptions | TPE availability |
| machine.json | X (legacy?) | Some trade logic |

---

## Sheet Categories

### Core Data (source-of-truth)

- **Y Warehouse** (`y.json`) — pivoted salary matrix, one row per player
- **Dynamic Contracts** (`dynamic_contracts.json`) — raw contract rows with all permutations
- **Contract Protections** (`contract_protections.json`) — guarantee details

### CBA Constants

- **System Values** (`system_values.json`) — cap/tax/apron levels by year
- **Minimum Salary Scale** (`minimum_salary_scale.json`) — min salary by years of service
- **Rookie Scale Amounts** (`rookie_scale_amounts.json`) — rookie scale by pick + year
- **Tax Array** (`tax_array.json`) — luxury tax bracket calculations

### Team Views (salary book / playground)

- **Playground** (`playground.json`) — interactive team selector → roster view
- **POR** (`por.json`) — Portland snapshot (same layout as playground)
- **2025** (`2025.json`) — 2025 season snapshot
- **Team** (`team.json`) — team roster with contract blocks
- **Team Summary** (`team_summary.json`) — 30-team dashboard (salary vs cap/tax/apron)
- **Finance** (`finance.json`) — financial data by team
- **GA** (`ga.json`) — G-League / two-way players

### Trade Tooling

- **Machine** (`machine.json`) — trade machine: salary matching, exception usage
- **Exceptions** (`exceptions.json`) — active trade exceptions by team
- **Trade Bonus Amounts** (`trade_bonus_amounts.json`) — trade kicker lookup

### Draft

- **Draft Picks** (`draft_picks.json`) — pick ownership/trades
- **Pick Database** (`pick_database.json`) — historical pick reference

### Calculators

- **The Matrix** (`the_matrix.json`) — contract extension calculator
- **High Low** (`high_low.json`) — high/low salary projections
- **Buyout Calculator** (`buyout_calculator.json`) — buyout scenarios
- **Kuzma Buyout** (`kuzma_buyout.json`) — specific buyout example
- **Set-Off** (`set-off.json`) — waiver set-off calculations

---

## Mapping to Our Postgres Model

| Sean Concept | Warehouse File(s) | Our Table(s) |
|--------------|-------------------|--------------|
| Player salaries by year | `y.json`, `dynamic_contracts.json` | `pcms.salary_book_warehouse`, `pcms.contract_amounts` |
| CBA constants | `system_values.json` | `pcms.league_system_values` |
| Trade exceptions | `exceptions.json` | `pcms.exceptions_warehouse`, `pcms.team_exceptions` |
| Team totals | `team_summary.json` | `pcms.team_salary_warehouse`, `pcms.team_budget_snapshots` |
| Contract protections | `contract_protections.json` | `pcms.contract_amounts` (guarantee fields) |
| Rookie scale | `rookie_scale_amounts.json` | `pcms.rookie_scale` |
| Draft picks | `draft_picks.json`, `pick_database.json` | `pcms.draft_picks` |
| Trade kickers | `trade_bonus_amounts.json` | `pcms.contract_versions.trade_bonus_percent` |
| Minimum salary | `minimum_salary_scale.json` | `pcms.minimum_salary_scale` |

---

## Key Patterns

### Y Warehouse is the hub

Almost every presentation sheet uses `INDEX(Y!$D:$J, ...)` or similar to pull player salaries. The Y sheet is a **pivoted view** — one row per player with columns for each year's cap/tax/apron amounts.

Row 2 headers in Y:
- A: `PlayerID`
- B: `Name`
- C: `Team`
- D-J: Cap amounts (2025-2031)
- K-Q: Option types (2025-2031)
- R-X: Tax amounts (2025-2031)
- Y-AE: Apron amounts (2025-2031)
- AF: `DOB`, AG: `Age`, AH: `Agent`, AI: `TK` (trade kicker), AJ: `Tier`, AK: `Top`, AL: `Bottom`, AM: `SB`, AN: `Pos`

### Dynamic Contracts is the detail layer

Multiple rows per player/contract. Used to track all year permutations, options, protections. References `Contract Protections` for guarantee lookup.

### System Values drives thresholds

`team_summary.json` and `tax_array.json` both reference `='System Values'!G8` (cap), `!H8` (tax), `!I8` (apron 1), `!J8` (apron 2) for the current season.

### Team selector pattern

Presentation sheets like `playground.json` use a team dropdown (e.g., cell `D1 = "POR"`) that filters which players appear. Formulas then filter the Y warehouse by team code.

---

## Open Questions

1. **X sheet?** — `machine.json` references `X!` but there's no `x.json`. May be a legacy sheet or different naming.
2. **Exceptions self-reference** — `exceptions.json` references `Exceptions!` (itself). Likely named range or table reference.
3. **Contract Protections external reference** — `dynamic_contracts.json` references `[2]Contract Protections` which suggests it was linking to an external workbook at some point.

---

## Next Steps

Create individual spec files for each sheet following the template in `.ralph/SEAN.md`. Priority order:

1. `y.md` — central warehouse (most dependencies)
2. `system_values.md` — CBA constants
3. `dynamic_contracts.md` — contract detail layer
4. `playground.md` — team salary book view
5. `machine.md` — trade machine logic
6. `team_summary.md` — team dashboard
