# Sean workbook (current) — reverse engineering backlog

**Source of truth:** `reference/warehouse/*.json`

These JSON files are exports of Sean’s current Excel workbook. Our older mental models in `reference/sean/` are now **legacy** and should not be treated as accurate.

**Goal:** for each worksheet export, write a concise but accurate “mental model” spec in:

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
   - quote representative formulas (and explain what they’re computing)
7. **Mapping to our Postgres model**
   - which `pcms.*` tables/views this corresponds to
   - what’s missing from our schema/caches (if anything)
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
- [x] Spec: `y.json` (Y Warehouse — multi-year salary matrix)
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

- [x] Resolve **external workbook references** in formulas (e.g. `X!` and `[2]Exceptions Warehouse - 2024`) and map them to our in-repo sheets and/or `pcms.*` tables. → See `specs/external-refs.md`
- [ ] Validate **luxury tax parity**: Sean’s `Tax Array` SUMPRODUCT vs `pcms.league_tax_rates` (and repeater flags from `pcms.tax_team_status`).
- [ ] Validate **minimum salary parity**: Sean’s multi-year minimum escalators vs what PCMS provides (`pcms.league_salary_scales` is year-1 only).
- [ ] Decide whether our tool-facing warehouses should extend to **2031** (Sean’s Y goes to 2031; ours is typically 2025–2030).
- [ ] Reverse-engineer **buyout / waiver scenario math** from `buyout_calculator` + `kuzma_buyout`:
  - confirm the `174` day constant + `waived_date + 2` clearance assumption
  - explain the **$600,000 subtraction** in `kuzma_buyout` (guarantee protection?)
  - codify **stretch provision years** rule (typically `2 × years_remaining + 1`)
- [ ] Identify other **duplicate snapshot sheets** (like `por.json` = `playground.json`) so we don’t spec/implement redundant logic.
