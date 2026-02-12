# Design Consistency Audit

> Propagate Salary Book polish to every other page in `web/`.
>
> **Gold standard:** `web/app/views/tools/salary_book/` (especially `_player_row`, `_team_section`, `_table_header`, `_sidebar_player`)
>
> **Design contract:** `web/docs/design_guide.md`, `web/AGENTS.md`
>
> **Rule:** Do NOT modify Salary Book files. They are the reference. Fix everything else to match.

---

## ⚠️ Supervisor notes (pattern guardrails)

**KPI cards vs table cells — do NOT conflate:**
- `entity-cell-two-line` / `entity-cell-primary` / `entity-cell-secondary` are **table-cell components** (fixed grid-rows, text-[13px]). Use them ONLY inside `<td>` or dense table-row contexts.
- **KPI/vitals cards** (standalone `rounded-lg border p-3` cards in grid layouts) use the simpler pattern: `text-xs text-muted-foreground` label on top → `text-sm/text-lg font-medium/font-semibold` value below. See `entities/transactions/show.html.erb` vitals section as the reference.
- Do not "upgrade" KPI cards to `entity-cell-two-line` — it shrinks the value text, inverts the label/value order, and breaks visual weight.

**Scope of `entity-chip` migration:**
- When replacing bespoke badge colors with `entity-chip` tokens, verify the existing chip variants (`entity-chip--muted`, `--warning`, `--danger`, `--success`, `--accent`) cover the semantic need. If a new variant is needed, add it to `application.css` first.

**EXTSN chip color note (accepted):**
- EXTSN transaction type was originally `bg-blue-100 text-blue-700` (blue). Mapped to `entity-chip--accent` (purple) because no `entity-chip--info` (blue) variant exists. Acceptable for now — if blue chips are needed across 3+ surfaces, add `entity-chip--info` to `application.css` first.

**Red text dark mode variants — context matters:**
- `_kpi_cell.html.erb` uses bare `text-red-500` for negative values (KPI card context). The dark footer variant uses `text-red-400 dark:text-red-500` (inverted).
- `_player_row.html.erb` uses `text-red-600 dark:text-red-400` for inline status tokens (table-row context).
- Team summary table cells (entity-cell-two-line in `<div>` rows) follow the table-row context → `text-red-600 dark:text-red-400` is correct.
- `design_guide.md` currently says bare `text-red-500` — this is a simplification. Future cleanup: update the guide to document both contexts.

**Next priority items:** rookie_scale_amounts audit (done ✅), then sticky-column opacity fix (lower-priority), then players/teams/agents entity page audits.

**Sticky column `group-hover` opacity rule (from Salary Book):**
- Outer row: `hover:bg-yellow-50/70` (with opacity — transparent rows blend with table bg)
- Sticky column: `group-hover:bg-yellow-50` (NO opacity — opaque to fully cover `bg-background` underneath)
- The worker had `group-hover:bg-yellow-50/70` on the two_way_utility sticky column; supervisor corrected to `group-hover:bg-yellow-50`.

**`before:` gradient shadow vs JS-toggled overlay:**
- Salary Book uses a separate `<div data-salarytable-sticky-shadow>` that fades in via JS when scrolled (`opacity-0` default). This is the canonical approach for sticky-column scroll shadows.
- Several entity pages (e.g., `drafts/_results.html.erb` L63) use always-visible `before:` CSS pseudo-elements instead. These are functional but visually less refined (shadow visible even when not scrolled). Lower-priority cleanup — do NOT break horizontal scroll behavior when removing these.

---

## entities/trades/show.html.erb

- [x] `web/app/views/entities/trades/show.html.erb` L136-145: trade-group inner `<thead>` uses bare `text-xs text-muted-foreground` instead of `bg-muted/40 text-[10px] uppercase tracking-wide text-muted-foreground/90 font-medium`
- [x] `web/app/views/entities/trades/show.html.erb` L148: trade-group inner `<tr>` rows have no hover class; add `hover:bg-yellow-50/70 dark:hover:bg-yellow-900/10 transition-colors duration-75`
- [x] `web/app/views/entities/trades/show.html.erb` L326-335: pick details inner `<thead>` uses bare `text-muted-foreground` instead of the standard header treatment; pick detail `<tr>` rows have no hover class
- [x] `web/app/views/entities/trades/show.html.erb` L363-371: cash details inner `<thead>` uses bare `text-muted-foreground` instead of the standard header treatment; cash detail `<tr>` rows have no hover class
- [x] `web/app/views/entities/trades/show.html.erb` L339: pick year/round column uses `font-mono` but not `tabular-nums`
- ~~[x]~~ **REVERTED** `web/app/views/entities/trades/show.html.erb` vitals KPI cards: `entity-cell-two-line` is a table-cell component (grid-rows-[20px_14px], text-[13px]) — it does NOT belong in standalone KPI cards. The standard KPI card pattern across all entity pages is `text-xs text-muted-foreground` label on top → `text-sm/text-lg font-medium/font-semibold` value below (see transactions/show). Reverted to original pattern. **Do not use `entity-cell-two-line` outside of `<table>` / `<tr>` contexts.**

