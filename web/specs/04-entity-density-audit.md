# Entity UI Density Audit (Salary Book transfer)

Date: 2026-02-05

## What was audited

Reference source-of-truth: `tools/salary_book/*` (especially `_player_row`, `_table_header`, `_team_section`).

Compared against:

- `app/views/entities/**/*`
- `app/views/tools/two_way_utility/*`

## Salary Book patterns worth reusing

1. **Dense but scannable rows**
   - Tight vertical rhythm (`h-8` headers, compact body rows)
   - Monospace/tabular numbers for all numeric columns
2. **Two-level row semantics**
   - Primary line for identity/value
   - Secondary line for metadata/context
3. **Hover semantics**
   - Subtle yellow hover (`hover:bg-yellow-50/70 dark:hover:bg-yellow-900/10`)
   - Fast color transition (`duration-75`)
4. **Low-noise headers**
   - Small uppercase labels (`text-[10px] uppercase tracking-wide`)
   - Reduced contrast header background (`bg-muted/40`)

## Repo-wide styling pass applied

### Global shared classes
Added reusable component classes in `app/assets/tailwind/application.css`:

- `.entity-table`
- `.entity-cell-two-line`
- `.entity-cell-primary`
- `.entity-cell-secondary`

These mirror Salary Book row hierarchy while remaining utility-first.

### Entity table normalization
Across entity pages:

- `text-sm` tables → `text-xs`
- table headers normalized to Salary Book-like micro-label treatment
- row hover converted from muted gray to Salary Book yellow hover treatment

### Two-level cell treatment added to high-traffic index pages
- `entities/players/index`
- `entities/teams/index`
- `entities/agents/index`
- `entities/agencies/index`
- `entities/draft_selections/index`

These now use explicit primary/secondary line structure in key cells.

## Follow-up polish opportunities

1. Convert additional show-page cells to `entity-cell-*` where secondary metadata exists.
2. Add sticky left column for selected long tables (team/transaction/trade pages).
3. Introduce consistent badge palette tokens for status chips across entities.
4. Consider extracting a shared `entities/shared/_dense_table_header` partial if repetition grows.
