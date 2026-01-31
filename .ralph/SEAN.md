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
rg -n "='[^']+'!" reference/warehouse/<sheet>.json

# Find where a specific sheet is referenced (cross-sheet dependency)
rg -n "'<Sheet Name>'!" reference/warehouse/*.json
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
- [ ] Spec: `high_low.json`
- [ ] Spec: `tax_array.json`

### Snapshots / examples / misc
- [x] Spec: `2025.json`
- [ ] Spec: `por.json`
- [x] Spec: `buyout_calculator.json`
- [x] Spec: `kuzma_buyout.json`
- [ ] Spec: `set-off.json`
- [x] Spec: `cover.json`