## entities/trades/_results.html.erb

- [x] `web/app/views/entities/trades/_results.html.erb` L31: rows have correct hover, but the `<td>` cells for trade date and team codes don't use `font-mono tabular-nums` for the date or numeric trade ID values

## entities/transactions/_results.html.erb

- [x] `web/app/views/entities/transactions/_results.html.erb`: the Date column renders dates but the `entity-cell-primary` div doesn't use `font-mono tabular-nums` for the date text
- [x] `web/app/views/entities/transactions/_results.html.erb`: transaction type badges use bespoke per-type color classes (`bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-300`) instead of `entity-chip` tokens — consider migrating to `entity-chip--success` / `entity-chip--danger` / `entity-chip--accent`
- [x] `web/app/views/entities/transactions/_results.html.erb`: the `signed_method_lk` column uses `text-[11px]` instead of `text-[10px]` (minor inconsistency with secondary text convention)

## entities/transactions/show.html.erb

- [x] `web/app/views/entities/transactions/show.html.erb` vitals section: the Vitals KPI cards are consistent, but the "Player" card value doesn't use `font-medium` on the link text when a player exists (it inherits `text-sm font-medium` from the wrapper, so this is actually fine — verify) ✅ Verified: `font-weight` is inherited from the parent `div.text-sm.font-medium` wrapper — no change needed

## entities/drafts/_results.html.erb

- [x] `web/app/views/entities/drafts/_results.html.erb` L62-63: the sticky left column uses `group-hover:bg-yellow-50/70 dark:group-hover:bg-yellow-900/10` but the `bg_class` conditional backgrounds (for own picks, traded picks, etc.) may conflict with hover treatment — verify the hover is visible when rows already have colored backgrounds
- [x] `web/app/views/entities/drafts/_results.html.erb` L142,184: bottom summary table rows have hover but the inner pick-grid `<td>` cells (L75) use `text-[10px]` with `font-mono` but not `tabular-nums`
- [x] `web/app/views/entities/drafts/_results.html.erb` L63: sticky column still uses always-visible `before:` gradient shadow pseudo-element — lower-priority cleanup (see supervisor note on `before:` vs JS-toggled overlay pattern)

## tools/two_way_utility/_player_row.html.erb

- [x] `web/app/views/tools/two_way_utility/_player_row.html.erb`: overall very well matched to Salary Book patterns — verify that the `h-10` fixed height doesn't clip the double-row grid content (24px + 16px = 40px = h-10, so it's correct) ✅ Verified: math checks out, no clipping
- [x] `web/app/views/tools/two_way_utility/_player_row.html.erb` L118: outer row div uses `border-border/40` but Salary Book uses `border-border/50`; hover dark variant is `dark:hover:bg-yellow-900/10` vs Salary Book's `dark:hover:bg-yellow-900/25`; missing `transition-colors duration-75` on outer div
- [x] `web/app/views/tools/two_way_utility/_player_row.html.erb` L119-121: sticky column has extra `before:` gradient shadow pseudo-element (`before:w-[6px] before:bg-gradient-to-r before:from-[rgba(0,0,0,0.08)]`) that Salary Book's `_player_row` does not use — may be intentional for this tool's wider scroll area but should be verified for consistency ✅ Removed: Salary Book uses only `after:` border line, no gradient shadow

## tools/two_way_utility/_team_section.html.erb

