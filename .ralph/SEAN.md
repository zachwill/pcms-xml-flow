# Sean workbook (current) - reverse engineering backlog

**Source of truth:** `reference/warehouse/*.json`

These JSON files are exports of Sean's current Excel workbook. Our older mental models in `reference/sean/` are now **legacy** and should not be treated as accurate.

**Goal:** for each worksheet export, write a concise but accurate "mental model" spec in:

- `reference/warehouse/specs/<sheet>.md`

So future agents (and humans) can:
- understand what each sheet *does*,
- see how sheets depend on each other (lookups/formulas),
- map sheet concepts to our DB tables (`pcms.*`) and tool-facing caches.

---

## Spec template (use for every sheet)

Each `reference/warehouse/specs/<sheet>.md` should include:

1. **Purpose / why the sheet exists**
2. **Key inputs / controls** (which cells appear to be user-edited; dropdowns; team selector; year selector)
3. **Key outputs** (tables, dashboards, totals, scenario results)
4. **Layout / zones** (rough column/row blocks; header rows; section titles)
5. **Cross-sheet dependencies**
   - what sheets it references (grep formulas like `='System Values'!G8`)
   - what sheets reference *it* (grep other files for its sheet name)
6. **Key formulas / logic patterns**
   - quote representative formulas (and explain what they're computing)
7. **Mapping to our Postgres model**
   - which `pcms.*` tables/views this corresponds to
   - what's missing from our schema/caches (if anything)
8. **Open questions / TODO**

---

## Quick inspection commands (preferred)

```bash
# Show first ~15 rows in numeric order (row keys are strings)
jq 'to_entries | sort_by(.key|tonumber) | .[0:15]' reference/warehouse/<sheet>.json

# Show a specific row
jq '."10"' reference/warehouse/<sheet>.json

# Find formulas referencing another sheet
# (Use rg if installed; otherwise use grep -E)
rg -n "='[^']+'!" reference/warehouse/<sheet>.json 2>/dev/null || true
grep -nE "='[^']+'!" reference/warehouse/<sheet>.json

# Find where a specific sheet is referenced (cross-sheet dependency)
rg -n "'<Sheet Name>'!" reference/warehouse/*.json 2>/dev/null || true
grep -nE "'<Sheet Name>'!" reference/warehouse/*.json
```

**Rules:**
- Do **not** edit `reference/warehouse/*.json` (treat as immutable reference artifacts).
- Prefer evidence-based claims: cite row/column addresses and/or paste a few real formulas.

---

## TODO (one spec per sheet)

### Meta / index
- [x] Create `reference/warehouse/specs/00-index.md` (workbook overview + dependency graph + links to each spec)

### Core warehouses / constants
- [x] Spec: `y.json` (Y Warehouse - multi-year salary matrix)
- [x] Spec: `dynamic_contracts.json`
- [x] Spec: `contract_protections.json`
- [x] Spec: `system_values.json`
- [x] Spec: `minimum_salary_scale.json`
- [x] Spec: `rookie_scale_amounts.json`

### Team + salary book views
- [x] Spec: `playground.json`
- [x] Spec: `team.json`
- [x] Spec: `team_summary.json`
- [x] Spec: `finance.json`
- [x] Spec: `ga.json`

### Trade tooling
- [x] Spec: `machine.json` (trade machine)
- [x] Spec: `exceptions.json`
- [x] Spec: `trade_bonus_amounts.json`

### Draft picks
- [x] Spec: `draft_picks.json`
- [x] Spec: `pick_database.json`

### Projections / calculators
- [x] Spec: `the_matrix.json`
- [x] Spec: `high_low.json`
- [x] Spec: `tax_array.json`

### Snapshots / examples / misc
- [x] Spec: `2025.json`
- [x] Spec: `por.json` (duplicate of playground.json)
- [x] Spec: `buyout_calculator.json`
- [x] Spec: `kuzma_buyout.json`
- [x] Spec: `set-off.json`
- [x] Spec: `cover.json`

---

## Follow-ups (post-spec / tooling parity)

### Completed analysis

- [x] Resolve **external workbook references** in formulas (e.g. `X!` and `[2]Exceptions Warehouse - 2024`) and map them to our in-repo sheets and/or `pcms.*` tables. → See `reference/warehouse/specs/external-refs.md`
- [x] Validate **luxury tax parity** (analysis): Sean's `Tax Array` SUMPRODUCT vs `pcms.league_tax_rates` (and repeater flags from `pcms.tax_team_status`). → See `reference/warehouse/specs/tax_array.md` §8-10.

### Next (tooling correctness blockers)

- [x] **Decide warehouse year horizon**: extend tool-facing warehouses to **2031** (Sean's Y goes to 2031) vs keep 2025–2030. → **Decision: Keep 2025–2030** (see `reference/warehouse/specs/year-horizon-decision.md`).
- [x] **Minimum salary parity**: validate Sean's multi-year minimum escalators (Years 2-5) + proration assumptions (`/174`) vs what we expose from `pcms.league_salary_scales` (Year 1 only today). → See `reference/warehouse/specs/minimum-salary-parity.md`.
- [x] **Luxury tax primitive**: implement `pcms.fn_luxury_tax_amount(salary_year, over_tax_amount, is_repeater)` (or equivalent) using `pcms.league_tax_rates`, so UI tools can replicate the workbook's "Tax Payment" outputs without SUMPRODUCT emulation. → See `migrations/057_fn_luxury_tax_amount.sql` and `reference/warehouse/specs/fn_luxury_tax_amount.md`.

### Scenario math

- [x] Reverse-engineer **buyout / waiver scenario math** from `buyout_calculator` + `kuzma_buyout`:
  - ✅ Confirmed `174` day constant + `waived_date + 2` clearance assumption
  - ⚠️ $600,000 subtraction appears contract-specific (protection threshold) — needs further validation
  - ✅ Codified **stretch provision years** rule: `2 × years_remaining + 1`
  - → See `reference/warehouse/specs/buyout-waiver-math.md`

### Hygiene

- [x] Identify other **duplicate snapshot sheets** (like `por.json` = `playground.json`) so we don't spec/implement redundant logic.
  - Result: only `por.json` and `playground.json` are byte-for-byte identical among the exported `reference/warehouse/*.json` files.

### Next (tooling parity follow-ups implied by specs)

- [x] Replace hard-coded repeater flags (Playground/Team `J1`/`N1`) with `pcms.tax_team_status` (or `pcms.team_salary_warehouse.is_repeater_taxpayer`), parameterized by year. → See `reference/warehouse/specs/repeater-flag-parameterization.md`.
- [x] Parameterize trade-matching thresholds in SQL (`pcms.fn_tpe_trade_math`) from `pcms.league_system_values` (TPE allowance) instead of hard-coded 2024/2025 constants (see `machine.md`). → **Analysis complete:** Already parameterized via `tpe_dollar_allowance`; tier breakpoints are implicit. See `reference/warehouse/specs/tpe-threshold-parameterization.md`.
- [ ] Add a small helper primitive for Trade Machine “can bring back” (invert matching rules) to match Sean’s `E5/J5` logic.
- [ ] Decide how to represent the season-day constants for buyout/stretch tooling (`174` days, waivers clear at `+2` days): hardcoded constant vs system table.
- [ ] Repo hygiene: restore/update `SCHEMA.md` (repo docs reference it; currently missing) or replace with a generated schema reference from `migrations/`.
