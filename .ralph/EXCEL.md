# Excel Workbook Progress

**Last updated:** 2026-02-01

---

## Current State

PLAYGROUND sheet exists with basic functionality:
- Team selector with dropdown
- Roster pulls from `tbl_salary_book_warehouse`, sorted by salary
- Trade Out/In/Waive/Sign inputs with named ranges
- Conditional formatting for trade-out (gray strikethrough) and trade-in (purple)
- Basic totals and KPIs

**But it's nowhere near Sean's professional workbook.**

---

## The Gap (Sean's vs Ours)

### Formatting
| Sean's | Ours | Priority |
|--------|------|----------|
| No `$` in roster - just `32,400,000` | `$32,000,001` with dollar signs | HIGH |
| `%` column right next to each salary year | Single `%` column | HIGH |
| Smaller, denser fonts | Default sizing, too much whitespace | MEDIUM |
| Green/red conditional formatting on thresholds | No threshold colors | HIGH |
| Multi-year columns (2025-2030) | Single year only | HIGH |

### Structure - Totals Section
Sean has a comprehensive totals block. We need:

- [x] **Team Salary** - sum of all roster salaries (uses `tbl_team_salary_warehouse[cap_total]`)
- [x] **Team Salary (fill to 14)** - with roster fills added
- [ ] **Minimum Level** - league minimum team salary
- [ ] **+/- Minimum** - delta from minimum
- [ ] **Cap Level** - salary cap amount
- [ ] **Cap Space** - GREEN if positive, RED if negative
- [ ] **Tax Level** - luxury tax threshold
- [ ] **+/- Tax** - GREEN if under, RED if over
- [ ] **Tax Payment** - calculated tax owed (if over)
- [ ] **Tax Refund** - (if applicable)
- [ ] **Apron 1 Level** - first apron threshold
- [ ] **+/- Apron 1** - GREEN/RED
- [ ] **Apron 2 Level** - second apron threshold  
- [ ] **+/- Apron 2** - GREEN/RED
- [ ] **Net Cost** - total cost including tax
- [ ] **Cost Savings** - (for trade scenarios)

### Structure - Roster Fills
- [ ] **Roster Count** - current count vs 15
- [ ] **(+) Rookie Mins** - slots filled at rookie minimum
- [ ] **(+) Vet Mins** - slots filled at vet minimum
- [ ] **Dead Money** - stretched/waived amounts

### Structure - Multi-Year View
- [ ] Columns for 2025, 2026, 2027, 2028, 2029, 2030
- [ ] Each year shows: Salary | % of Cap
- [ ] Option years highlighted (PO/TO/ETO in different colors)
- [ ] Contract end years visible

### Structure - Depth Chart
- [ ] Actual player names by position (not just PG/SG/SF labels)
- [ ] Shows starters + backups
- [ ] Reactive to roster changes

### Structure - Draft Picks
- [ ] Grid by year (2025-2032)
- [ ] 1st Round / 2nd Round columns
- [ ] Shows: Own, owed to team, protections
- [ ] Pull from `tbl_draft_picks_warehouse`

### Structure - Trade Machine
Sean has a dedicated trade machine section:
- [ ] Expanded salary matching view
- [ ] Shows outgoing vs incoming
- [ ] 125% + $250K rule calculation
- [ ] Multi-team trade support (future)

### Structure - Contract Calculators
- [ ] Contract Calculator - Total (max contract by years)
- [ ] Contract Calculator - Start Number (given starting salary)
- [ ] Renegotiation Calculator

---

## Immediate TODO (Formatting Polish)

### Phase 1: Clean up roster formatting
- [ ] Remove `$` from salary column - use `#,##0` not `$#,##0`
- [ ] Tighten column widths
- [ ] Smaller font (10pt instead of 11pt for data)
- [ ] Right-align all numbers

### Phase 2: Conditional formatting for thresholds
- [ ] Cap Space cell: GREEN if positive, RED if negative
- [ ] Tax cell: GREEN if under, RED if over
- [ ] Apron cells: GREEN/RED based on threshold
- [ ] Apply to both current values and scenario values

### Phase 3: Better totals section
- [ ] Add all the totals rows Sean has (see list above)
- [ ] Color-code the threshold comparisons
- [ ] Show deltas clearly (Base → Modified)

### Phase 4: Multi-year view
- [ ] Expand roster to show cap_y0 through cap_y5
- [ ] Add % column for each year
- [ ] Highlight option years with color

---

## Later TODO (Structure)

### Phase 5: Roster fills
- [ ] Calculate roster count
- [ ] Add rookie min fills to reach 14
- [ ] Add vet min fills to reach 15 (if needed)
- [ ] Show dead money

### Phase 6: Depth chart
- [ ] Filter roster by position
- [ ] Display in depth chart grid
- [ ] Make reactive to trade/waive inputs

### Phase 7: Draft picks
- [ ] Pull from `tbl_draft_picks_warehouse`
- [ ] Display ownership grid by year
- [ ] Show protections

### Phase 8: Trade machine improvements
- [ ] Dedicated trade matching section
- [ ] Show 125% rule calculation
- [ ] Better UX for entering trades

---

## Technical Notes

### XlsxWriter Patterns (from XLSXWRITER.md)
- Use `write_dynamic_array_formula("E3", formula)` for spill formulas
- Use `ANCHORARRAY(E3)` to reference spilled ranges (not `E3#`)
- LAMBDA params need `_xlpm.` prefix: `LAMBDA(_xlpm.x, _xlpm.x+1)`
- Pre-format columns with `set_column("F:F", width, fmt)` for spill formatting
- Enable `use_future_functions: True` on workbook creation

### Data Sources
| Need | Table | Key Columns |
|------|-------|-------------|
| Player salaries | `tbl_salary_book_warehouse` | player_name, team_code, cap_y0..cap_y5 |
| Team totals | `tbl_team_salary_warehouse` | All threshold comparisons |
| System values | `tbl_system_values` | salary_cap_amount, tax_level_amount, tax_apron_amount |
| Draft picks | `tbl_draft_picks_warehouse` | Ownership by year |
| Cap holds | `tbl_cap_holds_warehouse` | Player rights |
| Dead money | `tbl_dead_money_warehouse` | Stretched/waived |
| Exceptions | `tbl_exceptions_warehouse` | MLE, BAE, TPE amounts |

### Named Ranges Defined
- `SelectedTeam` - B1 (team selector)
- `TradeOutNames` - B3:B8
- `TradeInNames` - B10:B15
- `WaivedNames` - B17:B19
- `SignNames` - B21:B22
- `SignSalaries` - C21:C22
- `TeamSalary` - F21 (base team salary from warehouse)
- `ModifiedSalary` - F22 (scenario-adjusted total)

---

## Reference
- Sean's workbook: The gold standard for density and functionality
- Blueprints: `reference/blueprints/excel-cap-book-blueprint.md`
- Data contract: `reference/blueprints/data-contract.md`
- XlsxWriter docs: `excel/XLSXWRITER.md`
