# Design Consistency Audit

> Propagate Salary Book polish to every other page in `web/`.
>
> **Gold standard:** `web/app/views/tools/salary_book/` (especially `_player_row`, `_team_section`, `_table_header`, `_sidebar_player`)
>
> **Design contract:** `web/docs/design_guide.md`, `web/AGENTS.md`
>
> **Rule:** Do NOT modify Salary Book files. They are the reference. Fix everything else to match.

---

## entities/trades/show.html.erb

- [x] `web/app/views/entities/trades/show.html.erb` L136-145: trade-group inner `<thead>` uses bare `text-xs text-muted-foreground` instead of `bg-muted/40 text-[10px] uppercase tracking-wide text-muted-foreground/90 font-medium`
- [x] `web/app/views/entities/trades/show.html.erb` L148: trade-group inner `<tr>` rows have no hover class; add `hover:bg-yellow-50/70 dark:hover:bg-yellow-900/10 transition-colors duration-75`
- [x] `web/app/views/entities/trades/show.html.erb` L326-335: pick details inner `<thead>` uses bare `text-muted-foreground` instead of the standard header treatment; pick detail `<tr>` rows have no hover class
- [x] `web/app/views/entities/trades/show.html.erb` L363-371: cash details inner `<thead>` uses bare `text-muted-foreground` instead of the standard header treatment; cash detail `<tr>` rows have no hover class
- [x] `web/app/views/entities/trades/show.html.erb` L339: pick year/round column uses `font-mono` but not `tabular-nums`
- [x] `web/app/views/entities/trades/show.html.erb` vitals KPI cards: `text-xs text-muted-foreground` label + `text-sm font-medium` value is fine, but the pattern could use `entity-cell-two-line` for consistency (low priority)

## entities/trades/_results.html.erb

- [ ] `web/app/views/entities/trades/_results.html.erb` L31: rows have correct hover, but the `<td>` cells for trade date and team codes don't use `font-mono tabular-nums` for the date or numeric trade ID values

## entities/transactions/_results.html.erb

- [ ] `web/app/views/entities/transactions/_results.html.erb`: the Date column renders dates but the `entity-cell-primary` div doesn't use `font-mono tabular-nums` for the date text
- [ ] `web/app/views/entities/transactions/_results.html.erb`: transaction type badges use bespoke per-type color classes (`bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-300`) instead of `entity-chip` tokens — consider migrating to `entity-chip--success` / `entity-chip--danger` / `entity-chip--accent`
- [ ] `web/app/views/entities/transactions/_results.html.erb`: the `signed_method_lk` column uses `text-[11px]` instead of `text-[10px]` (minor inconsistency with secondary text convention)

## entities/transactions/show.html.erb

- [ ] `web/app/views/entities/transactions/show.html.erb` vitals section: the Vitals KPI cards are consistent, but the "Player" card value doesn't use `font-medium` on the link text when a player exists (it inherits `text-sm font-medium` from the wrapper, so this is actually fine — verify)

## entities/drafts/_results.html.erb

- [ ] `web/app/views/entities/drafts/_results.html.erb` L62-63: the sticky left column uses `group-hover:bg-yellow-50/70 dark:group-hover:bg-yellow-900/10` but the `bg_class` conditional backgrounds (for own picks, traded picks, etc.) may conflict with hover treatment — verify the hover is visible when rows already have colored backgrounds
- [ ] `web/app/views/entities/drafts/_results.html.erb` L142,184: bottom summary table rows have hover but the inner pick-grid `<td>` cells (L75) use `text-[10px]` with `font-mono` but not `tabular-nums`

## tools/two_way_utility/_player_row.html.erb

- [ ] `web/app/views/tools/two_way_utility/_player_row.html.erb`: overall very well matched to Salary Book patterns — verify that the `h-10` fixed height doesn't clip the double-row grid content (24px + 16px = 40px = h-10, so it's correct)

## tools/two_way_utility/_team_section.html.erb

- [ ] `web/app/views/tools/two_way_utility/_team_section.html.erb`: verify that the team header section has the same sticky header shadow treatment as Salary Book (`shadow-[0_1px_3px_0_rgb(0_0_0/0.08),0_1px_2px_-1px_rgb(0_0_0/0.08)]` — confirmed present)

## tools/team_summary/show.html.erb

- [ ] `web/app/views/tools/team_summary/show.html.erb`: audit the full file for dark mode coverage on conditional color tints (cap space positive/negative, tax overage colors) — Salary Book uses explicit `dark:text-emerald-400` / `dark:text-red-400` pairs for every semantic color

## tools/system_values/

- [ ] `web/app/views/tools/system_values/_league_system_values_table.html.erb`: well-polished (uses Salary Book-style sticky column, shadow, group-hover, entity-cell-two-line) — confirm other system values partials match
- [ ] `web/app/views/tools/system_values/_league_tax_rates_table.html.erb`: audit for consistent header treatment and hover patterns matching `_league_system_values_table.html.erb`
- [ ] `web/app/views/tools/system_values/_league_salary_scales_table.html.erb`: same audit
- [ ] `web/app/views/tools/system_values/_rookie_scale_amounts_table.html.erb`: same audit

## entities/players/ (index + show)

- [ ] `web/app/views/entities/players/show.html.erb`: audit all section module partials for consistent table header treatment, row hover, and font-mono on numeric values
- [ ] `web/app/views/entities/players/`: audit all partials in this directory for dark mode coverage

## entities/teams/ (index + show)

- [ ] `web/app/views/entities/teams/show.html.erb`: audit section modules for table header consistency, hover treatment, and numeric formatting
- [ ] `web/app/views/entities/teams/`: audit all partials for dark mode coverage

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