- [x] `web/app/views/tools/two_way_utility/_team_section.html.erb`: verify that the team header section has the same sticky header shadow treatment as Salary Book — confirmed present (note: uses `0.08` opacity vs Salary Book's `0.1`, acceptable for this lighter surface)
- [x] `web/app/views/tools/two_way_utility/_team_section.html.erb` L99: column header sticky cell had extra `before:` gradient shadow pseudo-element — removed by supervisor to match Salary Book (Salary Book uses a separate JS-toggled overlay div, not a CSS pseudo-element)

## tools/team_summary/show.html.erb

- [x] `web/app/views/tools/team_summary/show.html.erb`: audit the full file for dark mode coverage on conditional color tints — **specific findings:** L289 `text-emerald-600 dark:text-emerald-400` is correct ✅ but the negative branch uses bare `text-red-500` without `dark:text-red-400`; L310, L317, L324, L331 all use `text-red-500` without dark variants. Salary Book reference uses `text-red-600 dark:text-red-400` pairs. Fix all to `text-red-600 dark:text-red-400`.

## tools/system_values/

- [x] `web/app/views/tools/system_values/_league_system_values_table.html.erb`: well-polished (uses Salary Book-style sticky column, shadow, group-hover, entity-cell-two-line) — confirmed other system values partials now match (added missing `overflow-x-auto` + `min-w-[X]` wrapper to `_league_salary_scales_table` and `_rookie_scale_amounts_table`; `_league_tax_rates_table` already matched)
- [x] `web/app/views/tools/system_values/_league_tax_rates_table.html.erb`: audit for consistent header treatment and hover patterns matching `_league_system_values_table.html.erb` ✅ Audited: header treatment (h-9 title bar, h-8 column headers), hover patterns (`hover:bg-yellow-50/70 dark:hover:bg-yellow-900/10`), sticky column (`group-hover`, `transition-colors duration-75`, `before:`/`after:` pseudo-elements), highlight treatment, empty state, and dark mode variants all already match `_league_system_values_table.html.erb` — no changes needed
- [x] `web/app/views/tools/system_values/_league_salary_scales_table.html.erb`: same audit ✅ Audited: header treatment (h-9 title bar, h-8 column headers), hover patterns (`hover:bg-yellow-50/70 dark:hover:bg-yellow-900/10`), sticky column (`group-hover`, `transition-colors duration-75`, `before:`/`after:` pseudo-elements), `entity-cell-two-line` in sticky column, `font-mono tabular-nums` on all data cells, highlight treatment, empty state, and dark mode variants all already match `_league_system_values_table.html.erb` — no changes needed
- [x] `web/app/views/tools/system_values/_rookie_scale_amounts_table.html.erb`: same audit ✅ Audited by supervisor: header treatment (h-9 title bar, h-8 column headers), hover patterns (`hover:bg-yellow-50/70 dark:hover:bg-yellow-900/10`), sticky column (`group-hover`, `transition-colors duration-75`, `before:`/`after:` pseudo-elements), `entity-cell-two-line` in sticky column, `font-mono tabular-nums` on all data cells, highlight treatment, empty state, and dark mode variants all already match `_league_system_values_table.html.erb` — no changes needed
- [x] `web/app/views/tools/system_values/_league_tax_rates_table.html.erb` L35, `_league_system_values_table.html.erb` L38: sticky column uses `group-hover:bg-yellow-50/70` (with opacity) — per supervisor note, sticky columns should use `group-hover:bg-yellow-50` (NO opacity) to fully cover `bg-background` underneath. Applies to all four system_values table partials. ✅ Fixed: changed `group-hover:bg-yellow-50/70 dark:group-hover:bg-yellow-900/10` → `group-hover:bg-yellow-50 dark:group-hover:bg-yellow-900/25` in all four partials to match Salary Book `_player_row.html.erb` pattern.
- [x] `web/app/views/tools/system_values/` all four table partials: outer row div uses `dark:hover:bg-yellow-900/10` but Salary Book `_player_row.html.erb` L20 uses `dark:hover:bg-yellow-900/25`. Low priority — cosmetic dark mode hover intensity mismatch. ✅ Fixed: changed `dark:hover:bg-yellow-900/10` → `dark:hover:bg-yellow-900/25` in all four partials.

## entities/players/ (index + show)

- [x] `web/app/views/entities/players/show.html.erb`: audit all section module partials for consistent table header treatment, row hover, and font-mono on numeric values — **Findings:** All 9 section partials audited. Table headers (`bg-muted/40 text-[10px] uppercase tracking-wide text-muted-foreground/90`) and row hover (`hover:bg-yellow-50/70 dark:hover:bg-yellow-900/10 transition-colors duration-75`) were already correct in all tables. Fixed `font-mono tabular-nums` missing on: (1) `_section_contract_history` signing dates/years in chronology table, start_salary_year/contract_length in version table; (2) `_section_guarantees` earned_date in protection conditions table, payment date window in payment schedule table.
- [x] `web/app/views/entities/players/`: audit all partials in this directory for dark mode coverage — ✅ **All clean.** Audited all 13 partials (`index.html.erb`, `show.html.erb`, `_sticky_header.html.erb`, `_rightpanel_base.html.erb`, `_section_vitals.html.erb`, `_section_constraints.html.erb`, `_section_connections.html.erb`, `_section_contract.html.erb`, `_section_contract_history.html.erb`, `_section_guarantees.html.erb`, `_section_incentives.html.erb`, `_section_ledger.html.erb`, `_section_team_history.html.erb`). Every color class with a specific color name has a corresponding `dark:` variant. Theme tokens (`text-foreground`, `bg-background`, `text-muted-foreground`, `border-border`, `bg-muted`, `text-primary`, `bg-primary`) used correctly throughout and auto-adapt. Hover treatments use `dark:hover:bg-yellow-900/10` per design guide for entity workspace `<tr>` rows. Entity-chip classes handle dark mode via CSS. No changes needed.

## entities/teams/ (index + show)

- [x] `web/app/views/entities/teams/show.html.erb`: audit section modules for table header consistency, hover treatment, and numeric formatting — **Findings:** (1) `_roster_breakdown.html.erb`: standard contracts & two-way contracts `<thead>` used `bg-muted/30` instead of `bg-muted/40` — fixed. Cap holds / exceptions / dead money mini-tables used `hover:bg-muted/20` instead of `hover:bg-yellow-50/70 dark:hover:bg-yellow-900/10 transition-colors duration-75` — fixed. Exception expiration_date `<td>` missing `font-mono tabular-nums` — fixed. Standard contracts Total column missing `font-medium` — fixed. (2) `_section_two_way.html.erb`: game_date_est column missing `font-mono tabular-nums` — fixed. (3) `_section_apron_provenance.html.erb`: transaction ID links had `font-mono` but missing `tabular-nums` — fixed. All other section partials (cap_horizon, activity, vitals, constraints, draft_assets) already matched design guide.
- [x] `web/app/views/entities/teams/`: audit all partials for dark mode coverage — ✅ **All clean.** Supervisor verified: grep for bare color classes (`text-red-*`, `bg-green-*`, `text-emerald-*`, etc.) without corresponding `dark:` variants found zero issues. All specific-color classes have dark mode pairs. Theme tokens (`text-foreground`, `bg-muted`, etc.) auto-adapt. Entity-chip variants handle dark mode via CSS. No changes needed.

## entities/agents/ (index + show + directory)

- [ ] `web/app/views/entities/agents/show.html.erb` (601 lines): large file — audit for consistent table headers (`bg-muted/40 text-[10px] uppercase`), row hover on all `<tr>` elements, `font-mono tabular-nums` on all financial values, and dark mode variants
- [ ] `web/app/views/entities/agents/_workspace_main.html.erb`: audit for design consistency
- [ ] `web/app/views/entities/agents/_rightpanel_overlay_agent.html.erb`: audit for consistent sidebar patterns matching Salary Book's `_sidebar_agent.html.erb`
- [ ] `web/app/views/entities/agents/_rightpanel_overlay_agency.html.erb`: audit for sidebar consistency

## entities/agencies/

- [ ] `web/app/views/entities/agencies/`: audit all files for design consistency (hover, headers, dark mode, font-mono)

## entities/draft_picks/ and entities/draft_selections/

- [ ] `web/app/views/entities/draft_picks/`: audit all files for design consistency
- [ ] `web/app/views/entities/draft_selections/`: audit all files for design consistency

## Cross-cutting concerns

- [ ] Grep all entity/tool views for bare `<th>` elements missing the standard header classes — every `<thead>` should use `bg-muted/40 text-[10px] uppercase tracking-wide text-muted-foreground/90` or at minimum `text-muted-foreground`
- [ ] Grep all entity/tool views for `<tr>` in `<tbody>` missing hover treatment — every data row should have `hover:bg-yellow-50/70 dark:hover:bg-yellow-900/10 transition-colors duration-75`
- [ ] Grep for numeric values rendered without `font-mono tabular-nums` (especially `format_salary`, `format_compact_currency`, dates, IDs)
- [ ] Grep for color classes missing `dark:` variants (e.g., `text-red-600` without `dark:text-red-400`, `bg-green-100` without `dark:bg-green-900/30`)
